/**
 * «Туғилган кун ва байрам саватчаси» — СЕРВЕР (эга 2026-11-26).
 *
 * МАВЖУД занжир устида (параллел тизим ЙЎҚ, 3/4/43-банд):
 *   - каталог/нарх/буюртма — AVA Супермаркет (`platform_products` sm таклифлари, `placeSupermarketOrder`);
 *   - туғилган кунлар — «Яқин қариндошлар» `relatives/{userDocId}/people/{personId}.birthDate` (Timestamp);
 *   - хабар — `notifyUserInApp`; бонус — мавжуд рағбат тизими (`incentive_programs` / `incentive_grants` /
 *     `incentive_ledger` / `users.incentiveBalance`, incentives.js) — янги ҳамён йўқ;
 *   - фойдаланувчи саватлари — `users/{uid}/sm_lists` (+ ихтиёрий `occasionId`), янги омбор йўқ.
 *
 * Коллекциялар:
 *   holiday_occasions/{id}  — байрам/туғилган кун (админ, `visible` = stage=='public', фақат CF ёзади)
 *   holiday_baskets/{id}    — тайёр саватлар (админ, `visible` = active && occasion public, фақат CF ёзади)
 *   holiday_birthday_index/{ownerDocId}_{personId} — {ownerId, personId, md:'MM-DD'} (ИСМ ЙЎҚ, 40-банд; фақат CF)
 *   holiday_reminder_log/{key} — эслатма идемпотентлиги (бир қариндошга йилига бир марта)
 *   holiday_reminder_runs/{key} — оммавий тарқатиш курсори (бир байрам — бир ҳужжат)
 *
 * Пул — бутун сўм (8-банд). Ҳеч қачон буюртма бермайди / пул ечмайди (эга 2026-11-26).
 */
'use strict';

const sm = require('./supermarket');
const inc = require('./incentives');
const { normalizeLang } = require('./notif_i18n');

const MODULE = 'holiday';
const OCCASIONS = 'holiday_occasions';
const BASKETS = 'holiday_baskets';
const BD_INDEX = 'holiday_birthday_index';
const REMIND_LOG = 'holiday_reminder_log';
const RUNS = 'holiday_reminder_runs';
const ADMIN_AUDIT = 'admin_audit';
const PRODUCTS = 'platform_products';
const ORDERS = 'orders';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const KINDS = Object.freeze(['birthday', 'holiday']);
const TIERS = Object.freeze(['simple', 'medium', 'large']);
const STAGES = sm.STAGES; // off · internal · pilot · public
const LANGS = sm.LANGS;
const ID_RE = sm.ID_RE;
const PRODUCT_ID_RE = sm.PRODUCT_ID_RE;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MD_RE = /^\d{2}-\d{2}$/;
const TZ_OFFSET_MS = 5 * 3600000;
const DAY_MS = 86400000;
const MAX_AHEAD_DAYS = 14; // етказиш санаси (эга 2026-11-26)
const DEFAULT_REMIND = 5;
const BIG_REMIND = 10;
const GIFT_PURGE_DAYS = 1; // эга 2026-11-27 (аввал 7): етказилган/бекор қилингандан 1 кун кейин
const SELF_BD_INDEX = 'holiday_self_birthday_index'; // {ownerId, personId, md} — фойдаланувчининг ЎЗ туғилган куни (исмсиз)
const BONUS_PROGRAM_ID = 'relatives_birthdays';
const BONUS_BUCKET = 'supermarket';
const LIMITS = Object.freeze({
  name: 60, items: 60, dates: 30, guestsMax: 500, budgetMax: 100000000, recipientName: 60, giftMessage: 200,
  remindMax: 30, image: 500, bdPage: 300, usersPage: 300, maxPerRun: 2000, giftSweep: 200, peopleScan: 200,
  selfReminders: 10, textTitle: 80, textBody: 300, targetCategories: 10,
});

// ── Хабарлар (3 тил, 25-банд) ──
const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  INVALID_REQUEST: ['Маълумот нотўғри. Қайта уриниб кўринг.', "Ma'lumot notöğri. Qayta urinib köring.", 'Неверные данные. Попробуйте ещё раз.'],
  OCCASION_INVALID: ['Байрам маълумоти нотўғри.', "Bayram ma'lumoti notöğri.", 'Неверные данные праздника.'],
  BASKET_INVALID: ['Саватча маълумоти нотўғри.', "Savatça ma'lumoti notöğri.", 'Неверные данные корзины.'],
  OCCASION_NOT_FOUND: ['Байрам топилмади.', 'Bayram topilmadi.', 'Праздник не найден.'],
  BASKET_NOT_FOUND: ['Саватча топилмади.', 'Savatça topilmadi.', 'Корзина не найдена.'],
  GROUP_UNKNOWN: ['Бундай гуруҳ йўқ.', "Bunday guruh yöq.", 'Такой группы нет.'],
  TAXONOMY_MISSING: ['Бўлимлар рўйхати ҳали яратилмаган.', "Bölimlar röyxati hali yaratilmagan.", 'Список категорий ещё не создан.'],
  NOT_AVAILABLE: ['Саватча ҳозир мавжуд эмас.', 'Savatça hozir mavjud emas.', 'Корзина сейчас недоступна.'],
  PROGRAM_INVALID: ['Бонус дастури маълумоти нотўғри.', "Bonus dasturi ma'lumoti notöğri.", 'Неверные данные бонусной программы.'],
  INTERNAL: ['Амални бажариб бўлмади. Қайта уриниб кўринг.', "Amalni bajarib bölmadi. Qayta urinib köring.", 'Не удалось выполнить. Попробуйте ещё раз.'],
});
const messagesOf = (code) => { const m = MSG[code] || MSG.INTERNAL; return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] }; };

// Эслатма матнлари: {name}/{days}/{holiday}. Қариндош исми — эга ўзи киритган (ҳар қандай алифбода).
const BIRTHDAY_TEXT = Object.freeze({
  uz_Cyrl: { title: 'Туғилган кун яқинлашмоқда', body: '{name}нинг туғилган кунига {days} кун қолди — саватча тайёрлаймизми?' },
  uz_Latn: { title: "Tuğilgan kun yaqinlaşmoqda", body: '{name}ning tuğilgan kuniga {days} kun qoldi — savatça tayyorlaymizmi?' },
  ru: { title: 'Скоро день рождения', body: 'До дня рождения {name} осталось {days} дн. — соберём корзину?' },
});
const HOLIDAY_TEXT = Object.freeze({
  uz_Cyrl: { title: 'Байрам яқинлашмоқда', body: '{holiday}га {days} кун қолди — байрам саватчасини тайёрлаймизми?' },
  uz_Latn: { title: 'Bayram yaqinlaşmoqda', body: '{holiday}ga {days} kun qoldi — bayram savatçasini tayyorlaymizmi?' },
  ru: { title: 'Скоро праздник', body: 'До праздника «{holiday}» осталось {days} дн. — соберём праздничную корзину?' },
});
// Совға олувчига — курьер олиб йўлга чиққанда (эга 2026-11-27: буюртма берилганда ЭМАС). Нарх йўқ.
const GIFT_TEXT = Object.freeze({
  uz_Cyrl: { title: 'Сизга совға!', body: 'Сизга AVA орқали совға юборилди. Курьер уни олиб йўлга чиқди ва олдиндан қўнғироқ қилади.' },
  uz_Latn: { title: "Sizga sovğa!", body: "Sizga AVA orqali sovğa yuborildi. Kuryer uni olib yölga çiqdi va oldindan qöngiroq qiladi." },
  ru: { title: 'Вам подарок!', body: 'Вам отправили подарок через AVA. Курьер уже везёт его и заранее позвонит.' },
});
// Фойдаланувчининг ЎЗ туғилган куни (эга 2026-11-27): D-7..D-3, ҳар куни бошқа таклиф. Матн/мақсад — PROPOSED сукут,
// админ `holiday_occasions/birthday.selfReminders` орқали ўзгартиради ([] — ўчирилган).
const T = (c, l, r) => ({ uz_Cyrl: c, uz_Latn: l, ru: r });
const SELF_TITLE = T('Туғилган кунингиз яқин', 'Tuğilgan kuningiz yaqin', 'Скоро ваш день рождения');
const selfText = (c, l, r) => ({
  uz_Cyrl: { title: SELF_TITLE.uz_Cyrl, body: c }, uz_Latn: { title: SELF_TITLE.uz_Latn, body: l }, ru: { title: SELF_TITLE.ru, body: r },
});
const DEFAULT_SELF_REMINDERS = Object.freeze([
  { daysBefore: 7, target: { type: 'holiday_basket', occasionId: 'birthday', mode: 'guests' }, texts: selfText(
    'Туғилган кунингизга 7 кун қолди — меҳмонлар учун байрам саватчасини тайёрлаймизми?',
    'Tuğilgan kuningizga 7 kun qoldi — mehmonlar uçun bayram savatçasini tayyorlaymizmi?',
    'До вашего дня рождения 7 дней — собрать праздничную корзину для гостей?') },
  { daysBefore: 6, target: { type: 'restaurants_preorder' }, texts: selfText(
    'Туғилган кунингизга 6 кун қолди. Торт ва таомларни олдиндан буюртма қилинг.',
    'Tuğilgan kuningizga 6 kun qoldi. Tort va taomlarni oldindan buyurtma qiling.',
    'До вашего дня рождения 6 дней. Закажите торт и блюда заранее.') },
  { daysBefore: 5, target: { type: 'holiday_basket', occasionId: 'birthday', mode: 'guests' }, texts: selfText(
    'Яқинларингизни таклиф қилинг — сават ва етказишни AVA ўз зиммасига олади.',
    'Yaqinlaringizni taklif qiling — savat va yetkazişni AVA öz zimmasiga oladi.',
    'Пригласите близких — корзину и доставку AVA берёт на себя.') },
  { daysBefore: 4, target: { type: 'holiday_basket', occasionId: 'birthday', mode: 'gift' }, texts: selfText(
    'Совға ва гуллар учун яқинларингизга эслатма юборамизми?',
    'Sovğa va gullar uçun yaqinlaringizga eslatma yuboramizmi?',
    'Напомнить близким о подарке и цветах?') },
  { daysBefore: 3, target: { type: 'holiday_basket', occasionId: 'birthday' }, texts: selfText(
    'Сўнгги имконият: саватча ва тортни ҳозир буюртма қилинг — етказишга улгурамиз.',
    "Sönggi imkoniyat: savatça va tortni hozir buyurtma qiling — yetkazişga ulguramiz.",
    'Последний шанс: закажите корзину и торт сейчас — успеем доставить.') },
]);
// Байрам эслатмаси CTA мақсадлари (эга 2026-11-27). Қурбон ҳайит — Мол бозори (сават эмас).
const TARGET_TYPES = Object.freeze(['holiday_basket', 'restaurants_preorder', 'supermarket', 'market']);
const BASKET_MODES = Object.freeze(['guests', 'gift']);
const BONUS_TEXT = Object.freeze({
  uz_Cyrl: { title: 'Бонус берилди', body: 'Қариндошларингиз туғилган кунлари учун {amount} сўм бонус — Супермаркетда {min} сўмдан ортиқ буюртмада ишлатинг.' },
  uz_Latn: { title: 'Bonus berildi', body: "Qarindoşlaringiz tuğilgan kunlari uçun {amount} söm bonus — Supermarketda {min} sömdan ortiq buyurtmada işlating." },
  ru: { title: 'Бонус начислен', body: 'За дни рождения родных — бонус {amount} сум. Используйте в Супермаркете при заказе от {min} сум.' },
});
const fill = (s, p) => s.replace(/\{(\w+)\}/g, (_, k) => (p[k] === undefined ? '' : String(p[k])));

const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const isObj = sm.isPlainObject;
const isInt = (v, a, b) => Number.isInteger(v) && v >= a && v <= b;

// ══════════════════════ САНА (Тошкент, тоза) ══════════════════════

const pad = (n) => String(n).padStart(2, '0');
function dateKeyOf(ms) {
  const t = new Date(ms + TZ_OFFSET_MS);
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}
function utcOfKey(key) {
  const [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}
/** Ҳақиқий календар санасими (2027-02-29 — йўқ). */
function validDateKey(key) {
  if (typeof key !== 'string' || !DATE_RE.test(key)) return false;
  const [y, m, d] = key.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}
function addDays(key, n) {
  const t = new Date(utcOfKey(key) + n * DAY_MS);
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}
const daysBetween = (a, b) => Math.round((utcOfKey(b) - utcOfKey(a)) / DAY_MS);
const isLeap = (y) => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
/** Тошкент санаси бошланиши (UTC мс). */
const startOfKeyMs = (key) => utcOfKey(key) - TZ_OFFSET_MS;

/** Туғилган сана (Timestamp/Date/мс) → Тошкент 'MM-DD'. Клиент маҳаллий ярим тунни сақлайди (UTC'да олдинги кун 19:00). */
function mdOfBirth(v) {
  let ms = null;
  if (v && typeof v.toMillis === 'function') ms = v.toMillis();
  else if (v instanceof Date) ms = v.getTime();
  else if (typeof v === 'number' && Number.isFinite(v)) ms = v;
  if (ms == null) return null;
  return dateKeyOf(ms).slice(5);
}
/** today+days санасида нишонланадиган 'MM-DD'лар; кабиса бўлмаган йилда 02-28 га 02-29 ҳам қўшилади (PROPOSED). */
function birthdayMdTargets(todayKey, days) {
  const target = addDays(todayKey, days);
  const md = target.slice(5);
  const out = [md];
  if (md === '02-28' && !isLeap(Number(target.slice(0, 4)))) out.push('02-29');
  return { target, mds: out };
}
/** Эслатма кунлари: берилмаса — туғилган кун/оддий байрам 5, катта байрам 10 (эга 2026-11-26). */
function remindDaysOf(occ) {
  const o = occ || {};
  if (isInt(o.remindDaysBefore, 1, LIMITS.remindMax)) return o.remindDaysBefore;
  return o.kind === 'holiday' && o.bigHoliday === true ? BIG_REMIND : DEFAULT_REMIND;
}
/** Кейинги сана (≥ today): fixed MM-DD — ҳар йил; list — админ киритган рўйхатдан (Ҳайит/Рамазон — ой тақвими). */
function occasionNextDate(occ, todayKey) {
  const r = occ && occ.dateRule;
  if (!isObj(r)) return null;
  if (r.type === 'fixed' && typeof r.md === 'string' && MD_RE.test(r.md)) {
    const y = Number(todayKey.slice(0, 4));
    for (const yy of [y, y + 1]) {
      const k = `${yy}-${r.md}`;
      if (validDateKey(k) && k >= todayKey) return k;
    }
    return null;
  }
  if (r.type === 'list' && Array.isArray(r.dates)) {
    const next = r.dates.filter((d) => validDateKey(d) && d >= todayKey).sort();
    return next[0] || null;
  }
  return null;
}
/** Байрам эслатмаси бугунми: кейинги сана − remindDays == бугун. */
function holidayDue(occ, todayKey) {
  const date = occasionNextDate(occ, todayKey);
  if (!date) return { due: false, date: null };
  const days = remindDaysOf(occ);
  return { due: daysBetween(todayKey, date) === days, date, days };
}

// ══════════════════════ ВАЛИДАТОРЛАР (тоза) ══════════════════════

function checkNames(v, p, errors, max = LIMITS.name) {
  if (!isObj(v)) { errors.push(`NAME_MISSING ${p}`); return; }
  for (const l of LANGS) {
    if (typeof v[l] !== 'string' || !v[l].trim()) errors.push(`NAME_MISSING ${p}.${l}`);
    else if (v[l].length > max) errors.push(`NAME_TOO_LONG ${p}.${l}`);
  }
  for (const k of Object.keys(v)) if (!LANGS.includes(k)) errors.push(`UNKNOWN_KEY ${p}.${k}`);
}
/** Эслатма матнлари: {uz_Cyrl|uz_Latn|ru: {title, body}}; {days}/{holiday} ўрин белгилари рухсат. */
function checkTexts(v, p, errors) {
  if (!isObj(v)) { errors.push(`TEXTS_INVALID ${p}`); return; }
  for (const k of Object.keys(v)) if (!LANGS.includes(k)) errors.push(`UNKNOWN_KEY ${p}.${k}`);
  for (const l of LANGS) {
    const x = v[l];
    if (!isObj(x) || Object.keys(x).some((k) => !['title', 'body'].includes(k))) { errors.push(`TEXTS_INVALID ${p}.${l}`); continue; }
    if (typeof x.title !== 'string' || !x.title.trim() || x.title.length > LIMITS.textTitle) errors.push(`TEXT_TITLE_INVALID ${p}.${l}`);
    if (typeof x.body !== 'string' || !x.body.trim() || x.body.length > LIMITS.textBody) errors.push(`TEXT_BODY_INVALID ${p}.${l}`);
  }
}
/** CTA мақсади (клиент навигацияси учун; сервер ҳеч нарса бермайди). */
function checkTarget(t, p, errors) {
  if (!isObj(t) || !TARGET_TYPES.includes(t.type)) { errors.push(`TARGET_INVALID ${p}`); return; }
  const allowed = { holiday_basket: ['type', 'occasionId', 'mode'], restaurants_preorder: ['type'], supermarket: ['type'], market: ['type', 'market', 'categories'] }[t.type];
  for (const k of Object.keys(t)) if (!allowed.includes(k)) errors.push(`UNKNOWN_KEY ${p}.${k}`);
  if (t.type === 'holiday_basket') {
    if (typeof t.occasionId !== 'string' || !ID_RE.test(t.occasionId)) errors.push(`TARGET_OCCASION_INVALID ${p}.occasionId`);
    if (t.mode != null && !BASKET_MODES.includes(t.mode)) errors.push(`TARGET_MODE_INVALID ${p}.mode`);
  }
  if (t.type === 'market') {
    if (typeof t.market !== 'string' || !/^[a-z][a-z0-9_]{1,39}$/.test(t.market)) errors.push(`TARGET_MARKET_INVALID ${p}.market`);
    const c = t.categories;
    if (c != null && (!Array.isArray(c) || c.length > LIMITS.targetCategories || new Set(c).size !== c.length
      || !c.every((x) => typeof x === 'string' && /^[a-z][a-z0-9_]{1,39}$/.test(x)))) errors.push(`TARGET_CATEGORIES_INVALID ${p}.categories`);
  }
}
function checkSelfReminders(list, errors) {
  if (!Array.isArray(list) || list.length > LIMITS.selfReminders) { errors.push('SELF_REMINDERS_INVALID selfReminders'); return; }
  const seen = new Set();
  list.forEach((r, i) => {
    const p = `selfReminders[${i}]`;
    if (!isObj(r)) { errors.push(`SELF_REMINDER_INVALID ${p}`); return; }
    for (const k of Object.keys(r)) if (!['daysBefore', 'texts', 'target'].includes(k)) errors.push(`UNKNOWN_KEY ${p}.${k}`);
    if (!isInt(r.daysBefore, 1, LIMITS.remindMax)) errors.push(`DAYS_INVALID ${p}.daysBefore`);
    else if (seen.has(r.daysBefore)) errors.push(`DAYS_DUPLICATE ${p}.daysBefore`);
    seen.add(r.daysBefore);
    checkTexts(r.texts, `${p}.texts`, errors);
    checkTarget(r.target, `${p}.target`, errors);
  });
}

const OCC_KEYS = ['id', 'names', 'kind', 'bigHoliday', 'dateRule', 'remindDaysBefore', 'stage', 'order', 'image',
  'selfReminders', 'target', 'reminderTexts'];
function validateOccasion(o) {
  const errors = [];
  if (!isObj(o)) return { ok: false, errors: ['OCCASION_NOT_OBJECT'] };
  for (const k of Object.keys(o)) if (!OCC_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${k}`);
  if (o.target != null) checkTarget(o.target, 'target', errors);
  if (o.reminderTexts != null) {
    if (o.kind !== 'holiday') errors.push('REMINDER_TEXTS_FORBIDDEN reminderTexts'); // туғилган кун (қариндош) — исмли қатъий матн
    else checkTexts(o.reminderTexts, 'reminderTexts', errors);
  }
  if (o.selfReminders != null) {
    if (o.kind !== 'birthday') errors.push('SELF_REMINDERS_FORBIDDEN selfReminders');
    else checkSelfReminders(o.selfReminders, errors);
  }
  if (typeof o.id !== 'string' || !ID_RE.test(o.id)) errors.push('ID_INVALID id');
  checkNames(o.names, 'names', errors);
  if (!KINDS.includes(o.kind)) errors.push('KIND_INVALID kind');
  if (o.bigHoliday != null && typeof o.bigHoliday !== 'boolean') errors.push('BIG_INVALID bigHoliday');
  if (o.remindDaysBefore != null && !isInt(o.remindDaysBefore, 1, LIMITS.remindMax)) errors.push('REMIND_INVALID remindDaysBefore');
  if (!STAGES.includes(o.stage)) errors.push('STAGE_INVALID stage');
  if (!Number.isInteger(o.order)) errors.push('ORDER_INVALID order');
  if (o.image != null && o.image !== '' && !(typeof o.image === 'string' && /^https:\/\//.test(o.image) && o.image.length <= LIMITS.image)) errors.push('IMAGE_INVALID image');
  if (o.kind === 'birthday') {
    if (o.dateRule != null) errors.push('DATE_RULE_FORBIDDEN dateRule'); // сана — қариндош картасидан
  } else if (o.kind === 'holiday') {
    const r = o.dateRule;
    if (!isObj(r)) errors.push('DATE_RULE_INVALID dateRule');
    else if (r.type === 'fixed') {
      if (Object.keys(r).some((k) => !['type', 'md'].includes(k))) errors.push('UNKNOWN_KEY dateRule');
      if (typeof r.md !== 'string' || !MD_RE.test(r.md) || !validDateKey(`2028-${r.md}`) || r.md === '02-29') errors.push('MD_INVALID dateRule.md');
    } else if (r.type === 'list') {
      if (Object.keys(r).some((k) => !['type', 'dates'].includes(k))) errors.push('UNKNOWN_KEY dateRule');
      if (!Array.isArray(r.dates) || r.dates.length > LIMITS.dates) errors.push('DATES_INVALID dateRule.dates');
      else {
        const seen = new Set();
        r.dates.forEach((d, i) => {
          if (!validDateKey(d)) errors.push(`DATE_INVALID dateRule.dates[${i}]`);
          else if (seen.has(d)) errors.push(`DATE_DUPLICATE dateRule.dates[${i}]`);
          seen.add(d);
        });
      }
    } else errors.push('DATE_RULE_TYPE_INVALID dateRule.type');
  }
  return { ok: errors.length === 0, errors };
}
/** Сақланадиган шакл (бўш майдонлар нормаллашади). */
function normalizeOccasion(o) {
  const out = {
    id: o.id, names: o.names, kind: o.kind, bigHoliday: o.bigHoliday === true, stage: o.stage, order: o.order,
    remindDaysBefore: remindDaysOf(o), image: o.image || '', dateRule: o.kind === 'holiday' ? o.dateRule : null,
    target: o.target || null, reminderTexts: o.reminderTexts || null,
    // null — сукут (DEFAULT_SELF_REMINDERS); [] — ўчирилган.
    selfReminders: o.kind === 'birthday' && Array.isArray(o.selfReminders) ? o.selfReminders : null,
  };
  if (out.dateRule && out.dateRule.type === 'list') out.dateRule = { type: 'list', dates: [...out.dateRule.dates].sort() };
  return out;
}

const BASKET_KEYS = ['id', 'occasionId', 'tier', 'names', 'items', 'baseGuests', 'active'];
const ITEM_KEYS = ['groupId', 'varietyId', 'offerId', 'qtyPerGuest', 'qty', 'priority'];
/** groups — {groupId: true} (таксономия) ёки null (текширилмайди). */
function validateBasket(b, groups) {
  const errors = [];
  if (!isObj(b)) return { ok: false, errors: ['BASKET_NOT_OBJECT'] };
  for (const k of Object.keys(b)) if (!BASKET_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${k}`);
  if (typeof b.id !== 'string' || !ID_RE.test(b.id)) errors.push('ID_INVALID id');
  if (typeof b.occasionId !== 'string' || !ID_RE.test(b.occasionId)) errors.push('OCCASION_ID_INVALID occasionId');
  if (!TIERS.includes(b.tier)) errors.push('TIER_INVALID tier');
  checkNames(b.names, 'names', errors);
  if (!isInt(b.baseGuests, 1, LIMITS.guestsMax)) errors.push('BASE_GUESTS_INVALID baseGuests');
  if (typeof b.active !== 'boolean') errors.push('ACTIVE_INVALID active');
  if (!Array.isArray(b.items) || b.items.length < 1 || b.items.length > LIMITS.items) errors.push('ITEMS_INVALID items');
  else {
    const seen = new Set();
    b.items.forEach((it, i) => {
      const p = `items[${i}]`;
      if (!isObj(it)) { errors.push(`ITEM_INVALID ${p}`); return; }
      for (const k of Object.keys(it)) if (!ITEM_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${p}.${k}`);
      if (typeof it.groupId !== 'string' || !ID_RE.test(it.groupId)) errors.push(`GROUP_ID_INVALID ${p}.groupId`);
      else if (groups && !groups[it.groupId]) errors.push(`GROUP_UNKNOWN ${p}.groupId`);
      else if (seen.has(it.groupId)) errors.push(`GROUP_DUPLICATE ${p}.groupId`);
      seen.add(it.groupId);
      if (it.varietyId != null && (typeof it.varietyId !== 'string' || !ID_RE.test(it.varietyId))) errors.push(`VARIETY_INVALID ${p}.varietyId`);
      if (it.offerId != null && (typeof it.offerId !== 'string' || !PRODUCT_ID_RE.test(it.offerId))) errors.push(`OFFER_INVALID ${p}.offerId`);
      const q = sm.toMilli(it.qty);
      if (q == null || q <= 0 || q > sm.LIMITS.qtyMilliMax) errors.push(`QTY_INVALID ${p}.qty`);
      if (it.qtyPerGuest != null) {
        const g = sm.toMilli(it.qtyPerGuest);
        if (g == null || g <= 0 || g > sm.LIMITS.qtyMilliMax) errors.push(`QTY_PER_GUEST_INVALID ${p}.qtyPerGuest`);
      }
      if (it.priority != null && !isInt(it.priority, 1, 9)) errors.push(`PRIORITY_INVALID ${p}.priority`);
    });
  }
  return { ok: errors.length === 0, errors };
}

// ══════════════════════ АҚЛЛИ САВАТ (тоза) ══════════════════════

const ceilTo = (q, step) => Math.ceil(q / step) * step;
/** Мижоз сони бўйича керакли миқдор (милли): qtyPerGuest × guests, ёки qty × guests / baseGuests (юқорига). */
function wantedMilli(item, baseGuests, guests) {
  const g = guests == null ? baseGuests : guests;
  if (item.qtyPerGuest != null) return sm.toMilli(item.qtyPerGuest) * g;
  return Math.ceil((sm.toMilli(item.qty) * g) / baseGuests);
}

/**
 * Тайёр саватни ЖОРИЙ каталогга ечиш (ҳеч нарса ёзмайди, буюртма бермайди).
 * groups: {groupId: group}; offers: [{id, ...platform_products data}]; feeBp — settings/app % (bps), null → 0.
 * Танлов: offerId (сотувда бўлса) → нав ичида энг арзон → гуруҳда энг арзон. Бирлик — гуруҳ бирлиги; qtyStep га юқорига.
 * budget (goods+fee): аввал нав/таклифни гуруҳдаги энг арзонига алмаштириш (энг катта тежамдан), кейин энг паст
 * устуворликдаги (priority катта рақам; тенг бўлса — рўйхатда кейинги) қаторларни олиб ташлаш. Ҳар ўзгариш — changes.
 */
function buildBasketPure({ basket, groups, offers, guests, budget, feeBp }) {
  const base = basket.baseGuests;
  const changes = [];
  const lines = [];
  const bp = Number.isInteger(feeBp) && feeBp > 0 ? feeBp : 0;
  basket.items.forEach((item, index) => {
    const group = groups[item.groupId];
    const want = wantedMilli(item, base, guests);
    if (!group) { changes.push({ type: 'unavailable', groupId: item.groupId }); return; }
    const opts = [];
    for (const o of offers) {
      if (o.smGroupId !== item.groupId || !sm.offerSellable(o)) continue;
      if ((o.unit || group.unit) !== group.unit) continue;
      const step = sm.stepOk(o.qtyStep) ? sm.toMilli(o.qtyStep) : 1000;
      const q = ceilTo(want, step);
      const stock = sm.toMilli(Number(o.stock));
      if (stock == null || q > stock) continue;
      opts.push({ o, q, total: sm.lineTotalOf(o.price, q) });
    }
    if (!opts.length) { changes.push({ type: 'unavailable', groupId: item.groupId }); return; }
    const cheapest = (arr) => arr.slice().sort((a, b) => (a.total - b.total) || String(a.o.id).localeCompare(String(b.o.id)))[0];
    let pick = null;
    if (item.offerId) pick = opts.find((x) => x.o.id === item.offerId) || null;
    if (!pick && item.varietyId) pick = cheapest(opts.filter((x) => x.o.smVariety && x.o.smVariety.id === item.varietyId)) || null;
    const groupCheapest = cheapest(opts);
    if (!pick) {
      if (item.offerId || item.varietyId) changes.push({ type: 'swap', reason: 'unavailable', groupId: item.groupId, toOfferId: groupCheapest.o.id });
      pick = groupCheapest;
    }
    lines.push({ index, item, pick, groupCheapest });
  });
  const view = (l) => {
    const o = l.pick.o;
    const v = {
      productId: o.id, groupId: l.item.groupId, name: String(o.name || o.id).slice(0, 80), price: o.price,
      qty: sm.fromMilli(l.pick.q), qtyStep: sm.stepOk(o.qtyStep) ? o.qtyStep : 1, unit: o.unit || (groups[l.item.groupId] || {}).unit,
      total: l.pick.total, weighed: o.weighed === true, priority: l.item.priority || 5,
    };
    if (o.smVariety && o.smVariety.id) v.varietyId = o.smVariety.id;
    if (o.imageUrl) v.imageUrl = o.imageUrl;
    return v;
  };
  const sum = (arr) => {
    const goods = arr.reduce((s, l) => s + l.pick.total, 0);
    const fee = sm.feeOf(goods, bp);
    return { goods, fee, total: goods + fee };
  };
  if (budget != null) {
    let t = sum(lines);
    while (t.total > budget) {
      let best = null;
      for (const l of lines) {
        const saving = l.pick.total - l.groupCheapest.total;
        if (saving > 0 && (!best || saving > best.saving)) best = { l, saving };
      }
      if (!best) break;
      changes.push({ type: 'swap', reason: 'budget', groupId: best.l.item.groupId, fromOfferId: best.l.pick.o.id, toOfferId: best.l.groupCheapest.o.id, saving: best.saving });
      best.l.pick = best.l.groupCheapest;
      t = sum(lines);
    }
    const dropOrder = lines.slice().sort((a, b) => ((b.item.priority || 5) - (a.item.priority || 5)) || (b.index - a.index));
    for (const l of dropOrder) {
      if (t.total <= budget) break;
      lines.splice(lines.indexOf(l), 1);
      changes.push({ type: 'drop', reason: 'budget', groupId: l.item.groupId, offerId: l.pick.o.id, saving: l.pick.total });
      t = sum(lines);
    }
  }
  const t = sum(lines);
  return {
    lines: lines.map(view), goods: t.goods, fee: t.fee, total: t.total, changes,
    guests: guests == null ? base : guests, ...(budget != null ? { budget, withinBudget: t.total <= budget } : {}),
  };
}

// ══════════════════════ СОВҒА ВА САНА (тоза) ══════════════════════

/** gift → {gift} | {code}. canonical — телефон → 998XXXXXXXXX. hidePrice доим true (эга). */
function parseGift(raw, canonical) {
  if (raw == null) return { gift: null };
  if (!isObj(raw)) return { code: 'INVALID_REQUEST' };
  if (Object.keys(raw).some((k) => !['recipientName', 'recipientPhone', 'message', 'hidePrice'].includes(k))) return { code: 'INVALID_REQUEST' };
  const name = typeof raw.recipientName === 'string' ? raw.recipientName.trim() : '';
  if (!name || name.length > LIMITS.recipientName) return { code: 'INVALID_REQUEST' };
  const digits = String(raw.recipientPhone || '').replace(/\D/g, '');
  if (digits.length < 9 || digits.length > 12) return { code: 'INVALID_REQUEST' };
  const phone = canonical(digits);
  if (!/^998\d{9}$/.test(phone)) return { code: 'INVALID_REQUEST' };
  const message = raw.message == null ? '' : (typeof raw.message === 'string' ? raw.message.trim() : null);
  if (message == null || message.length > LIMITS.giftMessage) return { code: 'INVALID_REQUEST' };
  if (raw.hidePrice != null && raw.hidePrice !== true) return { code: 'INVALID_REQUEST' };
  return { gift: { recipientName: name, recipientPhone: phone, message, hidePrice: true } };
}

/**
 * Берилган санадаги оралиқлар: бугун — cutoff билан (мавжуд availableSlots қоидаси), 1..14 кун — барчаси, бошқа — [].
 */
function slotsForDate(settings, nowMs, dateKey) {
  if (!validDateKey(dateKey)) return [];
  const today = dateKeyOf(nowMs);
  const off = daysBetween(today, dateKey);
  if (off < 0 || off > MAX_AHEAD_DAYS) return [];
  if (off <= 1) return sm.availableSlots(settings, nowMs)[off === 0 ? 'today' : 'tomorrow'];
  const slots = Array.isArray((settings || {}).slots) ? settings.slots : [];
  return slots.map((sl) => ({ id: sl.id, names: sl.names, startMin: sl.startMin, endMin: sl.endMin, date: dateKey }));
}

const DELIVERED = new Set(['delivered', 'completed']);
/** Буюртма якунланганми ('delivered' | 'cancelled' | null). */
function terminalOf(od) {
  if (sm.isCancelled(od)) return 'cancelled';
  const s = String(od.status || '');
  const fs = String(od.fulfillmentStatus || '').toLowerCase();
  if (DELIVERED.has(s) || fs === 'completed' || fs === 'delivered') return 'delivered';
  return null;
}
/**
 * Совға курьерга ўтдими (эга 2026-11-27: олувчига хабар шу пайтда): status courier|in_delivery ёки
 * fulfillmentStatus courier_picked|arrived; бекор қилинган/якунланган — йўқ.
 */
function giftDispatched(od) {
  const x = od || {};
  if (terminalOf(x)) return false;
  const s = String(x.status || '');
  const fs = String(x.fulfillmentStatus || '').toLowerCase();
  return s === 'courier' || s === 'in_delivery' || fs === 'courier_picked' || fs === 'arrived';
}
const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : (typeof v === 'number' ? v : null));
/**
 * Совға PII тозалаш қарори: якунланган + GIFT_PURGE_DAYS (1) кун → redact; якунланган, муддат ўтмаган → шу вақтга кўчир;
 * ҳали фаол → эртага қайта қара.
 */
function giftPurgeDecision(od, nowMs) {
  const term = terminalOf(od);
  if (!term) return { action: 'reschedule', nextMs: nowMs + DAY_MS };
  const at = msOf(od.deliveredAt) || msOf(od.statusUpdatedAt) || msOf(od.updatedAt) || nowMs;
  const due = at + GIFT_PURGE_DAYS * DAY_MS;
  return due <= nowMs ? { action: 'redact' } : { action: 'reschedule', nextMs: due };
}

// ══════════════════════ ЎЗ ТУҒИЛГАН КУН (тоза) ══════════════════════

/**
 * users/{uid}.birthDate — сатр (рўйхатдан ўтиш: 'YYYY-MM-DD' ёки 'D.M.YYYY', lib/core/utils/formatters.dart parseBirthDate)
 * ёки Timestamp (эски) → 'MM-DD'; ҳақиқий бўлмаса null.
 */
function mdOfUserBirth(v) {
  if (typeof v === 'string') {
    const s = v.trim();
    let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
    let key = null;
    if (m) key = `${m[1]}-${m[2]}-${m[3]}`;
    else if ((m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(s))) key = `${m[3]}-${pad(Number(m[2]))}-${pad(Number(m[1]))}`;
    return key && validDateKey(key) ? key.slice(5) : null;
  }
  return v && typeof v.toMillis === 'function' ? mdOfBirth(v) : null; // рақам/бошқа — сақланадиган шакл эмас
}
/** Самарали рўйхат: null → сукут; бузуқ ёзув — ташланади (ҳимоя). */
function selfRemindersOf(occ) {
  const list = occ && Array.isArray(occ.selfReminders) ? occ.selfReminders : DEFAULT_SELF_REMINDERS;
  return list.filter((r) => { const e = []; checkSelfReminders([r], e); return e.length === 0; });
}
/** Бугун учун: {md: {reminder, target(date)}} — ҳар эслатма ўз кун сони бўйича (кабиса қоидаси birthdayMdTargets'дан). */
function selfDueMap(todayKey, reminders) {
  const out = {};
  for (const r of reminders) {
    const { target, mds } = birthdayMdTargets(todayKey, r.daysBefore);
    for (const md of mds) if (!out[md]) out[md] = { reminder: r, date: target };
  }
  return out;
}
/** Пуш data (FCM — фақат сатрлар) ва экран: клиент мақсадга шу орқали ўтади. */
function targetPush(target) {
  const t = target || { type: 'supermarket' };
  const data = { targetType: t.type };
  if (t.occasionId) data.occasionId = t.occasionId;
  if (t.mode) data.mode = t.mode;
  if (t.market) data.market = t.market;
  if (Array.isArray(t.categories) && t.categories.length) data.categories = t.categories.join(',');
  const screen = { holiday_basket: 'supermarket', supermarket: 'supermarket', restaurants_preorder: 'restaurants', market: 'market' }[t.type] || 'supermarket';
  return { screen, data };
}

// ══════════════════════ ҚАРИНДОШЛАР БОНУСИ (тоза) ══════════════════════

/**
 * Шахс калити (эга 2026-11-27): телефоннинг охирги 9 рақами → '998XXXXXXXXX'. users/998… ва эски 9 хонали
 * ҳужжатлар БИР шахс — битта грант. 9 ёки 998+9 хонали бўлмаса — null.
 */
function personKeyOf(id) {
  const d = String(id || '').replace(/\D/g, '');
  if (d.length === 9) return `998${d}`;
  if (d.length === 12 && d.startsWith('998')) return d;
  return null;
}

/** Исм + туғилган сана бор, «Мен» эмас. */
function relativeEligible(d) {
  const x = d || {};
  if (x.isSelf === true) return false;
  const name = String(x.firstName || x.fullName || '').trim();
  return !!name && mdOfBirth(x.birthDate) != null;
}
const BONUS_KEYS = ['title', 'stage', 'internalPhones', 'pilotDistrictIds', 'amount', 'minRelatives', 'minOrderAmount',
  'maxOrderSharePct', 'validityDays', 'budgetTotal'];
function validateBonusProgram(p) {
  const errors = [];
  if (!isObj(p)) return { ok: false, errors: ['PROGRAM_NOT_OBJECT'] };
  for (const k of Object.keys(p)) if (!BONUS_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${k}`);
  checkNames(p.title, 'title', errors, 80);
  if (!STAGES.includes(p.stage)) errors.push('STAGE_INVALID stage');
  if (!Array.isArray(p.internalPhones) || p.internalPhones.length > 50 || !p.internalPhones.every((x) => /^998\d{9}$/.test(x))) errors.push('INTERNAL_PHONES_INVALID');
  if (!Array.isArray(p.pilotDistrictIds) || p.pilotDistrictIds.length > 50 || !p.pilotDistrictIds.every((x) => typeof x === 'string' && /^[a-z0-9_-]{2,40}$/.test(x))) errors.push('PILOT_DISTRICTS_INVALID');
  if (!isInt(p.amount, 1, 10000000)) errors.push('AMOUNT_INVALID amount');
  if (!isInt(p.minRelatives, 1, 20)) errors.push('MIN_RELATIVES_INVALID minRelatives');
  if (!isInt(p.minOrderAmount, 0, 100000000)) errors.push('MIN_ORDER_INVALID minOrderAmount');
  if (!isInt(p.maxOrderSharePct, 1, 100)) errors.push('SHARE_INVALID maxOrderSharePct');
  if (!isInt(p.validityDays, 1, 365)) errors.push('VALIDITY_INVALID validityDays');
  if (!isInt(p.budgetTotal, Number.isInteger(p.amount) ? p.amount : 1, 100000000000)) errors.push('BUDGET_INVALID budgetTotal');
  return { ok: errors.length === 0, errors };
}
/** Дастур босқичи (рағбат тизимидаги айнан шу қоида): internal — internalPhones; pilot — + туман; public — ҳамма. */
function bonusStageAllows(p, uid, districtId) {
  const stage = (p && p.stage) || 'off';
  if (stage === 'off') return false;
  const internal = Array.isArray(p.internalPhones) && p.internalPhones.includes(uid);
  if (stage === 'internal') return internal;
  if (stage === 'pilot') return internal || (Array.isArray(p.pilotDistrictIds) && p.pilotDistrictIds.includes(String(districtId || '')));
  return stage === 'public';
}
/**
 * Супермаркет буюртмасида ишлатиладиган грантлар: фақат `supermarket` туркуми бор ва minOrderAmount ≤ goods.
 * (Аёллар/машина грантлари — `any`/авто туркумлар — бу ерга КИРМАЙДИ: супермаркет улар учун эга қарори эмас.)
 */
function supermarketGrants(docs, goods) {
  return docs.filter((d) => {
    const x = d.data() || {};
    const b = x.buckets || {};
    return Number.isSafeInteger(b[BONUS_BUCKET]) && b[BONUS_BUCKET] > 0 && Object.keys(b).length === 1
      && (Number.isInteger(x.minOrderAmount) ? x.minOrderAmount : 0) <= goods;
  }).map(grantView);
}
/** incentives.js `grantFromDoc` шакли (у экспорт қилинмаган; incentives.js жонли нусхага тенг сақланади — ўзгартирилмайди). */
function grantView(d) {
  const x = d.data() || {};
  const buckets = {};
  Object.entries(x.buckets || {}).forEach(([k, v]) => { if (Number.isSafeInteger(v)) buckets[k] = v; });
  return {
    id: d.id, ref: d.ref, programId: x.programId, uid: x.uid, status: x.status,
    remaining: Number.isSafeInteger(x.remaining) ? x.remaining : 0, buckets,
    maxOrderSharePct: x.maxOrderSharePct, expiresAtMs: msOf(x.expiresAt),
  };
}

// ══════════════════════ CLOUD FUNCTIONS ══════════════════════

function attachHoliday(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const TS = admin.firestore.Timestamp;
  const ts = () => FV.serverTimestamp();
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (o) => console.log(JSON.stringify({ module: MODULE, ...o }));
  const tail = (p) => String(p || '').slice(-4);

  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };
  function callerUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 9) throw fail('unauthenticated', 'UNAUTHENTICATED');
    return uid;
  }
  async function userDoc(uid12) {
    const uid9 = uid12.length === 12 && uid12.startsWith('998') ? uid12.slice(3) : uid12;
    for (const id of uid9 !== uid12 ? [uid12, uid9] : [uid12]) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return { ref: s.ref, data: s.data() || {} };
    }
    return null;
  }
  const smSettings = async () => {
    const s = await db.collection(sm.SETTINGS_DOC[0]).doc(sm.SETTINGS_DOC[1]).get();
    return s.exists ? (s.data() || {}) : null;
  };
  /** Фойдаланувчи учун кўринадими: супермаркет дарвозаси + байрам босқичи (internal/pilot — админ ва тестерлар). */
  function occasionVisibleFor(occ, settings, uid, role, districtId) {
    if (!occ || occ.stage === 'off' || !STAGES.includes(occ.stage)) return false;
    // Бозор мақсадли байрам (Қурбон ҳайит → Мол бозори) супермаркет дарвозасига боғлиқ эмас (эга 2026-11-27).
    const marketTarget = isObj(occ.target) && occ.target.type === 'market';
    if (!marketTarget && !sm.gateDecision(settings, { uid, role, districtId, requireDistrict: false }).allowed) return false;
    if (occ.stage === 'public') return true;
    return ADMIN_ROLES.includes(role) || (Array.isArray((settings || {}).testerIds) && settings.testerIds.includes(uid));
  }

  // ── 1. Админ: байрам ──
  exportsObj.adminUpsertHolidayOccasion = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const occ = sm.trimDeep(data && data.occasion);
    const v = validateOccasion(occ);
    if (!v.ok) throw fail('invalid-argument', 'OCCASION_INVALID', { errors: v.errors.slice(0, 50) });
    const clean = normalizeOccasion(occ);
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, 300) : '';
    const ref = db.collection(OCCASIONS).doc(clean.id);
    const out = await db.runTransaction(async (t) => {
      const [snap, bSnap] = await Promise.all([t.get(ref), t.get(db.collection(BASKETS).where('occasionId', '==', clean.id))]);
      const cur = snap.exists ? (snap.data() || {}) : null;
      const pick = (o) => (o ? Object.fromEntries(OCC_KEYS.map((k) => [k, o[k] === undefined ? null : o[k]])) : null);
      if (cur && sm.stableStringify(pick(cur)) === sm.stableStringify(pick(clean))) return { changed: false, version: cur.version || 1 };
      const version = (cur && Number.isInteger(cur.version) ? cur.version : 0) + 1;
      const visible = clean.stage === 'public';
      t.set(ref, { ...clean, visible, version, updatedAt: ts(), updatedBy: actor, ...(cur ? {} : { createdAt: ts() }) });
      bSnap.docs.forEach((d) => {
        const want = visible && (d.data() || {}).active === true;
        if ((d.data() || {}).visible !== want) t.update(d.ref, { visible: want, updatedAt: ts() });
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'holiday_occasion_set', actor, target: `${OCCASIONS}/${clean.id} v${version}`, before: pick(cur), after: pick(clean), reason, at: ts(),
      });
      return { changed: true, version };
    });
    log({ action: 'adminUpsertHolidayOccasion', result: 'ok', userId: tail(actor), occasionId: clean.id, ...out });
    return { ok: true, occasionId: clean.id, ...out };
  });

  // ── 2. Админ: тайёр сават ──
  exportsObj.adminUpsertHolidayBasket = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const basket = sm.trimDeep(data && data.basket);
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, 300) : '';
    const pre = validateBasket(basket, null);
    if (!pre.ok) throw fail('invalid-argument', 'BASKET_INVALID', { errors: pre.errors.slice(0, 50) });
    const ref = db.collection(BASKETS).doc(basket.id);
    const out = await db.runTransaction(async (t) => {
      const [taxSnap, occSnap, snap] = await Promise.all([
        t.get(db.collection(sm.TAXONOMY_DOC[0]).doc(sm.TAXONOMY_DOC[1])), t.get(db.collection(OCCASIONS).doc(basket.occasionId)), t.get(ref),
      ]);
      if (!taxSnap.exists) throw fail('failed-precondition', 'TAXONOMY_MISSING');
      if (!occSnap.exists) throw fail('failed-precondition', 'OCCASION_NOT_FOUND');
      const groups = {};
      for (const c of (taxSnap.data().categories || [])) for (const g of (c.groups || [])) groups[g.id] = true;
      const v = validateBasket(basket, groups);
      if (!v.ok) throw fail('invalid-argument', 'BASKET_INVALID', { errors: v.errors.slice(0, 50) });
      const cur = snap.exists ? (snap.data() || {}) : null;
      const pick = (o) => (o ? Object.fromEntries(BASKET_KEYS.map((k) => [k, o[k] === undefined ? null : o[k]])) : null);
      const visible = basket.active === true && (occSnap.data() || {}).stage === 'public';
      if (cur && sm.stableStringify(pick(cur)) === sm.stableStringify(pick(basket)) && cur.visible === visible) return { changed: false, version: cur.version || 1 };
      const version = (cur && Number.isInteger(cur.version) ? cur.version : 0) + 1;
      t.set(ref, { ...basket, visible, version, updatedAt: ts(), updatedBy: actor, ...(cur ? {} : { createdAt: ts() }) });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'holiday_basket_set', actor, target: `${BASKETS}/${basket.id} v${version}`, before: pick(cur), after: pick(basket), reason, at: ts(),
      });
      return { changed: true, version };
    });
    log({ action: 'adminUpsertHolidayBasket', result: 'ok', userId: tail(actor), basketId: basket.id, ...out });
    return { ok: true, basketId: basket.id, ...out };
  });

  // ── 3. Мижоз: каталог (internal тестерлар ҳам кўради; public — rules орқали тўғридан-тўғри ҳам ўқиш мумкин) ──
  exportsObj.getHolidayCatalog = functions.https.onCall(async (data, context) => {
    const uid = callerUid(context);
    const [settings, user, occSnap] = await Promise.all([smSettings(), userDoc(uid), db.collection(OCCASIONS).get()]);
    const role = String((user && user.data.role) || 'user');
    const districtId = String((user && user.data.districtId) || '');
    const today = dateKeyOf(now());
    const occasions = occSnap.docs.map((d) => d.data() || {}).filter((o) => occasionVisibleFor(o, settings, uid, role, districtId))
      .sort((a, b) => (a.order - b.order) || String(a.id).localeCompare(String(b.id)))
      .map((o) => ({
        id: o.id, names: o.names, kind: o.kind, bigHoliday: o.bigHoliday === true, image: o.image || '', order: o.order,
        remindDaysBefore: remindDaysOf(o), nextDate: o.kind === 'holiday' ? occasionNextDate(o, today) : null,
        target: o.target || null,
      }));
    const ids = occasions.map((o) => o.id);
    const baskets = [];
    for (let i = 0; i < ids.length; i += 30) {
      const s = await db.collection(BASKETS).where('occasionId', 'in', ids.slice(i, i + 30)).where('active', '==', true).get();
      s.docs.forEach((d) => { const b = d.data(); baskets.push({ id: b.id, occasionId: b.occasionId, tier: b.tier, names: b.names, baseGuests: b.baseGuests, items: b.items.length }); });
    }
    return { ok: true, occasions, baskets, today };
  });

  // ── 4. Мижоз: ақлли сават (ҳеч нарса ёзмайди) ──
  exportsObj.buildHolidayBasket = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = callerUid(context);
    const d = data || {};
    const basketId = typeof d.basketId === 'string' ? d.basketId.trim() : '';
    if (!ID_RE.test(basketId)) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'basketId' });
    const guests = d.guests == null ? null : d.guests;
    if (guests != null && !isInt(guests, 1, LIMITS.guestsMax)) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'guests' });
    const budget = d.budget == null ? null : d.budget;
    if (budget != null && !isInt(budget, 1, LIMITS.budgetMax)) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'budget' });
    const [settings, user, bSnap, taxSnap, appSnap] = await Promise.all([
      smSettings(), userDoc(uid), db.collection(BASKETS).doc(basketId).get(),
      db.collection(sm.TAXONOMY_DOC[0]).doc(sm.TAXONOMY_DOC[1]).get(), db.collection('settings').doc('app').get(),
    ]);
    if (!bSnap.exists || (bSnap.data() || {}).active !== true) throw fail('not-found', 'BASKET_NOT_FOUND');
    const basket = bSnap.data();
    const occSnap = await db.collection(OCCASIONS).doc(basket.occasionId).get();
    const role = String((user && user.data.role) || 'user');
    if (!occSnap.exists || !occasionVisibleFor(occSnap.data(), settings, uid, role, String((user && user.data.districtId) || ''))) {
      throw fail('failed-precondition', 'NOT_AVAILABLE');
    }
    if (!taxSnap.exists) throw fail('failed-precondition', 'TAXONOMY_MISSING');
    const groups = {};
    for (const c of (taxSnap.data().categories || [])) for (const g of (c.groups || [])) groups[g.id] = g;
    const groupIds = [...new Set(basket.items.map((it) => it.groupId))];
    const offers = [];
    for (let i = 0; i < groupIds.length; i += 30) {
      const s = await db.collection(PRODUCTS).where('smGroupId', 'in', groupIds.slice(i, i + 30)).where('smStatus', '==', 'active').get();
      s.docs.forEach((x) => offers.push({ id: x.id, ...x.data() }));
    }
    const fc = sm.feeConfigFromApp(appSnap.exists ? appSnap.data() : {});
    const res = buildBasketPure({ basket, groups, offers, guests, budget, feeBp: fc ? fc.bps : 0 });
    log({ action: 'buildHolidayBasket', result: 'ok', userId: tail(uid), basketId, lines: res.lines.length, changes: res.changes.length, duration: Date.now() - started });
    return { ok: true, basketId, occasionId: basket.occasionId, tier: basket.tier, feePercent: fc ? fc.percent : null, ...res };
  });

  // ── 5. Туғилган кун индекси (исм сақланмайди) + қариндошлар бонуси ──
  exportsObj.onRelativeBirthdayIndex = functions.firestore
    .document('relatives/{ownerId}/people/{personId}')
    .onWrite(async (change, context) => {
      const { ownerId, personId } = context.params;
      const after = change.after.exists ? (change.after.data() || {}) : null;
      const md = after && relativeEligible(after) ? mdOfBirth(after.birthDate) : null;
      const ref = db.collection(BD_INDEX).doc(`${ownerId}_${personId}`);
      // «Мен» ёзуви (isSelf) — профилдан синхронланади (index.js syncSelfRelativePerson, users.birthDate) →
      // фойдаланувчининг ЎЗ туғилган куни индекси (эга 2026-11-27). Юбориш олдидан users.birthDate қайта текширилади.
      const selfMd = after && after.isSelf === true ? mdOfBirth(after.birthDate) : null;
      const selfRef = db.collection(SELF_BD_INDEX).doc(ownerId);
      const res = await db.runTransaction(async (t) => {
        const [s, ss] = await Promise.all([t.get(ref), t.get(selfRef)]);
        const cur = s.exists ? (s.data() || {}).md : null;
        const sc = ss.exists ? (ss.data() || {}) : null;
        let r = 'noop';
        if (cur !== md) {
          if (md == null) { t.delete(ref); r = 'removed'; } else { t.set(ref, { ownerId, personId, md, updatedAt: ts() }); r = 'indexed'; }
        }
        if (selfMd != null && (!sc || sc.md !== selfMd || sc.personId !== personId)) {
          t.set(selfRef, { ownerId, personId, md: selfMd, updatedAt: ts() }); r = `${r}+self`;
        } else if (selfMd == null && sc && sc.personId === personId) {
          t.delete(selfRef); r = `${r}+self_removed`;
        }
        return r;
      });
      let bonus = null;
      if (md != null) {
        try { bonus = await grantRelativesBonus(ownerId); } catch (e) { bonus = 'error'; log({ action: 'relativesBonus', result: 'error', errorCode: (e.details && e.details.code) || 'INTERNAL' }); }
      }
      log({ action: 'onRelativeBirthdayIndex', result: res, bonus: bonus && (bonus.result || bonus) });
      return null;
    });

  /**
   * Қариндошлар бонуси (бир марта, умрбод): ≥ minRelatives қариндошда исм+сана → грант (мавжуд рағбат тизими).
   * БАРЧА телефон шакллари (эга 2026-11-27): шахс калити = охирги 9 рақам ('998'+9). Грант id =
   * `${programId}_${personKey}` — users/998… ва эски 9 хонали ҳужжат БИР грантга тўқнашади (t.create — фақат битта ғолиб).
   * Грант `uid` = ҳисоб ҳужжати id'си (канон бор бўлса — канон, йўқ бўлса — эски 9 хонали): мавжуд incentives.js
   * (сарф/қайтариш/муддат/бекор) `users/{grant.uid}` га ёзади — ҳужжат мавжуд бўлиши шарт. Қариндошлар иккала
   * relatives/{…} ҳужжатидан санолади (исм+сана бўйича такрорсиз). Қариндош ўчирилса ҳам грант қайтариб олинмайди.
   */
  async function grantRelativesBonus(ownerDocId) {
    const personKey = personKeyOf(ownerDocId);
    if (!personKey) return { result: 'skip', code: 'UID_INVALID' };
    const progRef = db.collection('incentive_programs').doc(BONUS_PROGRAM_ID);
    const [pSnap, user] = await Promise.all([progRef.get(), userDoc(personKey)]);
    if (!pSnap.exists || (pSnap.data() || {}).kind !== BONUS_PROGRAM_ID) return { result: 'skip', code: 'PROGRAM_OFF' };
    if (!user) return { result: 'skip', code: 'NOT_ELIGIBLE' };
    const userRef = user.ref;
    const p0 = pSnap.data();
    if (!bonusStageAllows(p0, personKey, user.data.districtId)) return { result: 'skip', code: 'NOT_IN_STAGE' };
    const seen = new Set();
    let count = 0;
    for (const owner of [personKey, personKey.slice(3)]) {
      const people = await db.collection('relatives').doc(owner).collection('people').limit(LIMITS.peopleScan).get();
      for (const x of people.docs) {
        const d = x.data() || {};
        if (!relativeEligible(d)) continue;
        const key = `${String(d.firstName || d.fullName || '').trim().toLowerCase()}|${mdOfBirth(d.birthDate)}`;
        if (seen.has(key)) continue;
        seen.add(key); count += 1;
      }
    }
    if (count < p0.minRelatives) return { result: 'skip', code: 'NOT_ENOUGH_RELATIVES', count };
    const grantId = inc.grantIdOf(BONUS_PROGRAM_ID, personKey);
    const grantRef = db.collection('incentive_grants').doc(grantId);
    const uid = userRef.id;
    const out = await db.runTransaction(async (t) => {
      const nowMs = now();
      const [ps, gs, us] = await Promise.all([t.get(progRef), t.get(grantRef), t.get(userRef)]);
      if (gs.exists) return { result: 'duplicate' };
      const p = ps.data() || {};
      if (!us.exists || !bonusStageAllows(p, personKey, (us.data() || {}).districtId)) return { result: 'skip', code: 'NOT_IN_STAGE' };
      const granted = Number.isSafeInteger((p.counters || {}).grantedAmount) ? p.counters.grantedAmount : 0;
      if (granted + p.amount > p.budgetTotal) return { result: 'skip', code: 'BUDGET_EXHAUSTED' };
      const buckets = { [BONUS_BUCKET]: p.amount };
      t.create(grantRef, {
        uid, personKey, programId: BONUS_PROGRAM_ID, programKey: BONUS_PROGRAM_ID, amount: p.amount, remaining: p.amount, buckets,
        maxOrderSharePct: p.maxOrderSharePct, minOrderAmount: p.minOrderAmount, scope: BONUS_BUCKET, status: 'active',
        expiresAt: TS.fromMillis(nowMs + p.validityDays * DAY_MS), relativesCount: count, createdAt: ts(), updatedAt: ts(),
      });
      t.update(userRef, { incentiveBalance: FV.increment(p.amount), incentiveUpdatedAt: ts() });
      t.update(progRef, { 'counters.grantedAmount': FV.increment(p.amount), 'counters.grantedCount': FV.increment(1), updatedAt: ts() });
      t.create(db.collection('incentive_ledger').doc(`grant_${grantId}`), {
        type: 'grant', uid, programId: BONUS_PROGRAM_ID, grantId, amount: p.amount, buckets, actor: 'system:relatives_birthdays', at: ts(),
      });
      return { result: 'granted', amount: p.amount, minOrderAmount: p.minOrderAmount };
    });
    if (out.result === 'granted') {
      log({ action: 'relativesBonus', result: 'granted', userId: tail(uid), amount: out.amount });
      try {
        const m = BONUS_TEXT[normalizeLang(user.data.appLang)] || BONUS_TEXT.uz_Cyrl;
        const params = { amount: out.amount, min: out.minOrderAmount };
        await notifyUserInApp({ userId: uid, title: m.title, body: fill(m.body, params), category: 'info', source: 'holiday_relatives_bonus', dataType: 'holiday_relatives_bonus', screen: 'supermarket' });
      } catch (e) { log({ action: 'relativesBonus', result: 'notify_error', errorCode: 'NOTIFY_FAILED' }); }
    }
    return out;
  }

  /** Илова «бонусни олиш» тугмаси учун (триггер ўтказиб юборилган бўлса). Идемпотент. */
  exportsObj.claimRelativesBonus = functions.https.onCall(async (data, context) => {
    const uid = callerUid(context);
    const res = await grantRelativesBonus(uid);
    return { ok: res.result === 'granted' || res.result === 'duplicate', ...res };
  });

  /**
   * Админ: дастур созламаси. ЯГОНА ёзиш йўли шу (умумий adminUpsertIncentiveProgram ЭМАС — у `kind` ва
   * minOrderAmount'ни билмайди). audience.newUsersSince ЁЗИЛМАЙДИ → мавжуд claimIncentive/getMyIncentiveOffers
   * бу дастурни ҳеч кимга бермайди (NOT_NEW_USER); грант фақат шу модулдан.
   */
  exportsObj.adminUpsertRelativesBonusProgram = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const p = sm.trimDeep(data && data.program);
    const v = validateBonusProgram(p);
    if (!v.ok) throw fail('invalid-argument', 'PROGRAM_INVALID', { errors: v.errors });
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, 300) : '';
    const ref = db.collection('incentive_programs').doc(BONUS_PROGRAM_ID);
    const out = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const cur = s.exists ? (s.data() || {}) : null;
      if (cur && cur.kind !== BONUS_PROGRAM_ID) throw fail('failed-precondition', 'PROGRAM_INVALID');
      const pick = (o) => (o ? Object.fromEntries(BONUS_KEYS.map((k) => [k, o[k] === undefined ? null : o[k]])) : null);
      if (cur && sm.stableStringify(pick(cur)) === sm.stableStringify(pick(p))) return { changed: false };
      t.set(ref, {
        ...p, kind: BONUS_PROGRAM_ID, key: BONUS_PROGRAM_ID, audience: { gender: 'any' },
        buckets: [{ category: BONUS_BUCKET, amount: p.amount }], budgetDaily: 0,
        updatedAt: ts(), updatedBy: actor, ...(cur ? {} : { createdAt: ts(), counters: { grantedAmount: 0, grantedCount: 0, spentAmount: 0 } }),
      }, { merge: true });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'incentive_program_upsert', programKind: BONUS_PROGRAM_ID, actor, target: `incentive_programs/${BONUS_PROGRAM_ID}`,
        before: pick(cur), after: pick(p), reason, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminUpsertRelativesBonusProgram', result: 'ok', userId: tail(actor), stage: p.stage, ...out });
    return { ok: true, programId: BONUS_PROGRAM_ID, ...out };
  });

  // ── 6. Эслатмалар ──
  async function notifyText(uid, lang, texts, params, extra) {
    const m = texts[normalizeLang(lang)] || texts.uz_Cyrl;
    await notifyUserInApp({ userId: uid, title: m.title, body: fill(m.body, params), category: 'info', screen: 'supermarket', ...extra });
  }

  /** (а) қариндошлар туғилган кунлари — эгасига, бир қариндошга бир йилда бир марта (holiday_reminder_log). */
  async function runBirthdayReminders(nowMs, settings, occasions, budget) {
    const occ = occasions.find((o) => o.kind === 'birthday');
    const stat = { sent: 0, skipped: 0, scanned: 0 };
    if (!occ || occ.stage === 'off') return { ...stat, reason: 'OCCASION_OFF' };
    const today = dateKeyOf(nowMs);
    const days = remindDaysOf(occ);
    const { target, mds } = birthdayMdTargets(today, days);
    const runRef = db.collection(RUNS).doc(`bd_${today}`);
    const run = (await runRef.get()).data() || {};
    if (run.done === true) return { ...stat, reason: 'DONE' };
    let cursor = run.cursor || null;
    let done = false;
    while (budget.left > 0) {
      let q = db.collection(BD_INDEX).where('md', 'in', mds).orderBy(admin.firestore.FieldPath.documentId()).limit(Math.min(LIMITS.bdPage, budget.left));
      if (cursor) q = q.startAfter(cursor);
      const snap = await q.get();
      if (snap.empty) { done = true; break; }
      cursor = snap.docs[snap.docs.length - 1].id;
      await runRef.set({ kind: 'birthday', date: today, cursor, updatedAt: ts() }, { merge: true }); // курсор олдин (энг кўпи бир марта)
      for (const d of snap.docs) {
        budget.left -= 1; stat.scanned += 1;
        const x = d.data() || {};
        const uid = canonicalUid(x.ownerId);
        const user = await userDoc(uid);
        const role = String((user && user.data.role) || 'user');
        if (!user || !occasionVisibleFor(occ, settings, uid, role, String(user.data.districtId || ''))) { stat.skipped += 1; continue; }
        const person = await db.collection('relatives').doc(x.ownerId).collection('people').doc(x.personId).get();
        if (!person.exists || !relativeEligible(person.data()) || !mds.includes(mdOfBirth(person.data().birthDate))) { stat.skipped += 1; continue; }
        const logRef = db.collection(REMIND_LOG).doc(`bd_${x.ownerId}_${x.personId}_${target.slice(0, 4)}`);
        const claimed = await db.runTransaction(async (t) => {
          const s = await t.get(logRef);
          if (s.exists) return false;
          t.create(logRef, { kind: 'birthday', ownerId: x.ownerId, personId: x.personId, year: Number(target.slice(0, 4)), at: ts() });
          return true;
        });
        if (!claimed) { stat.skipped += 1; continue; }
        const pd = person.data();
        const name = String(pd.firstName || pd.fullName || '').trim().slice(0, 40);
        try {
          await notifyText(uid, user.data.appLang, BIRTHDAY_TEXT, { name, days }, {
            source: 'holiday_birthday_reminder', dataType: 'holiday_birthday_reminder',
            extraNews: { occasionId: occ.id, personId: x.personId }, extraData: { occasionId: occ.id, personId: x.personId },
          });
          stat.sent += 1;
        } catch (e) { stat.skipped += 1; log({ action: 'holidayReminders', result: 'notify_error', errorCode: 'NOTIFY_FAILED' }); }
      }
      if (snap.size < LIMITS.bdPage) { done = true; break; }
    }
    if (done) await runRef.set({ done: true, updatedAt: ts() }, { merge: true });
    return { ...stat, done };
  }

  /**
   * (б) байрамлар — опт-ин фойдаланувчиларга (`users.holidayRemindersOptIn !== false`; PROPOSED: йўқ = ON).
   * internal/pilot — фақат settings/supermarket.testerIds; public — users бўйлаб курсор (holiday_reminder_runs), чегараланган.
   */
  async function runHolidayReminders(nowMs, settings, occasions, budget) {
    const today = dateKeyOf(nowMs);
    const stat = { sent: 0, skipped: 0, scanned: 0, occasions: 0 };
    for (const occ of occasions) {
      if (occ.kind !== 'holiday' || occ.stage === 'off') continue;
      const due = holidayDue(occ, today);
      if (!due.due) continue;
      stat.occasions += 1;
      const runRef = db.collection(RUNS).doc(`hol_${occ.id}_${due.date}`);
      const run = (await runRef.get()).data() || {};
      if (run.done === true) continue;
      const params = (u) => ({ holiday: (occ.names || {})[normalizeLang(u.appLang)] || (occ.names || {}).uz_Cyrl || '', days: due.days });
      const sendTo = async (uid, u) => {
        if (u.holidayRemindersOptIn === false) { stat.skipped += 1; return; }
        if (!occasionVisibleFor(occ, settings, uid, String(u.role || 'user'), String(u.districtId || ''))) { stat.skipped += 1; return; }
        try {
          // Админ матни (масалан Қурбон ҳайит → Мол бозори) ва CTA мақсади бўлса — шу; йўқ бўлса — умумий сават матни.
          const tp = targetPush(occ.target || { type: 'holiday_basket', occasionId: occ.id });
          await notifyText(uid, u.appLang, occ.reminderTexts || HOLIDAY_TEXT, params(u), {
            source: 'holiday_reminder', dataType: 'holiday_reminder', screen: tp.screen,
            extraNews: { occasionId: occ.id, target: occ.target || null }, extraData: { occasionId: occ.id, ...tp.data },
          });
          stat.sent += 1;
        } catch (e) { stat.skipped += 1; }
      };
      if (occ.stage !== 'public') {
        await runRef.set({ kind: 'holiday', occasionId: occ.id, date: due.date, done: true, updatedAt: ts() }, { merge: true });
        for (const tid of (Array.isArray((settings || {}).testerIds) ? settings.testerIds : [])) {
          const u = await userDoc(tid);
          stat.scanned += 1;
          if (u) await sendTo(tid, u.data); else stat.skipped += 1;
        }
        continue;
      }
      let cursor = run.cursor || null;
      let done = false;
      while (budget.left > 0) {
        let q = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(Math.min(LIMITS.usersPage, budget.left));
        if (cursor) q = q.startAfter(cursor);
        const snap = await q.get();
        if (snap.empty) { done = true; break; }
        cursor = snap.docs[snap.docs.length - 1].id;
        await runRef.set({ kind: 'holiday', occasionId: occ.id, date: due.date, cursor, updatedAt: ts() }, { merge: true });
        for (const d of snap.docs) {
          budget.left -= 1; stat.scanned += 1;
          const uid = canonicalUid(d.id);
          if (!/^998\d{9}$/.test(uid)) { stat.skipped += 1; continue; }
          await sendTo(uid, d.data() || {});
        }
        if (snap.size < LIMITS.usersPage) { done = true; break; }
      }
      if (done) await runRef.set({ done: true, updatedAt: ts() }, { merge: true });
    }
    return stat;
  }

  /**
   * (в) фойдаланувчининг ЎЗ туғилган куни (эга 2026-11-27): D-7…D-3 (сукут) — ҳар куни бошқа таклиф.
   * Манба — users/{uid}.birthDate (индекс — «Мен» ёзувидан; юборишдан олдин профилдаги сана қайта текширилади).
   * holidayRemindersOptIn === false — юборилмайди. Идемпотент: бир шахсга (охирги 9 рақам) бир йилда ҳар кун сонига
   * бир марта (holiday_reminder_log/self_{personKey}_{йил}_d{N}); кун курсори holiday_reminder_runs/self_{сана}.
   */
  async function runSelfBirthdayReminders(nowMs, settings, occasions, budget) {
    const occ = occasions.find((o) => o.kind === 'birthday');
    const stat = { sent: 0, skipped: 0, scanned: 0 };
    if (!occ || occ.stage === 'off') return { ...stat, reason: 'OCCASION_OFF' };
    const reminders = selfRemindersOf(occ);
    if (!reminders.length) return { ...stat, reason: 'NO_REMINDERS' };
    const today = dateKeyOf(nowMs);
    const due = selfDueMap(today, reminders);
    const mds = Object.keys(due);
    const runRef = db.collection(RUNS).doc(`self_${today}`);
    const run = (await runRef.get()).data() || {};
    if (run.done === true) return { ...stat, reason: 'DONE' };
    let cursor = run.cursor || null;
    let done = false;
    while (budget.left > 0) {
      let q = db.collection(SELF_BD_INDEX).where('md', 'in', mds).orderBy(admin.firestore.FieldPath.documentId()).limit(Math.min(LIMITS.bdPage, budget.left));
      if (cursor) q = q.startAfter(cursor);
      const snap = await q.get();
      if (snap.empty) { done = true; break; }
      cursor = snap.docs[snap.docs.length - 1].id;
      await runRef.set({ kind: 'self_birthday', date: today, cursor, updatedAt: ts() }, { merge: true });
      for (const d of snap.docs) {
        budget.left -= 1; stat.scanned += 1;
        const x = d.data() || {};
        const personKey = personKeyOf(x.ownerId);
        const us = personKey ? await db.collection('users').doc(String(x.ownerId)).get() : null;
        const u = us && us.exists ? (us.data() || {}) : null;
        const md = u ? mdOfUserBirth(u.birthDate) : null;
        const hit = md ? due[md] : null;
        if (!u || !hit || u.holidayRemindersOptIn === false
          || !occasionVisibleFor(occ, settings, personKey, String(u.role || 'user'), String(u.districtId || ''))) { stat.skipped += 1; continue; }
        const r = hit.reminder;
        const logRef = db.collection(REMIND_LOG).doc(`self_${personKey}_${hit.date.slice(0, 4)}_d${r.daysBefore}`);
        const claimed = await db.runTransaction(async (t) => {
          const s = await t.get(logRef);
          if (s.exists) return false;
          t.create(logRef, { kind: 'self_birthday', personKey, daysBefore: r.daysBefore, year: Number(hit.date.slice(0, 4)), at: ts() });
          return true;
        });
        if (!claimed) { stat.skipped += 1; continue; }
        const tp = targetPush(r.target);
        try {
          await notifyText(personKey, u.appLang, r.texts, { days: r.daysBefore }, {
            source: 'holiday_self_birthday', dataType: 'holiday_self_birthday', screen: tp.screen,
            extraNews: { occasionId: occ.id, daysBefore: r.daysBefore, target: r.target },
            extraData: { daysBefore: String(r.daysBefore), ...tp.data },
          });
          stat.sent += 1;
        } catch (e) { stat.skipped += 1; log({ action: 'holidayReminders', result: 'notify_error', errorCode: 'NOTIFY_FAILED' }); }
      }
      if (snap.size < LIMITS.bdPage) { done = true; break; }
    }
    if (done) await runRef.set({ done: true, updatedAt: ts() }, { merge: true });
    return { ...stat, done };
  }

  async function runHolidayRemindersAll(opts = {}) {
    const nowMs = now();
    const [settings, occSnap] = await Promise.all([smSettings(), db.collection(OCCASIONS).get()]);
    const occasions = occSnap.docs.map((d) => d.data() || {});
    const budget = { left: Number.isInteger(opts.maxPerRun) ? opts.maxPerRun : LIMITS.maxPerRun };
    const birthdays = await runBirthdayReminders(nowMs, settings, occasions, budget);
    const self = await runSelfBirthdayReminders(nowMs, settings, occasions, budget);
    const holidays = await runHolidayReminders(nowMs, settings, occasions, budget);
    log({ action: 'holidayReminders', result: 'ok', birthdays, self, holidays, budgetLeft: budget.left });
    return { birthdays, self, holidays };
  }

  // Ҳар куни 09:00 дан бошлаб (Тошкент); 15 дақиқалик давомлар — фақат курсор тугамаган бўлса иш қилади
  // (идемпотент: бажарилган кун/байрам — `done`, қариндош — log). 21:00 дан кейин юборилмайди.
  exportsObj.holidayReminders = functions.pubsub
    .schedule('*/15 9-20 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(() => runHolidayRemindersAll());

  // ── 7. Совға PII тозалаш (етказилган/бекор қилингандан 1 кун кейин, ҳар соат) ──
  async function runGiftPiiSweep() {
    const nowMs = now();
    const snap = await db.collection(ORDERS).where('giftPurgeAfter', '<=', TS.fromMillis(nowMs)).orderBy('giftPurgeAfter').limit(LIMITS.giftSweep).get();
    let redacted = 0;
    let rescheduled = 0;
    for (const d of snap.docs) {
      const r = await db.runTransaction(async (t) => {
        const s = await t.get(d.ref);
        if (!s.exists) return 'gone';
        const od = s.data() || {};
        const at = msOf(od.giftPurgeAfter);
        if (at == null || at > nowMs) return 'noop';
        const dec = giftPurgeDecision(od, nowMs);
        if (dec.action === 'reschedule') { t.update(d.ref, { giftPurgeAfter: TS.fromMillis(dec.nextMs) }); return 'rescheduled'; }
        const ap = od.addressParts || {};
        t.update(d.ref, {
          gift: { recipientName: '', recipientPhone: '', message: '', hidePrice: true, redacted: true },
          contactPhone: '', address: '', addressParts: { districtId: String(ap.districtId || '') },
          lat: FV.delete(), lng: FV.delete(), giftPurgeAfter: FV.delete(), giftRedactedAt: ts(),
        });
        return 'redacted';
      });
      if (r === 'redacted') redacted += 1; else if (r === 'rescheduled') rescheduled += 1;
    }
    log({ action: 'smGiftPiiSweep', result: 'ok', scanned: snap.size, redacted, rescheduled });
    return { scanned: snap.size, redacted, rescheduled };
  }
  // Ҳар соатда (эга 2026-11-27: 1 кунлик муддат кун бўйи кечикмасин). Индекс: giftPurgeAfter (бир майдон, автоматик).
  exportsObj.smGiftPiiSweep = functions.pubsub.schedule('every 60 minutes').timeZone('Asia/Tashkent').onRun(() => runGiftPiiSweep());

  // Совға олувчига хабар — supermarket.js onSupermarketOrderCancelStock (буюртма курьерга ўтганда, бир марта).
  return { runHolidayRemindersAll, runGiftPiiSweep, grantRelativesBonus };
}

module.exports = {
  attachHoliday,
  // тоза (тестлар)
  dateKeyOf, validDateKey, addDays, daysBetween, startOfKeyMs, mdOfBirth, birthdayMdTargets, remindDaysOf, occasionNextDate,
  holidayDue, validateOccasion, normalizeOccasion, validateBasket, wantedMilli, buildBasketPure, parseGift, slotsForDate,
  terminalOf, giftPurgeDecision, relativeEligible, validateBonusProgram, bonusStageAllows, supermarketGrants, messagesOf,
  mdOfUserBirth, selfRemindersOf, selfDueMap, targetPush, personKeyOf, giftDispatched,
  DEFAULT_SELF_REMINDERS, TARGET_TYPES, SELF_BD_INDEX,
  OCCASIONS, BASKETS, BD_INDEX, REMIND_LOG, RUNS, MAX_AHEAD_DAYS, GIFT_PURGE_DAYS, BONUS_PROGRAM_ID, BONUS_BUCKET,
  BIRTHDAY_TEXT, HOLIDAY_TEXT, GIFT_TEXT, BONUS_TEXT, LIMITS, TIERS, KINDS,
};
