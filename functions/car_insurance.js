/**
 * «Автомобил суғуртаси» (эга қарорлари 2026-11-28).
 *
 * Оқим: ариза (машина маълумоти профилдан, сервер ўқийди) → нарх АДМИН жадвалидан (версияланган, ҳар аризада
 * `tariffVersion`) → тўлов ҲАМЁНДАН (мой дастури чегирмаси 50/100% + AVA бонуси `incentive_grants` сервер
 * томонда) → AVA суғурта агенти полисни ТИЗИМДАН ТАШҚАРИДА расмийлаштиради, файл + рақам + муддатни юклайди →
 * мижоз хабар олади ва иловада полисни кўради; муддат машина профилига ёзилади. Агент бекор қилса — тўлиқ қайтариш.
 * Ҳолатлар: requested → paid → in_progress → issued | cancelled (тўланган бўлса — refunded).
 *
 * Машина рўйхатдан ўтказилганда рағбат (кампания йили бўйича, бир машина + бир шахс; номер + personKey):
 *   (a) AVA бонуси — мавжуд рағбат тизими (`incentive_programs/car_insurance_bonus`, грант `incentive_grants`,
 *       ечиб бўлмайди) ёки
 *   (b) мой алмаштириш дастури — AVA Сервис маркази КУНЛИК ҲИСОБОТИ (сана + номерлар) бўйича: 1 марта → кейинги
 *       суғуртага 50%, 2 марта → 100% (кампания `oilSteps`, админ). Такрор (номер+сана) — ҳисобланмайди.
 * Эслатма: суғурта тугашига 4 ва 3 кун қолганда (ҳар полис муддатига бир мартадан, идемпотент;
 * `users.insuranceRemindersOptIn === false` — юборилмайди).
 *
 * Коллекциялар (ёзиш ФАҚАТ CF):
 *   insurance_config/main               — {stage, internalPhones, pilotDistrictIds, kaskoEnabled, agentPhones,
 *                                          reporterPhones, remindersEnabled, activeTariffVersion}
 *   insurance_tariffs/v{n}              — ўзгармас нарх жадвали {version, rows[{policyType, regionId|'*', vehicleType,
 *                                          termMonths, price}], note}
 *   insurance_campaigns/{year}          — рағбат созламаси (сукут OFF)
 *   insurance_enrollments/{year}_{plateKey}, insurance_enroll_persons/{year}_{personKey}
 *   insurance_requests/{ins_…}          — ариза (эгаси ва админ ўқийди — rules)
 *   insurance_open/{personKey}_{policyType} — битта очиқ ариза қулфи
 *   insurance_events/{auto}             — ўзгармас ҳодисалар журнали
 *   insurance_policy_files/{requestId}  — Storage йўли + token (мижоз ЎҚИМАЙДИ; ҳавола — callable орқали)
 *   insurance_expiry_index/{personKey}  — эслатма учун муддат индекси
 *   insurance_reminder_log/{personKey}_{expiresOn}_d{N}
 *   insurance_service_reports/{auto}, insurance_oil_credits/{plateKey}_{date}
 *
 * Пул — бутун сўм (8-банд). Логда телефон тўлиқ чиқмайди (40-банд). AVA лицензияли суғурта агенти орқали
 * ишлайди — ҳуқуқий жавобгарлик эгада (ҳисоботда очиқ масала).
 */
'use strict';

const crypto = require('crypto');
const inc = require('./incentives');
const settlementLedger = require('./settlement_ledger');
const { personKeyOf, stageAllows, dayKeyOf } = require('./family_links');
const { normalizeLang } = require('./notif_i18n');

const MODULE = 'car_insurance';
const CONFIG = 'insurance_config';
const CONFIG_DOC = 'main';
const TARIFFS = 'insurance_tariffs';
const CAMPAIGNS = 'insurance_campaigns';
const ENROLL = 'insurance_enrollments';
const ENROLL_PERSONS = 'insurance_enroll_persons';
const REQUESTS = 'insurance_requests';
const OPEN = 'insurance_open';
const EVENTS = 'insurance_events';
const FILES = 'insurance_policy_files';
const EXPIRY = 'insurance_expiry_index';
const REMIND_LOG = 'insurance_reminder_log';
const REPORTS = 'insurance_service_reports';
const OIL_CREDITS = 'insurance_oil_credits';
const ADMIN_AUDIT = 'admin_audit';
const BONUS_PROGRAM = 'car_insurance_bonus';

const STAGES = Object.freeze(['off', 'internal', 'pilot', 'public']);
const POLICY_TYPES = Object.freeze(['osago', 'kasko']);
/**
 * Транспорт тоифаси — эга расмий ОСАГО жадвали (2026-11-28): car = «Енгил автомобил», truck = «Юк автомобили»,
 * bus = «Микроавтобус», moto = «Трактор ва мотоцикл» (калитлар аввалги рўйхатдан ўзгармаган — эски аризалар мос).
 */
const VEHICLE_TYPES = Object.freeze(['car', 'truck', 'bus', 'moto']);
/**
 * Нарх ҳудуди (эга жадвали 2026-11-28): tashkent = «Тошкент шаҳри ва Тошкент вилояти», other = «Ўзбекистоннинг бошқа
 * ҳудудлари», cis = «МДҲ давлатларидан кирувчи автомобиллар» (фақат car + truck). Профил туманидан автоматик
 * (tashkent/other), cis — фойдаланувчи танлайди; фойдаланувчи ҳудуд/тоифа/ҳайдовчини тузатиши мумкин (эга).
 */
const ZONES = Object.freeze(['tashkent', 'other', 'cis']);
const TASHKENT_REGION_IDS = Object.freeze(['toshkent_shahri', 'toshkent_viloyati']);
const CIS_VEHICLE_TYPES = Object.freeze(['car', 'truck']);
/** Ҳайдовчилар: limited = «Чекланган», unlimited = «Чекланмаган». */
const DRIVER_SCOPES = Object.freeze(['limited', 'unlimited']);
/** Ҳудуд × тоифа × ҳайдовчи жадвали (schema 2). Эски (schema йўқ) жадваллар — вилоят қаторлари, фақат ўқиш. */
const TARIFF_SCHEMA = 2;
/**
 * Эга расмий ОСАГО жадвали (2026-11-28), сўм, 12 ой — ФАҚАТ админ таҳрирловчисига ҚОРАЛАМА (`adminInsuranceGetSettings`
 * `draftRows`). Нарх админ «Эълон қилиш» босгандагина (янги версия) кучга киради; бу ерда ҳеч нарса ёзилмайди.
 */
const OSAGO_OWNER_TABLE_2026_11_28 = Object.freeze({
  tashkent: { car: [192000, 384000], truck: [336000, 672000], bus: [384000, 768000], moto: [72000, 144000] },
  other: { car: [160000, 320000], truck: [280000, 560000], bus: [320000, 640000], moto: [60000, 120000] },
  cis: { car: [320000, 640000], truck: [560000, 1120000] },
});
function ownerDraftRows() {
  const rows = [];
  for (const zone of ZONES) {
    for (const vehicleType of VEHICLE_TYPES) {
      const p = OSAGO_OWNER_TABLE_2026_11_28[zone][vehicleType];
      if (!p) continue;
      DRIVER_SCOPES.forEach((driverScope, i) => rows.push({ policyType: 'osago', zone, vehicleType, driverScope, termMonths: 12, price: p[i] }));
    }
  }
  return rows;
}
const STATUSES = Object.freeze(['requested', 'paid', 'in_progress', 'issued', 'cancelled']);
/** Рухсат этилган ўтишлар (17-банд). */
const TRANSITIONS = Object.freeze({
  requested: ['paid', 'cancelled'],
  paid: ['in_progress', 'issued', 'cancelled'],
  in_progress: ['issued', 'cancelled'],
  issued: [],
  cancelled: [],
});
const OPEN_STATUSES = Object.freeze(['requested', 'paid', 'in_progress']);
const OPTIONS = Object.freeze(['bonus', 'oil']);
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
/** Агент/ҳисобот топширувчи: админ, ёки панел ходими + рухсат рўйхатида (agentPhones/reporterPhones). */
const STAFF_ROLES = Object.freeze(['admin', 'superadmin', 'dispatcher', 'staff', 'finance']);
const REMIND_DAYS = Object.freeze([4, 3]);
const DAY_MS = 86400000;
const TZ_OFFSET_MS = 5 * 3600000;
const MAX_PRICE = 100000000;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MAX_REPORT_PLATES = 300;
const REPORT_MAX_AGE_DAYS = 7; // PROPOSED: ҳисобот кечи билан 7 кун ичида
const IDEM_RE = /^[A-Za-z0-9_-]{8,64}$/;
const REQ_ID_RE = /^ins_[A-Za-z0-9_-]{8,100}$/;
const GEO_RE = /^[a-z0-9_-]{2,40}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const PHONE_RE = /^998\d{9}$/;

const TEXT = Object.freeze({
  INVALID_REQUEST: ['Маълумот нотўғри.', "Ma'lumot notöğri.", 'Неверные данные.'],
  UNAUTHENTICATED: ['Ҳисобга киринг.', 'Hisobga kiring.', 'Войдите в аккаунт.'],
  PERMISSION_DENIED: ['Рухсат йўқ.', 'Ruxsat yöq.', 'Нет доступа.'],
  NOT_AVAILABLE: ['Суғурта хизмати ҳозирча мавжуд эмас.', 'Suğurta xizmati hozirça mavjud emas.', 'Услуга страхования пока недоступна.'],
  CAR_PROFILE_REQUIRED: ['Аввал машина маълумотини тўлдиринг.', "Avval maşina ma'lumotini töldiring.", 'Сначала заполните данные автомобиля.'],
  POLICY_TYPE_OFF: ['Бу суғурта тури ҳозирча мавжуд эмас.', 'Bu suğurta turi hozirça mavjud emas.', 'Этот вид страхования пока недоступен.'],
  TARIFF_NOT_FOUND: ['Бу танлов учун нарх белгиланмаган.', 'Bu tanlov uçun narx belgilanmagan.', 'Цена для этого выбора не задана.'],
  OPEN_REQUEST_EXISTS: ['Сизда бу тур бўйича очиқ ариза бор.', "Sizda bu tur böyiça oçiq ariza bor.", 'У вас уже есть открытая заявка этого вида.'],
  REQUEST_NOT_FOUND: ['Ариза топилмади.', 'Ariza topilmadi.', 'Заявка не найдена.'],
  REQUEST_CLOSED: ['Ариза ёпилган.', 'Ariza yopilgan.', 'Заявка закрыта.'],
  INVALID_TRANSITION: ['Бу амални ҳозир бажариб бўлмайди.', "Bu amalni hozir bajarib bölmaydi.", 'Это действие сейчас недоступно.'],
  INSUFFICIENT_BALANCE: ['Ҳамёнда маблағ етарли эмас. Ҳамённи тўлдиринг.', "Hamyonda mablağ yetarli emas. Hamyonni töldiring.", 'Недостаточно средств в кошельке. Пополните кошелёк.'],
  CAMPAIGN_OFF: ['Бу таклиф ҳозирча мавжуд эмас.', 'Bu taklif hozirça mavjud emas.', 'Это предложение пока недоступно.'],
  OPTION_OFF: ['Бу танлов ҳозирча мавжуд эмас.', 'Bu tanlov hozirça mavjud emas.', 'Этот вариант пока недоступен.'],
  PLATE_ALREADY_ENROLLED: ['Бу машина аллақачон рўйхатдан ўтган.', "Bu maşina allaqaçon röyxatdan ötgan.", 'Этот автомобиль уже зарегистрирован.'],
  PERSON_ALREADY_ENROLLED: ['Сиз бу йил таклифдан фойдалангансиз.', 'Siz bu yil taklifdan foydalangansiz.', 'Вы уже воспользовались предложением в этом году.'],
  BUDGET_EXHAUSTED: ['Бонус бюджети тугади.', 'Bonus byudjeti tugadi.', 'Бюджет бонусов исчерпан.'],
  DATE_INVALID: ['Сана нотўғри.', 'Sana notöğri.', 'Неверная дата.'],
  FILE_INVALID: ['Файл PDF ёки расм (≤5 МБ) бўлиши керак.', "Fayl PDF yoki rasm (≤5 MB) bölişi kerak.", 'Файл должен быть PDF или изображением (≤5 МБ).'],
  POLICY_FILE_MISSING: ['Полис файли топилмади.', 'Polis fayli topilmadi.', 'Файл полиса не найден.'],
  CENTER_NOT_FOUND: ['Сервис маркази топилмади.', 'Servis markazi topilmadi.', 'Сервисный центр не найден.'],
  CONFIG_INVALID: ['Созлама нотўғри.', 'Sozlama notöğri.', 'Неверные настройки.'],
  TARIFF_INVALID: ['Нарх жадвали нотўғри.', "Narx jadvali notöğri.", 'Неверная таблица цен.'],
  CIS_VEHICLE_NOT_ALLOWED: [
    'Чет эл (МДҲ) рақамли автомобил учун фақат енгил ёки юк автомобили.',
    'Çet el (MDH) raqamli avtomobil uçun faqat yengil yoki yuk avtomobili.',
    'Для автомобилей с номерами СНГ — только легковой или грузовой.',
  ],
  CAMPAIGN_INVALID: ['Таклиф созламаси нотўғри.', "Taklif sozlamasi notöğri.", 'Неверные настройки предложения.'],
  REASON_REQUIRED: ['Сабабни ёзинг.', 'Sababni yozing.', 'Укажите причину.'],
});
function messagesOf(code) {
  const t = TEXT[code] || TEXT.INVALID_REQUEST;
  return { uz_Cyrl: t[0], uz_Latn: t[1], ru: t[2] };
}

const POLICY_NAMES = Object.freeze({
  osago: { uz_Cyrl: 'ОСАГО', uz_Latn: 'OSAGO', ru: 'ОСАГО' },
  kasko: { uz_Cyrl: 'КАСКО', uz_Latn: 'KASKO', ru: 'КАСКО' },
});

/** Хабарлар (3 тил). */
const NOTICE = Object.freeze({
  paid: {
    uz_Cyrl: { title: 'Суғурта аризаси тўланди', body: '{policy} аризангиз қабул қилинди. Полис тайёр бўлгач хабар берамиз.' },
    uz_Latn: { title: "Suğurta arizasi tölandi", body: "{policy} arizangiz qabul qilindi. Polis tayyor bölgaç xabar beramiz." },
    ru: { title: 'Заявка на страховку оплачена', body: 'Ваша заявка {policy} принята. Сообщим, когда полис будет готов.' },
  },
  issued: {
    uz_Cyrl: { title: 'Суғурта полисингиз тайёр', body: '{policy} полиси № {number}, {to} гача амал қилади. Иловада кўришингиз мумкин.' },
    uz_Latn: { title: 'Suğurta polisingiz tayyor', body: "{policy} polisi № {number}, {to} gaça amal qiladi. Ilovada körişingiz mumkin." },
    ru: { title: 'Ваш страховой полис готов', body: 'Полис {policy} № {number} действует до {to}. Его можно посмотреть в приложении.' },
  },
  cancelled: {
    uz_Cyrl: { title: 'Суғурта аризаси бекор қилинди', body: '{policy} аризангиз бекор қилинди. Тўланган маблағ қайтарилди.' },
    uz_Latn: { title: 'Suğurta arizasi bekor qilindi', body: "{policy} arizangiz bekor qilindi. Tölangan mablağ qaytarildi." },
    ru: { title: 'Заявка на страховку отменена', body: 'Ваша заявка {policy} отменена. Оплаченная сумма возвращена.' },
  },
  remind: {
    uz_Cyrl: { title: 'Суғурта муддати тугаяпти', body: 'Машинангиз суғуртаси {days} кундан кейин ({date}) тугайди. Иловада янгилашингиз мумкин.' },
    uz_Latn: { title: 'Suğurta muddati tugayapti', body: "Maşinangiz suğurtasi {days} kundan keyin ({date}) tugaydi. Ilovada yangilaşingiz mumkin." },
    ru: { title: 'Страховка скоро закончится', body: 'Страховка вашего автомобиля закончится через {days} дн. ({date}). Продлить можно в приложении.' },
  },
  bonus: {
    uz_Cyrl: { title: 'Табриклаймиз!', body: 'Ҳисобингизга {amount} сўм AVA бонуси тушди, {days} кун амал қилади.' },
    uz_Latn: { title: 'Tabriklaymiz!', body: "Hisobingizga {amount} söm AVA bonusi tuşdi, {days} kun amal qiladi." },
    ru: { title: 'Поздравляем!', body: 'На ваш счёт зачислен бонус AVA {amount} сум, действует {days} дней.' },
  },
  oil: {
    uz_Cyrl: { title: 'Мой алмаштириш ҳисобланди', body: '{n}/{goal} мой алмаштириш — кейинги суғуртага {pct}% чегирма тайёр.' },
    uz_Latn: { title: 'Moy almaştiriş hisoblandi', body: "{n}/{goal} moy almaştiriş — keyingi suğurtaga {pct}% çegirma tayyor." },
    ru: { title: 'Замена масла засчитана', body: '{n}/{goal} замен масла — скидка {pct}% на следующую страховку готова.' },
  },
  agent_new: {
    uz_Cyrl: { title: 'Янги суғурта аризаси', body: '{policy} аризаси тўланди — полисни расмийлаштиринг.' },
    uz_Latn: { title: 'Yangi suğurta arizasi', body: "{policy} arizasi tölandi — polisni rasmiylaştiring." },
    ru: { title: 'Новая заявка на страховку', body: 'Заявка {policy} оплачена — оформите полис.' },
  },
});

// ══════════════════════ ТОЗА ФУНКЦИЯЛАР ══════════════════════

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isInt = (v, min, max) => Number.isSafeInteger(v) && v >= min && v <= max;
const fill = (s, p) => String(s).replace(/\{(\w+)\}/g, (m, k) => (p[k] == null ? m : String(p[k])));
const money = (n) => Number(n || 0).toLocaleString('ru-RU').replace(/\s/g, ' ');

/** Кирилл ҳарфлари лотин ўхшашига (номер киритишдаги аралашма) — фақат мос шакллар. */
const CYR_TO_LAT = Object.freeze({
  А: 'A', В: 'B', Е: 'E', К: 'K', М: 'M', Н: 'H', О: 'O', Р: 'P', С: 'C', Т: 'T', Х: 'X', У: 'Y',
});
/** Давлат рақами калити: катта ҳарф, кирилл→лотин ўхшаш, фақат A-Z0-9; 5..12 белги, бўлмаса ''. */
function normalizePlate(raw) {
  const up = String(raw || '').toUpperCase();
  let out = '';
  for (const ch of up) {
    const c = CYR_TO_LAT[ch] || ch;
    if (/[A-Z0-9]/.test(c)) out += c;
  }
  return out.length >= 5 && out.length <= 12 ? out : '';
}

/** 'YYYY-MM-DD' — ҳақиқий сана ёки false. */
function dateOk(s) {
  if (typeof s !== 'string' || !DATE_RE.test(s)) return false;
  const [y, m, d] = s.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d && y >= 2000 && y <= 2100;
}
/** Тошкент кунига N кун қўшиш. */
function addDaysKey(key, n) {
  const [y, m, d] = key.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d) + n * DAY_MS);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}
function tashkentYear(ms) {
  return new Date(ms + TZ_OFFSET_MS).getUTCFullYear();
}
/** 'YYYY-MM-DD' → 'DD.MM.YYYY'. */
function displayDate(key) {
  return dateOk(key) ? key.split('-').reverse().join('.') : String(key || '');
}

function cleanPhones(list) {
  if (!Array.isArray(list)) return null;
  const out = [];
  for (const x of list) {
    const k = personKeyOf(x);
    if (!k) return null;
    if (!out.includes(k)) out.push(k);
  }
  return out.length <= 50 ? out : null;
}

/** Админ созламаси (соф). → {ok, value|errors}. */
function validateConfig(input) {
  const p = isObj(input) ? input : {};
  const errors = [];
  if (!STAGES.includes(p.stage)) errors.push('STAGE_INVALID');
  const internalPhones = cleanPhones(p.internalPhones || []);
  if (!internalPhones) errors.push('INTERNAL_PHONES_INVALID');
  const pilot = Array.isArray(p.pilotDistrictIds) ? p.pilotDistrictIds.map((x) => String(x).trim()) : [];
  if (pilot.length > 50 || !pilot.every((x) => GEO_RE.test(x))) errors.push('PILOT_DISTRICTS_INVALID');
  const agentPhones = cleanPhones(p.agentPhones || []);
  if (!agentPhones) errors.push('AGENT_PHONES_INVALID');
  const reporterPhones = cleanPhones(p.reporterPhones || []);
  if (!reporterPhones) errors.push('REPORTER_PHONES_INVALID');
  if (p.kaskoEnabled != null && typeof p.kaskoEnabled !== 'boolean') errors.push('KASKO_INVALID');
  if (p.remindersEnabled != null && typeof p.remindersEnabled !== 'boolean') errors.push('REMINDERS_INVALID');
  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    value: {
      stage: p.stage, internalPhones, pilotDistrictIds: pilot, agentPhones, reporterPhones,
      kaskoEnabled: p.kaskoEnabled === true, remindersEnabled: p.remindersEnabled !== false,
    },
  };
}

/** Ҳудуд учун рухсат этилган тоифалар (cis — фақат енгил ва юк). */
const vehiclesForZone = (zone) => (zone === 'cis' ? CIS_VEHICLE_TYPES : VEHICLE_TYPES);

/**
 * Нарх жадвали (соф, schema 2): rows [{policyType, zone, vehicleType, driverScope, termMonths, price}]. Ҳар
 * (policyType, termMonths) гуруҳида БАРЧА комбинация шарт: tashkent/other × 4 тоифа × 2, cis × 2 тоифа × 2 = 20 қатор;
 * етишмаган — `MISSING …`, cis + микроавтобус/трактор — `ROW_i_CIS_VEHICLE`. Нарх — бутун сўм.
 */
function validateTariffRows(rows) {
  const errors = [];
  if (!Array.isArray(rows) || rows.length < 1 || rows.length > 500) return { ok: false, errors: ['ROWS_COUNT'] };
  const seen = new Set();
  const groups = new Set();
  const clean = [];
  rows.forEach((r, i) => {
    const x = isObj(r) ? r : {};
    const row = {
      policyType: String(x.policyType || ''), zone: String(x.zone || ''), vehicleType: String(x.vehicleType || ''),
      driverScope: String(x.driverScope || ''), termMonths: x.termMonths, price: x.price,
    };
    if (!POLICY_TYPES.includes(row.policyType)) errors.push(`ROW_${i}_POLICY`);
    if (!ZONES.includes(row.zone)) errors.push(`ROW_${i}_ZONE`);
    if (!VEHICLE_TYPES.includes(row.vehicleType)) errors.push(`ROW_${i}_VEHICLE`);
    else if (row.zone === 'cis' && !CIS_VEHICLE_TYPES.includes(row.vehicleType)) errors.push(`ROW_${i}_CIS_VEHICLE`);
    if (!DRIVER_SCOPES.includes(row.driverScope)) errors.push(`ROW_${i}_SCOPE`);
    if (!isInt(row.termMonths, 1, 36)) errors.push(`ROW_${i}_TERM`);
    if (!isInt(row.price, 1, MAX_PRICE)) errors.push(`ROW_${i}_PRICE`);
    const k = `${row.policyType}|${row.zone}|${row.vehicleType}|${row.driverScope}|${row.termMonths}`;
    if (seen.has(k)) errors.push(`ROW_${i}_DUPLICATE`);
    seen.add(k);
    if (POLICY_TYPES.includes(row.policyType) && isInt(row.termMonths, 1, 36)) groups.add(`${row.policyType}|${row.termMonths}`);
    clean.push(row);
  });
  for (const g of groups) {
    const [policyType, term] = g.split('|');
    for (const zone of ZONES) {
      for (const vehicleType of vehiclesForZone(zone)) {
        for (const driverScope of DRIVER_SCOPES) {
          const k = `${policyType}|${zone}|${vehicleType}|${driverScope}|${term}`;
          if (!seen.has(k)) errors.push(`MISSING ${k}`);
        }
      }
    }
  }
  return errors.length ? { ok: false, errors } : { ok: true, rows: clean };
}

/** Профил вилоятидан ҳудуд (соф): Тошкент шаҳри/вилояти → tashkent, бошқаси (номаълум ҳам) → other. */
function zoneForRegion(regionId) {
  return TASHKENT_REGION_IDS.includes(String(regionId || '')) ? 'tashkent' : 'other';
}

/** schema 2 нархи (соф): аниқ мос қатор ёки null. */
function findZoneTariffRow(rows, { policyType, zone, vehicleType, driverScope, termMonths }) {
  const list = Array.isArray(rows) ? rows : [];
  return list.find((r) => r.policyType === policyType && r.zone === zone && r.vehicleType === vehicleType
    && r.driverScope === driverScope && r.termMonths === termMonths) || null;
}

/** schema 2 танловлари (соф): рухсат этилган турлар, барча ҳудудлар (клиент олдиндан кўради; нарх серверда қайта). */
function zoneTariffOptions(rows, policyTypes) {
  const zi = (z) => ZONES.indexOf(z);
  const vi = (v) => VEHICLE_TYPES.indexOf(v);
  const si = (s) => DRIVER_SCOPES.indexOf(s);
  return (Array.isArray(rows) ? rows : [])
    .filter((r) => policyTypes.includes(r.policyType))
    .map((r) => ({ policyType: r.policyType, zone: r.zone, vehicleType: r.vehicleType, driverScope: r.driverScope, termMonths: r.termMonths, price: r.price }))
    .sort((a, b) => a.policyType.localeCompare(b.policyType) || zi(a.zone) - zi(b.zone) || vi(a.vehicleType) - vi(b.vehicleType)
      || si(a.driverScope) - si(b.driverScope) || a.termMonths - b.termMonths);
}

const isZoneTariff = (tariff) => !!tariff && tariff.schema === TARIFF_SCHEMA;

/** ЭСКИ (schema йўқ) жадвал: аниқ вилоят қатори устун, бўлмаса '*' (соф). → row | null. Фақат олдин эълон қилинганлар учун. */
function findTariffRow(rows, { policyType, regionId, vehicleType, termMonths }) {
  const list = Array.isArray(rows) ? rows : [];
  const match = (r, reg) => r.policyType === policyType && r.vehicleType === vehicleType
    && r.termMonths === termMonths && r.regionId === reg;
  return (regionId && list.find((r) => match(r, regionId))) || list.find((r) => match(r, '*')) || null;
}

/** Фойдаланувчи вилояти учун танловлар (вилоят қатори '*' устидан ёзади), рухсат этилган турлар (соф). */
function tariffOptionsFor(rows, regionId, policyTypes) {
  const out = new Map();
  for (const r of Array.isArray(rows) ? rows : []) {
    if (!policyTypes.includes(r.policyType)) continue;
    if (r.regionId !== '*' && r.regionId !== regionId) continue;
    const k = `${r.policyType}|${r.vehicleType}|${r.termMonths}`;
    const prev = out.get(k);
    if (!prev || (prev.regionId === '*' && r.regionId !== '*')) out.set(k, r);
  }
  return [...out.values()]
    .map((r) => ({ policyType: r.policyType, vehicleType: r.vehicleType, termMonths: r.termMonths, price: r.price }))
    .sort((a, b) => a.policyType.localeCompare(b.policyType) || a.vehicleType.localeCompare(b.vehicleType) || a.termMonths - b.termMonths);
}

/** Мой дастури босқичлари [{count, pct}] (соф): count 1..10 ўсувчи, pct 1..100 камаймайдиган. */
function validOilSteps(steps) {
  if (!Array.isArray(steps) || steps.length < 1 || steps.length > 5) return false;
  let prevC = 0; let prevP = 0;
  for (const s of steps) {
    if (!isObj(s) || !isInt(s.count, 1, 10) || !isInt(s.pct, 1, 100)) return false;
    if (s.count <= prevC || s.pct < prevP) return false;
    prevC = s.count; prevP = s.pct;
  }
  return true;
}
/** Мой алмаштиришлар сонига мос чегирма фоизи (соф). */
function oilDiscountPct(oilChanges, steps) {
  let pct = 0;
  for (const s of Array.isArray(steps) ? steps : []) if (oilChanges >= s.count) pct = Math.max(pct, s.pct);
  return pct;
}
function oilGoal(steps) {
  return Array.isArray(steps) && steps.length ? steps[steps.length - 1].count : 0;
}

const CAMPAIGN_KEYS = ['stage', 'internalPhones', 'pilotDistrictIds', 'bonusEnabled', 'bonusAmount', 'bonusValidityDays',
  'bonusMaxOrderSharePct', 'bonusBudgetTotal', 'oilEnabled', 'oilSteps'];
/** Кампания (бир полис йили) созламаси (соф). */
function validateCampaign(year, input) {
  const p = isObj(input) ? input : {};
  const errors = [];
  if (!isInt(year, 2026, 2100)) errors.push('YEAR_INVALID');
  for (const k of Object.keys(p)) if (!CAMPAIGN_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${k}`);
  if (!STAGES.includes(p.stage)) errors.push('STAGE_INVALID');
  const internalPhones = cleanPhones(p.internalPhones || []);
  if (!internalPhones) errors.push('INTERNAL_PHONES_INVALID');
  const pilot = Array.isArray(p.pilotDistrictIds) ? p.pilotDistrictIds.map((x) => String(x).trim()) : [];
  if (pilot.length > 50 || !pilot.every((x) => GEO_RE.test(x))) errors.push('PILOT_DISTRICTS_INVALID');
  const bonusEnabled = p.bonusEnabled === true;
  const oilEnabled = p.oilEnabled === true;
  if (bonusEnabled) {
    if (!isInt(p.bonusAmount, 1, 10000000)) errors.push('BONUS_AMOUNT_INVALID');
    if (!isInt(p.bonusValidityDays, 1, 365)) errors.push('BONUS_VALIDITY_INVALID');
    if (!isInt(p.bonusMaxOrderSharePct, 1, 100)) errors.push('BONUS_SHARE_INVALID');
    if (!isInt(p.bonusBudgetTotal, Number.isSafeInteger(p.bonusAmount) ? p.bonusAmount : 1, 100000000000)) errors.push('BONUS_BUDGET_INVALID');
  }
  if (oilEnabled && !validOilSteps(p.oilSteps)) errors.push('OIL_STEPS_INVALID');
  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    value: {
      year, stage: p.stage, internalPhones, pilotDistrictIds: pilot,
      bonusEnabled, bonusAmount: bonusEnabled ? p.bonusAmount : 0, bonusValidityDays: bonusEnabled ? p.bonusValidityDays : 0,
      bonusMaxOrderSharePct: bonusEnabled ? p.bonusMaxOrderSharePct : 0, bonusBudgetTotal: bonusEnabled ? p.bonusBudgetTotal : 0,
      oilEnabled, oilSteps: oilEnabled ? p.oilSteps.map((s) => ({ count: s.count, pct: s.pct })) : [],
    },
  };
}

/**
 * Тўлов тақсимоти (соф): нарх → мой чегирмаси (pct) → AVA бонуси (`incentive_grants`, туркум 'insurance';
 * 'any' грант ҳам қоплайди, ҳар грант ўз улуш чегараси билан) → қолгани ҳамёндан.
 */
function computePayment({ price, oilPct, grants, walletBalance, nowMs }) {
  const pct = isInt(oilPct, 0, 100) ? oilPct : 0;
  const oilDiscount = pct >= 100 ? price : Math.floor(price * pct / 100);
  const afterOil = price - oilDiscount;
  const plan = afterOil > 0
    ? inc.computeIncentivePlan(grants || [], [{ category: 'insurance', total: afterOil }], nowMs)
    : { total: 0, perGrant: [], itemsTotal: 0 };
  const walletDue = afterOil - plan.total;
  const balance = Number.isSafeInteger(walletBalance) ? walletBalance : 0;
  return { price, oilPct: pct, oilDiscount, afterOil, incentive: plan.total, plan, walletDue, sufficient: walletDue <= balance };
}

function canTransition(from, to) {
  return Array.isArray(TRANSITIONS[from]) && TRANSITIONS[from].includes(to);
}

/** Эслатма кунлари (соф): [{n, date}] — бугун + N кун. */
function reminderTargets(nowMs, days = REMIND_DAYS) {
  const today = dayKeyOf(nowMs);
  return days.map((n) => ({ n, date: addDaysKey(today, n) }));
}

/** Файл тури (магик байтлар) → {contentType, ext} | null. */
function sniffFile(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;
  if (buf.slice(0, 5).toString('latin1') === '%PDF-') return { contentType: 'application/pdf', ext: 'pdf' };
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return { contentType: 'image/jpeg', ext: 'jpg' };
  if (buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return { contentType: 'image/png', ext: 'png' };
  if (buf.slice(0, 4).toString('latin1') === 'RIFF' && buf.slice(8, 12).toString('latin1') === 'WEBP') return { contentType: 'image/webp', ext: 'webp' };
  return null;
}

/** Мижозга кўринадиган ариза шакли (ички майдонларсиз). */
function requestView(id, r) {
  const x = r || {};
  const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : (Number.isFinite(v) ? v : null));
  return {
    requestId: id, status: x.status, policyType: x.policyType, vehicleType: x.vehicleType, termMonths: x.termMonths,
    zone: x.zone || '', driverScope: x.driverScope || '',
    car: x.car || {}, tariffVersion: x.tariffVersion, price: x.price || 0,
    oilDiscountPct: x.oilDiscountPct || 0, oilDiscount: x.oilDiscount || 0, incentiveApplied: x.incentiveApplied || 0,
    walletPaid: x.walletPaid || 0,
    policy: x.policy ? { number: x.policy.number, validFrom: x.policy.validFrom, validTo: x.policy.validTo, contentType: x.policy.contentType } : null,
    cancelReason: x.cancelReason || '', refund: x.refund || null,
    createdAtMs: toMs(x.createdAt), paidAtMs: toMs(x.paidAt), issuedAtMs: toMs(x.issuedAt), cancelledAtMs: toMs(x.cancelledAt),
  };
}

// ══════════════════════ CLOUD FUNCTIONS ══════════════════════

function attachCarInsurance(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const TS = admin.firestore.Timestamp;
  const ts = () => FV.serverTimestamp();
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (o) => console.log(JSON.stringify({ module: MODULE, ...o }));
  const tail = (p) => `***${String(p || '').slice(-4)}`;
  /** Storage: {save(path, buf, contentType) → {token, bucket}}; тестда алмаштирилади. */
  const storage = deps.storage || {
    async save(path, buf, contentType) {
      const bucket = admin.storage().bucket();
      const token = crypto.randomUUID();
      await bucket.file(path).save(buf, { resumable: false, metadata: { contentType, metadata: { firebaseStorageDownloadTokens: token } } });
      return { token, bucket: bucket.name };
    },
  };

  function callerKey(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const key = personKeyOf(canonicalUid(callerPhone(context)));
    if (!key) throw fail('unauthenticated', 'UNAUTHENTICATED');
    return key;
  }
  /** Ҳисоб ҳужжати: канон (998…) бўлса — у, йўқ бўлса — эски 9 хонали. */
  async function userDoc(key) {
    for (const id of [key, key.slice(3)]) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return { ref: s.ref, id: s.id, data: s.data() || {} };
    }
    return null;
  }
  async function roleGate(context, roles, listField) {
    let actor;
    try {
      actor = await requireCallerRoles(context, roles, 'Role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
    if (!listField) return actor;
    const role = String(((await db.collection('users').doc(actor).get()).data() || {}).role || '');
    if (ADMIN_ROLES.includes(role)) return actor;
    const cfg = await loadConfig();
    if (!(cfg[listField] || []).includes(personKeyOf(actor))) throw fail('permission-denied', 'PERMISSION_DENIED');
    return actor;
  }
  const requireAdmin = (context) => roleGate(context, ADMIN_ROLES, null);
  const requireAgent = (context) => roleGate(context, STAFF_ROLES, 'agentPhones');
  const requireReporter = (context) => roleGate(context, STAFF_ROLES, 'reporterPhones');

  const configRef = () => db.collection(CONFIG).doc(CONFIG_DOC);
  async function loadConfig() {
    const s = await configRef().get();
    const d = s.exists ? (s.data() || {}) : {};
    return {
      stage: STAGES.includes(d.stage) ? d.stage : 'off',
      internalPhones: Array.isArray(d.internalPhones) ? d.internalPhones : [],
      pilotDistrictIds: Array.isArray(d.pilotDistrictIds) ? d.pilotDistrictIds : [],
      agentPhones: Array.isArray(d.agentPhones) ? d.agentPhones : [],
      reporterPhones: Array.isArray(d.reporterPhones) ? d.reporterPhones : [],
      kaskoEnabled: d.kaskoEnabled === true,
      remindersEnabled: d.remindersEnabled !== false,
      activeTariffVersion: Number.isSafeInteger(d.activeTariffVersion) ? d.activeTariffVersion : 0,
    };
  }
  async function loadTariff(version) {
    if (!version) return null;
    const s = await db.collection(TARIFFS).doc(`v${version}`).get();
    return s.exists ? (s.data() || null) : null;
  }
  async function regionOf(districtId) {
    const id = String(districtId || '').trim();
    if (!GEO_RE.test(id)) return '';
    const s = await db.collection('geo_districts').doc(id).get();
    return s.exists ? String((s.data() || {}).regionId || '') : '';
  }
  const policyTypesOf = (cfg) => (cfg.kaskoEnabled ? ['osago', 'kasko'] : ['osago']);
  function carOf(u) {
    const d = u || {};
    const plate = String(d.carPlate || '').trim().toUpperCase();
    return {
      brand: String(d.carBrand || '').trim().slice(0, 40), model: String(d.carModel || '').trim().slice(0, 60),
      year: Number.isSafeInteger(d.carYear) ? d.carYear : (parseInt(String(d.carYear || 0), 10) || 0),
      color: String(d.carColor || '').trim().slice(0, 30), plate: plate.slice(0, 20), plateKey: normalizePlate(plate),
    };
  }
  const langOf = (u) => normalizeLang((u && u.data && u.data.appLang) || 'uz_Cyrl');
  async function notify(userId, lang, kind, params, extra = {}) {
    const t = NOTICE[kind][normalizeLang(lang)] || NOTICE[kind].uz_Cyrl;
    try {
      await notifyUserInApp({ userId, title: t.title, body: fill(t.body, params), category: 'info', source: `insurance_${kind}`, dataType: `insurance_${kind}`, screen: 'car_insurance', ...extra });
    } catch (e) { log({ action: 'notify', result: 'error', errorCode: 'NOTIFY_FAILED', kind }); }
  }
  const policyName = (type, lang) => (POLICY_NAMES[type] || POLICY_NAMES.osago)[normalizeLang(lang)];
  function event(t, requestId, type, actor, extra = {}) {
    t.create(db.collection(EVENTS).doc(), { requestId, type, actor, at: ts(), ...extra });
  }
  async function campaignFor(nowMs) {
    const year = tashkentYear(nowMs);
    const s = await db.collection(CAMPAIGNS).doc(String(year)).get();
    return s.exists ? { year, ...(s.data() || {}) } : null;
  }

  // ── Фойдаланувчи ──

  /** Ҳолат: мавжудми, танловлар/нархлар, машина, суғурта муддати, кампания ва менинг рағбатим. */
  exportsObj.insuranceGetMyState = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const [cfg, user] = await Promise.all([loadConfig(), userDoc(key)]);
    const u = user ? user.data : {};
    const available = !!user && stageAllows(cfg, key, u.districtId);
    const ci = isObj(u.carInsurance) ? u.carInsurance : null;
    const out = {
      ok: true, available, kaskoEnabled: cfg.kaskoEnabled, options: [], tariffVersion: 0, tariffSchema: 1,
      derivedZone: 'other', zones: ZONES, driverScopes: DRIVER_SCOPES, cisVehicleTypes: CIS_VEHICLE_TYPES,
      car: { ...carOf(u), complete: inc.hasCarProfile(u) },
      carInsurance: ci ? { expiresOn: ci.expiresOn || '', policyType: ci.policyType || '', source: ci.source || '' } : null,
      remindersOptIn: u.insuranceRemindersOptIn !== false,
      campaign: null, enrollment: null,
    };
    if (!available) return out;
    const tariff = await loadTariff(cfg.activeTariffVersion);
    const regionId = await regionOf(u.districtId);
    out.derivedZone = zoneForRegion(regionId);
    if (tariff) {
      out.tariffVersion = tariff.version;
      if (isZoneTariff(tariff)) {
        out.tariffSchema = TARIFF_SCHEMA;
        out.options = zoneTariffOptions(tariff.rows, policyTypesOf(cfg));
      } else {
        out.options = tariffOptionsFor(tariff.rows, regionId, policyTypesOf(cfg));
      }
    }
    const nowMs = now();
    const camp = await campaignFor(nowMs);
    if (camp && stageAllows(camp, key, u.districtId) && (camp.bonusEnabled || camp.oilEnabled)) {
      out.campaign = {
        year: camp.year, bonusEnabled: camp.bonusEnabled === true, bonusAmount: camp.bonusAmount || 0,
        bonusValidityDays: camp.bonusValidityDays || 0, oilEnabled: camp.oilEnabled === true, oilSteps: camp.oilSteps || [],
      };
    }
    const es = await db.collection(ENROLL).where('uid', '==', key).get();
    const mine = es.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => (b.year || 0) - (a.year || 0))[0];
    if (mine) {
      out.enrollment = {
        year: mine.year, option: mine.option, plate: mine.plate, status: mine.status, oilChanges: mine.oilChanges || 0,
        oilGoal: oilGoal(mine.oilSteps), discountPct: mine.discountUsedRequestId ? 0 : oilDiscountPct(mine.oilChanges || 0, mine.oilSteps),
        discountUsed: !!mine.discountUsedRequestId,
      };
    }
    return out;
  });

  /** Ариза: { policyType, vehicleType, termMonths, idempotencyKey } → { requestId, price, tariffVersion, duplicate }. */
  exportsObj.insuranceCreateRequest = functions.https.onCall(async (data, context) => {
    const started = now();
    const key = callerKey(context);
    const d = isObj(data) ? data : {};
    const policyType = String(d.policyType || '');
    const vehicleType = String(d.vehicleType || '');
    const termMonths = d.termMonths;
    const idem = String(d.idempotencyKey || '');
    // Эга 2026-11-28: ҳудуд (бўш — профилдан автоматик; фойдаланувчи тузатиши мумкин) ва ҳайдовчилар доираси.
    const zoneIn = d.zone == null ? '' : String(d.zone);
    const driverScopeIn = d.driverScope == null ? '' : String(d.driverScope);
    if (!POLICY_TYPES.includes(policyType) || !VEHICLE_TYPES.includes(vehicleType) || !isInt(termMonths, 1, 36) || !IDEM_RE.test(idem)
      || (zoneIn && !ZONES.includes(zoneIn)) || (driverScopeIn && !DRIVER_SCOPES.includes(driverScopeIn))) {
      throw fail('invalid-argument', 'INVALID_REQUEST');
    }
    const requestId = `ins_${key}_${idem}`;
    const reqRef = db.collection(REQUESTS).doc(requestId);
    const existing = await reqRef.get();
    if (existing.exists) {
      if (existing.data().uid !== key) throw fail('permission-denied', 'PERMISSION_DENIED');
      return { ok: true, requestId, price: existing.data().price, tariffVersion: existing.data().tariffVersion, duplicate: true };
    }
    const [cfg, user] = await Promise.all([loadConfig(), userDoc(key)]);
    if (!user || !stageAllows(cfg, key, user.data.districtId)) throw fail('failed-precondition', 'NOT_AVAILABLE');
    if (!policyTypesOf(cfg).includes(policyType)) throw fail('failed-precondition', 'POLICY_TYPE_OFF');
    const car = carOf(user.data);
    if (!inc.hasCarProfile(user.data) || !car.plateKey) throw fail('failed-precondition', 'CAR_PROFILE_REQUIRED');
    const tariff = await loadTariff(cfg.activeTariffVersion);
    const regionId = await regionOf(user.data.districtId);
    const zoneDerived = zoneForRegion(regionId);
    let row = null;
    let sel = {};
    if (isZoneTariff(tariff)) {
      if (!driverScopeIn) throw fail('invalid-argument', 'INVALID_REQUEST');
      const zone = zoneIn || zoneDerived;
      if (zone === 'cis' && !CIS_VEHICLE_TYPES.includes(vehicleType)) throw fail('failed-precondition', 'CIS_VEHICLE_NOT_ALLOWED');
      row = findZoneTariffRow(tariff.rows, { policyType, zone, vehicleType, driverScope: driverScopeIn, termMonths });
      // Ҳудуд фойдаланувчи танлови бўлса — агент полисда текширади (zoneSource 'user').
      sel = { zone, zoneDerived, zoneSource: zoneIn && zoneIn !== zoneDerived ? 'user' : 'auto', driverScope: driverScopeIn, tariffSchema: TARIFF_SCHEMA };
    } else if (tariff) {
      row = findTariffRow(tariff.rows, { policyType, regionId, vehicleType, termMonths });
    }
    if (!row) throw fail('failed-precondition', 'TARIFF_NOT_FOUND');
    const lockRef = db.collection(OPEN).doc(`${key}_${policyType}`);
    const out = await db.runTransaction(async (t) => {
      const [rs, ls] = await Promise.all([t.get(reqRef), t.get(lockRef)]);
      if (rs.exists) return { duplicate: true, price: rs.data().price, tariffVersion: rs.data().tariffVersion };
      if (ls.exists) throw fail('failed-precondition', 'OPEN_REQUEST_EXISTS', { requestId: ls.data().requestId });
      t.create(lockRef, { requestId, uid: key, policyType, createdAt: ts() });
      t.create(reqRef, {
        uid: key, walletDocId: user.id, status: 'requested', policyType, vehicleType, termMonths,
        districtId: String(user.data.districtId || ''), regionId, car,
        tariffVersion: tariff.version, tariffRegionId: row.regionId || null, price: row.price, ...sel,
        idempotencyKey: idem, createdAt: ts(), updatedAt: ts(),
      });
      event(t, requestId, 'requested', key, { price: row.price, tariffVersion: tariff.version, ...(sel.zone ? { zone: sel.zone, driverScope: sel.driverScope } : {}) });
      return { duplicate: false, price: row.price, tariffVersion: tariff.version };
    });
    log({ action: 'insuranceCreateRequest', userId: tail(key), requestId: requestId.replace(key, tail(key)), result: out.duplicate ? 'duplicate' : 'created', price: out.price, durationMs: now() - started });
    return { ok: true, requestId, ...out };
  });

  /** Олдиндан кўриш: { requestId } → нарх тақсимоти (ёзмайди). */
  exportsObj.insuranceQuote = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const requestId = String((data && data.requestId) || '');
    if (!REQ_ID_RE.test(requestId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const rs = await db.collection(REQUESTS).doc(requestId).get();
    if (!rs.exists || rs.data().uid !== key) throw fail('not-found', 'REQUEST_NOT_FOUND');
    const r = rs.data();
    const user = await userDoc(key);
    const enr = await bestDiscount(key, null);
    const gs = await db.collection('incentive_grants').where('uid', '==', user ? user.id : key).where('status', '==', 'active').get();
    const grants = gs.docs.map((g) => {
      const x = g.data();
      return { id: g.id, programId: x.programId, remaining: x.remaining, buckets: x.buckets || {}, maxOrderSharePct: x.maxOrderSharePct, expiresAtMs: x.expiresAt && x.expiresAt.toMillis ? x.expiresAt.toMillis() : null };
    });
    const balance = user && Number.isSafeInteger(user.data.bonusBalance) ? user.data.bonusBalance : (parseInt(String((user && user.data.bonusBalance) || 0), 10) || 0);
    const p = computePayment({ price: r.price, oilPct: enr ? enr.pct : 0, grants, walletBalance: balance, nowMs: now() });
    return { ok: true, price: p.price, oilPct: p.oilPct, oilDiscount: p.oilDiscount, incentive: p.incentive, walletDue: p.walletDue, walletBalance: balance, sufficient: p.sufficient };
  });

  /** Энг яхши фаол мой чегирмаси (транзакциядан ташқари ўқиш; t берилса — транзакцияда қайта ўқилади). */
  async function bestDiscount(key, t) {
    const snap = await db.collection(ENROLL).where('uid', '==', key).get();
    let best = null;
    for (const d of snap.docs) {
      const x = t ? ((await t.get(d.ref)).data() || {}) : d.data();
      if (x.option !== 'oil' || x.status !== 'active' || x.discountUsedRequestId) continue;
      const pct = oilDiscountPct(x.oilChanges || 0, x.oilSteps);
      if (pct > 0 && (!best || pct > best.pct)) best = { ref: d.ref, id: d.id, pct, data: x };
    }
    return best;
  }

  /** Тўлов: { requestId } → { status:'paid', walletPaid, incentive, oilDiscount, duplicate }. Идемпотент. */
  exportsObj.insurancePayRequest = functions.https.onCall(async (data, context) => {
    const started = now();
    const key = callerKey(context);
    const requestId = String((data && data.requestId) || '');
    if (!REQ_ID_RE.test(requestId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const reqRef = db.collection(REQUESTS).doc(requestId);
    const pre = await reqRef.get();
    if (!pre.exists || pre.data().uid !== key) throw fail('not-found', 'REQUEST_NOT_FOUND');
    const walletDocId = pre.data().walletDocId || key;
    const userRef = db.collection('users').doc(walletDocId);
    const enrollSnap = await db.collection(ENROLL).where('uid', '==', key).get();
    const out = await db.runTransaction(async (t) => {
      const rs = await t.get(reqRef);
      const r = rs.data();
      if (r.status !== 'requested') {
        if (r.status === 'cancelled') throw fail('failed-precondition', 'REQUEST_CLOSED');
        return { duplicate: true, walletPaid: r.walletPaid || 0, incentive: r.incentiveApplied || 0, oilDiscount: r.oilDiscount || 0 };
      }
      const nowMs = now();
      const us = await t.get(userRef);
      const enrolls = [];
      for (const d of enrollSnap.docs) enrolls.push({ ref: d.ref, id: d.id, data: (await t.get(d.ref)).data() || {} });
      const grants = await inc.readActiveGrantsInTx(t, db, walletDocId);
      const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, walletDocId, { idempotencyKey: `insurance_pay_${requestId}` });
      let best = null;
      for (const e of enrolls) {
        const x = e.data;
        if (x.option !== 'oil' || x.status !== 'active' || x.discountUsedRequestId) continue;
        const pct = oilDiscountPct(x.oilChanges || 0, x.oilSteps);
        if (pct > 0 && (!best || pct > best.pct)) best = { ...e, pct };
      }
      const ud = us.exists ? (us.data() || {}) : {};
      const balance = parseInt(String(ud.bonusBalance ?? 0), 10) || 0;
      const p = computePayment({ price: r.price, oilPct: best ? best.pct : 0, grants, walletBalance: balance, nowMs });
      if (!p.sufficient) throw fail('failed-precondition', 'INSUFFICIENT_BALANCE', { walletDue: p.walletDue, balance });
      // ── ЁЗИШ ──
      if (p.walletDue > 0) {
        t.set(userRef, { bonusBalance: balance - p.walletDue, balanceUpdatedAt: ts() }, { merge: true });
        t.set(userRef.collection('wallet_ledger').doc(`insurance_pay_${requestId}`), {
          type: 'purchase_debit', amount: -p.walletDue, module: 'insurance', refType: 'insurance_request', refId: requestId,
          meta: { policyType: r.policyType, termMonths: r.termMonths, tariffVersion: r.tariffVersion }, createdAt: ts(), createdBy: key,
        });
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta: -p.walletDue, kind: 'purchase_debit', refType: 'insurance_request', refId: requestId,
          meta: { module: 'insurance' }, postedBy: key, postedRole: 'user',
        });
      }
      inc.applyIncentiveSpendInTx(t, db, admin, { uid: walletDocId, grants, plan: p.plan, orderId: requestId });
      if (best && p.oilDiscount > 0) {
        t.update(best.ref, { discountUsedRequestId: requestId, discountUsedPct: best.pct, status: 'used', updatedAt: ts() });
      }
      t.update(reqRef, {
        status: 'paid', oilDiscountPct: p.oilPct, oilDiscount: p.oilDiscount, oilEnrollmentId: best && p.oilDiscount > 0 ? best.id : null,
        incentiveApplied: p.incentive, incentiveUid: walletDocId,
        incentiveGrants: p.plan.perGrant.map((g) => ({ grantId: g.grantId, programId: g.programId, amount: g.amount, byBucket: g.byBucket })),
        walletPaid: p.walletDue, paidAt: ts(), updatedAt: ts(),
      });
      event(t, requestId, 'paid', key, { walletPaid: p.walletDue, incentive: p.incentive, oilDiscount: p.oilDiscount });
      return { duplicate: false, walletPaid: p.walletDue, incentive: p.incentive, oilDiscount: p.oilDiscount, policyType: r.policyType };
    });
    log({ action: 'insurancePayRequest', userId: tail(key), result: out.duplicate ? 'duplicate' : 'paid', walletPaid: out.walletPaid, incentive: out.incentive, oilDiscount: out.oilDiscount, durationMs: now() - started });
    if (!out.duplicate) {
      const user = await userDoc(key);
      await notify(user ? user.id : key, user && user.data.appLang, 'paid', { policy: policyName(out.policyType, user && user.data.appLang) }, { extraData: { requestId } });
      const cfg = await loadConfig();
      for (const a of cfg.agentPhones.slice(0, 10)) await notify(a, 'uz_Cyrl', 'agent_new', { policy: policyName(out.policyType, 'uz_Cyrl') }, { extraData: { requestId } });
    }
    return { ok: true, status: 'paid', walletPaid: out.walletPaid, incentive: out.incentive, oilDiscount: out.oilDiscount, duplicate: out.duplicate };
  });

  /** Тўланмаган аризани мижоз ўзи бекор қилади: { requestId }. */
  exportsObj.insuranceCancelMyRequest = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const requestId = String((data && data.requestId) || '');
    if (!REQ_ID_RE.test(requestId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const reqRef = db.collection(REQUESTS).doc(requestId);
    const res = await db.runTransaction(async (t) => {
      const rs = await t.get(reqRef);
      if (!rs.exists || rs.data().uid !== key) throw fail('not-found', 'REQUEST_NOT_FOUND');
      const r = rs.data();
      if (r.status === 'cancelled') return { duplicate: true };
      if (r.status !== 'requested') throw fail('failed-precondition', 'INVALID_TRANSITION');
      const lockRef = db.collection(OPEN).doc(`${key}_${r.policyType}`);
      const ls = await t.get(lockRef);
      if (ls.exists && ls.data().requestId === requestId) t.delete(lockRef);
      t.update(reqRef, { status: 'cancelled', cancelReason: 'customer', cancelledBy: key, cancelledAt: ts(), updatedAt: ts() });
      event(t, requestId, 'cancelled', key, { reason: 'customer', refund: null });
      return { duplicate: false };
    });
    return { ok: true, ...res };
  });

  /** Профилдаги суғурта муддати (қўлда): { expiresOn:'YYYY-MM-DD'|'' , policyType }. */
  exportsObj.insuranceSetMyExpiry = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const d = isObj(data) ? data : {};
    const [cfg, user] = await Promise.all([loadConfig(), userDoc(key)]);
    if (!user || !stageAllows(cfg, key, user.data.districtId)) throw fail('failed-precondition', 'NOT_AVAILABLE');
    const expiresOn = String(d.expiresOn || '');
    const idxRef = db.collection(EXPIRY).doc(key);
    if (!expiresOn) {
      await db.runTransaction(async (t) => {
        t.delete(idxRef);
        t.set(user.ref, { carInsurance: FV.delete() }, { merge: true });
      });
      return { ok: true, cleared: true };
    }
    const policyType = POLICY_TYPES.includes(d.policyType) ? d.policyType : 'osago';
    const today = dayKeyOf(now());
    if (!dateOk(expiresOn) || expiresOn < addDaysKey(today, -366) || expiresOn > addDaysKey(today, 3 * 366)) throw fail('invalid-argument', 'DATE_INVALID');
    const car = carOf(user.data);
    await db.runTransaction(async (t) => {
      t.set(idxRef, { uid: key, userDocId: user.id, expiresOn, policyType, plate: car.plate, source: 'manual', requestId: null, updatedAt: ts() });
      t.set(user.ref, { carInsurance: { expiresOn, policyType, source: 'manual', requestId: null, updatedAt: ts() } }, { merge: true });
    });
    return { ok: true, expiresOn, policyType };
  });

  /** Машина рўйхатдан ўтгандаги рағбат: { option:'bonus'|'oil' }. Бир машина + бир шахс (кампания йилида). */
  exportsObj.insuranceChooseCarOffer = functions.https.onCall(async (data, context) => {
    const started = now();
    const key = callerKey(context);
    const option = String((data && data.option) || '');
    if (!OPTIONS.includes(option)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const nowMs = now();
    const [camp, user] = await Promise.all([campaignFor(nowMs), userDoc(key)]);
    if (!camp || !user || !stageAllows(camp, key, user.data.districtId)) throw fail('failed-precondition', 'CAMPAIGN_OFF');
    if ((option === 'bonus' && camp.bonusEnabled !== true) || (option === 'oil' && camp.oilEnabled !== true)) throw fail('failed-precondition', 'OPTION_OFF');
    const car = carOf(user.data);
    if (!inc.hasCarProfile(user.data) || !car.plateKey) throw fail('failed-precondition', 'CAR_PROFILE_REQUIRED');
    const year = camp.year;
    const enrRef = db.collection(ENROLL).doc(`${year}_${car.plateKey}`);
    const personRef = db.collection(ENROLL_PERSONS).doc(`${year}_${key}`);
    const campRef = db.collection(CAMPAIGNS).doc(String(year));
    const progRef = db.collection('incentive_programs').doc(BONUS_PROGRAM);
    const grantId = `${BONUS_PROGRAM}_${year}_${key}`;
    const grantRef = db.collection('incentive_grants').doc(grantId);
    const out = await db.runTransaction(async (t) => {
      const [es, ps, cs, prs, gs] = await Promise.all([t.get(enrRef), t.get(personRef), t.get(campRef), t.get(progRef), t.get(grantRef)]);
      if (ps.exists) {
        if (ps.data().plateKey === car.plateKey) return { duplicate: true, option: ps.data().option };
        throw fail('failed-precondition', 'PERSON_ALREADY_ENROLLED');
      }
      if (es.exists) throw fail('failed-precondition', 'PLATE_ALREADY_ENROLLED');
      const c = cs.data() || {};
      const base = {
        year, plateKey: car.plateKey, plate: car.plate, uid: key, userDocId: user.id, option, status: 'active',
        createdDay: dayKeyOf(nowMs), createdAt: ts(), updatedAt: ts(),
      };
      if (option === 'oil') {
        t.create(enrRef, { ...base, oilChanges: 0, oilSteps: c.oilSteps, discountUsedRequestId: null });
        t.create(personRef, { plateKey: car.plateKey, option, uid: key, createdAt: ts() });
        return { duplicate: false, option };
      }
      const granted = Number.isSafeInteger((c.counters || {}).bonusGrantedAmount) ? c.counters.bonusGrantedAmount : 0;
      if (granted + c.bonusAmount > c.bonusBudgetTotal) throw fail('resource-exhausted', 'BUDGET_EXHAUSTED');
      if (!prs.exists || gs.exists) throw fail('failed-precondition', 'CAMPAIGN_OFF');
      const buckets = { any: c.bonusAmount };
      t.create(grantRef, {
        uid: user.id, personKey: key, programId: BONUS_PROGRAM, programKey: BONUS_PROGRAM, amount: c.bonusAmount, remaining: c.bonusAmount,
        buckets, maxOrderSharePct: c.bonusMaxOrderSharePct, status: 'active', campaignYear: year, plateKey: car.plateKey,
        expiresAt: TS.fromMillis(nowMs + c.bonusValidityDays * DAY_MS), createdAt: ts(), updatedAt: ts(),
      });
      t.update(user.ref, { incentiveBalance: FV.increment(c.bonusAmount), incentiveUpdatedAt: ts() });
      t.update(progRef, { 'counters.grantedAmount': FV.increment(c.bonusAmount), 'counters.grantedCount': FV.increment(1), updatedAt: ts() });
      t.update(campRef, { 'counters.bonusGrantedAmount': FV.increment(c.bonusAmount), 'counters.bonusGrantedCount': FV.increment(1), updatedAt: ts() });
      t.create(db.collection('incentive_ledger').doc(`grant_${grantId}`), {
        type: 'grant', uid: user.id, programId: BONUS_PROGRAM, grantId, amount: c.bonusAmount, buckets, actor: `system:${BONUS_PROGRAM}`, at: ts(),
      });
      t.create(enrRef, { ...base, grantId, bonusAmount: c.bonusAmount });
      t.create(personRef, { plateKey: car.plateKey, option, uid: key, createdAt: ts() });
      return { duplicate: false, option, amount: c.bonusAmount, days: c.bonusValidityDays };
    });
    log({ action: 'insuranceChooseCarOffer', userId: tail(key), option, year, result: out.duplicate ? 'duplicate' : 'enrolled', durationMs: now() - started });
    if (!out.duplicate && option === 'bonus') {
      await notify(user.id, langOf(user), 'bonus', { amount: money(out.amount), days: out.days });
    }
    return { ok: true, ...out };
  });

  /** Полис файли ҳаволаси (эгаси ёки агент/админ): { requestId } → { url, contentType }. */
  exportsObj.insuranceGetPolicyLink = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const requestId = String((data && data.requestId) || '');
    if (!REQ_ID_RE.test(requestId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const rs = await db.collection(REQUESTS).doc(requestId).get();
    if (!rs.exists) throw fail('not-found', 'REQUEST_NOT_FOUND');
    if (rs.data().uid !== key) await requireAgent(context);
    const fs = await db.collection(FILES).doc(requestId).get();
    if (rs.data().status !== 'issued' || !fs.exists) throw fail('not-found', 'POLICY_FILE_MISSING');
    const f = fs.data();
    const url = `https://firebasestorage.googleapis.com/v0/b/${f.bucket}/o/${encodeURIComponent(f.path)}?alt=media&token=${f.token}`;
    return { ok: true, url, contentType: f.contentType };
  });

  // ── Агент ──

  /** { status } → { requests: [...] } (энг янгиси биринчи, ≤200). */
  exportsObj.insuranceAgentListRequests = functions.https.onCall(async (data, context) => {
    await requireAgent(context);
    const status = String((data && data.status) || 'paid');
    if (!STATUSES.includes(status)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const snap = await db.collection(REQUESTS).where('status', '==', status).limit(200).get();
    const list = snap.docs.map((d) => ({ ...requestView(d.id, d.data()), uid: d.data().uid, regionId: d.data().regionId || '', districtId: d.data().districtId || '', zoneDerived: d.data().zoneDerived || '', zoneSource: d.data().zoneSource || '' }));
    list.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
    return { ok: true, requests: list };
  });

  async function agentTransition(requestId, actor, to, patch, eventExtra) {
    const reqRef = db.collection(REQUESTS).doc(requestId);
    return db.runTransaction(async (t) => {
      const rs = await t.get(reqRef);
      if (!rs.exists) throw fail('not-found', 'REQUEST_NOT_FOUND');
      const r = rs.data();
      if (r.status === to) return { duplicate: true, r };
      if (!canTransition(r.status, to)) throw fail('failed-precondition', 'INVALID_TRANSITION');
      t.update(reqRef, { status: to, ...patch, updatedAt: ts() });
      event(t, requestId, to, actor, eventExtra || {});
      t.create(db.collection(ADMIN_AUDIT).doc(), { action: `insurance_${to}`, requestId, actor, at: ts() });
      return { duplicate: false, r };
    });
  }

  /** { requestId } paid → in_progress (агент ишни бошлади). */
  exportsObj.insuranceAgentStart = functions.https.onCall(async (data, context) => {
    const actor = await requireAgent(context);
    const requestId = String((data && data.requestId) || '');
    if (!REQ_ID_RE.test(requestId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const res = await agentTransition(requestId, actor, 'in_progress', { agentPhone: actor, startedAt: ts() });
    return { ok: true, duplicate: res.duplicate };
  });

  /**
   * Полис: { requestId, policyNumber, validFrom, validTo, fileBase64 } → issued. Файл (PDF/JPG/PNG/WEBP ≤5 МБ)
   * Storage'га (`insurance_policies/{requestId}/…`, Storage rules йўқ — мижоз тўғридан ўқимайди).
   */
  exportsObj.insuranceAgentIssuePolicy = functions.https.onCall(async (data, context) => {
    const started = now();
    const actor = await requireAgent(context);
    const d = isObj(data) ? data : {};
    const requestId = String(d.requestId || '');
    const policyNumber = String(d.policyNumber || '').trim();
    const validFrom = String(d.validFrom || '');
    const validTo = String(d.validTo || '');
    if (!REQ_ID_RE.test(requestId) || !/^[A-Za-z0-9А-Яа-яЁёЎўҚқҒғҲҳ ./-]{3,40}$/.test(policyNumber)) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (!dateOk(validFrom) || !dateOk(validTo) || validTo <= validFrom || validTo > addDaysKey(validFrom, 3 * 366)) throw fail('invalid-argument', 'DATE_INVALID');
    const b64 = String(d.fileBase64 || '');
    if (!b64 || b64.length > Math.ceil(MAX_FILE_BYTES / 3) * 4 + 8) throw fail('invalid-argument', 'FILE_INVALID');
    const buf = Buffer.from(b64, 'base64');
    const kind = sniffFile(buf);
    if (!kind || buf.length > MAX_FILE_BYTES) throw fail('invalid-argument', 'FILE_INVALID');
    const reqRef = db.collection(REQUESTS).doc(requestId);
    const pre = await reqRef.get();
    if (!pre.exists) throw fail('not-found', 'REQUEST_NOT_FOUND');
    if (pre.data().status === 'issued') return { ok: true, duplicate: true };
    if (!canTransition(pre.data().status, 'issued')) throw fail('failed-precondition', 'INVALID_TRANSITION');
    const path = `insurance_policies/${requestId}/${crypto.randomUUID()}.${kind.ext}`;
    const saved = await storage.save(path, buf, kind.contentType);
    const res = await db.runTransaction(async (t) => {
      const rs = await t.get(reqRef);
      const r = rs.data();
      if (r.status === 'issued') return { duplicate: true, r };
      if (!canTransition(r.status, 'issued')) throw fail('failed-precondition', 'INVALID_TRANSITION');
      const lockRef = db.collection(OPEN).doc(`${r.uid}_${r.policyType}`);
      const ls = await t.get(lockRef);
      if (ls.exists && ls.data().requestId === requestId) t.delete(lockRef);
      const policy = { number: policyNumber, validFrom, validTo, contentType: kind.contentType, size: buf.length };
      t.update(reqRef, { status: 'issued', policy, issuedBy: actor, issuedAt: ts(), updatedAt: ts() });
      t.set(db.collection(FILES).doc(requestId), { requestId, uid: r.uid, path, bucket: saved.bucket, token: saved.token, contentType: kind.contentType, size: buf.length, uploadedBy: actor, at: ts() });
      const userRef = db.collection('users').doc(r.walletDocId || r.uid);
      t.set(db.collection(EXPIRY).doc(r.uid), { uid: r.uid, userDocId: r.walletDocId || r.uid, expiresOn: validTo, policyType: r.policyType, plate: (r.car || {}).plate || '', source: 'ava', requestId, updatedAt: ts() });
      t.set(userRef, { carInsurance: { expiresOn: validTo, policyType: r.policyType, source: 'ava', requestId, updatedAt: ts() } }, { merge: true });
      event(t, requestId, 'issued', actor, { policyNumber, validFrom, validTo });
      t.create(db.collection(ADMIN_AUDIT).doc(), { action: 'insurance_issued', requestId, actor, policyNumber, validTo, at: ts() });
      return { duplicate: false, r };
    });
    log({ action: 'insuranceAgentIssuePolicy', actor: tail(actor), result: res.duplicate ? 'duplicate' : 'issued', size: buf.length, durationMs: now() - started });
    if (!res.duplicate) {
      const user = await userDoc(res.r.uid);
      const lang = user && user.data.appLang;
      await notify(user ? user.id : res.r.uid, lang, 'issued', { policy: policyName(res.r.policyType, lang), number: policyNumber, to: displayDate(validTo) }, { extraData: { requestId } });
    }
    return { ok: true, duplicate: res.duplicate };
  });

  /** { requestId, reason } → cancelled; тўланган бўлса ҳамён + бонус + мой чегирмаси қайтарилади. Идемпотент. */
  exportsObj.insuranceAgentCancel = functions.https.onCall(async (data, context) => {
    const started = now();
    const actor = await requireAgent(context);
    const requestId = String((data && data.requestId) || '');
    const reason = String((data && data.reason) || '').trim().slice(0, 300);
    if (!REQ_ID_RE.test(requestId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const reqRef = db.collection(REQUESTS).doc(requestId);
    const res = await db.runTransaction(async (t) => {
      const rs = await t.get(reqRef);
      if (!rs.exists) throw fail('not-found', 'REQUEST_NOT_FOUND');
      const r = rs.data();
      if (r.status === 'cancelled') return { duplicate: true, r };
      if (!canTransition(r.status, 'cancelled')) throw fail('failed-precondition', 'INVALID_TRANSITION');
      const walletDocId = r.walletDocId || r.uid;
      const userRef = db.collection('users').doc(walletDocId);
      const walletPaid = Number.isSafeInteger(r.walletPaid) ? r.walletPaid : 0;
      const lockRef = db.collection(OPEN).doc(`${r.uid}_${r.policyType}`);
      // ── ЎҚИШ ──
      const ls = await t.get(lockRef);
      const us = walletPaid > 0 ? await t.get(userRef) : null;
      const bonusCtx = walletPaid > 0 ? await settlementLedger.prepareBonusInTx(t, db, walletDocId, { idempotencyKey: `insurance_refund_${requestId}` }) : null;
      const incCtx = await inc.prepareIncentiveRefundInTx(t, db, requestId, r);
      const enrRef = r.oilEnrollmentId ? db.collection(ENROLL).doc(r.oilEnrollmentId) : null;
      const es = enrRef ? await t.get(enrRef) : null;
      // ── ЁЗИШ ──
      let walletRefund = 0;
      if (bonusCtx && !bonusCtx.jExists) {
        const bal = parseInt(String(((us && us.data()) || {}).bonusBalance ?? 0), 10) || 0;
        t.set(userRef, { bonusBalance: bal + walletPaid, balanceUpdatedAt: ts() }, { merge: true });
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta: walletPaid, kind: 'insurance_cancel_refund', refType: 'insurance_request', refId: requestId,
          meta: { module: 'insurance' }, postedBy: actor, postedRole: 'agent',
        });
        t.set(userRef.collection('wallet_ledger').doc(`insurance_refund_${requestId}`), {
          type: 'insurance_cancel_refund', amount: walletPaid, module: 'insurance', refType: 'insurance_request', refId: requestId,
          meta: { reason }, createdAt: ts(), createdBy: actor,
        });
        walletRefund = walletPaid;
      }
      const incentiveRefund = inc.commitIncentiveRefundInTx(t, db, admin, incCtx, { actor, nowMs: now() });
      let oilRestored = false;
      if (es && es.exists && es.data().discountUsedRequestId === requestId) {
        t.update(enrRef, { discountUsedRequestId: null, discountUsedPct: FV.delete(), status: 'active', updatedAt: ts() });
        oilRestored = true;
      }
      if (ls.exists && ls.data().requestId === requestId) t.delete(lockRef);
      const refund = { wallet: walletRefund, incentive: incentiveRefund, oilRestored };
      t.update(reqRef, { status: 'cancelled', cancelReason: reason, cancelledBy: actor, cancelledAt: ts(), refund, updatedAt: ts() });
      event(t, requestId, 'cancelled', actor, { reason, refund });
      t.create(db.collection(ADMIN_AUDIT).doc(), { action: 'insurance_cancelled', requestId, actor, reason, refund, at: ts() });
      return { duplicate: false, r, refund };
    });
    log({ action: 'insuranceAgentCancel', actor: tail(actor), result: res.duplicate ? 'duplicate' : 'cancelled', refund: res.refund || null, durationMs: now() - started });
    if (!res.duplicate) {
      const user = await userDoc(res.r.uid);
      const lang = user && user.data.appLang;
      await notify(user ? user.id : res.r.uid, lang, 'cancelled', { policy: policyName(res.r.policyType, lang) }, { extraData: { requestId } });
    }
    return { ok: true, duplicate: res.duplicate, refund: res.refund || null };
  });

  // ── Сервис маркази кунлик ҳисоботи ──

  /**
   * { centerId, date:'YYYY-MM-DD', plates:[…] } → { reportId, results:[{plate, result}] }.
   * result: credited | duplicate | not_enrolled | goal_reached | invalid. Такрор (номер+сана) — ҳисобланмайди.
   */
  exportsObj.insuranceSubmitServiceReport = functions.https.onCall(async (data, context) => {
    const started = now();
    const actor = await requireReporter(context);
    const d = isObj(data) ? data : {};
    const centerId = String(d.centerId || '').trim();
    const date = String(d.date || '');
    const plates = Array.isArray(d.plates) ? d.plates.map((x) => String(x || '').slice(0, 30)) : null;
    if (!/^[A-Za-z0-9_-]{2,60}$/.test(centerId) || !plates || plates.length < 1 || plates.length > MAX_REPORT_PLATES) throw fail('invalid-argument', 'INVALID_REQUEST');
    const today = dayKeyOf(now());
    if (!dateOk(date) || date > today || date < addDaysKey(today, -REPORT_MAX_AGE_DAYS)) throw fail('invalid-argument', 'DATE_INVALID');
    const center = await db.collection('oil_change_services').doc(centerId).get();
    if (!center.exists) throw fail('not-found', 'CENTER_NOT_FOUND');
    const reportRef = db.collection(REPORTS).doc();
    const results = [];
    const seen = new Set();
    const notices = [];
    for (const raw of plates) {
      const plateKey = normalizePlate(raw);
      if (!plateKey) { results.push({ plate: raw, plateKey: '', result: 'invalid' }); continue; }
      if (seen.has(plateKey)) { results.push({ plate: raw, plateKey, result: 'duplicate' }); continue; }
      seen.add(plateKey);
      const creditRef = db.collection(OIL_CREDITS).doc(`${plateKey}_${date}`);
      const cand = await db.collection(ENROLL).where('plateKey', '==', plateKey).get();
      const r = await db.runTransaction(async (t) => {
        const cs = await t.get(creditRef);
        if (cs.exists) return { result: 'duplicate' };
        let target = null;
        for (const e of cand.docs) {
          const x = (await t.get(e.ref)).data() || {};
          if (x.option !== 'oil' || x.status !== 'active' || x.discountUsedRequestId) continue;
          if (String(x.createdDay || '') > date) continue; // рўйхатдан олдинги мой ҳисобланмайди
          if (!target || (x.year || 0) > (target.x.year || 0)) target = { ref: e.ref, id: e.id, x };
        }
        let result = 'not_enrolled';
        let n = 0; let goal = 0; let pct = 0;
        if (target) {
          goal = oilGoal(target.x.oilSteps);
          const cur = target.x.oilChanges || 0;
          if (cur >= goal) result = 'goal_reached';
          else {
            n = cur + 1;
            pct = oilDiscountPct(n, target.x.oilSteps);
            t.update(target.ref, { oilChanges: n, lastOilDate: date, lastOilCenterId: centerId, updatedAt: ts() });
            result = 'credited';
          }
        }
        t.create(creditRef, { plateKey, date, centerId, reportId: reportRef.id, enrollmentId: target ? target.id : null, result, submittedBy: actor, at: ts() });
        return { result, n, goal, pct, uid: target ? target.x.uid : null, userDocId: target ? target.x.userDocId : null };
      });
      results.push({ plate: raw, plateKey, result: r.result });
      if (r.result === 'credited') notices.push(r);
    }
    const counts = results.reduce((m, x) => ({ ...m, [x.result]: (m[x.result] || 0) + 1 }), {});
    await reportRef.set({ centerId, date, plates: results.map((x) => x.plate), results, counts, submittedBy: actor, at: ts() });
    await db.collection(ADMIN_AUDIT).add({ action: 'insurance_service_report', reportId: reportRef.id, centerId, date, counts, actor, at: ts() });
    for (const r of notices) {
      const user = await userDoc(r.uid);
      await notify(user ? user.id : r.uid, user && user.data.appLang, 'oil', { n: r.n, goal: r.goal, pct: r.pct });
    }
    log({ action: 'insuranceSubmitServiceReport', actor: tail(actor), centerId, date, counts, durationMs: now() - started });
    return { ok: true, reportId: reportRef.id, results: results.map((x) => ({ plate: x.plate, result: x.result })), counts };
  });

  /** Ҳисоботлар тарихи: { limit } → { reports }. */
  exportsObj.insuranceListServiceReports = functions.https.onCall(async (data, context) => {
    await requireReporter(context);
    const limit = isInt(data && data.limit, 1, 100) ? data.limit : 50;
    const snap = await db.collection(REPORTS).orderBy('at', 'desc').limit(limit).get();
    return {
      ok: true,
      reports: snap.docs.map((x) => {
        const r = x.data();
        return { reportId: x.id, centerId: r.centerId, date: r.date, counts: r.counts || {}, results: r.results || [], submittedBy: tail(r.submittedBy), atMs: r.at && r.at.toMillis ? r.at.toMillis() : null };
      }),
    };
  });

  // ── Админ ──

  /** Ҳамма созлама бир жойда: config, фаол тариф, тарифлар рўйхати, кампаниялар. */
  exportsObj.adminInsuranceGetSettings = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const cfg = await loadConfig();
    const [tariff, tariffs, camps] = await Promise.all([
      loadTariff(cfg.activeTariffVersion),
      db.collection(TARIFFS).orderBy('version', 'desc').limit(20).get(),
      db.collection(CAMPAIGNS).orderBy('year', 'desc').limit(10).get(),
    ]);
    return {
      ok: true, config: cfg, vehicleTypes: VEHICLE_TYPES, policyTypes: POLICY_TYPES,
      zones: ZONES, driverScopes: DRIVER_SCOPES, cisVehicleTypes: CIS_VEHICLE_TYPES, tariffSchema: TARIFF_SCHEMA,
      tariff: tariff ? { version: tariff.version, schema: isZoneTariff(tariff) ? TARIFF_SCHEMA : 1, rows: tariff.rows, note: tariff.note || '' } : null,
      // Эга расмий ОСАГО жадвали — фаол жадвал schema 2 бўлмаса таҳрирловчига қоралама (админ «Эълон қилиш» босади).
      draftRows: isZoneTariff(tariff) ? null : ownerDraftRows(),
      tariffVersions: tariffs.docs.map((x) => ({ version: x.data().version, note: x.data().note || '', rowCount: (x.data().rows || []).length })),
      campaigns: camps.docs.map((x) => {
        const c = x.data();
        const out = {};
        for (const k of ['year', ...CAMPAIGN_KEYS, 'counters', 'version']) if (c[k] !== undefined) out[k] = c[k];
        return out;
      }),
    };
  });

  /** { config } — босқич, рухсат рўйхатлари, КАСКО, эслатмалар. activeTariffVersion ўзгармайди. */
  exportsObj.adminInsuranceSaveConfig = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const v = validateConfig(data && data.config);
    if (!v.ok) throw fail('invalid-argument', 'CONFIG_INVALID', { errors: v.errors });
    await db.runTransaction(async (t) => {
      const s = await t.get(configRef());
      const prev = s.exists ? s.data() : {};
      t.set(configRef(), { ...v.value, updatedAt: ts(), updatedBy: actor }, { merge: true });
      t.create(db.collection(ADMIN_AUDIT).doc(), { action: 'insurance_config', actor, from: { stage: prev.stage || 'off', kaskoEnabled: prev.kaskoEnabled === true }, to: { stage: v.value.stage, kaskoEnabled: v.value.kaskoEnabled }, at: ts() });
    });
    return { ok: true };
  });

  /** { rows, note } → янги ўзгармас версия v{n} ва у фаол бўлади. Эски аризалар ўз нархида қолади. */
  exportsObj.adminInsurancePublishTariff = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const v = validateTariffRows(data && data.rows);
    if (!v.ok) throw fail('invalid-argument', 'TARIFF_INVALID', { errors: v.errors.slice(0, 20) });
    const note = String((data && data.note) || '').trim().slice(0, 200);
    const version = await db.runTransaction(async (t) => {
      const s = await t.get(configRef());
      const prev = s.exists && Number.isSafeInteger(s.data().activeTariffVersion) ? s.data().activeTariffVersion : 0;
      const maxV = Number.isSafeInteger((s.data() || {}).maxTariffVersion) ? s.data().maxTariffVersion : prev;
      const next = maxV + 1;
      t.create(db.collection(TARIFFS).doc(`v${next}`), { version: next, schema: TARIFF_SCHEMA, rows: v.rows, note, createdBy: actor, createdAt: ts() });
      t.set(configRef(), { activeTariffVersion: next, maxTariffVersion: next, updatedAt: ts(), updatedBy: actor }, { merge: true });
      t.create(db.collection(ADMIN_AUDIT).doc(), { action: 'insurance_tariff_publish', actor, from: prev, to: next, rowCount: v.rows.length, note, at: ts() });
      return next;
    });
    return { ok: true, version };
  });

  /** { year, campaign } — кампания (полис йили). Бонус танлови учун `incentive_programs/car_insurance_bonus` ҳам. */
  exportsObj.adminInsuranceSaveCampaign = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const year = data && data.year;
    const v = validateCampaign(year, data && data.campaign);
    if (!v.ok) throw fail('invalid-argument', 'CAMPAIGN_INVALID', { errors: v.errors });
    const ref = db.collection(CAMPAIGNS).doc(String(year));
    const progRef = db.collection('incentive_programs').doc(BONUS_PROGRAM);
    await db.runTransaction(async (t) => {
      const [s, ps] = await Promise.all([t.get(ref), t.get(progRef)]);
      const granted = s.exists ? (((s.data() || {}).counters || {}).bonusGrantedAmount || 0) : 0;
      if (v.value.bonusEnabled && v.value.bonusBudgetTotal < granted) throw fail('invalid-argument', 'CAMPAIGN_INVALID', { errors: ['BUDGET_BELOW_GRANTED'] });
      if (s.exists) t.update(ref, { ...v.value, version: FV.increment(1), updatedAt: ts(), updatedBy: actor });
      else t.create(ref, { ...v.value, version: 1, counters: { bonusGrantedAmount: 0, bonusGrantedCount: 0 }, createdAt: ts(), createdBy: actor, updatedAt: ts(), updatedBy: actor });
      // Рағбат тизими ҳужжати: stage ДОИМ 'off' — claimIncentive/getMyIncentiveOffers уни бермайди; грант фақат шу модулдан.
      const prog = {
        kind: BONUS_PROGRAM, key: BONUS_PROGRAM, stage: 'off',
        title: { uz_Cyrl: 'Машина суғуртаси бонуси', uz_Latn: 'Maşina suğurtasi bonusi', ru: 'Бонус за страховку авто' },
        amount: v.value.bonusAmount || 1, buckets: [], maxOrderSharePct: v.value.bonusMaxOrderSharePct || 100,
        validityDays: v.value.bonusValidityDays || 1, budgetTotal: Math.max(v.value.bonusBudgetTotal, 1), budgetDaily: 0,
        updatedAt: ts(), updatedBy: actor,
      };
      if (ps.exists) t.update(progRef, prog);
      else t.create(progRef, { ...prog, version: 1, createdAt: ts(), createdBy: actor, counters: { grantedAmount: 0, grantedCount: 0, spentAmount: 0, expiredAmount: 0, revokedAmount: 0 } });
      t.create(db.collection(ADMIN_AUDIT).doc(), { action: 'insurance_campaign', actor, year, stage: v.value.stage, bonusAmount: v.value.bonusAmount, oilSteps: v.value.oilSteps, at: ts() });
    });
    return { ok: true, year };
  });

  // ── Эслатмалар ──

  /** Бугун + 4 ва + 3 кунда тугайдиганларга бир мартадан (insurance_reminder_log). */
  async function runReminders(nowMs, budget = 2000) {
    const cfg = await loadConfig();
    const stat = { sent: 0, skipped: 0, scanned: 0 };
    if (cfg.stage === 'off' || !cfg.remindersEnabled) return { ...stat, reason: 'OFF' };
    for (const { n, date } of reminderTargets(nowMs)) {
      let cursor = null;
      while (budget > 0) {
        let q = db.collection(EXPIRY).where('expiresOn', '==', date).orderBy(admin.firestore.FieldPath.documentId()).limit(Math.min(200, budget));
        if (cursor) q = q.startAfter(cursor);
        const snap = await q.get();
        if (snap.empty) break;
        cursor = snap.docs[snap.docs.length - 1].id;
        for (const d of snap.docs) {
          budget -= 1; stat.scanned += 1;
          const x = d.data() || {};
          const user = await userDoc(d.id);
          if (!user || user.data.insuranceRemindersOptIn === false || !stageAllows(cfg, d.id, user.data.districtId)) { stat.skipped += 1; continue; }
          const logRef = db.collection(REMIND_LOG).doc(`${d.id}_${date}_d${n}`);
          const claimed = await db.runTransaction(async (t) => {
            const s = await t.get(logRef);
            if (s.exists) return false;
            t.create(logRef, { uid: d.id, expiresOn: date, days: n, policyType: x.policyType || '', at: ts() });
            return true;
          });
          if (!claimed) { stat.skipped += 1; continue; }
          await notify(user.id, langOf(user), 'remind', { days: n, date: displayDate(date) });
          stat.sent += 1;
        }
        if (snap.size < 200) break;
      }
    }
    return stat;
  }

  exportsObj.insuranceExpiryReminders = functions.pubsub
    .schedule('every day 10:00').timeZone('Asia/Tashkent')
    .onRun(async () => {
      const res = await runReminders(Date.now());
      log({ action: 'insuranceExpiryReminders', ...res });
      return null;
    });

  return { runReminders, loadConfig };
}

module.exports = {
  attachCarInsurance,
  normalizePlate, dateOk, addDaysKey, tashkentYear, displayDate, validateConfig, validateTariffRows, findTariffRow,
  tariffOptionsFor, zoneForRegion, findZoneTariffRow, zoneTariffOptions, ownerDraftRows, validOilSteps, oilDiscountPct, oilGoal, validateCampaign, computePayment, canTransition,
  reminderTargets, sniffFile, requestView, messagesOf,
  STAGES, POLICY_TYPES, VEHICLE_TYPES, ZONES, DRIVER_SCOPES, CIS_VEHICLE_TYPES, TASHKENT_REGION_IDS, TARIFF_SCHEMA,
  OSAGO_OWNER_TABLE_2026_11_28, STATUSES, TRANSITIONS, OPEN_STATUSES, OPTIONS, REMIND_DAYS, BONUS_PROGRAM, NOTICE,
  REQUESTS, ENROLL, EXPIRY, FILES, CAMPAIGNS, TARIFFS, CONFIG,
};
