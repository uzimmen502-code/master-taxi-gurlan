/**
 * РАҒБАТ ДАСТУРЛАРИ — ягона тизим (эга қарори 2026-11-02).
 *
 * Аёллар (15–60) — AVA дўкони учун 100 000; машинаси бор ҳар ким — авто туркумлари учун 200 000.
 * Админ ҳар дастурни ёқади/ўчиради, миқдор, туркум тақсимоти, буюртмада улуш чегараси, муддат,
 * бюджет ва босқични (off → internal → pilot → public) белгилайди.
 *
 * ПУЛ МОДЕЛИ (эга 2026-11-02: «фойдаланувчига пул бўлиб кўринсин, тизим бонус сифатида қайд қилсин»;
 * «Хавфсизроқ ечим — маъқул»): рағбат `users.bonusBalance`га ҚЎШИЛМАЙДИ — алоҳида
 * `users.incentiveBalance` (фаол грантлар қолдиқлари йиғиндиси). Илова иккаласини битта сумма қилиб
 * кўрсатади. Ҳамёндан пул камайтирадиган 29 та мавжуд жой фақат `bonusBalance`/ledger'ни кўради —
 * рағбатни ечиб, ўтказиб ёки бошқа хизматга сарфлаб бўлмайди. Сарфлаш — фақат AVA дўкони буюртмаси
 * (2-босқич).
 *
 * Коллекциялар (ҳаммаси client-write ЁПИҚ):
 *   incentive_programs/{programId}          — дастур созламаси + counters (сервер)
 *   incentive_grants/{programId}_{uid}      — бир одамга бир дастурдан БИР грант (детерминистик ID)
 *   incentive_ledger/{type}_{grantId}[...]  — ўзгармас журнал (grant/expire/revoke/spend/refund)
 *   incentive_budget_days/{programId}_{YYYYMMDD} — кунлик бюджет ҳисоби (Тошкент куни)
 *   incentive_profiles/{uid}                — МУҲРЛАНГАН жинс ва туғилган сана (эга 2026-11-03: жинс бир
 *                                             марта, ўзгариш — админ тасдиғи билан). Биринчи марта қиймат
 *                                             пайдо бўлганда ёзилади; шартлар ШУ бўйича текширилади —
 *                                             иловани қайта ўрнатиб «аёл» деб танлаш бонус бермайди.
 *
 * Пул — бутун сўм (8-банд). Логда телефон рақам тўлиқ чиқмайди (40-банд).
 *
 * Диагностика кодлари: PHONE_REQUIRED, PROGRAM_INVALID, PROGRAM_OFF, NOT_IN_STAGE, NOT_STARTED, ENDED,
 * NOT_NEW_USER, GENDER_MISMATCH, AGE_UNKNOWN, AGE_OUT_OF_RANGE, CAR_PROFILE_REQUIRED, BUDGET_EXHAUSTED,
 * DAILY_BUDGET_EXHAUSTED, GRANT_NOT_FOUND, VALIDATION_<field>.
 */
'use strict';

const PROGRAMS = 'incentive_programs';
const GRANTS = 'incentive_grants';
const LEDGER = 'incentive_ledger';
const DAYS = 'incentive_budget_days';
const PROFILES = 'incentive_profiles';
const FROZEN_GENDERS = Object.freeze(['male', 'female']);

const STAGES = Object.freeze(['off', 'internal', 'pilot', 'public']);
const GENDERS = Object.freeze(['female', 'male', 'any']);
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const KEY_RE = /^[a-z0-9_]{2,40}$/;
const CATEGORY_RE = /^[a-z0-9_]{2,30}$/;
const ID_RE = /^[A-Za-z0-9_-]{2,60}$/;
const UID_RE = /^\d{9,15}$/;
const MAX_AMOUNT = 10000000;
const TASHKENT_OFFSET_MS = 5 * 3600 * 1000;

function vErr(field) {
  const e = new Error(`VALIDATION_${field}`);
  e.code = `VALIDATION_${field}`;
  return e;
}

function isInt(v, min, max) {
  return Number.isSafeInteger(v) && v >= min && v <= max;
}

function toMs(v) {
  if (v == null || v === '') return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'string') { const t = Date.parse(v); return Number.isFinite(t) ? t : null; }
  return null;
}

/** Тошкент куни калити: YYYYMMDD. */
function tashkentDayKey(ms) {
  const d = new Date(ms + TASHKENT_OFFSET_MS);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}${m}${day}`;
}

/**
 * Туғилган сана: илова форматлари (`parseBirthDate`, formatters.dart): `YYYY-MM-DD` ёки `D.M.YYYY`.
 * Нотўғри сана — null.
 */
function parseBirthDate(raw) {
  const s = String(raw || '').trim();
  let y; let m; let d;
  let mt = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (mt) { y = +mt[1]; m = +mt[2]; d = +mt[3]; } else {
    mt = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(s);
    if (!mt) return null;
    d = +mt[1]; m = +mt[2]; y = +mt[3];
  }
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return { y, m, d };
}

/** Тўлиқ ёш (Тошкент куни бўйича). */
function ageAt(birth, nowMs) {
  const t = new Date(nowMs + TASHKENT_OFFSET_MS);
  const ty = t.getUTCFullYear(); const tm = t.getUTCMonth() + 1; const td = t.getUTCDate();
  let age = ty - birth.y;
  if (tm < birth.m || (tm === birth.m && td < birth.d)) age -= 1;
  return age;
}

/**
 * Муҳрлаш: ҳали муҳрланмаган ва фойдаланувчида тўғри қиймати бор майдонлар (соф функция).
 * → { gender?, birthDate? } — бўш объект: ёзиш керак эмас.
 */
function frozenPatch(user, frozen) {
  const u = user || {};
  const f = frozen || {};
  const patch = {};
  if (!FROZEN_GENDERS.includes(f.gender) && FROZEN_GENDERS.includes(u.gender)) patch.gender = u.gender;
  if (!parseBirthDate(f.birthDate) && parseBirthDate(u.birthDate)) patch.birthDate = String(u.birthDate).trim();
  return patch;
}

/** Шартлар учун фойдаланувчи: муҳрланган жинс/сана устун (соф функция). */
function withFrozen(user, frozen) {
  const f = frozen || {};
  const out = { ...(user || {}) };
  if (FROZEN_GENDERS.includes(f.gender)) out.gender = f.gender;
  if (parseBirthDate(f.birthDate)) out.birthDate = String(f.birthDate).trim();
  return out;
}

/** Машина профили — `claimCarProfileBonus` билан БИР ХИЛ қоида (эга: «ҳозирги ҳолат ўзгармасин»). */
function hasCarProfile(user) {
  const u = user || {};
  const seats = parseInt(String(u.carSeats ?? 0), 10) || 0;
  return String(u.carModel || '').trim() !== ''
    && String(u.carColor || '').trim() !== ''
    && String(u.carPlate || '').trim() !== ''
    && seats > 0;
}

/** Админ киритган дастурни текшириш ва тозалаш (соф функция). */
function validateProgram(input) {
  const p = input || {};
  const key = String(p.key || '').trim();
  if (!KEY_RE.test(key)) throw vErr('key');
  const title = {};
  for (const lang of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    const t = String((p.title || {})[lang] || '').trim();
    if (t.length < 1 || t.length > 80) throw vErr(`title_${lang}`);
    title[lang] = t;
  }
  const stage = String(p.stage || 'off');
  if (!STAGES.includes(stage)) throw vErr('stage');
  const internalPhones = Array.isArray(p.internalPhones) ? p.internalPhones.map((x) => String(x).replace(/\D/g, '')) : [];
  if (internalPhones.length > 50 || internalPhones.some((x) => !UID_RE.test(x))) throw vErr('internalPhones');
  const pilotDistrictIds = Array.isArray(p.pilotDistrictIds) ? p.pilotDistrictIds.map((x) => String(x).trim()) : [];
  if (pilotDistrictIds.length > 50 || pilotDistrictIds.some((x) => !ID_RE.test(x))) throw vErr('pilotDistrictIds');

  const a = p.audience || {};
  const gender = String(a.gender || 'any');
  if (!GENDERS.includes(gender)) throw vErr('gender');
  const ageMin = a.ageMin == null ? 0 : a.ageMin;
  const ageMax = a.ageMax == null ? 120 : a.ageMax;
  if (!isInt(ageMin, 0, 120) || !isInt(ageMax, ageMin, 120)) throw vErr('age');
  const requireCar = a.requireCar === true;
  const newUsersSinceMs = toMs(a.newUsersSince);
  if (newUsersSinceMs == null) throw vErr('newUsersSince');

  const amount = p.amount;
  if (!isInt(amount, 1, MAX_AMOUNT)) throw vErr('amount');
  const buckets = Array.isArray(p.buckets) ? p.buckets : [];
  const seen = new Set();
  let sum = 0;
  const cleanBuckets = buckets.map((b) => {
    const category = String((b || {}).category || '').trim();
    const bAmount = (b || {}).amount;
    if (!CATEGORY_RE.test(category) || seen.has(category)) throw vErr('buckets');
    if (!isInt(bAmount, 1, MAX_AMOUNT)) throw vErr('buckets');
    seen.add(category);
    sum += bAmount;
    return { category, amount: bAmount };
  });
  if (cleanBuckets.length > 20) throw vErr('buckets');
  if (cleanBuckets.length && sum !== amount) throw vErr('buckets_sum');

  if (!isInt(p.maxOrderSharePct, 1, 100)) throw vErr('maxOrderSharePct');
  if (!isInt(p.validityDays, 1, 3650)) throw vErr('validityDays');
  if (!isInt(p.budgetTotal, amount, 100000000000)) throw vErr('budgetTotal');
  const budgetDaily = p.budgetDaily == null ? 0 : p.budgetDaily;
  if (!isInt(budgetDaily, 0, 100000000000)) throw vErr('budgetDaily');
  const startAtMs = toMs(p.startAt);
  const endAtMs = toMs(p.endAt);
  if (startAtMs != null && endAtMs != null && endAtMs <= startAtMs) throw vErr('endAt');

  return {
    key, title, stage, internalPhones, pilotDistrictIds,
    audience: { gender, ageMin, ageMax, requireCar, newUsersSinceMs },
    amount, buckets: cleanBuckets, maxOrderSharePct: p.maxOrderSharePct, validityDays: p.validityDays,
    budgetTotal: p.budgetTotal, budgetDaily, startAtMs, endAtMs,
  };
}

/**
 * Фойдаланувчи дастурга мос келадими (соф функция). Бюджет ва «аллақачон олган» — транзакцияда.
 * ctx: { nowMs, uid, registeredMs (Firebase Auth яратилган вақт — телефондан ўзгармайди) }.
 */
function evaluateEligibility(program, user, ctx) {
  const p = program || {};
  const u = user || {};
  const a = p.audience || {};
  const stage = p.stage || 'off';
  if (stage === 'off') return { ok: false, code: 'PROGRAM_OFF' };
  const internal = Array.isArray(p.internalPhones) && p.internalPhones.includes(ctx.uid);
  if (stage === 'internal' && !internal) return { ok: false, code: 'NOT_IN_STAGE' };
  if (stage === 'pilot' && !internal) {
    const district = String(u.districtId || '').trim();
    if (!district || !(p.pilotDistrictIds || []).includes(district)) return { ok: false, code: 'NOT_IN_STAGE' };
  }
  const startAtMs = toMs(p.startAt);
  const endAtMs = toMs(p.endAt);
  if (startAtMs != null && ctx.nowMs < startAtMs) return { ok: false, code: 'NOT_STARTED' };
  if (endAtMs != null && ctx.nowMs >= endAtMs) return { ok: false, code: 'ENDED' };
  const since = toMs(a.newUsersSince);
  if (since == null || ctx.registeredMs == null || ctx.registeredMs < since) return { ok: false, code: 'NOT_NEW_USER' };
  if (a.gender && a.gender !== 'any' && String(u.gender || '') !== a.gender) return { ok: false, code: 'GENDER_MISMATCH' };
  const needAge = (a.ageMin || 0) > 0 || (a.ageMax != null && a.ageMax < 120);
  if (needAge) {
    const birth = parseBirthDate(u.birthDate);
    if (!birth) return { ok: false, code: 'AGE_UNKNOWN' };
    const age = ageAt(birth, ctx.nowMs);
    if (age < (a.ageMin || 0) || age > (a.ageMax == null ? 120 : a.ageMax)) return { ok: false, code: 'AGE_OUT_OF_RANGE' };
  }
  if (a.requireCar === true && !hasCarProfile(u)) return { ok: false, code: 'CAR_PROFILE_REQUIRED' };
  return { ok: true };
}

function grantIdOf(programId, uid) {
  return `${programId}_${uid}`;
}

// ── AVA дўкони буюртмасида сарфлаш (2-босқич) ─────────────────────────────────
// Қоида (эга 2026-11-02 қарорлари асосида):
//  • рағбат фақат МАҲСУЛОТ суммасини қоплайди (етказиш ҳақи — ҳамён/нақд);
//  • ҳар грант ўз `maxOrderSharePct` чегарасидан ошмайди (ўзи қоплай оладиган туркумлар
//    суммасининг фоизи) ва ўз туркум қолдиқларидан;
//  • бир қатор суммасини фақат бир марта қоплаш мумкин; муддати яқинроқ грант биринчи;
//  • туркумсиз маҳсулот — `general` (фақат «any» грант қоплайди).
// Натижа буюртма суммасини КАМАЙТИРАДИ (`total` = нетто) — курьер/касса/чек ўзгаришсиз тўғри ишлайди.

const BUCKET_ANY = 'any';

function normCategory(c) {
  const s = String(c || '').trim().toLowerCase();
  return CATEGORY_RE.test(s) ? s : 'general';
}

/**
 * Соф функция. grants: [{id, programId, remaining, buckets:{k:int}, maxOrderSharePct, expiresAtMs}],
 * lines: [{category, total}] → { total, perGrant:[{grantId, programId, amount, byBucket}], itemsTotal }.
 */
function computeIncentivePlan(grants, lines, nowMs) {
  const lineAvail = {};
  const lineBase = {};
  let itemsTotal = 0;
  for (const l of lines || []) {
    const c = normCategory(l && l.category);
    const t = Math.max(0, Math.trunc(Number(l && l.total) || 0));
    lineAvail[c] = (lineAvail[c] || 0) + t;
    lineBase[c] = (lineBase[c] || 0) + t;
    itemsTotal += t;
  }
  const active = (grants || [])
    .filter((g) => Number.isSafeInteger(g.remaining) && g.remaining > 0 && g.expiresAtMs != null && g.expiresAtMs > nowMs)
    .sort((a, b) => (a.expiresAtMs - b.expiresAtMs) || String(a.id).localeCompare(String(b.id)));
  const perGrant = [];
  let total = 0;
  for (const g of active) {
    const pct = Math.min(100, Math.max(1, Math.trunc(Number(g.maxOrderSharePct) || 0)));
    const keys = Object.keys(g.buckets || {})
      .filter((k) => Number.isSafeInteger(g.buckets[k]) && g.buckets[k] > 0)
      .sort((a, b) => Number(a === BUCKET_ANY) - Number(b === BUCKET_ANY));
    if (!keys.length) continue;
    const coversAll = keys.includes(BUCKET_ANY);
    const cats = coversAll ? Object.keys(lineBase) : keys.filter((k) => lineBase[k] > 0);
    const base = cats.reduce((s, c) => s + (lineBase[c] || 0), 0);
    let capLeft = Math.min(Math.floor(base * pct / 100), g.remaining);
    if (capLeft <= 0) continue;
    const byBucket = {};
    let used = 0;
    for (const k of keys) {
      let bucketLeft = g.buckets[k];
      const targets = k === BUCKET_ANY ? Object.keys(lineAvail).sort() : [k];
      for (const c of targets) {
        if (capLeft <= 0 || bucketLeft <= 0) break;
        const take = Math.min(capLeft, bucketLeft, lineAvail[c] || 0);
        if (take <= 0) continue;
        lineAvail[c] -= take;
        capLeft -= take;
        bucketLeft -= take;
        used += take;
        byBucket[k] = (byBucket[k] || 0) + take;
      }
    }
    if (used > 0) {
      perGrant.push({ grantId: g.id, programId: g.programId, amount: used, byBucket });
      total += used;
    }
  }
  return { total, perGrant, itemsTotal };
}

function grantFromDoc(d) {
  const x = d.data() || {};
  const buckets = {};
  Object.entries(x.buckets || {}).forEach(([k, v]) => { if (Number.isSafeInteger(v)) buckets[k] = v; });
  return {
    id: d.id, ref: d.ref, programId: x.programId, uid: x.uid, status: x.status,
    remaining: Number.isSafeInteger(x.remaining) ? x.remaining : 0, buckets,
    maxOrderSharePct: x.maxOrderSharePct, expiresAtMs: toMs(x.expiresAt),
  };
}

/** Транзакция ичида (ЁЗИШДАН ОЛДИН): фойдаланувчининг фаол грантлари. */
async function readActiveGrantsInTx(t, db, uid) {
  const snap = await t.get(db.collection(GRANTS).where('uid', '==', uid).where('status', '==', 'active'));
  return snap.docs.map(grantFromDoc);
}

/** Режани ёзиш: грант қолдиқлари, users.incentiveBalance, дастур counters, ўзгармас журнал. */
function applyIncentiveSpendInTx(t, db, admin, { uid, grants, plan, orderId }) {
  if (!plan || plan.total <= 0) return;
  const FieldValue = admin.firestore.FieldValue;
  for (const pg of plan.perGrant) {
    const g = grants.find((x) => x.id === pg.grantId);
    if (!g) throw new Error(`incentive grant missing ${pg.grantId}`);
    const remaining = g.remaining - pg.amount;
    if (remaining < 0) throw new Error('incentive overspend');
    const buckets = { ...g.buckets };
    Object.entries(pg.byBucket).forEach(([k, v]) => { buckets[k] = (buckets[k] || 0) - v; });
    t.update(g.ref, { remaining, buckets, status: remaining > 0 ? 'active' : 'spent', updatedAt: FieldValue.serverTimestamp() });
    t.update(db.collection(PROGRAMS).doc(pg.programId), { 'counters.spentAmount': FieldValue.increment(pg.amount) });
    t.create(db.collection(LEDGER).doc(`spend_${orderId}_${pg.grantId}`), {
      type: 'spend', uid, programId: pg.programId, grantId: pg.grantId, amount: pg.amount,
      byBucket: pg.byBucket, orderId, actor: uid, at: FieldValue.serverTimestamp(),
    });
  }
  t.update(db.collection('users').doc(uid), {
    incentiveBalance: FieldValue.increment(-plan.total), incentiveUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/** Бекор қилишда (ЎҚИШ босқичи): буюртмада ишлатилган грантлар. */
async function prepareIncentiveRefundInTx(t, db, orderId, od) {
  const applied = Number.isSafeInteger(od && od.incentiveApplied) ? od.incentiveApplied : 0;
  const list = Array.isArray(od && od.incentiveGrants) ? od.incentiveGrants : [];
  const uid = String((od && od.incentiveUid) || '');
  if (applied <= 0 || !list.length || !UID_RE.test(uid)) return null;
  const entries = [];
  for (const pg of list) {
    if (!pg || !pg.grantId || !Number.isSafeInteger(pg.amount) || pg.amount <= 0) continue;
    const ref = db.collection(GRANTS).doc(String(pg.grantId));
    const ledgerRef = db.collection(LEDGER).doc(`refund_${orderId}_${pg.grantId}`);
    const [snap, ledgerSnap] = await Promise.all([t.get(ref), t.get(ledgerRef)]);
    entries.push({ pg, ref, snap, ledgerRef, done: ledgerSnap.exists });
  }
  return { uid, orderId, entries };
}

/**
 * Бекор қилишда (ЁЗИШ босқичи). Грант фаол/сарфланган ва муддати ўтмаган — қолдиқ ва туркумлар
 * тикланади; муддати ўтган/бекор қилинган — қайтарилмайди (журналда `refund_forfeit`). Идемпотент.
 * → ҳақиқатда тикланган сумма.
 */
function commitIncentiveRefundInTx(t, db, admin, ctx, { actor, nowMs }) {
  if (!ctx) return 0;
  const FieldValue = admin.firestore.FieldValue;
  let restored = 0;
  for (const e of ctx.entries) {
    if (e.done) continue;
    const g = e.snap.exists ? e.snap.data() : null;
    const exp = g ? toMs(g.expiresAt) : null;
    const ok = g && (g.status === 'active' || g.status === 'spent') && exp != null && exp > nowMs;
    if (ok) {
      const buckets = { ...(g.buckets || {}) };
      Object.entries(e.pg.byBucket || {}).forEach(([k, v]) => {
        if (Number.isSafeInteger(v)) buckets[k] = (Number.isSafeInteger(buckets[k]) ? buckets[k] : 0) + v;
      });
      t.update(e.ref, {
        remaining: (Number.isSafeInteger(g.remaining) ? g.remaining : 0) + e.pg.amount,
        buckets, status: 'active', updatedAt: FieldValue.serverTimestamp(),
      });
      t.update(db.collection(PROGRAMS).doc(e.pg.programId), { 'counters.spentAmount': FieldValue.increment(-e.pg.amount) });
      restored += e.pg.amount;
    } else if (g) {
      t.update(db.collection(PROGRAMS).doc(e.pg.programId), {
        'counters.spentAmount': FieldValue.increment(-e.pg.amount),
        'counters.expiredAmount': FieldValue.increment(e.pg.amount),
      });
    }
    t.create(e.ledgerRef, {
      type: ok ? 'refund' : 'refund_forfeit', uid: ctx.uid, programId: e.pg.programId, grantId: e.pg.grantId,
      amount: e.pg.amount, byBucket: e.pg.byBucket || {}, orderId: ctx.orderId, actor, at: FieldValue.serverTimestamp(),
    });
  }
  if (restored > 0) {
    t.update(db.collection('users').doc(ctx.uid), {
      incentiveBalance: FieldValue.increment(restored), incentiveUpdatedAt: FieldValue.serverTimestamp(),
    });
  }
  return restored;
}

function attachIncentives(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const FieldValue = admin.firestore.FieldValue;
  const Timestamp = admin.firestore.Timestamp;
  const ts = () => FieldValue.serverTimestamp();
  const fail = (status, code) => new HttpsError(status, code, { code });
  const mask = (p) => `***${String(p || '').slice(-4)}`;
  const log = (o) => console.log(JSON.stringify({ module: 'incentives', ...o }));

  function requireUser(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!UID_RE.test(uid)) throw fail('unauthenticated', 'PHONE_REQUIRED');
    return uid;
  }

  /** Рўйхатдан ўтган вақт — Firebase Auth (сервер манбаси). Олиб бўлмаса — null (янги деб ҳисобланмайди). */
  async function registeredMsOf(context) {
    try {
      const rec = await admin.auth().getUser(context.auth.uid);
      const t = Date.parse(rec.metadata && rec.metadata.creationTime);
      return Number.isFinite(t) ? t : null;
    } catch (e) {
      log({ action: 'registeredMs', result: 'error', message: String(e && e.message).slice(0, 120) });
      return null;
    }
  }

  function programPublicView(id, p) {
    return {
      programId: id, key: p.key, title: p.title || {}, amount: p.amount,
      buckets: p.buckets || [], maxOrderSharePct: p.maxOrderSharePct, validityDays: p.validityDays,
      requireCar: (p.audience || {}).requireCar === true,
    };
  }

  /**
   * Менга тегишли таклифлар (илова табриклаш/таклиф ойнаси учун). Ёпиқ (off) дастурлар қайтмайди.
   * `needsCar` — фақат машина профили етишмайди (бошқа шартлар мос): «Машинангизни киритинг» таклифи.
   */
  exportsObj.getMyIncentiveOffers = functions.https.onCall(async (data, context) => {
    const uid = requireUser(context);
    const profRef = db.collection(PROFILES).doc(uid);
    const [progSnap, userSnap, registeredMs, profSnap] = await Promise.all([
      db.collection(PROGRAMS).where('stage', 'in', ['internal', 'pilot', 'public']).get(),
      db.collection('users').doc(uid).get(),
      registeredMsOf(context),
      profRef.get(),
    ]);
    const rawUser = userSnap.exists ? userSnap.data() : {};
    // Рўйхатдан кейинги биринчи чақирувда жинс/сана муҳрланади (бир марта; кейин ўзгармайди).
    const frozen = profSnap.exists ? profSnap.data() : {};
    const patch = frozenPatch(rawUser, frozen);
    if (Object.keys(patch).length) {
      await profRef.set({ uid, ...patch, updatedAt: ts(), ...(profSnap.exists ? {} : { createdAt: ts() }) }, { merge: true });
    }
    const user = withFrozen(rawUser, { ...frozen, ...patch });
    const nowMs = Date.now();
    const offers = [];
    for (const d of progSnap.docs) {
      const p = d.data();
      const grantSnap = await db.collection(GRANTS).doc(grantIdOf(d.id, uid)).get();
      if (grantSnap.exists) {
        const g = grantSnap.data();
        offers.push({ ...programPublicView(d.id, p), claimed: true, remaining: g.remaining || 0, status: g.status });
        continue;
      }
      const el = evaluateEligibility(p, user, { nowMs, uid, registeredMs });
      if (el.ok) offers.push({ ...programPublicView(d.id, p), claimed: false, eligible: true });
      else if (el.code === 'CAR_PROFILE_REQUIRED') offers.push({ ...programPublicView(d.id, p), claimed: false, eligible: false, needsCar: true });
    }
    return { ok: true, offers, incentiveBalance: Number.isSafeInteger(user.incentiveBalance) ? user.incentiveBalance : 0 };
  });

  /** data: { programId } → { ok, grantId, amount, duplicate }. Идемпотент; бюджет транзакцияда. */
  exportsObj.claimIncentive = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const programId = String((data && data.programId) || '').trim();
    if (!ID_RE.test(programId)) throw fail('invalid-argument', 'PROGRAM_INVALID');
    const registeredMs = await registeredMsOf(context);
    const grantId = grantIdOf(programId, uid);
    const progRef = db.collection(PROGRAMS).doc(programId);
    const grantRef = db.collection(GRANTS).doc(grantId);
    const userRef = db.collection('users').doc(uid);
    const profRef = db.collection(PROFILES).doc(uid);

    const out = await db.runTransaction(async (t) => {
      const nowMs = Date.now();
      const dayRef = db.collection(DAYS).doc(`${programId}_${tashkentDayKey(nowMs)}`);
      const [progSnap, grantSnap, userSnap, daySnap, profSnap] = await Promise.all([
        t.get(progRef), t.get(grantRef), t.get(userRef), t.get(dayRef), t.get(profRef),
      ]);
      if (grantSnap.exists) return { duplicate: true, amount: grantSnap.data().amount };
      if (!progSnap.exists) throw fail('not-found', 'PROGRAM_INVALID');
      if (!userSnap.exists) throw fail('failed-precondition', 'PHONE_REQUIRED');
      const p = progSnap.data();
      const frozen = profSnap.exists ? profSnap.data() : {};
      const patch = frozenPatch(userSnap.data(), frozen);
      const el = evaluateEligibility(p, withFrozen(userSnap.data(), { ...frozen, ...patch }), { nowMs, uid, registeredMs });
      if (!el.ok) {
        // Рад этилса ҳам муҳр ёзилади (кейинги уринишда жинсни алмаштириш ёрдам бермасин).
        if (Object.keys(patch).length) t.set(profRef, { uid, ...patch, updatedAt: ts() }, { merge: true });
        return { rejected: el.code };
      }
      if (Object.keys(patch).length) t.set(profRef, { uid, ...patch, updatedAt: ts() }, { merge: true });
      const counters = p.counters || {};
      const granted = Number.isSafeInteger(counters.grantedAmount) ? counters.grantedAmount : 0;
      if (granted + p.amount > p.budgetTotal) throw fail('resource-exhausted', 'BUDGET_EXHAUSTED');
      const dayUsed = daySnap.exists && Number.isSafeInteger(daySnap.data().grantedAmount) ? daySnap.data().grantedAmount : 0;
      if (p.budgetDaily > 0 && dayUsed + p.amount > p.budgetDaily) throw fail('resource-exhausted', 'DAILY_BUDGET_EXHAUSTED');

      const buckets = {};
      if (Array.isArray(p.buckets) && p.buckets.length) p.buckets.forEach((b) => { buckets[b.category] = b.amount; });
      else buckets.any = p.amount;
      const expiresAt = Timestamp.fromMillis(nowMs + p.validityDays * 86400000);
      t.create(grantRef, {
        uid, programId, programKey: p.key, amount: p.amount, remaining: p.amount, buckets,
        maxOrderSharePct: p.maxOrderSharePct, status: 'active', expiresAt,
        createdAt: ts(), updatedAt: ts(),
      });
      t.update(userRef, { incentiveBalance: FieldValue.increment(p.amount), incentiveUpdatedAt: ts() });
      t.update(progRef, {
        'counters.grantedAmount': FieldValue.increment(p.amount),
        'counters.grantedCount': FieldValue.increment(1),
        updatedAt: ts(),
      });
      t.set(dayRef, { programId, day: tashkentDayKey(nowMs), grantedAmount: FieldValue.increment(p.amount), updatedAt: ts() }, { merge: true });
      t.create(db.collection(LEDGER).doc(`grant_${grantId}`), {
        type: 'grant', uid, programId, grantId, amount: p.amount, buckets, actor: uid, at: ts(),
      });
      return { duplicate: false, amount: p.amount };
    });
    if (out.rejected) {
      log({ action: 'claimIncentive', userId: mask(uid), programId, result: 'rejected', errorCode: out.rejected, durationMs: Date.now() - started });
      throw fail('failed-precondition', out.rejected);
    }
    log({ action: 'claimIncentive', userId: mask(uid), programId, result: out.duplicate ? 'duplicate' : 'granted', amount: out.amount, durationMs: Date.now() - started });
    return { ok: true, grantId, amount: out.amount, duplicate: out.duplicate };
  });

  async function requireAdmin(context) {
    return requireCallerRoles(context, ADMIN_ROLES, 'Admin only');
  }

  /** data: { programId?, ...program } → { ok, programId, created }. counters ўзгармайди. */
  exportsObj.adminUpsertIncentiveProgram = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    let clean;
    try {
      clean = validateProgram(data || {});
    } catch (e) {
      throw fail('invalid-argument', e.code || 'VALIDATION');
    }
    const reqId = String((data && data.programId) || '').trim();
    if (reqId && !ID_RE.test(reqId)) throw fail('invalid-argument', 'PROGRAM_INVALID');
    const ref = reqId ? db.collection(PROGRAMS).doc(reqId) : db.collection(PROGRAMS).doc(clean.key);
    const doc = {
      key: clean.key, title: clean.title, stage: clean.stage,
      internalPhones: clean.internalPhones, pilotDistrictIds: clean.pilotDistrictIds,
      audience: {
        gender: clean.audience.gender, ageMin: clean.audience.ageMin, ageMax: clean.audience.ageMax,
        requireCar: clean.audience.requireCar, newUsersSince: Timestamp.fromMillis(clean.audience.newUsersSinceMs),
      },
      amount: clean.amount, buckets: clean.buckets, maxOrderSharePct: clean.maxOrderSharePct,
      validityDays: clean.validityDays, budgetTotal: clean.budgetTotal, budgetDaily: clean.budgetDaily,
      startAt: clean.startAtMs == null ? null : Timestamp.fromMillis(clean.startAtMs),
      endAt: clean.endAtMs == null ? null : Timestamp.fromMillis(clean.endAtMs),
      updatedAt: ts(), updatedBy: actor,
    };
    const created = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (snap.exists) {
        const prev = snap.data();
        // Бюджетни берилгандан камайтириб бўлмайди.
        const granted = ((prev.counters || {}).grantedAmount) || 0;
        if (clean.budgetTotal < granted) throw fail('invalid-argument', 'VALIDATION_budgetTotal_below_granted');
        t.update(ref, { ...doc, version: FieldValue.increment(1) });
      } else {
        t.create(ref, {
          ...doc, version: 1, createdAt: ts(), createdBy: actor,
          counters: { grantedAmount: 0, grantedCount: 0, spentAmount: 0, expiredAmount: 0, revokedAmount: 0 },
        });
      }
      t.create(db.collection('admin_audit').doc(), {
        action: snap.exists ? 'incentiveProgramUpdate' : 'incentiveProgramCreate',
        programId: ref.id, actor, stage: clean.stage, amount: clean.amount,
        budgetTotal: clean.budgetTotal, at: ts(),
      });
      return !snap.exists;
    });
    log({ action: 'adminUpsertIncentiveProgram', programId: ref.id, actor: mask(actor), created });
    return { ok: true, programId: ref.id, created };
  });

  /**
   * data: { uid } — админ жинс/туғилган сана ўзгаришини ТАСДИҚЛАГАНДАН кейин муҳрни users ҳужжатидаги
   * янги қийматга алмаштириш («Админ тасдиқлари» экрани чақиради). Аудит: admin_audit.
   */
  exportsObj.adminResyncIncentiveProfile = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, [...ADMIN_ROLES, 'dispatcher'], 'Admin only');
    const uid = String((data && data.uid) || '').replace(/\D/g, '');
    if (!UID_RE.test(uid)) throw fail('invalid-argument', 'PHONE_REQUIRED');
    const userRef = db.collection('users').doc(uid);
    const profRef = db.collection(PROFILES).doc(uid);
    const out = await db.runTransaction(async (t) => {
      const [userSnap, profSnap] = await Promise.all([t.get(userRef), t.get(profRef)]);
      if (!userSnap.exists) throw fail('not-found', 'USER_NOT_FOUND');
      const u = userSnap.data();
      const prev = profSnap.exists ? profSnap.data() : {};
      const next = {};
      if (FROZEN_GENDERS.includes(u.gender)) next.gender = u.gender;
      if (parseBirthDate(u.birthDate)) next.birthDate = String(u.birthDate).trim();
      t.set(profRef, { uid, ...next, updatedAt: ts(), resyncedBy: actor }, { merge: true });
      t.create(db.collection('admin_audit').doc(), {
        action: 'incentiveProfileResync', userId: uid, actor, at: ts(),
        from: { gender: prev.gender || '', birthDate: prev.birthDate || '' },
        to: { gender: next.gender || '', birthDate: next.birthDate || '' },
      });
      return next;
    });
    log({ action: 'adminResyncIncentiveProfile', userId: mask(uid), actor: mask(actor), result: 'ok' });
    return { ok: true, gender: out.gender || '', birthDate: out.birthDate || '' };
  });

  /** data: { programId, stage } — тез ёқиш/ўчириш. */
  exportsObj.adminSetIncentiveStage = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const programId = String((data && data.programId) || '').trim();
    const stage = String((data && data.stage) || '');
    if (!ID_RE.test(programId)) throw fail('invalid-argument', 'PROGRAM_INVALID');
    if (!STAGES.includes(stage)) throw fail('invalid-argument', 'VALIDATION_stage');
    const ref = db.collection(PROGRAMS).doc(programId);
    await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'PROGRAM_INVALID');
      t.update(ref, { stage, updatedAt: ts(), updatedBy: actor });
      t.create(db.collection('admin_audit').doc(), {
        action: 'incentiveStage', programId, actor, from: snap.data().stage || 'off', to: stage, at: ts(),
      });
    });
    log({ action: 'adminSetIncentiveStage', programId, stage, actor: mask(actor) });
    return { ok: true };
  });

  /** Грантни бекор қилиш (сохта ҳисоб ва ҳ.к.): қолдиқ фойдаланувчидан олинади. data: { grantId, reason }. */
  exportsObj.adminRevokeIncentiveGrant = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const grantId = String((data && data.grantId) || '').trim();
    const reason = String((data && data.reason) || '').trim().slice(0, 300);
    if (!/^[A-Za-z0-9_-]{2,60}_\d{9,15}$/.test(grantId)) throw fail('invalid-argument', 'GRANT_NOT_FOUND');
    if (reason.length < 3) throw fail('invalid-argument', 'VALIDATION_reason');
    const grantRef = db.collection(GRANTS).doc(grantId);
    const out = await db.runTransaction(async (t) => {
      const g = await t.get(grantRef);
      if (!g.exists) throw fail('not-found', 'GRANT_NOT_FOUND');
      const gd = g.data();
      if (gd.status !== 'active') return { changed: false, amount: 0 };
      const rem = Number.isSafeInteger(gd.remaining) ? gd.remaining : 0;
      const zero = {};
      Object.keys(gd.buckets || {}).forEach((k) => { zero[k] = 0; });
      t.update(grantRef, { status: 'revoked', remaining: 0, buckets: zero, revokedBy: actor, revokeReason: reason, updatedAt: ts() });
      if (rem > 0) {
        t.update(db.collection('users').doc(gd.uid), { incentiveBalance: FieldValue.increment(-rem), incentiveUpdatedAt: ts() });
        t.update(db.collection(PROGRAMS).doc(gd.programId), { 'counters.revokedAmount': FieldValue.increment(rem), updatedAt: ts() });
      }
      t.create(db.collection(LEDGER).doc(`revoke_${grantId}`), {
        type: 'revoke', uid: gd.uid, programId: gd.programId, grantId, amount: rem, actor, reason, at: ts(),
      });
      t.create(db.collection('admin_audit').doc(), {
        action: 'incentiveRevoke', grantId, programId: gd.programId, actor, amount: rem, reason, at: ts(),
      });
      return { changed: true, amount: rem };
    });
    log({ action: 'adminRevokeIncentiveGrant', grantId: grantId.replace(/\d{5}(\d{4})$/, '*****$1'), actor: mask(actor), ...out });
    return { ok: true, ...out };
  });

  /** Бир грантнинг муддатини ёпиш (транзакция; қайта чақирилса — ўзгармайди). */
  async function expireGrant(grantRef, nowMs) {
    return db.runTransaction(async (t) => {
      const g = await t.get(grantRef);
      if (!g.exists) return 0;
      const gd = g.data();
      const exp = toMs(gd.expiresAt);
      if (gd.status !== 'active' || exp == null || exp > nowMs) return 0;
      const rem = Number.isSafeInteger(gd.remaining) ? gd.remaining : 0;
      const zero = {};
      Object.keys(gd.buckets || {}).forEach((k) => { zero[k] = 0; });
      t.update(grantRef, { status: 'expired', remaining: 0, buckets: zero, updatedAt: ts() });
      if (rem > 0) {
        t.update(db.collection('users').doc(gd.uid), { incentiveBalance: FieldValue.increment(-rem), incentiveUpdatedAt: ts() });
        t.update(db.collection(PROGRAMS).doc(gd.programId), { 'counters.expiredAmount': FieldValue.increment(rem), updatedAt: ts() });
      }
      t.create(db.collection(LEDGER).doc(`expire_${grantRef.id}`), {
        type: 'expire', uid: gd.uid, programId: gd.programId, grantId: grantRef.id, amount: rem, actor: 'system', at: ts(),
      });
      return rem;
    });
  }

  async function runExpirySweep(nowMs, maxBatches = 20) {
    let expired = 0; let amount = 0;
    for (let i = 0; i < maxBatches; i++) {
      const snap = await db.collection(GRANTS)
        .where('status', '==', 'active')
        .where('expiresAt', '<=', Timestamp.fromMillis(nowMs))
        .orderBy('expiresAt', 'asc')
        .limit(100)
        .get();
      if (snap.empty) break;
      for (const d of snap.docs) {
        const rem = await expireGrant(d.ref, nowMs);
        expired += 1; amount += rem;
      }
      if (snap.size < 100) break;
    }
    return { expired, amount };
  }

  /**
   * Саватча учун олдиндан ҳисоб (ёзув йўқ): data { items:[{productId, qty}], pricingVersion } →
   * { ok, incentiveTotal, itemsTotal, perGrant }. Буюртмадаги ҳисоб билан БИР функция ([computeIncentivePlan]).
   */
  exportsObj.previewIncentiveForOrder = functions.https.onCall(async (data, context) => {
    const uid = requireUser(context);
    const reprice = deps.repricePlatformOrderFromCatalog;
    if (typeof reprice !== 'function') throw fail('failed-precondition', 'PREVIEW_UNAVAILABLE');
    const priced = await reprice(data && data.items, data && data.pricingVersion);
    const snap = await db.collection(GRANTS).where('uid', '==', uid).where('status', '==', 'active').get();
    const plan = computeIncentivePlan(snap.docs.map(grantFromDoc),
      priced.items.map((it) => ({ category: it.incentiveCategory, total: it.total })), Date.now());
    return {
      ok: true, incentiveTotal: plan.total, itemsTotal: plan.itemsTotal,
      perGrant: plan.perGrant.map((p) => ({ programId: p.programId, amount: p.amount, byBucket: p.byBucket })),
    };
  });

  exportsObj.incentiveExpirySweep = functions.pubsub
    .schedule('every day 03:10').timeZone('Asia/Tashkent')
    .onRun(async () => {
      const res = await runExpirySweep(Date.now());
      log({ action: 'incentiveExpirySweep', ...res });
      return null;
    });

  return { runExpirySweep, expireGrant };
}

module.exports = {
  attachIncentives, validateProgram, evaluateEligibility, parseBirthDate, ageAt, hasCarProfile,
  frozenPatch, withFrozen,
  tashkentDayKey, grantIdOf, STAGES,
  computeIncentivePlan, normCategory, readActiveGrantsInTx, applyIncentiveSpendInTx,
  prepareIncentiveRefundInTx, commitIncentiveRefundInTx,
};
