/**
 * «Splash реклама» — СЕРВЕР (эга 2026-11-28).
 *
 * Илова очилишидаги 2 сониялик реклама ўрни. Креатив (расм ва/ёки матн, ихтиёрий ҳавола, муддат, ҳудуд,
 * оғирлик) `splash_ads/{id}` да; мижоз фақат `visible == true` ни ўқийди (rules), креативларни олдиндан
 * кешлайди ва ҲАР очилишда навбатдагисини ОҒИРЛИК бўйича (smooth weighted round-robin) кўрсатади.
 *
 * ПУЛЛИК РЕКЛАМА (эга 2026-11-28): рекламачи иловада 1/3/5/7 кун, бошланиш санаси, ҳудуд (туман(лар) / вилоят /
 * республика), креатив танлайди → нарх СЕРВЕРДА (админ версияланган тарифи: кунлик нарх × [туманлар сони] ×
 * кун, бутун сўм, `tariffVersion` сақланади) → ҲАМЁНДАН тўлов (`bonusBalance` + `wallet_ledger` +
 * `settlement_ledger` — car_insurance билан бир хил механизм; `clientRequestId` бўйича идемпотент) →
 * модерация: админ тасдиқласа — `splash_ads/{orderId}` (оғирлик = кунига тўланган сумма), рад этса — ТЎЛИҚ
 * қайтариш + сабаб + хабар. Ҳолатлар: pending → approved | rejected (17-банд).
 *
 * Коллекциялар (ёзиш ФАҚАТ CF):
 *   splash_ads/{id}                — оммавий креатив (рекламачи телефони ЁЗИЛМАЙДИ, 40-банд)
 *   splash_ad_stats/{adId}_{day}   — кунлик кўрсатишлар {adId, day, impressions, devices} (админ ўқийди)
 *   splash_ad_imp_log/{key}_{day}  — идемпотентлик: бир қурилма/фойдаланувчи бир кунни бир марта юборади
 *   splash_ad_orders/{orderId}     — пуллик буюртма (эгаси ва админ ўқийди — rules)
 *   splash_ad_config/main          — {stage, internalPhones, pilotDistrictIds, activeTariffVersion, maxTariffVersion}
 *   splash_ad_tariffs/v{n}         — ўзгармас тариф {version, perDay{district, region, republic}, note}
 *   splash_ad_events/{auto}        — ўзгармас ҳодисалар журнали (paid/approved/rejected)
 *
 * Арзонлик (37-банд): кўрсатишлар кунлик йиғма (кунига ≤ 1 чақирув/қурилма); мижоз ҳудуд калити
 * (`areaKeys`) бўйича фақат ўзига тегишли рекламаларни ўқийди; муддати ўтганлари кунлик `visible=false`.
 */
'use strict';

const crypto = require('crypto');
const settlementLedger = require('./settlement_ledger');
const { personKeyOf, stageAllows } = require('./family_links');
const { normalizeLang } = require('./notif_i18n');

const MODULE = 'splash_ads';
const ADS = 'splash_ads';
const STATS = 'splash_ad_stats';
const IMP_LOG = 'splash_ad_imp_log';
const ORDERS = 'splash_ad_orders';
const CONFIG = 'splash_ad_config';
const CONFIG_DOC = 'main';
const TARIFFS = 'splash_ad_tariffs';
const EVENTS = 'splash_ad_events';
const ADMIN_AUDIT = 'admin_audit';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const LANGS = Object.freeze(['uz_Cyrl', 'uz_Latn', 'ru']);
const STAGES = Object.freeze(['off', 'internal', 'pilot', 'public']);
const AREA_LEVELS = Object.freeze(['district', 'region', 'republic']);
/** Эга 2026-11-28: 1 / 3 / 5 / 7 кун. */
const DURATIONS = Object.freeze([1, 3, 5, 7]);
const ORDER_TRANSITIONS = Object.freeze({ pending: ['approved', 'rejected'], approved: [], rejected: [] });
const AD_ID_RE = /^[A-Za-z0-9_-]{2,40}$/;
const GEO_RE = /^[a-z0-9_-]{2,40}$/;
const DISTRICT_RE = GEO_RE;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const IDEM_RE = /^[A-Za-z0-9_-]{8,64}$/;
const PHONE_RE = /^998\d{9}$/;
const STORAGE_URL_PREFIX = 'https://firebasestorage.googleapis.com/';
const TZ_OFFSET_MS = 5 * 3600000; // Тошкент
const DAY_MS = 86400000;
/**
 * Ҳар очилишда реклама (эга 2026-11-28 — аввалги 3/кун чегараси олиб ташланди). Бу — фақат ҲИСОБОТ чегараси
 * (бир қурилма бир кунда кўпи билан шунча кўрсатиш юбора олади; сохта статистикага қарши).
 */
const MAX_IMPRESSIONS_PER_DAY = 200;
const MAX_PRICE_PER_DAY = 100000000;
const MAX_WEIGHT = 100000000;
const LIMITS = Object.freeze({
  title: 80, text: 140, imageUrl: 1000, linkUrl: 500, districts: 50, regionIds: 14, priorityMax: 100, reason: 300,
  maxDurationDays: 366, statsDays: 7, statsAdsPerDay: 30, logTtlDays: 30,
  purchaseDistricts: 10, startAheadDays: 60, myOrders: 30, phones: 100, note: 200, expireBatch: 300,
});
const AD_KEYS = Object.freeze(['title', 'text', 'imageUrl', 'linkUrl', 'startAtMs', 'endAtMs', 'districts', 'regionIds', 'priority', 'weight', 'active']);

const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  SPLASH_AD_INVALID: ['Реклама маълумоти нотўғри.', "Reklama ma'lumoti notöğri.", 'Неверные данные рекламы.'],
  SPLASH_AD_NOT_FOUND: ['Реклама топилмади.', 'Reklama topilmadi.', 'Реклама не найдена.'],
  SPLASH_AD_PAID_READONLY: ['Пуллик рекламани бу ерда таҳрирлаб бўлмайди.', "Pullik reklamani bu yerda tahrirlab bölmaydi.", 'Платную рекламу здесь редактировать нельзя.'],
  INVALID_REQUEST: ['Маълумот нотўғри. Қайта уриниб кўринг.', "Ma'lumot notöğri. Qayta urinib köring.", 'Неверные данные. Попробуйте ещё раз.'],
  NOT_AVAILABLE: ['Реклама сотиб олиш ҳозирча мавжуд эмас.', 'Reklama sotib oliş hozirça mavjud emas.', 'Покупка рекламы пока недоступна.'],
  AREA_INVALID: ['Ҳудуд нотўғри танланган.', 'Hudud notöğri tanlangan.', 'Неверно выбран регион.'],
  PRICE_CHANGED: ['Нарх ўзгарди. Янги нархни кўриб чиқинг.', "Narx özgardi. Yangi narxni körib çiqing.", 'Цена изменилась. Проверьте новую цену.'],
  INSUFFICIENT_BALANCE: ['Ҳамёнда маблағ етарли эмас. Ҳамённи тўлдиринг.', 'Hamyonda mablağ yetarli emas. Hamyonni töldiring.', 'Недостаточно средств в кошельке. Пополните кошелёк.'],
  ORDER_NOT_FOUND: ['Буюртма топилмади.', 'Buyurtma topilmadi.', 'Заказ не найден.'],
  INVALID_TRANSITION: ['Бу ҳолатда амал бажариб бўлмайди.', "Bu holatda amal bajarib bölmaydi.", 'В этом статусе действие невозможно.'],
  ORDER_EXPIRED: ['Реклама муддати ўтиб кетган — рад этинг (пул қайтади).', "Reklama muddati ötib ketgan — rad eting (pul qaytadi).", 'Срок рекламы прошёл — отклоните (деньги вернутся).'],
  REASON_REQUIRED: ['Сабабини ёзинг.', 'Sababini yozing.', 'Укажите причину.'],
  TARIFF_INVALID: ['Тариф нотўғри.', 'Tarif notöğri.', 'Неверный тариф.'],
  CONFIG_INVALID: ['Созлама нотўғри.', 'Sozlama notöğri.', 'Неверные настройки.'],
});
const messagesOf = (code) => { const m = MSG[code] || MSG.INVALID_REQUEST; return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] }; };

/** Рекламачига хабар (3 тил). */
const NOTICE = Object.freeze({
  approved: {
    uz_Cyrl: { title: 'Рекламангиз тасдиқланди', body: 'Реклама {start} дан {days} кун илова очилишида кўрсатилади.' },
    uz_Latn: { title: 'Reklamangiz tasdiqlandi', body: 'Reklama {start} dan {days} kun ilova oçilişida körsatiladi.' },
    ru: { title: 'Ваша реклама одобрена', body: 'Реклама будет показываться при запуске приложения {days} дн. с {start}.' },
  },
  rejected: {
    uz_Cyrl: { title: 'Реклама рад этилди', body: 'Сабаб: {reason}. {amount} сўм ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Reklama rad etildi', body: "Sabab: {reason}. {amount} söm hamyoningizga qaytarildi." },
    ru: { title: 'Реклама отклонена', body: 'Причина: {reason}. {amount} сум возвращены в кошелёк.' },
  },
});
const fill = (s, p) => String(s).replace(/\{(\w+)\}/g, (_, k) => (p[k] === undefined ? '' : String(p[k])));

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const str = (v) => (typeof v === 'string' ? v.trim() : '');
const isInt = (v, min, max) => Number.isSafeInteger(v) && v >= min && v <= max;

/** Тошкент санаси `YYYY-MM-DD`. */
function dayKeyOf(ms) {
  return new Date(ms + TZ_OFFSET_MS).toISOString().slice(0, 10);
}
/** `YYYY-MM-DD` (Тошкент) → шу кун 00:00 миллисекунд; нотўғри сана — null. */
function dayStartMs(day) {
  if (typeof day !== 'string' || !DAY_RE.test(day)) return null;
  const [y, m, d] = day.split('-').map(Number);
  const ms = Date.UTC(y, m - 1, d);
  if (dayKeyOf(ms - TZ_OFFSET_MS) !== day) return null;
  return ms - TZ_OFFSET_MS;
}

/** Ҳудуд калитлари (мижоз сўрови учун): иккала рўйхат бўш — 'all'; акс ҳолда 'd:{id}' / 'r:{id}'. */
function areaKeysOf(districts, regionIds) {
  const d = Array.isArray(districts) ? districts : [];
  const r = Array.isArray(regionIds) ? regionIds : [];
  if (!d.length && !r.length) return ['all'];
  return [...d.map((x) => `d:${x}`), ...r.map((x) => `r:${x}`)];
}

function cleanGeoList(v, max) {
  if (v === undefined) return { ok: true, list: [] };
  if (!Array.isArray(v) || v.length > max) return { ok: false, list: [] };
  const list = [...new Set(v.map(str))].sort();
  return { ok: list.every((x) => GEO_RE.test(x)), list };
}

/**
 * Админ киритган креативни текширади. Қайтаради: {ok, errors, clean}.
 * Вақт — миллисекунд (int). Расм — фақат Firebase Storage ҳаволаси; ҳавола — фақат https.
 * `weight` — айланишдаги улуш (сўм/кун эквиваленти; пуллик рекламада = кунига тўланган сумма).
 */
function validateAd(raw) {
  const errors = [];
  if (!isObj(raw)) return { ok: false, errors: ['ad'], clean: null };
  const title = str(raw.title);
  if (!title || title.length > LIMITS.title) errors.push('title');
  const textIn = isObj(raw.text) ? raw.text : {};
  const text = {};
  for (const l of LANGS) {
    const t = str(textIn[l]);
    if (t.length > LIMITS.text) errors.push(`text.${l}`);
    if (t) text[l] = t;
  }
  const imageUrl = str(raw.imageUrl);
  if (imageUrl && (!imageUrl.startsWith(STORAGE_URL_PREFIX) || imageUrl.length > LIMITS.imageUrl)) errors.push('imageUrl');
  if (!imageUrl && !text.uz_Cyrl) errors.push('content'); // расм ёки камида кирилл матн
  const linkUrl = str(raw.linkUrl);
  if (linkUrl && (!/^https:\/\/[^\s]+$/.test(linkUrl) || linkUrl.length > LIMITS.linkUrl)) errors.push('linkUrl');
  const startAtMs = raw.startAtMs;
  const endAtMs = raw.endAtMs;
  if (!Number.isSafeInteger(startAtMs) || startAtMs <= 0) errors.push('startAtMs');
  if (!Number.isSafeInteger(endAtMs) || endAtMs <= 0) errors.push('endAtMs');
  if (Number.isSafeInteger(startAtMs) && Number.isSafeInteger(endAtMs)
    && (endAtMs <= startAtMs || endAtMs - startAtMs > LIMITS.maxDurationDays * DAY_MS)) errors.push('window');
  const d = cleanGeoList(raw.districts, LIMITS.districts);
  if (!d.ok) errors.push('districts');
  const r = cleanGeoList(raw.regionIds, LIMITS.regionIds);
  if (!r.ok) errors.push('regionIds');
  const priority = raw.priority === undefined ? 0 : raw.priority;
  if (!Number.isInteger(priority) || priority < 0 || priority > LIMITS.priorityMax) errors.push('priority');
  const weight = raw.weight === undefined ? 1 : raw.weight;
  if (!isInt(weight, 1, MAX_WEIGHT)) errors.push('weight');
  if (typeof raw.active !== 'boolean') errors.push('active');
  if (errors.length) return { ok: false, errors: [...new Set(errors)], clean: null };
  return {
    ok: true, errors: [],
    clean: { title, text, imageUrl, linkUrl, startAtMs, endAtMs, districts: d.list, regionIds: r.list, priority, weight, active: raw.active },
  };
}

/**
 * Мижоз юборган кунлик кўрсатишларни тозалайди: охирги [statsDays] кун (бугун ҳам), кунига ≤ 30 реклама,
 * кунига жами ≤ [MAX_IMPRESSIONS_PER_DAY]. Қайтаради: [{day, ads: {adId: n}, total}].
 */
function sanitizeImpressions(days, nowMs) {
  if (!isObj(days)) return null;
  const today = dayKeyOf(nowMs);
  const oldest = dayKeyOf(nowMs - LIMITS.statsDays * DAY_MS);
  const out = [];
  for (const [day, ads] of Object.entries(days)) {
    if (!DAY_RE.test(day) || day > today || day < oldest || !isObj(ads)) continue;
    let left = MAX_IMPRESSIONS_PER_DAY;
    const clean = {};
    for (const [adId, n] of Object.entries(ads).slice(0, LIMITS.statsAdsPerDay)) {
      if (!AD_ID_RE.test(adId) || !Number.isInteger(n) || n <= 0 || left <= 0) continue;
      const take = Math.min(n, left);
      clean[adId] = take;
      left -= take;
    }
    const total = MAX_IMPRESSIONS_PER_DAY - left;
    if (total > 0) out.push({ day, ads: clean, total });
    if (out.length >= LIMITS.statsDays + 1) break;
  }
  return out;
}

/** Тариф нархи (бутун сўм): кунлик нарх × (туман бўлса — туманлар сони) × кун. Нарх йўқ — null. */
function priceOf(perDay, areaLevel, districtCount, days) {
  const base = isObj(perDay) ? perDay[areaLevel] : null;
  if (!isInt(base, 1, MAX_PRICE_PER_DAY) || !DURATIONS.includes(days)) return null;
  const units = areaLevel === 'district' ? districtCount : 1;
  if (!isInt(units, 1, LIMITS.purchaseDistricts)) return null;
  const pricePerDay = base * units;
  return { pricePerDay, amount: pricePerDay * days };
}

/** Рекламачи расми фақат ЎЗ `ads/{телефон}/` папкасидан (Storage rules ҳам шуни талаб қилади). */
function imageOwnedBy(url, key) {
  if (typeof url !== 'string' || !url.startsWith(STORAGE_URL_PREFIX) || url.length > LIMITS.imageUrl) return false;
  return [key, key.slice(3)].some((id) => url.includes(`/o/ads%2F${id}%2F`));
}

/** Харид сўровини текширади (география базада — CF ичида). */
function validatePurchase(raw, key, nowMs) {
  const errors = [];
  if (!isObj(raw)) return { ok: false, errors: ['request'], clean: null };
  const days = raw.days;
  if (!DURATIONS.includes(days)) errors.push('days');
  const startDay = str(raw.startDay);
  const startAtMs = dayStartMs(startDay);
  const today = dayKeyOf(nowMs);
  const lastDay = dayKeyOf(nowMs + LIMITS.startAheadDays * DAY_MS);
  if (startAtMs === null || startDay < today || startDay > lastDay) errors.push('startDay');
  const areaLevel = str(raw.areaLevel);
  if (!AREA_LEVELS.includes(areaLevel)) errors.push('areaLevel');
  let districts = [];
  let regionId = '';
  if (areaLevel === 'district') {
    const d = cleanGeoList(raw.districts, LIMITS.purchaseDistricts);
    if (!d.ok || !d.list.length) errors.push('districts');
    districts = d.list;
  } else if (areaLevel === 'region') {
    regionId = str(raw.regionId);
    if (!GEO_RE.test(regionId)) errors.push('regionId');
  }
  const c = isObj(raw.creative) ? raw.creative : {};
  const imageUrl = str(c.imageUrl);
  if (imageUrl && !imageOwnedBy(imageUrl, key)) errors.push('imageUrl');
  const t = str(c.text);
  if (t.length > LIMITS.text) errors.push('text');
  if (!imageUrl && !t) errors.push('content');
  const linkUrl = str(c.linkUrl);
  if (linkUrl && (!/^https:\/\/[^\s]+$/.test(linkUrl) || linkUrl.length > LIMITS.linkUrl)) errors.push('linkUrl');
  if (errors.length) return { ok: false, errors: [...new Set(errors)], clean: null };
  // Рекламачи матни қандай ёзилган бўлса, барча тилда шундай кўрсатилади.
  const text = t ? { uz_Cyrl: t, uz_Latn: t, ru: t } : {};
  return {
    ok: true, errors: [],
    clean: {
      days, startDay, startAtMs, endAtMs: startAtMs + days * DAY_MS, areaLevel, districts, regionId,
      creative: { imageUrl, text, linkUrl },
    },
  };
}

/** Пуллик буюртма ID — эгаси + clientRequestId дан детерминистик (идемпотент; `splash_ads` ID си ҳам шу). */
function orderIdOf(key, clientRequestId) {
  return `sa${crypto.createHash('sha256').update(`${key}:${clientRequestId}`).digest('hex').slice(0, 22)}`;
}

function validateTariff(perDay) {
  const errors = [];
  if (!isObj(perDay)) return { ok: false, errors: ['perDay'], value: null };
  const value = {};
  for (const l of AREA_LEVELS) {
    if (!isInt(perDay[l], 1, MAX_PRICE_PER_DAY)) errors.push(l);
    else value[l] = perDay[l];
  }
  return { ok: !errors.length, errors, value: errors.length ? null : value };
}

function validateConfig(raw) {
  const errors = [];
  if (!isObj(raw)) return { ok: false, errors: ['config'], value: null };
  if (!STAGES.includes(raw.stage)) errors.push('stage');
  const phones = Array.isArray(raw.internalPhones) ? [...new Set(raw.internalPhones.map((p) => personKeyOf(p)).filter(Boolean))] : null;
  if (!phones || phones.length > LIMITS.phones || (raw.internalPhones || []).some((p) => !personKeyOf(p))) errors.push('internalPhones');
  const pilot = cleanGeoList(raw.pilotDistrictIds === undefined ? [] : raw.pilotDistrictIds, LIMITS.districts);
  if (!pilot.ok) errors.push('pilotDistrictIds');
  if (errors.length) return { ok: false, errors, value: null };
  return { ok: true, errors, value: { stage: raw.stage, internalPhones: phones, pilotDistrictIds: pilot.list } };
}

/** Тест учун (эмуляторда Storage йўқ): 	estOverrides.storage = {copyCreative}. Production'да бўш. */
const testOverrides = {};

function attachSplashAds(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const TS = admin.firestore.Timestamp;
  const ts = () => FV.serverTimestamp();
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (o) => console.log(JSON.stringify({ module: MODULE, ...o }));
  const tail = (p) => String(p || '').slice(-4);
  const reasonOf = (data) => (typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, LIMITS.reason) : '');
  const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : (Number.isSafeInteger(v) ? v : null));

  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };
  /** Пуллик харид — фақат телефон билан кирган фойдаланувчи (аноним эмас). */
  function callerKey(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const key = personKeyOf(canonicalUid(callerPhone(context) || ''));
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
  const balanceOf = (d) => parseInt(String((d || {}).bonusBalance ?? 0), 10) || 0;
  const configRef = () => db.collection(CONFIG).doc(CONFIG_DOC);
  async function loadConfig() {
    const s = await configRef().get();
    const d = s.exists ? (s.data() || {}) : {};
    return {
      stage: STAGES.includes(d.stage) ? d.stage : 'off',
      internalPhones: Array.isArray(d.internalPhones) ? d.internalPhones : [],
      pilotDistrictIds: Array.isArray(d.pilotDistrictIds) ? d.pilotDistrictIds : [],
      activeTariffVersion: Number.isSafeInteger(d.activeTariffVersion) ? d.activeTariffVersion : 0,
    };
  }
  async function loadTariff(version) {
    if (!version) return null;
    const s = await db.collection(TARIFFS).doc(`v${version}`).get();
    return s.exists ? (s.data() || null) : null;
  }
  async function notify(userId, lang, kind, params, orderId) {
    const t = NOTICE[kind][normalizeLang(lang)] || NOTICE[kind].uz_Cyrl;
    try {
      await notifyUserInApp({
        userId, title: t.title, body: fill(t.body, params), category: 'info',
        source: `splash_ad_${kind}`, dataType: `splash_ad_${kind}`, screen: 'splash_ads_my', extraData: { orderId },
      });
    } catch (e) { log({ action: 'notify', result: 'error', errorCode: 'NOTIFY_FAILED', kind }); }
  }
  const event = (t, orderId, type, actor, extra = {}) => t.create(db.collection(EVENTS).doc(), { orderId, type, actor, at: ts(), ...extra });
  /**
   * Тасдиқда рекламачи расми `ads/{телефон}/…` дан `platform_images/splash_ads/{orderId}` га НУСХАЛАНАДИ —
   * оммавий `splash_ads` ҳужжатидаги ҳаволада телефон кўринмасин (40-банд). Манзил детерминистик (қайта
   * чақирув — устидан ёзади). Тестда алмаштирилади.
   */
  const defaultStorage = {
    async copyCreative(srcUrl, orderId) {
      const m = /\/o\/([^?]+)/.exec(srcUrl);
      if (!m) throw new Error('bad url');
      const bucket = admin.storage().bucket();
      const dst = `platform_images/splash_ads/${orderId}`;
      const token = crypto.randomUUID();
      await bucket.file(decodeURIComponent(m[1])).copy(bucket.file(dst));
      await bucket.file(dst).setMetadata({ metadata: { firebaseStorageDownloadTokens: token } });
      return `${STORAGE_URL_PREFIX}v0/b/${bucket.name}/o/${encodeURIComponent(dst)}?alt=media&token=${token}`;
    },
  };

  /** Ҳужжатдаги майдонларни аудит/солиштириш шаклига келтиради. */
  const pick = (d) => {
    if (!d) return null;
    return {
      title: d.title || '', text: isObj(d.text) ? d.text : {}, imageUrl: d.imageUrl || '', linkUrl: d.linkUrl || '',
      startAtMs: msOf(d.startAt), endAtMs: msOf(d.endAt), districts: Array.isArray(d.districts) ? d.districts : [],
      regionIds: Array.isArray(d.regionIds) ? d.regionIds : [],
      priority: Number.isInteger(d.priority) ? d.priority : 0, weight: Number.isInteger(d.weight) ? d.weight : 1, active: d.active === true,
    };
  };
  const same = (a, b) => JSON.stringify(AD_KEYS.map((k) => a[k])) === JSON.stringify(AD_KEYS.map((k) => b[k]));

  // ── 1. Админ: яратиш / таҳрирлаш (тўғридан-тўғри реклама) ──
  exportsObj.adminUpsertSplashAd = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const v = validateAd(data && data.ad);
    if (!v.ok) throw fail('invalid-argument', 'SPLASH_AD_INVALID', { errors: v.errors.slice(0, 30) });
    const rawId = str(data && data.ad && data.ad.id);
    if (rawId && !AD_ID_RE.test(rawId)) throw fail('invalid-argument', 'SPLASH_AD_INVALID', { errors: ['id'] });
    const ref = rawId ? db.collection(ADS).doc(rawId) : db.collection(ADS).doc();
    const clean = v.clean;
    const reason = reasonOf(data);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (snap.exists && (snap.data() || {}).source === 'paid') throw fail('failed-precondition', 'SPLASH_AD_PAID_READONLY');
      const cur = snap.exists ? pick(snap.data() || {}) : null;
      if (cur && same(cur, clean)) return { changed: false, version: (snap.data() || {}).version || 1 };
      const version = (snap.exists && Number.isInteger((snap.data() || {}).version) ? snap.data().version : 0) + 1;
      // Оммавий ҳужжат: админ телефони ЁЗИЛМАЙДИ (40-банд) — ким ўзгартиргани `admin_audit`да.
      t.set(ref, {
        title: clean.title, text: clean.text, imageUrl: clean.imageUrl, linkUrl: clean.linkUrl,
        startAt: TS.fromMillis(clean.startAtMs), endAt: TS.fromMillis(clean.endAtMs),
        districts: clean.districts, regionIds: clean.regionIds, areaKeys: areaKeysOf(clean.districts, clean.regionIds),
        priority: clean.priority, weight: clean.weight, source: 'admin', active: clean.active, visible: clean.active,
        version, updatedAt: ts(), ...(snap.exists ? {} : { createdAt: ts() }),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'splash_ad_set', actor, target: `${ADS}/${ref.id} v${version}`, before: cur, after: clean, reason, at: ts(),
      });
      return { changed: true, version };
    });
    log({ action: 'adminUpsertSplashAd', result: 'ok', userId: tail(actor), adId: ref.id, ...out });
    return { ok: true, adId: ref.id, ...out };
  });

  // ── 2. Админ: ўчириш (аудитда аввалги ҳолат сақланади) ──
  exportsObj.adminDeleteSplashAd = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const id = str(data && data.id);
    if (!AD_ID_RE.test(id)) throw fail('invalid-argument', 'SPLASH_AD_INVALID', { errors: ['id'] });
    const ref = db.collection(ADS).doc(id);
    const reason = reasonOf(data);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { deleted: false }; // идемпотент: қайта чақирув — хато эмас
      t.delete(ref);
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'splash_ad_delete', actor, target: `${ADS}/${id}`, before: pick(snap.data() || {}), after: null, reason, at: ts(),
      });
      return { deleted: true };
    });
    log({ action: 'adminDeleteSplashAd', result: 'ok', userId: tail(actor), adId: id, ...out });
    return { ok: true, adId: id, ...out };
  });

  // ── 3. Мижоз: кунлик кўрсатишлар (йиғма, идемпотент) ──
  exportsObj.recordSplashImpressions = functions.https.onCall(async (data, context) => {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const phone = canonicalUid(callerPhone(context) || '');
    const key = phone && phone.length >= 9 ? phone : `a_${String(context.auth.uid || '').slice(0, 64)}`;
    if (key === 'a_') throw fail('unauthenticated', 'UNAUTHENTICATED');
    const days = sanitizeImpressions(data && data.days, now());
    if (days === null) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (!days.length) return { ok: true, recorded: 0 };
    const out = await db.runTransaction(async (t) => {
      const logRefs = days.map((d) => db.collection(IMP_LOG).doc(`${key}_${d.day}`));
      const adIds = [...new Set(days.flatMap((d) => Object.keys(d.ads)))];
      const [logSnaps, adSnaps] = await Promise.all([
        Promise.all(logRefs.map((r) => t.get(r))),
        Promise.all(adIds.map((id) => t.get(db.collection(ADS).doc(id)))),
      ]);
      const known = new Set(adSnaps.filter((s) => s.exists).map((s) => s.id));
      let recorded = 0;
      days.forEach((d, i) => {
        if (logSnaps[i].exists) return; // бу кун аллақачон ҳисобланган (retry)
        const ads = Object.entries(d.ads).filter(([id]) => known.has(id));
        t.set(logRefs[i], {
          day: d.day, n: ads.reduce((s, [, n]) => s + n, 0), at: ts(),
          expireAt: TS.fromMillis(now() + LIMITS.logTtlDays * DAY_MS),
        });
        ads.forEach(([adId, n]) => {
          t.set(db.collection(STATS).doc(`${adId}_${d.day}`), {
            adId, day: d.day, impressions: FV.increment(n), devices: FV.increment(1), updatedAt: ts(),
          }, { merge: true });
          recorded += n;
        });
      });
      return { recorded };
    });
    log({ action: 'recordSplashImpressions', result: 'ok', userId: tail(key), days: days.length, ...out });
    return { ok: true, ...out };
  });

  // ══════════ ПУЛЛИК РЕКЛАМА ══════════

  /** Харид маълумоти: мавжудми, кунлик нархлар, муддатлар, ҳамён қолдиғи. */
  exportsObj.splashAdGetPurchaseInfo = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const [cfg, user] = await Promise.all([loadConfig(), userDoc(key)]);
    const tariff = await loadTariff(cfg.activeTariffVersion);
    const available = !!user && !!tariff && stageAllows(cfg, key, user.data.districtId);
    return {
      ok: true, available, durations: DURATIONS, areaLevels: AREA_LEVELS,
      perDay: available ? tariff.perDay : null, tariffVersion: available ? tariff.version : 0,
      balance: user ? balanceOf(user.data) : 0, maxDistricts: LIMITS.purchaseDistricts,
      maxStartAheadDays: LIMITS.startAheadDays, today: dayKeyOf(now()),
    };
  });

  /** Харидни текшириб, сервер нархини ҳисоблайди (ёзмайди). */
  async function preparePurchase(data, key) {
    const v = validatePurchase(data, key, now());
    if (!v.ok) throw fail('invalid-argument', 'INVALID_REQUEST', { errors: v.errors });
    const c = v.clean;
    const [cfg, user] = await Promise.all([loadConfig(), userDoc(key)]);
    const tariff = await loadTariff(cfg.activeTariffVersion);
    if (!user || !tariff || !stageAllows(cfg, key, user.data.districtId)) throw fail('failed-precondition', 'NOT_AVAILABLE');
    if (c.areaLevel === 'district') {
      const snaps = await Promise.all(c.districts.map((id) => db.collection('geo_districts').doc(id).get()));
      if (snaps.some((s) => !s.exists || (s.data() || {}).active === false)) throw fail('invalid-argument', 'AREA_INVALID');
    } else if (c.areaLevel === 'region') {
      const s = await db.collection('geo_regions').doc(c.regionId).get();
      if (!s.exists || (s.data() || {}).active === false) throw fail('invalid-argument', 'AREA_INVALID');
    }
    const price = priceOf(tariff.perDay, c.areaLevel, c.districts.length, c.days);
    if (!price) throw fail('failed-precondition', 'NOT_AVAILABLE');
    return { c, user, tariff, price };
  }

  exportsObj.splashAdQuote = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const { c, user, tariff, price } = await preparePurchase(data, key);
    const balance = balanceOf(user.data);
    return {
      ok: true, amount: price.amount, pricePerDay: price.pricePerDay, days: c.days, tariffVersion: tariff.version,
      balance, sufficient: price.amount <= balance,
    };
  });

  /** Тўлов: ҳамёндан ечиб, `pending` буюртма. `clientRequestId` бўйича идемпотент (қайта чақирув — қайта ечмайди). */
  exportsObj.splashAdPurchase = functions.https.onCall(async (data, context) => {
    const started = now();
    const key = callerKey(context);
    const crid = str(data && data.clientRequestId);
    if (!IDEM_RE.test(crid)) throw fail('invalid-argument', 'INVALID_REQUEST', { errors: ['clientRequestId'] });
    const orderId = orderIdOf(key, crid);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const dup = (o) => ({ ok: true, orderId, status: o.status, amount: o.amount, tariffVersion: o.tariffVersion, duplicate: true });
    const pre = await orderRef.get();
    if (pre.exists) {
      if (pre.data().uid !== key) throw fail('permission-denied', 'PERMISSION_DENIED');
      return dup(pre.data());
    }
    const { c, user, tariff, price } = await preparePurchase(data, key);
    if (data.expectedAmount !== undefined && data.expectedAmount !== price.amount) {
      throw fail('failed-precondition', 'PRICE_CHANGED', { amount: price.amount });
    }
    const userRef = user.ref;
    const out = await db.runTransaction(async (t) => {
      // ── ЎҚИШ ──
      const os = await t.get(orderRef);
      if (os.exists) return { duplicate: true, o: os.data() };
      const us = await t.get(userRef);
      const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, user.id, { idempotencyKey: `splash_pay_${orderId}` });
      const balance = balanceOf(us.exists ? us.data() : {});
      if (price.amount > balance) throw fail('failed-precondition', 'INSUFFICIENT_BALANCE', { amount: price.amount, balance });
      // Журнал бор, буюртма йўқ — аномалия (буюртма ўчирилган?): аввал bonusBalance журналсиз қайта ечиларди,
      // энди рад (на икки марта ечиш, на текин буюртма). Оддий йўлда бу ҳолат бўлмайди (бир транзакция).
      if (bonusCtx.jExists) {
        log({ action: 'splashAdPurchase', result: 'refused', errorCode: 'JOURNAL_EXISTS', orderId });
        throw fail('failed-precondition', 'INVALID_REQUEST', { errorCode: 'JOURNAL_EXISTS' });
      }
      // ── ЁЗИШ ── Ягона ёзиш йўли (W-1): журнал + bonusBalance (мутлақ, шу транзакцияда ўқилган) + wallet_ledger.
      settlementLedger.walletPost(t, bonusCtx, {
        delta: -price.amount, kind: 'purchase_debit', refType: 'splash_ad_order', refId: orderId,
        meta: { module: 'splash_ad' }, postedBy: key, postedRole: 'user',
        nextBalance: balance - price.amount,
        walletLedgerType: 'purchase_debit', walletLedgerId: `splash_pay_${orderId}`,
        walletLedger: {
          module: 'splash_ad', refType: 'splash_ad_order', refId: orderId,
          meta: { days: c.days, areaLevel: c.areaLevel, tariffVersion: tariff.version }, createdBy: key,
        },
      });
      t.create(orderRef, {
        uid: key, walletDocId: user.id, status: 'pending', clientRequestId: crid,
        days: c.days, startDay: c.startDay, startAt: TS.fromMillis(c.startAtMs), endAt: TS.fromMillis(c.endAtMs),
        areaLevel: c.areaLevel, districts: c.districts, regionId: c.regionId, creative: c.creative,
        tariffVersion: tariff.version, pricePerDay: price.pricePerDay, amount: price.amount, weight: price.pricePerDay,
        createdAt: ts(), updatedAt: ts(),
      });
      event(t, orderId, 'paid', key, { amount: price.amount, tariffVersion: tariff.version });
      return { duplicate: false };
    });
    if (out.duplicate) return dup(out.o);
    log({ action: 'splashAdPurchase', result: 'paid', userId: tail(key), orderId, amount: price.amount, tariffVersion: tariff.version, durationMs: now() - started });
    return { ok: true, orderId, status: 'pending', amount: price.amount, tariffVersion: tariff.version, duplicate: false };
  });

  /** «Менинг рекламаларим»: ҳолат, саналар, кўрсатишлар (CF орқали — статистика ҳужжатлари ёпиқ). */
  exportsObj.splashAdListMyOrders = functions.https.onCall(async (data, context) => {
    const key = callerKey(context);
    const snap = await db.collection(ORDERS).where('uid', '==', key).limit(LIMITS.myOrders).get();
    const orders = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
      .sort((a, b) => (msOf(b.createdAt) || 0) - (msOf(a.createdAt) || 0));
    const imp = {};
    const approved = orders.filter((o) => o.status === 'approved').map((o) => o.id);
    for (let i = 0; i < approved.length; i += 30) {
      const st = await db.collection(STATS).where('adId', 'in', approved.slice(i, i + 30)).get();
      st.docs.forEach((s) => { const x = s.data(); imp[x.adId] = (imp[x.adId] || 0) + (Number.isInteger(x.impressions) ? x.impressions : 0); });
    }
    return {
      ok: true,
      orders: orders.map((o) => ({
        orderId: o.id, status: o.status, days: o.days, startDay: o.startDay,
        endDay: dayKeyOf((msOf(o.endAt) || 0) - 1), areaLevel: o.areaLevel, districts: o.districts || [], regionId: o.regionId || '',
        amount: o.amount, tariffVersion: o.tariffVersion, impressions: imp[o.id] || 0,
        rejectReason: o.rejectReason || '', refund: o.refund || null,
        imageUrl: (o.creative || {}).imageUrl || '', text: ((o.creative || {}).text || {}).uz_Cyrl || '',
      })),
    };
  });

  /** Модерация: { orderId, decision: 'approve'|'reject', reason }. Рад — ТЎЛИҚ қайтариш. Идемпотент. */
  exportsObj.adminModerateSplashAdOrder = functions.https.onCall(async (data, context) => {
    const started = now();
    const actor = await requireAdmin(context);
    const orderId = str(data && data.orderId);
    const decision = str(data && data.decision);
    const reason = reasonOf(data);
    if (!AD_ID_RE.test(orderId) || !['approve', 'reject'].includes(decision)) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (decision === 'reject' && reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const target = decision === 'approve' ? 'approved' : 'rejected';
    const orderRef = db.collection(ORDERS).doc(orderId);
    let publicImageUrl = '';
    if (decision === 'approve') {
      const pre = await orderRef.get();
      const src = pre.exists && pre.data().status === 'pending' ? ((pre.data().creative || {}).imageUrl || '') : '';
      if (src) {
        try {
          publicImageUrl = await (deps.storage || testOverrides.storage || defaultStorage).copyCreative(src, orderId);
        } catch (e) {
          log({ action: 'adminModerateSplashAdOrder', result: 'error', errorCode: 'IMAGE_COPY_FAILED', orderId });
          throw fail('internal', 'INVALID_REQUEST', { errorCode: 'IMAGE_COPY_FAILED' });
        }
      }
    }
    const res = await db.runTransaction(async (t) => {
      // ── ЎҚИШ ──
      const os = await t.get(orderRef);
      if (!os.exists) throw fail('not-found', 'ORDER_NOT_FOUND');
      const o = os.data();
      if (o.status === target) return { duplicate: true, o };
      if (!(ORDER_TRANSITIONS[o.status] || []).includes(target)) throw fail('failed-precondition', 'INVALID_TRANSITION');
      const amount = Number.isSafeInteger(o.amount) ? o.amount : 0;
      if (decision === 'approve') {
        if ((msOf(o.endAt) || 0) <= now()) throw fail('failed-precondition', 'ORDER_EXPIRED');
        const districts = o.areaLevel === 'district' ? (o.districts || []) : [];
        const regionIds = o.areaLevel === 'region' && o.regionId ? [o.regionId] : [];
        const cr = o.creative || {};
        // ── ЁЗИШ ── (оммавий ҳужжатда рекламачи телефони йўқ)
        t.set(db.collection(ADS).doc(orderId), {
          title: `Пуллик · ${o.startDay} · ${o.days} кун`, text: cr.text || {}, imageUrl: cr.imageUrl ? publicImageUrl : '', linkUrl: cr.linkUrl || '',
          startAt: o.startAt, endAt: o.endAt, districts, regionIds, areaKeys: areaKeysOf(districts, regionIds),
          priority: 0, weight: isInt(o.weight, 1, MAX_WEIGHT) ? o.weight : 1, source: 'paid', orderId,
          active: true, visible: true, version: 1, createdAt: ts(), updatedAt: ts(),
        });
        t.update(orderRef, { status: 'approved', adId: orderId, decidedAt: ts(), decidedBy: actor, decisionNote: reason, updatedAt: ts() });
        event(t, orderId, 'approved', actor, { reason });
        t.create(db.collection(ADMIN_AUDIT).doc(), { kind: 'splash_ad_order_approve', actor, target: `${ORDERS}/${orderId}`, reason, amount, at: ts() });
        return { duplicate: false, o, refund: null };
      }
      const userRef = db.collection('users').doc(o.walletDocId || o.uid);
      const us = amount > 0 ? await t.get(userRef) : null;
      const bonusCtx = amount > 0 ? await settlementLedger.prepareBonusInTx(t, db, o.walletDocId || o.uid, { idempotencyKey: `splash_refund_${orderId}` }) : null;
      // ── ЁЗИШ ──
      let walletRefund = 0;
      if (bonusCtx && !bonusCtx.jExists) {
        // Ягона ёзиш йўли (W-1).
        settlementLedger.walletPost(t, bonusCtx, {
          delta: amount, kind: 'splash_ad_reject_refund', refType: 'splash_ad_order', refId: orderId,
          meta: { module: 'splash_ad' }, postedBy: actor, postedRole: 'admin',
          nextBalance: balanceOf(us && us.data()) + amount,
          walletLedgerType: 'splash_ad_reject_refund', walletLedgerId: `splash_refund_${orderId}`,
          walletLedger: { module: 'splash_ad', refType: 'splash_ad_order', refId: orderId, meta: { reason }, createdBy: actor },
        });
        walletRefund = amount;
      }
      const refund = { wallet: walletRefund };
      t.update(orderRef, { status: 'rejected', rejectReason: reason, refund, decidedAt: ts(), decidedBy: actor, updatedAt: ts() });
      event(t, orderId, 'rejected', actor, { reason, refund });
      t.create(db.collection(ADMIN_AUDIT).doc(), { kind: 'splash_ad_order_reject', actor, target: `${ORDERS}/${orderId}`, reason, refund, at: ts() });
      return { duplicate: false, o, refund };
    });
    log({ action: 'adminModerateSplashAdOrder', result: res.duplicate ? 'duplicate' : target, userId: tail(actor), orderId, durationMs: now() - started });
    if (!res.duplicate) {
      const user = await userDoc(res.o.uid);
      const lang = user && user.data.appLang;
      if (decision === 'approve') await notify(user ? user.id : res.o.uid, lang, 'approved', { start: res.o.startDay, days: res.o.days }, orderId);
      else await notify(user ? user.id : res.o.uid, lang, 'rejected', { reason, amount: res.refund.wallet }, orderId);
    }
    return { ok: true, orderId, status: target, duplicate: res.duplicate, refund: res.refund || null };
  });

  // ── Админ: созлама ва тариф ──
  exportsObj.adminSplashAdGetSettings = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const cfg = await loadConfig();
    const [tariff, list] = await Promise.all([
      loadTariff(cfg.activeTariffVersion),
      db.collection(TARIFFS).orderBy('version', 'desc').limit(20).get(),
    ]);
    return {
      ok: true, config: cfg, durations: DURATIONS, areaLevels: AREA_LEVELS,
      tariff: tariff ? { version: tariff.version, perDay: tariff.perDay, note: tariff.note || '' } : null,
      tariffVersions: list.docs.map((x) => ({ version: x.data().version, perDay: x.data().perDay, note: x.data().note || '' })),
    };
  });

  /** { config: {stage, internalPhones, pilotDistrictIds} } — activeTariffVersion ўзгармайди. */
  exportsObj.adminSplashAdSaveConfig = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const v = validateConfig(data && data.config);
    if (!v.ok) throw fail('invalid-argument', 'CONFIG_INVALID', { errors: v.errors });
    await db.runTransaction(async (t) => {
      const s = await t.get(configRef());
      const prev = s.exists ? (s.data() || {}) : {};
      t.set(configRef(), { ...v.value, updatedAt: ts(), updatedBy: actor }, { merge: true });
      t.create(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'splash_ad_config', actor, target: `${CONFIG}/${CONFIG_DOC}`,
        before: { stage: prev.stage || 'off', internalPhones: (prev.internalPhones || []).length }, after: { stage: v.value.stage, internalPhones: v.value.internalPhones.length }, at: ts(),
      });
    });
    return { ok: true };
  });

  /** { perDay: {district, region, republic}, note } → янги ўзгармас версия v{n} фаол бўлади. Эски буюртмалар ўз нархида. */
  exportsObj.adminSplashAdPublishTariff = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const v = validateTariff(data && data.perDay);
    if (!v.ok) throw fail('invalid-argument', 'TARIFF_INVALID', { errors: v.errors });
    const note = str(data && data.note).slice(0, LIMITS.note);
    const version = await db.runTransaction(async (t) => {
      const s = await t.get(configRef());
      const d = s.exists ? (s.data() || {}) : {};
      const prev = Number.isSafeInteger(d.activeTariffVersion) ? d.activeTariffVersion : 0;
      const next = (Number.isSafeInteger(d.maxTariffVersion) ? d.maxTariffVersion : prev) + 1;
      t.create(db.collection(TARIFFS).doc(`v${next}`), { version: next, perDay: v.value, note, createdBy: actor, createdAt: ts() });
      t.set(configRef(), { activeTariffVersion: next, maxTariffVersion: next, updatedAt: ts(), updatedBy: actor }, { merge: true });
      t.create(db.collection(ADMIN_AUDIT).doc(), { kind: 'splash_ad_tariff_publish', actor, target: `${TARIFFS}/v${next}`, before: prev, after: v.value, note, at: ts() });
      return next;
    });
    log({ action: 'adminSplashAdPublishTariff', result: 'ok', userId: tail(actor), tariffVersion: version });
    return { ok: true, version };
  });

  /** Муддати ўтган рекламалар `visible=false` (мижоз сўрови кичик қолсин). Идемпотент. */
  async function runExpire(nowMs) {
    const snap = await db.collection(ADS).where('endAt', '<', TS.fromMillis(nowMs)).limit(LIMITS.expireBatch).get();
    const stale = snap.docs.filter((d) => (d.data() || {}).visible === true);
    if (stale.length) {
      const b = db.batch();
      stale.forEach((d) => b.update(d.ref, { visible: false, updatedAt: ts() }));
      await b.commit();
    }
    return { scanned: snap.size, expired: stale.length };
  }
  exportsObj.splashAdsExpireDaily = functions.pubsub
    .schedule('every day 00:20').timeZone('Asia/Tashkent')
    .onRun(async () => {
      const res = await runExpire(Date.now());
      log({ action: 'splashAdsExpireDaily', result: 'ok', ...res });
      return null;
    });

  return { validateAd, sanitizeImpressions, dayKeyOf, runExpire };
}

module.exports = {
  attachSplashAds, validateAd, sanitizeImpressions, dayKeyOf, dayStartMs, areaKeysOf, priceOf, imageOwnedBy,
  validatePurchase, validateTariff, validateConfig, orderIdOf, testOverrides,
  MAX_IMPRESSIONS_PER_DAY, DURATIONS, ADS, STATS, IMP_LOG, ORDERS,
};
