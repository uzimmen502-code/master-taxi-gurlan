/**
 * Оила боғланиши ЎЗАРО тасдиқ билан + бонус (эга 2026-11-28, G/H/I/J).
 *
 * Турмуш ўртоғи ва яқин қариндошлар (ота, она, ака-ука, опа-сингил; тескариси — ўғил/қиз) фақат ИККИНЧИ томон
 * (AVA фойдаланувчиси, телефон: +998XXXXXXXXX ва эски 9 хонали ҳужжат) тасдиқласа боғланади. Манзил бўйича
 * БОҒЛАНМАЙДИ. Оилавий ҳолат ҳеч қаерда сақланмайди (фақат тасдиқланган боғланишлар).
 *
 * Бонус — мавжуд рағбат тизими (`incentive_programs` / `incentive_grants` / `incentive_ledger` /
 * `users.incentiveBalance`, incentives.js; супермаркет туркуми — байрам саватчаси буюртмаларида ҳам):
 *   - `spouse_link`  — ҳар бир шахсга умрбод БИР марта (грант id: spouse_link_<personKey>);
 *   - `relative_link` — ҳар бир тасдиқланган жуфтлик учун ҲАР ИККИ томонга бир марта
 *     (грант id: relative_link_<personKey>_<pairKey>, pairKey = тартибланган personKey'лар).
 *   Дастур ҳужжати йўқ / stage OFF — грант йўқ (сукут OFF). Сумма/муддат/min/бюджет/чегаралар — админ
 *   (`adminUpsertFamilyBonusProgram`, admin_audit). Ажратиш (unlink) бонусни қайтариб ОЛМАЙДИ, қайта БЕРИЛМАЙДИ.
 *   Эски «3 қариндош → 10 000» (`relatives_birthdays`) ЎЧИРИЛДИ (holiday.js) — мавжуд грантлар сарфланаверади.
 *
 * Коллекциялар (фақат CF; rules йўқ = мижоз учун ёпиқ):
 *   family_invites/{fromKey}_{toKey}  — {kind, relation, reverse, fromKey, toKey, fromUid, toUid|null, name, birthDate,
 *                                         personId, fromName, status pending|accepted|declined|cancelled, ...}
 *   family_links/{pairKey}            — {keys[2], kind, rel{<key>: менга нисбатан у ким}, status active|unlinked, ...}
 *   family_link_state/{personKey}     — {spousePair, parents, siblings, children, day, spouseInvites, relInvites}
 */
'use strict';

const sm = require('./supermarket');
const inc = require('./incentives');
const { normalizeLang } = require('./notif_i18n');

const MODULE = 'family_links';
const INVITES = 'family_invites';
const LINKS = 'family_links';
const STATE = 'family_link_state';
const ADMIN_AUDIT = 'admin_audit';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const STAGES = sm.STAGES;
const DAY_MS = 86400000;
const TZ_OFFSET_MS = 5 * 3600000;
const BUCKET = 'supermarket';

const SPOUSE_PROGRAM = 'spouse_link';
const RELATIVE_PROGRAM = 'relative_link';
const PROGRAMS = Object.freeze([SPOUSE_PROGRAM, RELATIVE_PROGRAM]);

/** Чегаралар (PROPOSED сукут; эга 2026-11-28: ака-ука/опа-сингил ≤15, ота-она ≤2) — дастурда `maxParents`/`maxSiblings`. */
const DEFAULT_MAX_PARENTS = 2;
const DEFAULT_MAX_SIBLINGS = 15;
const DEFAULT_MAX_CHILDREN = 30; // PROPOSED: тескари (ўғил/қиз) — суиистеъмолга қарши юқори чегара
/** Таклифлар/кун (PROPOSED; эга: «масалан 3/кун» турмуш ўртоғи учун). */
const SPOUSE_INVITES_PER_DAY = 3;
const RELATIVE_INVITES_PER_DAY = 10;

const RELATIONS = Object.freeze(['spouse', 'father', 'mother', 'brother', 'sister', 'son', 'daughter', 'child', 'sibling']);
/** Таклиф қилишда танланадиган (мижоз): турмуш ўртоғи + бир оила. */
const INVITE_RELATIONS = Object.freeze(['spouse', 'father', 'mother', 'brother', 'sister', 'son', 'daughter']);
const NAME_MAX = 60;

const TEXT = Object.freeze({
  INVALID_REQUEST: ['Маълумот нотўғри.', "Ma'lumot notöğri.", 'Неверные данные.'],
  UNAUTHENTICATED: ['Ҳисобга киринг.', 'Hisobga kiring.', 'Войдите в аккаунт.'],
  PERMISSION_DENIED: ['Рухсат йўқ.', "Ruxsat yöq.", 'Нет доступа.'],
  PHONE_INVALID: ['Телефон рақами нотўғри.', "Telefon raqami notöğri.", 'Неверный номер телефона.'],
  SELF_INVITE: ['Ўзингизни таклиф қила олмайсиз.', "Özingizni taklif qila olmaysiz.", 'Нельзя пригласить себя.'],
  SPOUSE_EXISTS: ['Сизда тасдиқланган турмуш ўртоғи бор. Аввал ажратинг.', "Sizda tasdiqlangan turmuş örtoği bor. Avval ajrating.", 'У вас уже есть подтверждённый супруг(а). Сначала отвяжите.'],
  ALREADY_LINKED: ['Бу одам билан аллақачон боғлангансиз.', "Bu odam bilan allaqaçon boğlangansiz.", 'Вы уже связаны с этим человеком.'],
  RATE_LIMITED: ['Бугун таклифлар чегараси тугади. Эртага уриниб кўринг.', "Bugun takliflar çegarasi tugadi. Ertaga urinib köring.", 'Лимит приглашений на сегодня исчерпан. Попробуйте завтра.'],
  CAP_REACHED: ['Бу турдаги қариндошлар чегарасига етилди.', "Bu turdagi qarindoşlar çegarasiga yetildi.", 'Достигнут лимит родственников этого типа.'],
  INVITE_NOT_FOUND: ['Таклиф топилмади.', 'Taklif topilmadi.', 'Приглашение не найдено.'],
  INVITE_CLOSED: ['Бу таклиф аллақачон кўриб чиқилган.', "Bu taklif allaqaçon körib çiqilgan.", 'Это приглашение уже рассмотрено.'],
  SPOUSE_TAKEN: ['Боғлаб бўлмади: турмуш ўртоғи аллақачон тасдиқланган.', "Bogğlab bölmadi: turmuş örtoği allaqaçon tasdiqlangan.", 'Не удалось связать: супруг(а) уже подтверждён(а).'],
  LINK_NOT_FOUND: ['Боғланиш топилмади.', "Bogğlaniş topilmadi.", 'Связь не найдена.'],
  PROGRAM_INVALID: ['Бонус дастури маълумоти нотўғри.', "Bonus dasturi ma'lumoti notöğri.", 'Неверные данные бонусной программы.'],
});
const LANG_IDX = { uz_Cyrl: 0, uz_Latn: 1, ru: 2 };
function messagesOf(code) {
  const t = TEXT[code] || TEXT.INVALID_REQUEST;
  return { uz_Cyrl: t[0], uz_Latn: t[1], ru: t[2] };
}

/** Хабар матнлари (3 тил). {name} — таклиф қилувчининг ЎЗ профилидаги исми. */
const NOTICE = Object.freeze({
  invite_spouse: {
    uz_Cyrl: { title: 'Турмуш ўртоғи тасдиғи', body: '{name} сизни турмуш ўртоғи деб кўрсатди — тасдиқлайсизми?' },
    uz_Latn: { title: 'Turmuş örtoği tasdiği', body: '{name} sizni turmuş örtoği deb körsatdi — tasdiqlaysizmi?' },
    ru: { title: 'Подтверждение супруга', body: '{name} указал(а) вас как супруга(у) — подтверждаете?' },
  },
  invite_relative: {
    uz_Cyrl: { title: 'Қариндошлик тасдиғи', body: '{name} сизни яқин қариндош ({relation}) деб кўрсатди — тасдиқлайсизми?' },
    uz_Latn: { title: 'Qarindoşlik tasdiği', body: '{name} sizni yaqin qarindoş ({relation}) deb körsatdi — tasdiqlaysizmi?' },
    ru: { title: 'Подтверждение родства', body: '{name} указал(а) вас как близкого родственника ({relation}) — подтверждаете?' },
  },
  accepted: {
    uz_Cyrl: { title: 'Тасдиқланди', body: '{name} боғланишни тасдиқлади.' },
    uz_Latn: { title: 'Tasdiqlandi', body: '{name} boğlanişni tasdiqladi.' },
    ru: { title: 'Подтверждено', body: '{name} подтвердил(а) связь.' },
  },
  // H: бонус хабари (сумма/кун — дастурдан).
  bonus: {
    uz_Cyrl: { title: 'Табриклаймиз!', body: 'Ҳисобингизга {amount} сўм AVA бонуси тушди — Супермаркет ва Байрам саватчасида ишлатинг, {days} кун амал қилади.' },
    uz_Latn: { title: 'Tabriklaymiz!', body: "Hisobingizga {amount} söm AVA bonusi tuşdi — Supermarket va Bayram savatçasida işlating, {days} kun amal qiladi." },
    ru: { title: 'Поздравляем!', body: 'На ваш счёт зачислен бонус AVA {amount} сум — используйте в Супермаркете и Праздничной корзине, действует {days} дней.' },
  },
});
const RELATION_NAMES = Object.freeze({
  spouse: ['турмуш ўртоғи', "turmuş örtoği", 'супруг(а)'],
  father: ['ота', 'ota', 'отец'],
  mother: ['она', 'ona', 'мать'],
  brother: ['ака-ука', 'aka-uka', 'брат'],
  sister: ['опа-сингил', 'opa-singil', 'сестра'],
  son: ['ўғил', 'öğil', 'сын'],
  daughter: ['қиз', 'qiz', 'дочь'],
  child: ['фарзанд', 'farzand', 'ребёнок'],
  sibling: ['ака-ука/опа-сингил', 'aka-uka/opa-singil', 'брат/сестра'],
});

// ══════════════════════ ТОЗА ФУНКЦИЯЛАР ══════════════════════

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isInt = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
const pad = (n) => String(n).padStart(2, '0');
const fill = (s, p) => String(s).replace(/\{(\w+)\}/g, (m, k) => (p[k] == null ? m : String(p[k])));

/** Шахс калити: охирги 9 рақам → '998'+9 (барча телефон шакллари бир шахс). */
function personKeyOf(id) {
  const d = String(id || '').replace(/\D/g, '');
  if (d.length === 9) return `998${d}`;
  if (d.length === 12 && d.startsWith('998')) return d;
  return null;
}
function pairKeyOf(a, b) {
  return [a, b].sort().join('_');
}
/** 'YYYY-MM-DD' (ҳақиқий сана, 1900..бугун) ёки null. */
function birthKeyOk(s, nowMs = Date.now()) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const [y, m, d] = s.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return false;
  return y >= 1900 && dt.getTime() <= nowMs + DAY_MS;
}
/** users.birthDate сатри ('YYYY-MM-DD' | 'D.M.YYYY') → 'YYYY-MM-DD' ёки null. */
function userBirthKey(v) {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  let key = null;
  if (m) key = `${m[1]}-${m[2]}-${m[3]}`;
  else if ((m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(s))) key = `${m[3]}-${pad(Number(m[2]))}-${pad(Number(m[1]))}`;
  return key && birthKeyOk(key) ? key : null;
}
/** Тошкент ярим тунидаги Timestamp миллисекунди (relatives.birthDate шакли — мавжуд ёзувлар каби). */
function birthMsOf(key) {
  const [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d) - TZ_OFFSET_MS;
}
function dayKeyOf(ms) {
  const d = new Date(ms + TZ_OFFSET_MS);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/** Тур: spouse | parent | sibling | child. */
function relationGroup(rel) {
  if (rel === 'spouse') return 'spouse';
  if (rel === 'father' || rel === 'mother') return 'parent';
  if (rel === 'brother' || rel === 'sister' || rel === 'sibling') return 'sibling';
  if (rel === 'son' || rel === 'daughter' || rel === 'child') return 'child';
  return null;
}
/**
 * Тескари муносабат: таклиф қилувчи A «B менинг {rel}им» деди → B учун A ким. A жинси (users.gender: male|female)
 * бўйича ўғил/қиз, ака-ука/опа-сингил, ота/она; номаълум — умумий (child/sibling; ота-она номаълум бўлса — null).
 */
function reverseRelation(rel, inviterGender) {
  const g = inviterGender === 'female' ? 'female' : inviterGender === 'male' ? 'male' : '';
  switch (relationGroup(rel)) {
    case 'spouse': return 'spouse';
    case 'parent': return g === 'female' ? 'daughter' : g === 'male' ? 'son' : 'child';
    case 'sibling': return g === 'female' ? 'sister' : g === 'male' ? 'brother' : 'sibling';
    case 'child': return g === 'female' ? 'mother' : g === 'male' ? 'father' : null;
    default: return null;
  }
}
/** Ҳолат ҳисоблагичини (state) ўзгартириш: менга нисбатан у [rel] → менинг қайси ҳисоблагичим. */
function counterOf(rel) {
  return { parent: 'parents', sibling: 'siblings', child: 'children' }[relationGroup(rel)] || null;
}
function capsOf(program) {
  const p = program || {};
  return {
    parents: isInt(p.maxParents, 0, 10) ? p.maxParents : DEFAULT_MAX_PARENTS,
    siblings: isInt(p.maxSiblings, 0, 50) ? p.maxSiblings : DEFAULT_MAX_SIBLINGS,
    children: DEFAULT_MAX_CHILDREN,
  };
}
/** state ва менга нисбатан у [rel] — чегара рухсат берадими. */
function capAllows(state, rel, caps) {
  const c = counterOf(rel);
  if (!c) return true;
  const n = Number.isInteger((state || {})[c]) ? state[c] : 0;
  return n + 1 <= caps[c];
}
/** Кунлик таклиф чегараси: {ok, next} (next — state учун янги қийматлар). */
function rateCheck(state, kind, nowMs) {
  const day = dayKeyOf(nowMs);
  const s = state && state.day === day ? state : { day, spouseInvites: 0, relInvites: 0 };
  const field = kind === 'spouse' ? 'spouseInvites' : 'relInvites';
  const limit = kind === 'spouse' ? SPOUSE_INVITES_PER_DAY : RELATIVE_INVITES_PER_DAY;
  const n = Number.isInteger(s[field]) ? s[field] : 0;
  if (n >= limit) return { ok: false };
  return { ok: true, next: { day, spouseInvites: s.spouseInvites || 0, relInvites: s.relInvites || 0, [field]: n + 1 } };
}

const PROGRAM_KEYS = ['title', 'stage', 'internalPhones', 'pilotDistrictIds', 'amount', 'minOrderAmount', 'maxOrderSharePct',
  'validityDays', 'budgetTotal', 'maxParents', 'maxSiblings'];
function validateFamilyProgram(programId, p) {
  const errors = [];
  if (!PROGRAMS.includes(programId)) return { ok: false, errors: ['PROGRAM_ID_INVALID'] };
  if (!isObj(p)) return { ok: false, errors: ['PROGRAM_NOT_OBJECT'] };
  for (const k of Object.keys(p)) if (!PROGRAM_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${k}`);
  if (programId === SPOUSE_PROGRAM && (p.maxParents !== undefined || p.maxSiblings !== undefined)) errors.push('CAPS_ONLY_RELATIVE');
  if (!isObj(p.title) || !['uz_Cyrl', 'uz_Latn', 'ru'].every((l) => typeof p.title[l] === 'string' && p.title[l].trim() && p.title[l].length <= 80)) errors.push('TITLE_INVALID');
  if (!STAGES.includes(p.stage)) errors.push('STAGE_INVALID');
  if (!Array.isArray(p.internalPhones) || p.internalPhones.length > 50 || !p.internalPhones.every((x) => /^998\d{9}$/.test(x))) errors.push('INTERNAL_PHONES_INVALID');
  if (!Array.isArray(p.pilotDistrictIds) || p.pilotDistrictIds.length > 50 || !p.pilotDistrictIds.every((x) => typeof x === 'string' && /^[a-z0-9_-]{2,40}$/.test(x))) errors.push('PILOT_DISTRICTS_INVALID');
  if (!isInt(p.amount, 1, 10000000)) errors.push('AMOUNT_INVALID');
  if (!isInt(p.minOrderAmount, 0, 100000000)) errors.push('MIN_ORDER_INVALID');
  if (!isInt(p.maxOrderSharePct, 1, 100)) errors.push('SHARE_INVALID');
  if (!isInt(p.validityDays, 1, 365)) errors.push('VALIDITY_INVALID');
  if (!isInt(p.budgetTotal, Number.isInteger(p.amount) ? p.amount : 1, 100000000000)) errors.push('BUDGET_INVALID');
  if (p.maxParents !== undefined && !isInt(p.maxParents, 0, 10)) errors.push('MAX_PARENTS_INVALID');
  if (p.maxSiblings !== undefined && !isInt(p.maxSiblings, 0, 50)) errors.push('MAX_SIBLINGS_INVALID');
  return { ok: errors.length === 0, errors };
}
/** Дастур босқичи (рағбат тизимидаги қоида): internal — internalPhones; pilot — + туман; public — ҳамма. */
function stageAllows(p, personKey, districtId) {
  const stage = (p && p.stage) || 'off';
  if (stage === 'off') return false;
  const internal = Array.isArray(p.internalPhones) && p.internalPhones.includes(personKey);
  if (stage === 'internal') return internal;
  if (stage === 'pilot') return internal || (Array.isArray(p.pilotDistrictIds) && p.pilotDistrictIds.includes(String(districtId || '')));
  return stage === 'public';
}
function grantIdFor(programId, personKey, pairKey) {
  return programId === SPOUSE_PROGRAM ? inc.grantIdOf(SPOUSE_PROGRAM, personKey) : inc.grantIdOf(RELATIVE_PROGRAM, `${personKey}_${pairKey}`);
}

// ══════════════════════ CLOUD FUNCTIONS ══════════════════════

function attachFamilyLinks(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const TS = admin.firestore.Timestamp;
  const ts = () => FV.serverTimestamp();
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (o) => console.log(JSON.stringify({ module: MODULE, ...o }));
  const tail = (p) => String(p || '').slice(-4);

  function callerKey(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const key = personKeyOf(canonicalUid(callerPhone(context)));
    if (!key) throw fail('unauthenticated', 'UNAUTHENTICATED');
    return key;
  }
  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };
  /** Ҳисоб ҳужжати: канон (998…) бўлса — у, йўқ бўлса — эски 9 хонали. */
  async function userDoc(key) {
    for (const id of [key, key.slice(3)]) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return { ref: s.ref, id: s.id, data: s.data() || {} };
    }
    return null;
  }
  const programRef = (id) => db.collection('incentive_programs').doc(id);
  async function program(id) {
    const s = await programRef(id).get();
    const d = s.exists ? (s.data() || {}) : null;
    return d && d.kind === id ? d : null;
  }
  const langOf = (u) => normalizeLang((u && u.data && u.data.appLang) || 'uz_Cyrl');
  const displayName = (u) => String((u && u.data && (u.data.name || u.data.fullName)) || '').trim().slice(0, NAME_MAX);
  async function notify(u, kind, params, extra = {}) {
    if (!u) return;
    const t = (NOTICE[kind][langOf(u)] || NOTICE[kind].uz_Cyrl);
    try {
      await notifyUserInApp({ userId: u.id, title: t.title, body: fill(t.body, params), category: 'info', ...extra });
    } catch (e) { log({ action: 'notify', result: 'error', errorCode: 'NOTIFY_FAILED', kind }); }
  }

  /**
   * Грант (идемпотент: t.create — бир марта): дастур фаол ва шахс босқичда бўлса. Хабар (H) — фақат янги грантда.
   */
  async function grantFamilyBonus(programId, personKey, pairKey) {
    const p0 = await program(programId);
    if (!p0) return { result: 'skip', code: 'PROGRAM_OFF' };
    const user = await userDoc(personKey);
    if (!user) return { result: 'skip', code: 'NOT_ON_AVA' };
    if (!stageAllows(p0, personKey, user.data.districtId)) return { result: 'skip', code: 'NOT_IN_STAGE' };
    const grantId = grantIdFor(programId, personKey, pairKey);
    const grantRef = db.collection('incentive_grants').doc(grantId);
    const out = await db.runTransaction(async (t) => {
      const [ps, gs, us] = await Promise.all([t.get(programRef(programId)), t.get(grantRef), t.get(user.ref)]);
      if (gs.exists) return { result: 'duplicate' };
      const p = ps.data() || {};
      if (!us.exists || !stageAllows(p, personKey, (us.data() || {}).districtId)) return { result: 'skip', code: 'NOT_IN_STAGE' };
      const granted = Number.isSafeInteger((p.counters || {}).grantedAmount) ? p.counters.grantedAmount : 0;
      if (granted + p.amount > p.budgetTotal) return { result: 'skip', code: 'BUDGET_EXHAUSTED' };
      const buckets = { [BUCKET]: p.amount };
      t.create(grantRef, {
        uid: user.id, personKey, programId, programKey: programId, amount: p.amount, remaining: p.amount, buckets,
        maxOrderSharePct: p.maxOrderSharePct, minOrderAmount: p.minOrderAmount, scope: BUCKET, status: 'active',
        expiresAt: TS.fromMillis(now() + p.validityDays * DAY_MS), pairKey, createdAt: ts(), updatedAt: ts(),
      });
      t.update(user.ref, { incentiveBalance: FV.increment(p.amount), incentiveUpdatedAt: ts() });
      t.update(programRef(programId), { 'counters.grantedAmount': FV.increment(p.amount), 'counters.grantedCount': FV.increment(1), updatedAt: ts() });
      t.create(db.collection('incentive_ledger').doc(`grant_${grantId}`), {
        type: 'grant', uid: user.id, programId, grantId, amount: p.amount, buckets, actor: `system:${programId}`, at: ts(),
      });
      return { result: 'granted', amount: p.amount, validityDays: p.validityDays };
    });
    if (out.result === 'granted') {
      log({ action: 'familyBonus', programId, result: 'granted', userId: tail(personKey), amount: out.amount });
      await notify(user, 'bonus', { amount: out.amount.toLocaleString('ru-RU').replace(/ /g, ' '), days: out.validityDays },
        { source: 'family_bonus', dataType: 'family_bonus', screen: 'supermarket' });
    }
    return out;
  }

  /** Таклиф қилувчининг «Яқин қариндошлар» рўйхатида шахс (туғилган кун эслатмаси учун). Мавжуд бўлса — тегмайди. */
  async function ensurePerson(ownerKey, personId, fields) {
    const col = db.collection('relatives').doc(ownerKey).collection('people');
    if (personId) {
      const s = await col.doc(personId).get();
      if (s.exists) {
        if (fields.linkPairKey) await s.ref.set({ linkPairKey: fields.linkPairKey, updatedAt: ts() }, { merge: true });
        return personId;
      }
    }
    const ref = personId ? col.doc(personId) : col.doc();
    await ref.set({
      fullName: fields.name, firstName: fields.name.split(/\s+/)[0] || fields.name, lastName: '', patronymic: '', gender: '',
      photoUrl: '', photoPath: '', phone: fields.phone || '', address: '', relationDegree: fields.relationLabel || '', side: '',
      notes: '', birthDate: fields.birthKey ? TS.fromMillis(birthMsOf(fields.birthKey)) : null,
      fatherId: null, motherId: null, spouseId: null, isSelf: false,
      ...(fields.linkPairKey ? { linkPairKey: fields.linkPairKey } : {}), createdAt: ts(), updatedAt: ts(),
    });
    return ref.id;
  }
  /** «Мен» ёзувининг spouseId'си (саватча сарлавҳаси, эслатмалар). [only] — фақат шу қиймат бўлса тозалаш. */
  async function setSelfSpouse(ownerKey, spouseId, { only } = {}) {
    const snap = await db.collection('relatives').doc(ownerKey).collection('people').where('isSelf', '==', true).limit(1).get();
    if (snap.empty) return false;
    const cur = (snap.docs[0].data() || {}).spouseId || null;
    if (only !== undefined && cur !== only) return false;
    await snap.docs[0].ref.set({ spouseId, updatedAt: ts() }, { merge: true });
    return true;
  }

  // ── Таклиф ──
  async function invite(data, context, kind) {
    const started = now();
    const fromKey = callerKey(context);
    const d = isObj(data) ? data : {};
    const relation = kind === 'spouse' ? 'spouse' : String(d.relation || '');
    if (!INVITE_RELATIONS.includes(relation) || (kind === 'relative' && relation === 'spouse')) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'relation' });
    const toKey = personKeyOf(d.phone);
    if (!toKey) throw fail('invalid-argument', 'PHONE_INVALID');
    if (toKey === fromKey) throw fail('invalid-argument', 'SELF_INVITE');
    const name = typeof d.name === 'string' ? d.name.trim() : '';
    if (!name || name.length > NAME_MAX) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'name' });
    const birthKey = d.birthDate == null || d.birthDate === '' ? null : String(d.birthDate);
    if ((kind === 'spouse' && !birthKey) || (birthKey && !birthKeyOk(birthKey, now()))) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'birthDate' });
    const personId = typeof d.personId === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(d.personId) ? d.personId : '';

    const [from, to, relProgram] = await Promise.all([userDoc(fromKey), userDoc(toKey), program(RELATIVE_PROGRAM)]);
    if (!from) throw fail('failed-precondition', 'UNAUTHENTICATED');
    const reverse = reverseRelation(relation, from.data.gender);
    if (!reverse) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'relation' });
    const caps = capsOf(relProgram);
    const pairKey = pairKeyOf(fromKey, toKey);
    const inviteId = `${fromKey}_${toKey}`;
    const invRef = db.collection(INVITES).doc(inviteId);
    const res = await db.runTransaction(async (t) => {
      const [st, link, inv] = await Promise.all([
        t.get(db.collection(STATE).doc(fromKey)), t.get(db.collection(LINKS).doc(pairKey)), t.get(invRef)]);
      const state = st.exists ? (st.data() || {}) : {};
      if (link.exists && (link.data() || {}).status === 'active') throw fail('failed-precondition', 'ALREADY_LINKED');
      if (inv.exists && (inv.data() || {}).status === 'pending') return { duplicate: true };
      if (kind === 'spouse' && state.spousePair) throw fail('failed-precondition', 'SPOUSE_EXISTS');
      if (kind === 'relative' && !capAllows(state, relation, caps)) throw fail('failed-precondition', 'CAP_REACHED');
      const rate = rateCheck(state, kind, now());
      if (!rate.ok) throw fail('resource-exhausted', 'RATE_LIMITED');
      t.set(db.collection(STATE).doc(fromKey), { ...rate.next, updatedAt: ts() }, { merge: true });
      t.set(invRef, {
        kind, relation, reverse, fromKey, toKey, fromUid: from.id, toUid: to ? to.id : null, pairKey,
        name, birthDate: birthKey, personId: personId || (inv.exists ? (inv.data() || {}).personId || '' : ''),
        fromName: displayName(from), status: 'pending', createdAt: ts(), updatedAt: ts(), respondedAt: null,
      });
      return { duplicate: false };
    });
    // Таклиф қилувчи рўйхатида шахс (эслатмалар — тасдиқсиз ҳам) + турмуш ўртоғи → «Мен».spouseId.
    let pid = personId;
    try {
      pid = await ensurePerson(fromKey, personId, { name, birthKey, phone: `+${toKey}`, relationLabel: RELATION_NAMES[relation][LANG_IDX[langOf(from)]] });
      if (pid !== personId) await invRef.set({ personId: pid }, { merge: true });
      if (kind === 'spouse') await setSelfSpouse(fromKey, pid);
    } catch (e) { log({ action: 'invite', result: 'person_error', errorCode: 'PERSON_WRITE_FAILED' }); }
    if (!res.duplicate && to) {
      const lang = langOf(to);
      await notify(to, kind === 'spouse' ? 'invite_spouse' : 'invite_relative',
        { name: displayName(from) || `+${fromKey.slice(0, 5)}…`, relation: RELATION_NAMES[reverse][LANG_IDX[lang]] },
        { source: 'family_invite', dataType: 'family_invite', screen: 'family_invite', extraNews: { inviteId }, extraData: { inviteId } });
    }
    log({ action: `invite_${kind}`, result: res.duplicate ? 'duplicate' : 'ok', userId: tail(fromKey), relation, onAva: !!to, duration: now() - started });
    return { ok: true, inviteId, duplicate: res.duplicate, onAva: !!to };
  }

  // ── Жавоб ──
  async function respond(data, context, kind) {
    const started = now();
    const me = callerKey(context);
    const d = isObj(data) ? data : {};
    const inviteId = typeof d.inviteId === 'string' && /^\d{12}_\d{12}$/.test(d.inviteId) ? d.inviteId : '';
    if (!inviteId) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'inviteId' });
    const accept = d.accept === true;
    const invRef = db.collection(INVITES).doc(inviteId);
    const relProgram = await program(RELATIVE_PROGRAM);
    const caps = capsOf(relProgram);
    const out = await db.runTransaction(async (t) => {
      const inv = await t.get(invRef);
      const x = inv.exists ? (inv.data() || {}) : null;
      if (!x || x.toKey !== me || (kind && x.kind !== kind)) throw fail('not-found', 'INVITE_NOT_FOUND');
      if (x.status !== 'pending') {
        if (x.status === (accept ? 'accepted' : 'declined')) return { result: 'duplicate', x };
        throw fail('failed-precondition', 'INVITE_CLOSED');
      }
      if (!accept) {
        t.update(invRef, { status: 'declined', respondedAt: ts(), updatedAt: ts() });
        return { result: 'declined', x };
      }
      const linkRef = db.collection(LINKS).doc(x.pairKey);
      const [sa, sb, link] = await Promise.all([t.get(db.collection(STATE).doc(x.fromKey)), t.get(db.collection(STATE).doc(me)), t.get(linkRef)]);
      const A = sa.exists ? (sa.data() || {}) : {};
      const B = sb.exists ? (sb.data() || {}) : {};
      if (link.exists && (link.data() || {}).status === 'active') return { result: 'duplicate', x };
      if (x.kind === 'spouse') {
        if ((A.spousePair && A.spousePair !== x.pairKey) || (B.spousePair && B.spousePair !== x.pairKey)) throw fail('failed-precondition', 'SPOUSE_TAKEN');
      } else if (!capAllows(A, x.relation, caps) || !capAllows(B, x.reverse, caps)) {
        throw fail('failed-precondition', 'CAP_REACHED');
      }
      const inc1 = (rel) => { const c = counterOf(rel); return c ? { [c]: FV.increment(1) } : {}; };
      t.set(db.collection(STATE).doc(x.fromKey), { ...(x.kind === 'spouse' ? { spousePair: x.pairKey } : inc1(x.relation)), updatedAt: ts() }, { merge: true });
      t.set(db.collection(STATE).doc(me), { ...(x.kind === 'spouse' ? { spousePair: x.pairKey } : inc1(x.reverse)), updatedAt: ts() }, { merge: true });
      t.set(linkRef, {
        keys: [x.fromKey, me].sort(), kind: x.kind, rel: { [x.fromKey]: x.relation, [me]: x.reverse },
        status: 'active', inviteId, createdAt: ts(), updatedAt: ts(), unlinkedAt: null, unlinkedBy: null,
      });
      t.update(invRef, { status: 'accepted', respondedAt: ts(), updatedAt: ts() });
      return { result: 'accepted', x };
    });
    const x = out.x;
    let bonus = null;
    if (out.result === 'accepted') {
      const [from, meDoc] = await Promise.all([userDoc(x.fromKey), userDoc(me)]);
      // Махфийлик: бир-бирининг фақат исми ва туғилган куни (бошқа ҳеч нарса).
      try {
        await ensurePerson(x.fromKey, x.personId, { name: x.name, birthKey: x.birthDate, linkPairKey: x.pairKey });
        const theirBirth = from ? userBirthKey(from.data.birthDate) : null;
        const myPid = await ensurePerson(me, `link_${x.pairKey}`, {
          name: displayName(from) || x.fromKey.slice(-4), birthKey: theirBirth, linkPairKey: x.pairKey,
          relationLabel: RELATION_NAMES[x.reverse][LANG_IDX[langOf(meDoc)]],
        });
        if (x.kind === 'spouse') {
          if (x.personId) await setSelfSpouse(x.fromKey, x.personId);
          await setSelfSpouse(me, myPid);
        }
      } catch (e) { log({ action: 'respond', result: 'person_error', errorCode: 'PERSON_WRITE_FAILED' }); }
      const programId = x.kind === 'spouse' ? SPOUSE_PROGRAM : RELATIVE_PROGRAM;
      bonus = {};
      for (const k of [x.fromKey, me]) {
        try { bonus[k === me ? 'me' : 'other'] = (await grantFamilyBonus(programId, k, x.pairKey)).result; } catch (e) { bonus[k === me ? 'me' : 'other'] = 'error'; }
      }
      await notify(from, 'accepted', { name: displayName(meDoc) || x.name }, { source: 'family_link', dataType: 'family_link', screen: 'relatives' });
    }
    log({ action: `respond_${x.kind}`, result: out.result, userId: tail(me), bonus, duration: now() - started });
    return { ok: true, result: out.result, bonus: bonus && bonus.me };
  }

  // ── Ажратиш (ҳар икки томон, исталган вақт; бонус қайтариб олинмайди, қайта берилмайди) ──
  async function unlink(data, context, kind) {
    const me = callerKey(context);
    const d = isObj(data) ? data : {};
    let pairKey = typeof d.pairKey === 'string' && /^\d{12}_\d{12}$/.test(d.pairKey) ? d.pairKey : '';
    if (!pairKey && kind === 'spouse') {
      const st = await db.collection(STATE).doc(me).get();
      pairKey = st.exists ? (st.data() || {}).spousePair || '' : '';
    }
    if (!pairKey) throw fail('not-found', 'LINK_NOT_FOUND');
    const linkRef = db.collection(LINKS).doc(pairKey);
    const res = await db.runTransaction(async (t) => {
      const link = await t.get(linkRef);
      const x = link.exists ? (link.data() || {}) : null;
      if (!x || !Array.isArray(x.keys) || !x.keys.includes(me) || (kind && x.kind !== kind)) throw fail('not-found', 'LINK_NOT_FOUND');
      if (x.status !== 'active') return { result: 'duplicate', x };
      for (const k of x.keys) {
        const theirRel = x.rel[k];
        const c = counterOf(theirRel);
        t.set(db.collection(STATE).doc(k), {
          ...(x.kind === 'spouse' ? { spousePair: null } : c ? { [c]: FV.increment(-1) } : {}), updatedAt: ts(),
        }, { merge: true });
      }
      t.update(linkRef, { status: 'unlinked', unlinkedAt: ts(), unlinkedBy: me, updatedAt: ts() });
      return { result: 'unlinked', x };
    });
    if (res.result === 'unlinked' && res.x.kind === 'spouse') {
      try {
        for (const k of res.x.keys) {
          const people = await db.collection('relatives').doc(k).collection('people').where('linkPairKey', '==', pairKey).limit(1).get();
          if (!people.empty) await setSelfSpouse(k, null, { only: people.docs[0].id });
        }
      } catch (e) { log({ action: 'unlink', result: 'person_error', errorCode: 'PERSON_WRITE_FAILED' }); }
    }
    log({ action: `unlink_${res.x.kind}`, result: res.result, userId: tail(me) });
    return { ok: true, result: res.result };
  }

  exportsObj.inviteSpouse = functions.https.onCall((data, context) => invite(data, context, 'spouse'));
  exportsObj.respondSpouseInvite = functions.https.onCall((data, context) => respond(data, context, 'spouse'));
  exportsObj.unlinkSpouse = functions.https.onCall((data, context) => unlink(data, context, 'spouse'));
  exportsObj.inviteRelative = functions.https.onCall((data, context) => invite(data, context, 'relative'));
  exportsObj.respondRelativeInvite = functions.https.onCall((data, context) => respond(data, context, 'relative'));
  exportsObj.unlinkRelative = functions.https.onCall((data, context) => unlink(data, context, 'relative'));

  /** Мижоз: кирувчи/чиқувчи таклифлар, боғланишлар, дастурлар (фаол бўлса — сумма; таклиф карточкаси учун). */
  exportsObj.getMyFamilyLinks = functions.https.onCall(async (data, context) => {
    const me = callerKey(context);
    const [inc1, out1, links, sp, rp, u] = await Promise.all([
      db.collection(INVITES).where('toKey', '==', me).where('status', '==', 'pending').limit(20).get(),
      db.collection(INVITES).where('fromKey', '==', me).limit(50).get(),
      db.collection(LINKS).where('keys', 'array-contains', me).limit(50).get(),
      program(SPOUSE_PROGRAM), program(RELATIVE_PROGRAM), userDoc(me),
    ]);
    const prog = (p) => (p && stageAllows(p, me, u && u.data.districtId)
      ? { active: true, amount: p.amount, validityDays: p.validityDays, minOrderAmount: p.minOrderAmount, ...(p === rp ? capsOf(p) : {}) }
      : { active: false });
    const linkName = async (x) => {
      const other = x.keys.find((k) => k !== me);
      const s = await db.collection('relatives').doc(me).collection('people').where('linkPairKey', '==', x.pairKey || '').limit(1).get();
      return { other, name: s.empty ? '' : String((s.docs[0].data() || {}).fullName || '') };
    };
    const linkViews = [];
    for (const l of links.docs) {
      const x = { ...(l.data() || {}), pairKey: l.id };
      if (x.status !== 'active') continue;
      const n = await linkName(x);
      linkViews.push({ pairKey: l.id, kind: x.kind, relation: x.rel[me], name: n.name }); // rel[me] — у менга ким
    }
    return {
      ok: true,
      incoming: inc1.docs.map((s) => { const x = s.data() || {}; return { inviteId: s.id, kind: x.kind, relation: x.reverse, fromName: x.fromName || '' }; }),
      outgoing: out1.docs.map((s) => { const x = s.data() || {}; return { inviteId: s.id, kind: x.kind, relation: x.relation, name: x.name, status: x.status, personId: x.personId || '' }; }),
      links: linkViews,
      programs: { spouse: prog(sp), relative: prog(rp) },
    };
  });

  /** Админ: spouse_link / relative_link созламаси (ЯГОНА ёзиш йўли), admin_audit. Сукут — ҳужжат йўқ = OFF. */
  exportsObj.adminUpsertFamilyBonusProgram = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const programId = String((data && data.programId) || '');
    const p = sm.trimDeep(data && data.program);
    const v = validateFamilyProgram(programId, p);
    if (!v.ok) throw fail('invalid-argument', 'PROGRAM_INVALID', { errors: v.errors });
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, 300) : '';
    const ref = programRef(programId);
    const pick = (o) => (o ? Object.fromEntries(PROGRAM_KEYS.map((k) => [k, o[k] === undefined ? null : o[k]])) : null);
    const out = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const cur = s.exists ? (s.data() || {}) : null;
      if (cur && cur.kind !== programId) throw fail('failed-precondition', 'PROGRAM_INVALID');
      if (cur && sm.stableStringify(pick(cur)) === sm.stableStringify(pick(p))) return { changed: false };
      t.set(ref, {
        ...p, kind: programId, key: programId, audience: { gender: 'any' }, buckets: [{ category: BUCKET, amount: p.amount }], budgetDaily: 0,
        updatedAt: ts(), updatedBy: actor, ...(cur ? {} : { createdAt: ts(), counters: { grantedAmount: 0, grantedCount: 0, spentAmount: 0 } }),
      }, { merge: true });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'incentive_program_upsert', programKind: programId, actor, target: `incentive_programs/${programId}`,
        before: pick(cur), after: pick(p), reason, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminUpsertFamilyBonusProgram', programId, result: 'ok', userId: tail(actor), stage: p.stage, ...out });
    return { ok: true, programId, ...out };
  });

  /** Админ: жорий созламалар (иккала дастур). */
  exportsObj.adminGetFamilyBonusPrograms = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const [s, r] = await Promise.all([program(SPOUSE_PROGRAM), program(RELATIVE_PROGRAM)]);
    const view = (p) => (p ? { ...Object.fromEntries(PROGRAM_KEYS.map((k) => [k, p[k] === undefined ? null : p[k]])), counters: p.counters || null } : null);
    return { ok: true, programs: { [SPOUSE_PROGRAM]: view(s), [RELATIVE_PROGRAM]: view(r) } };
  });

  return { grantFamilyBonus };
}

module.exports = {
  attachFamilyLinks,
  personKeyOf, pairKeyOf, birthKeyOk, userBirthKey, birthMsOf, dayKeyOf, relationGroup, reverseRelation, counterOf,
  capsOf, capAllows, rateCheck, validateFamilyProgram, stageAllows, grantIdFor, messagesOf,
  SPOUSE_PROGRAM, RELATIVE_PROGRAM, PROGRAMS, INVITES, LINKS, STATE, NOTICE, RELATIONS, INVITE_RELATIONS,
  DEFAULT_MAX_PARENTS, DEFAULT_MAX_SIBLINGS, SPOUSE_INVITES_PER_DAY, RELATIVE_INVITES_PER_DAY,
};
