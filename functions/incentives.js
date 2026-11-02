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
    const [progSnap, userSnap, registeredMs] = await Promise.all([
      db.collection(PROGRAMS).where('stage', 'in', ['internal', 'pilot', 'public']).get(),
      db.collection('users').doc(uid).get(),
      registeredMsOf(context),
    ]);
    const user = userSnap.exists ? userSnap.data() : {};
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

    const out = await db.runTransaction(async (t) => {
      const nowMs = Date.now();
      const dayRef = db.collection(DAYS).doc(`${programId}_${tashkentDayKey(nowMs)}`);
      const [progSnap, grantSnap, userSnap, daySnap] = await Promise.all([
        t.get(progRef), t.get(grantRef), t.get(userRef), t.get(dayRef),
      ]);
      if (grantSnap.exists) return { duplicate: true, amount: grantSnap.data().amount };
      if (!progSnap.exists) throw fail('not-found', 'PROGRAM_INVALID');
      if (!userSnap.exists) throw fail('failed-precondition', 'PHONE_REQUIRED');
      const p = progSnap.data();
      const el = evaluateEligibility(p, userSnap.data(), { nowMs, uid, registeredMs });
      if (!el.ok) throw fail('failed-precondition', el.code);
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
  tashkentDayKey, grantIdOf, STAGES,
};
