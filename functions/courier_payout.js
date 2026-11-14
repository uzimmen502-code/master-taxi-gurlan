'use strict';

/**
 * AVA LOGISTICS — KURYER HAQI AVTOMATIK HAMYONGA (ega qarori, 2026-10-31).
 * Default codebase (pul faqat `settlement_ledger.js` orqali — 43-band).
 *
 * Qaror (ega, 2026-10-31, yakuniy):
 *   - relay LEG uchun ISHLAB TOPILGAN haq (EARNED) kuryerning AVA HAMYONIGA
 *     AVTOMATIK tushadi (qo'lda qadam yo'q); kuryer mavjud hamyon yechish
 *     oqimi (`requestWalletWithdraw`) orqali naqdlashtiradi;
 *   - to'lov paytida ALOHIDA kuryer XIZMAT HAQI (foiz, tarifdagi AVA ulushiga
 *     QO'SHIMCHA) ushlanadi; foiz web adminda kiritiladi.
 *
 * Bu modul `relay_escrow.js` ga TEGMAYDI: EARNED yozuvi (`journal_entries/
 * relayEarned:{shipmentId}:{legId}`, kind `logistics_leg_earned`,
 * Dr platform_accrual / Cr supplier_payable:{provider}) yaratilganda
 * trigger ishga tushadi va ALOHIDA yozuv qiladi:
 *
 *   PAYOUT  Dr supplier_payable:{provider}           gross   (EARNED krediti)
 *           Cr passenger_credit:{walletUid}          gross − fee   (hamyon)
 *           Cr earnings:ava_courier_service_fee      fee
 *
 *   fee = ceil(gross × feeBps / 10000) — butun so'm (8-band); ceil: platforma
 *   ulushi yuqoriga, ijrochi ulushi pastga (`tariff.splitInternal` bilan bir xil).
 *
 * Kalit: `journal_entries/courierPayout:{shipmentId}:{legId}` — trigger qayta
 * ishlasa yoki reconcile bilan to'qnashsa ikkinchi to'lov YO'Q (21-band).
 * Hamyon ko'zgusi (bonusBalance + wallet_ledger `courier_payout`) AYNI
 * tranzaksiyada (`postEntry` mirrorBonus).
 *
 * INVARIANT: `supplier_payable:{provider}` hech qachon manfiy bo'lmaydi.
 * Yetmasa (masalan moliya `creditSupplier` bilan qo'lda to'lab qo'ygan) —
 * pul YO'Q, `courier_payout_anomalies/{kalit}` + log. Shu bois avtomatik
 * to'lovlar yig'indisi hech qachon ishlab topilgandan oshmaydi.
 *
 * Sozlama `settings/courier_service_fee` (faqat CF yozadi — rules alohida):
 *   { feeBps 0..5000, feeVersion, autoPayoutEnabled, reason, updatedAt, updatedBy }
 *   Hujjat yo'q → 0 bps, autoPayoutEnabled = true (PROPOSED: ega «avtomatik»
 *   dedi; aniq `false` — kill switch, hurmat qilinadi).
 *   Noto'g'ri qiymat (masalan qo'lda yozilgan 9999) → pul YO'Q, anomaliya.
 *
 * Reconcile (har 15 daqiqa): ochiq anomaliyalar (kill switch o'chiq paytida
 * kechiktirilganlar ham) + oxirgi RECONCILE_WINDOW_MS ichidagi EARNED
 * yozuvlaridan to'lovi yo'qlari → qayta urinish.
 */

const EARNED_KIND = 'logistics_leg_earned';
const EARNED_PREFIX = 'relayEarned:';
const PAYOUT_KIND = 'logistics_courier_payout';
const PAYOUT_PREFIX = 'courierPayout:';
const FEE_ACCOUNT = 'earnings:ava_courier_service_fee';
const ACCRUAL_ACCOUNT = 'platform_accrual';
const SETTINGS_DOC = Object.freeze(['settings', 'courier_service_fee']);
const HISTORY_COLLECTION = 'courier_service_fee_history';
const ANOMALIES = 'courier_payout_anomalies';
const PAYOUTS = 'courier_payouts';
const ADMIN_AUDIT = 'admin_audit';
const WALLET_LEDGER_TYPE = 'courier_payout';
const FEE_BPS_MIN = 0;
const FEE_BPS_MAX = 5000;
/** Reconcile: oxirgi 6 soatdagi EARNED (cron 15 daq — 24 marta qoplanadi). PROPOSED. */
const RECONCILE_WINDOW_MS = 6 * 60 * 60 * 1000;
const RECONCILE_PAGE = 300;
const RECONCILE_MAX_SCAN = 3000;
const RECONCILE_MAX_OPEN = 100;
const SET_ROLES = Object.freeze(['admin', 'superadmin', 'finance']);
const GET_ROLES = Object.freeze(['admin', 'superadmin', 'finance', 'auditor']);

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isFeeBps = (n) => isInt(n) && n >= FEE_BPS_MIN && n <= FEE_BPS_MAX;

/** ceil(amount × feeBps / 10000) — faqat butun sonlar bilan (float yo'q). */
function computeFee(amount, feeBps) {
  if (!isInt(amount) || amount <= 0) throw new Error('courierPayout: amount must be a positive integer');
  if (!isFeeBps(feeBps)) throw new Error('courierPayout: feeBps out of range');
  const product = amount * feeBps;
  if (!Number.isSafeInteger(product)) throw new Error('courierPayout: amount too large');
  const rem = product % 10000;
  return (product - rem) / 10000 + (rem > 0 ? 1 : 0);
}

/**
 * Sozlama hujjati → { feeBps, feeVersion, autoPayoutEnabled, valid, configured }.
 * Yo'q → 0 bps / v0 / yoqilgan (PROPOSED). `feeBps` noto'g'ri → valid=false.
 */
function parseSettings(doc) {
  const d = doc && typeof doc === 'object' ? doc : null;
  if (!d) return { feeBps: 0, feeVersion: 0, autoPayoutEnabled: true, valid: true, configured: false };
  const feeVersion = isInt(d.feeVersion) && d.feeVersion >= 0 ? d.feeVersion : 0;
  const autoPayoutEnabled = d.autoPayoutEnabled !== false;
  if (d.feeBps === undefined || d.feeBps === null) {
    return { feeBps: 0, feeVersion, autoPayoutEnabled, valid: true, configured: true };
  }
  if (!isFeeBps(d.feeBps)) return { feeBps: null, feeVersion, autoPayoutEnabled, valid: false, configured: true };
  return { feeBps: d.feeBps, feeVersion, autoPayoutEnabled, valid: true, configured: true };
}

function isEarnedEntry(entryId, data) {
  return typeof entryId === 'string' && entryId.startsWith(EARNED_PREFIX)
    && !!data && data.kind === EARNED_KIND;
}

/** `relayEarned:{s}:{l}` → `courierPayout:{s}:{l}` (relay kaliti bilan aynan mos). */
function payoutKeyFor(earnedEntryId) {
  return `${PAYOUT_PREFIX}${String(earnedEntryId).slice(EARNED_PREFIX.length)}`;
}

/**
 * EARNED yozuvini o'qiydi. Qaytaradi: { ok, key, shipmentId, legId, providerId,
 * payableAccount, amount } yoki { ok:false, key, reason }.
 */
function parseEarned(entryId, data) {
  const key = payoutKeyFor(entryId);
  const d = data || {};
  const meta = d.meta && typeof d.meta === 'object' ? d.meta : {};
  const shipmentId = typeof meta.shipmentId === 'string' ? meta.shipmentId : '';
  const legId = typeof meta.legId === 'string' ? meta.legId : '';
  const legs = Array.isArray(d.legs) ? d.legs : [];
  const cr = legs.filter((l) => l && isInt(l.cr) && l.cr > 0);
  const dr = legs.filter((l) => l && isInt(l.dr) && l.dr > 0);
  const base = { key, shipmentId, legId };
  if (!shipmentId || !legId || `${EARNED_PREFIX}${shipmentId}:${legId}` !== entryId) {
    return { ...base, ok: false, reason: 'earned_malformed' };
  }
  if (legs.length !== 2 || cr.length !== 1 || dr.length !== 1
      || !String(cr[0].account || '').startsWith('supplier_payable:')
      || dr[0].account !== ACCRUAL_ACCOUNT || cr[0].cr !== dr[0].dr) {
    return { ...base, ok: false, reason: 'earned_malformed' };
  }
  const payableAccount = String(cr[0].account);
  const providerId = payableAccount.slice('supplier_payable:'.length);
  if (!providerId) return { ...base, ok: false, reason: 'earned_malformed' };
  return { ...base, ok: true, providerId, payableAccount, amount: cr[0].cr };
}

const reasonError = (reason, extra) => Object.assign(new Error(reason), { reason, ...(extra || {}) });

function attachCourierPayout(exportsObj, deps) {
  const {
    functions, db, admin, canonicalUid, settlementLedger, requireCallerRoles, now: nowFn,
  } = deps;
  const { HttpsError } = functions.https;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const nowMs = () => (nowFn ? nowFn().getTime() : Date.now());
  const settingsRef = () => db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
  const journalRef = (id) => db.collection(settlementLedger.COL_JOURNAL).doc(id);
  const anomalyRef = (key) => db.collection(ANOMALIES).doc(key);
  const fail = (code, extra) => new HttpsError('invalid-argument', code, { code, reason: code, ...(extra || {}) });
  const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);

  function log(fields, level) {
    const line = JSON.stringify({ action: 'courierPayout', ...fields });
    if (level === 'error') console.error(line);
    else if (level === 'warn') console.warn(line);
    else console.log(line);
  }

  /** Kanonik telefon → `users` hujjat id (12 xonali, keyin 9 xonali). */
  async function resolveWalletUid(providerId) {
    const canon = canonicalUid(providerId);
    const candidates = [canon];
    if (canon.length === 12 && canon.startsWith('998')) candidates.push(canon.slice(3));
    for (const id of candidates) {
      if (!id || id.length < 9) continue;
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return id;
    }
    return null;
  }

  /**
   * Anomaliya / kechiktirilgan to'lov qaydi — PUL YO'Q. To'lov allaqachon
   * bo'lgan bo'lsa (parallel reconcile) ochiq qayd YARATILMAYDI.
   */
  async function recordAnomaly(info, reason, detail) {
    const ref = anomalyRef(info.key);
    await db.runTransaction(async (t) => {
      const [s, paid] = await Promise.all([t.get(ref), t.get(journalRef(info.key))]);
      if (paid.exists) return;
      const prev = s.exists ? (s.data() || {}) : null;
      const doc = {
        key: info.key,
        earnedEntryId: info.earnedEntryId,
        shipmentId: info.shipmentId || '',
        legId: info.legId || '',
        providerId: info.providerId || '',
        amount: isInt(info.amount) ? info.amount : null,
        reason,
        detail: detail || {},
        status: 'open',
        attempts: (prev && isInt(prev.attempts) ? prev.attempts : 0) + 1,
        lastSeenAt: ts(),
      };
      if (!prev) doc.firstSeenAt = ts();
      t.set(ref, doc, { merge: true });
    });
  }

  /** To'lov bor, lekin anomaliya ochiq qolgan (poyga) — yopiladi. */
  async function resolveStaleAnomaly(key) {
    const ref = anomalyRef(key);
    const s = await ref.get();
    if (s.exists && (s.data() || {}).status === 'open') {
      await ref.set({ status: 'resolved', resolvedAt: ts(), resolvedBy: 'system', payoutEntryId: key }, { merge: true });
    }
  }

  /**
   * Bitta EARNED → to'lov. Qaytaradi: { paid } | { idempotent } | { skipped } | { anomaly }.
   * `source`: 'trigger' | 'reconcile_open' | 'reconcile_scan'.
   */
  async function processEarned(earnedEntryId, data, source) {
    const started = Date.now();
    if (!isEarnedEntry(earnedEntryId, data)) return { skipped: 'not_earned' };
    const p = parseEarned(earnedEntryId, data);
    const info = { ...p, earnedEntryId };
    const base = { key: p.key, shipmentId: p.shipmentId, legId: p.legId, source };
    if (!p.ok) {
      await recordAnomaly(info, p.reason);
      log({ ...base, result: 'anomaly', errorCode: 'COURIER_PAYOUT_EARNED_MALFORMED' }, 'error');
      return { anomaly: p.reason };
    }
    if ((await journalRef(p.key).get()).exists) {
      await resolveStaleAnomaly(p.key);
      return { idempotent: true };
    }

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const settingsSnap = await settingsRef().get();
      const st = parseSettings(settingsSnap.exists ? settingsSnap.data() : null);
      if (!st.valid) {
        await recordAnomaly(info, 'fee_config_invalid');
        log({ ...base, result: 'anomaly', errorCode: 'COURIER_PAYOUT_FEE_CONFIG_INVALID' }, 'error');
        return { anomaly: 'fee_config_invalid' };
      }
      if (!st.autoPayoutEnabled) {
        await recordAnomaly(info, 'auto_payout_disabled', { feeVersion: st.feeVersion });
        log({ ...base, result: 'deferred', errorCode: 'COURIER_PAYOUT_DISABLED' }, 'warn');
        return { skipped: 'disabled' };
      }
      const walletUid = await resolveWalletUid(p.providerId);
      if (!walletUid) {
        await recordAnomaly(info, 'user_missing');
        log({ ...base, result: 'anomaly', errorCode: 'COURIER_PAYOUT_USER_MISSING' }, 'error');
        return { anomaly: 'user_missing' };
      }
      const gross = p.amount;
      const fee = computeFee(gross, st.feeBps);
      const net = gross - fee;
      const pcAccount = settlementLedger.passengerCreditAccount(walletUid);
      const legs = [{ account: p.payableAccount, dr: gross }];
      if (net > 0) legs.push({ account: pcAccount, cr: net });
      if (fee > 0) legs.push({ account: FEE_ACCOUNT, cr: fee });
      const meta = {
        shipmentId: p.shipmentId, legId: p.legId, providerId: p.providerId, walletUid,
        gross, fee, net, feeBps: st.feeBps, feeVersion: st.feeVersion, earnedEntryId,
      };
      const userRef = db.collection('users').doc(walletUid);
      const aRef = anomalyRef(p.key);
      try {
        const res = await settlementLedger.postEntry(db, {
          idempotencyKey: p.key,
          kind: PAYOUT_KIND,
          refType: 'shipment',
          refId: p.shipmentId,
          postedBy: 'system',
          postedRole: 'system',
          legs,
        }, {
          mirrorBonus: true,
          walletLedgerType: WALLET_LEDGER_TYPE,
          meta,
          // READ fazasi: sozlama, hamyon egasi va anomaliya — tranzaksiya ichida qayta.
          precheck: async (tx) => {
            const [sSnap, uSnap, aSnap] = await Promise.all([tx.get(settingsRef()), tx.get(userRef), tx.get(aRef)]);
            const cur = parseSettings(sSnap.exists ? sSnap.data() : null);
            if (!cur.autoPayoutEnabled) throw reasonError('disabled');
            if (!cur.valid || cur.feeBps !== st.feeBps || cur.feeVersion !== st.feeVersion) throw reasonError('settings_changed');
            if (!uSnap.exists) throw reasonError('user_missing');
            return { anomalyOpen: aSnap.exists && (aSnap.data() || {}).status === 'open', anomalyExists: aSnap.exists };
          },
          // INVARIANT: ijrochiga qarz manfiyga tushmaydi (ishlab topilgandan ortiq to'lov yo'q).
          assert: ({ accounts }) => {
            const s = accounts.get(p.payableAccount);
            if (s && s.next < 0) throw reasonError('payable_insufficient', { available: s.prev, shortfall: -s.next });
          },
          onCommit: (tx, { pre }) => {
            tx.set(db.collection(PAYOUTS).doc(p.key), {
              key: p.key, earnedEntryId, shipmentId: p.shipmentId, legId: p.legId,
              providerId: p.providerId, walletUid, gross, fee, net,
              feeBps: st.feeBps, feeVersion: st.feeVersion, source, createdAt: ts(),
            });
            if (pre && pre.anomalyExists) {
              tx.set(aRef, {
                status: 'resolved', resolvedAt: ts(), resolvedBy: 'system', payoutEntryId: p.key,
              }, { merge: true });
            }
          },
        });
        if (res.idempotent) return { idempotent: true };
        log({
          ...base, result: 'paid', gross, fee, net, feeBps: st.feeBps, feeVersion: st.feeVersion,
          durationMs: Date.now() - started,
        });
        return { paid: { gross, fee, net, walletUid, feeBps: st.feeBps, feeVersion: st.feeVersion } };
      } catch (e) {
        const reason = e && e.reason;
        if (reason === 'settings_changed') continue;
        if (reason === 'disabled') {
          await recordAnomaly(info, 'auto_payout_disabled', { feeVersion: st.feeVersion });
          log({ ...base, result: 'deferred', errorCode: 'COURIER_PAYOUT_DISABLED' }, 'warn');
          return { skipped: 'disabled' };
        }
        if (reason === 'user_missing') {
          await recordAnomaly(info, 'user_missing');
          log({ ...base, result: 'anomaly', errorCode: 'COURIER_PAYOUT_USER_MISSING' }, 'error');
          return { anomaly: 'user_missing' };
        }
        if (reason === 'payable_insufficient') {
          await recordAnomaly(info, 'payable_insufficient', {
            available: isInt(e.available) ? e.available : null, shortfall: isInt(e.shortfall) ? e.shortfall : null,
          });
          log({ ...base, result: 'anomaly', errorCode: 'COURIER_PAYOUT_PAYABLE_INSUFFICIENT', gross }, 'error');
          return { anomaly: 'payable_insufficient' };
        }
        log({ ...base, result: 'error', errorCode: 'COURIER_PAYOUT_FAILED', message: String(e && e.message) }, 'error');
        throw e;
      }
    }
    log({ ...base, result: 'error', errorCode: 'COURIER_PAYOUT_SETTINGS_RACE' }, 'error');
    return { skipped: 'settings_race' };
  }

  /** Reconcile: ochiq anomaliyalar + oyna ichidagi to'lovsiz EARNED. */
  async function reconcile({ windowMs = RECONCILE_WINDOW_MS } = {}) {
    const started = Date.now();
    const out = {
      retriedOpen: 0, scanned: 0, missing: 0, paid: 0, anomalies: 0, deferred: 0, idempotent: 0, truncated: false,
    };
    const tally = (r) => {
      if (r.paid) out.paid += 1;
      else if (r.anomaly) out.anomalies += 1;
      else if (r.skipped === 'disabled') out.deferred += 1;
      else if (r.idempotent) out.idempotent += 1;
    };
    const seen = new Set();
    const one = async (id, data, source) => {
      seen.add(id);
      try { tally(await processEarned(id, data, source)); } catch (e) {
        log({ key: payoutKeyFor(id), source, result: 'error', errorCode: 'COURIER_PAYOUT_RECONCILE_ITEM', message: String(e && e.message) }, 'error');
      }
    };

    const open = await db.collection(ANOMALIES).where('status', '==', 'open').limit(RECONCILE_MAX_OPEN).get();
    for (const d of open.docs) {
      const earnedId = String((d.data() || {}).earnedEntryId || '');
      if (!earnedId || seen.has(earnedId)) continue;
      const s = await journalRef(earnedId).get();
      if (!s.exists) continue;
      out.retriedOpen += 1;
      await one(earnedId, s.data(), 'reconcile_open');
    }

    const from = admin.firestore.Timestamp.fromMillis(nowMs() - windowMs);
    const q = db.collection(settlementLedger.COL_JOURNAL).where('ts', '>=', from).orderBy('ts').limit(RECONCILE_PAGE);
    let last = null;
    for (;;) {
      if (out.scanned >= RECONCILE_MAX_SCAN) { out.truncated = true; break; }
      const snap = await (last ? q.startAfter(last) : q).get();
      if (snap.empty) break;
      out.scanned += snap.size;
      const earned = snap.docs.filter((d) => isEarnedEntry(d.id, d.data()) && !seen.has(d.id));
      if (earned.length) {
        const pays = await db.getAll(...earned.map((d) => journalRef(payoutKeyFor(d.id))));
        for (let i = 0; i < earned.length; i += 1) {
          if (pays[i].exists) continue;
          out.missing += 1;
          await one(earned[i].id, earned[i].data(), 'reconcile_scan');
        }
      }
      if (snap.size < RECONCILE_PAGE) break;
      last = snap.docs[snap.docs.length - 1];
    }
    log({ source: 'reconcile', result: 'done', ...out, durationMs: Date.now() - started },
      out.truncated || out.anomalies ? 'warn' : undefined);
    return out;
  }

  // ── Admin ────────────────────────────────────────────────────────────
  function settingsView(doc) {
    const st = parseSettings(doc);
    const d = doc || {};
    return {
      configured: st.configured,
      valid: st.valid,
      feeBps: st.feeBps,
      feeVersion: st.feeVersion,
      autoPayoutEnabled: st.autoPayoutEnabled,
      reason: typeof d.reason === 'string' ? d.reason : '',
      updatedAtMs: toMs(d.updatedAt),
      updatedBy: typeof d.updatedBy === 'string' ? d.updatedBy : '',
      feeBpsMin: FEE_BPS_MIN,
      feeBpsMax: FEE_BPS_MAX,
    };
  }

  /** Admin — joriy sozlama + oxirgi to'lovlar + ochiq anomaliyalar (faqat o'qish). */
  exportsObj.adminGetCourierServiceFee = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(context, [...GET_ROLES], 'Admin role required');
    const [sSnap, paySnap, anSnap, feeAcc] = await Promise.all([
      settingsRef().get(),
      db.collection(PAYOUTS).orderBy('createdAt', 'desc').limit(20).get(),
      db.collection(ANOMALIES).where('status', '==', 'open').limit(50).get(),
      db.collection(settlementLedger.COL_ACCOUNTS).doc(FEE_ACCOUNT).get(),
    ]);
    const recentPayouts = paySnap.docs.map((d) => {
      const x = d.data() || {};
      return {
        key: d.id, shipmentId: x.shipmentId || '', legId: x.legId || '', providerId: x.providerId || '',
        walletUid: x.walletUid || '', gross: x.gross || 0, fee: x.fee || 0, net: x.net || 0,
        feeBps: isInt(x.feeBps) ? x.feeBps : null, feeVersion: isInt(x.feeVersion) ? x.feeVersion : null,
        createdAtMs: toMs(x.createdAt),
      };
    });
    const openAnomalies = anSnap.docs.map((d) => {
      const x = d.data() || {};
      return {
        key: d.id, shipmentId: x.shipmentId || '', legId: x.legId || '', providerId: x.providerId || '',
        amount: isInt(x.amount) ? x.amount : null, reason: x.reason || '', attempts: isInt(x.attempts) ? x.attempts : 0,
        firstSeenAtMs: toMs(x.firstSeenAt), lastSeenAtMs: toMs(x.lastSeenAt),
      };
    }).sort((a, b) => (b.lastSeenAtMs || 0) - (a.lastSeenAtMs || 0));
    return {
      ok: true,
      ...settingsView(sSnap.exists ? sSnap.data() : null),
      feeAccountBalance: feeAcc.exists ? ((feeAcc.data() || {}).balance || 0) : 0,
      recentPayouts,
      openAnomalies,
    };
  });

  /**
   * Admin — xizmat haqi foizi va avto-to'lov kaliti.
   * data: { feeBps?: butun 0..5000, autoPayoutEnabled?: bool, reason: ≥3 belgi }.
   * Har haqiqiy o'zgarish: feeVersion+1, o'zgarmas tarix `courier_service_fee_history/v{n}`
   * va `admin_audit` (kind `courier_service_fee`) — bitta tranzaksiyada (9, 16, 41-band).
   */
  exportsObj.adminSetCourierServiceFee = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, [...SET_ROLES], 'Admin role required');
    const d = data && typeof data === 'object' ? data : {};
    const hasFee = d.feeBps !== undefined && d.feeBps !== null;
    const hasSwitch = d.autoPayoutEnabled !== undefined && d.autoPayoutEnabled !== null;
    if (hasFee && !isFeeBps(d.feeBps)) throw fail('FEE_BPS_INVALID', { min: FEE_BPS_MIN, max: FEE_BPS_MAX });
    if (hasSwitch && typeof d.autoPayoutEnabled !== 'boolean') throw fail('AUTO_PAYOUT_INVALID');
    if (!hasFee && !hasSwitch) throw fail('NOTHING_TO_CHANGE');
    const reason = String(d.reason || '').trim().slice(0, 300);
    if (reason.length < 3) throw fail('REASON_REQUIRED');

    const ref = settingsRef();
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const raw = snap.exists ? (snap.data() || {}) : null;
      const cur = parseSettings(raw);
      const nextFee = hasFee ? d.feeBps : (cur.valid ? cur.feeBps : null);
      if (nextFee === null) throw fail('FEE_BPS_INVALID', { min: FEE_BPS_MIN, max: FEE_BPS_MAX, current: 'invalid' });
      const nextSwitch = hasSwitch ? d.autoPayoutEnabled : cur.autoPayoutEnabled;
      if (cur.configured && cur.valid && raw && isInt(raw.feeBps)
          && nextFee === cur.feeBps && nextSwitch === cur.autoPayoutEnabled) {
        return { feeVersion: cur.feeVersion, unchanged: true, feeBps: cur.feeBps, autoPayoutEnabled: cur.autoPayoutEnabled };
      }
      const next = cur.feeVersion + 1;
      const doc = {
        feeBps: nextFee, feeVersion: next, autoPayoutEnabled: nextSwitch, reason, updatedAt: ts(), updatedBy: actor,
      };
      const previous = {
        feeBps: raw && raw.feeBps !== undefined ? raw.feeBps : null,
        feeVersion: cur.feeVersion,
        autoPayoutEnabled: raw ? cur.autoPayoutEnabled : null,
      };
      t.set(ref, doc);
      t.create(db.collection(HISTORY_COLLECTION).doc(`v${next}`), {
        ...doc, previous, changedBy: actor, changedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'courier_service_fee', actor, target: SETTINGS_DOC.join('/'),
        from: String(cur.feeVersion), to: String(next), reason,
        detail: {
          feeBps: nextFee, prevFeeBps: previous.feeBps,
          autoPayoutEnabled: nextSwitch, prevAutoPayoutEnabled: previous.autoPayoutEnabled,
        },
        at: ts(),
      });
      return { feeVersion: next, unchanged: false, feeBps: nextFee, autoPayoutEnabled: nextSwitch };
    });
    console.log(JSON.stringify({
      action: 'adminSetCourierServiceFee', result: 'ok', feeVersion: out.feeVersion,
      feeBps: out.feeBps, autoPayoutEnabled: out.autoPayoutEnabled, unchanged: out.unchanged, userId: actor,
    }));
    return { ok: true, ...out };
  });

  // ── Triggerlar ───────────────────────────────────────────────────────
  // Har jurnal yozuvida ishga tushadi; relay EARNED bo'lmasa — darhol chiqadi
  // (o'qish yo'q). Firestore v1 trigger'ida maydon filtri yo'q.
  exportsObj.onRelayEarnedCourierPayout = functions.firestore
    .document(`${settlementLedger.COL_JOURNAL}/{entryId}`)
    .onCreate(async (snap) => {
      const data = snap.data() || {};
      if (!isEarnedEntry(snap.id, data)) return null;
      await processEarned(snap.id, data, 'trigger');
      return null;
    });

  exportsObj.courierPayoutReconcile = functions
    .runWith({ timeoutSeconds: 300 })
    .pubsub.schedule('every 15 minutes')
    .onRun(async () => { await reconcile(); return null; });

  return { processEarned, reconcile, resolveWalletUid };
}

module.exports = {
  EARNED_KIND,
  EARNED_PREFIX,
  PAYOUT_KIND,
  PAYOUT_PREFIX,
  FEE_ACCOUNT,
  SETTINGS_DOC,
  HISTORY_COLLECTION,
  ANOMALIES,
  PAYOUTS,
  WALLET_LEDGER_TYPE,
  FEE_BPS_MIN,
  FEE_BPS_MAX,
  RECONCILE_WINDOW_MS,
  computeFee,
  parseSettings,
  parseEarned,
  payoutKeyFor,
  isEarnedEntry,
  attachCourierPayout,
};
