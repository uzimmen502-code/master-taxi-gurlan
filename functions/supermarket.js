/**
 * «AVA Супермаркет» 1-босқич — СЕРВЕР (эга 2026-11-20).
 *
 * МАВЖУД занжир устида (параллел тизим ЙЎҚ, 3/4-банд):
 *   - каталог: `platform_products` (ҳар ҳужжат = битта ТАКЛИФ: гуруҳ → нав → сифат/қадоқ/нарх);
 *   - буюртма: `orders` (`type: 'platform'`, `subtype: 'supermarket'`) — мавжуд админ доскаси, курьер
 *     навбати (`status: 'ready'`), `customerCancelOrder` / `adminSetOrderStatus` (рад — `balanceApplied`
 *     қайтими) ўзгармасдан ишлайди;
 *   - ҳамён: `users.bonusBalance` + `settlement_ledger` (prepare/commitBonusInTx) + `users/{id}/wallet_ledger`
 *     — `placeOrderPostPaid` даги айнан шу механизм (янги ҳамён логикаси ЙЎҚ);
 *   - етказиш ҳақи: `settings/app.platformDeliveryFeePercent` (ЯГОНА манба, админ `adminSetPlatformDeliveryFeePercent`
 *     орқали ўзгартиради) — бу ерда фақат ўқилади;
 *   - қидирув: `market_search_tokens.buildSearchTokens` (алифбо folding билан) + гуруҳ синонимлари.
 *
 * ПУЛ — фақат бутун сўм (8-банд). Миқдор (кг/л) — каср; ҳисоб «милли-бирлик» бутун сонида:
 *   qMilli = qty × 1000; қатор = round_half_up(price × qMilli / 1000).
 * Тортиладиган товар: ушлаб туриш (hold) = goods + Σ ceil(weighed_line × weighHoldPercent / 100) + fee(goods).
 * Тортилгандан кейин: target = goods' + fee(goods'); янги ечим = min(жорий ечим, target) — ҳеч қачон
 * ушлангандан ортиқ эмас; фарқ ҳамёнга қайтади. `balanceApplied` доим ҲОЗИР ечилган суммани кўрсатади —
 * мавжуд бекор қилиш (рад/мижоз бекори) айнан қолганини қайтаради.
 *
 * Callables: adminSetSupermarketTaxonomy · adminSetSupermarketSettings · getSupermarketAccess ·
 *   adminUpsertSupermarketOffer · placeSupermarketOrder · adminSettleSupermarketWeights · adminRemoveSupermarketLine.
 * Trigger: onSupermarketOrderCancelStock (рад/бекор → `stock` қайтади, бир марта).
 */
'use strict';

const { buildSearchTokens } = require('./market_search_tokens');
const { normalizeLang, langOfPhone } = require('./notif_i18n');
// Мавжуд рағбат тизими (feat/incentives-srv e0985429 — жонли нусха; бу ердан фақат тоза/tx ёрдамчилар ишлатилади).
const incentivesLib = require('./incentives');
// Байрам саватчаси (эга 2026-11-26) — holiday.js бу модулни талаб қилади, шунинг учун кеч юкланади (айланма require йўқ).
let holidayMod = null;
const hol = () => holidayMod || (holidayMod = require('./holiday'));

const MODULE = 'supermarket';
const TAXONOMY_DOC = ['taxonomy', 'supermarket'];
const SETTINGS_DOC = ['settings', 'supermarket'];
const APP_SETTINGS_DOC = ['settings', 'app'];
const HISTORY_COLLECTION = 'taxonomy_history';
const HISTORY_PREFIX = 'supermarket_v'; // taxonomy/markets `v{n}` билан тўқнашмасин
const ADMIN_AUDIT = 'admin_audit';
const PRODUCTS = 'platform_products';
const ORDERS = 'orders';
const IDEM = 'wallet_idempotency';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const OPERATOR_ROLES = Object.freeze(['admin', 'superadmin', 'dispatcher']);
const PACK_UNITS = Object.freeze(['kg', 'l', 'piece']);
// Ҳамён тарихи изоҳи: калит + 3 тил (note — эски клиентлар учун uz_Cyrl).
const REFUND_NOTES = Object.freeze({
  weigh: { key: 'sm_refund_weigh', messages: { uz_Cyrl: 'Супермаркет: тортилгандан кейинги қайтим', uz_Latn: 'Supermarket: tortilgandan keyingi qaytim', ru: 'Супермаркет: возврат после взвешивания' } },
  remove: { key: 'sm_refund_line_removed', messages: { uz_Cyrl: 'Супермаркет: маҳсулот олинди, қайтим', uz_Latn: 'Supermarket: mahsulot olindi, qaytim', ru: 'Супермаркет: товар удалён, возврат' } },
  shortage_substitute: { key: 'sm_refund_substitute', messages: { uz_Cyrl: 'Супермаркет: арзонроқ маҳсулотга алмаштирилди, қайтим', uz_Latn: 'Supermarket: arzonroq mahsulotga almaştirildi, qaytim', ru: 'Супермаркет: замена на более дешёвый товар, возврат' } },
  shortage_reduce: { key: 'sm_refund_reduced', messages: { uz_Cyrl: 'Супермаркет: миқдор камайтирилди, қайтим', uz_Latn: 'Supermarket: miqdor kamaytirildi, qaytim', ru: 'Супермаркет: количество уменьшено, возврат' } },
  shortage_remove: { key: 'sm_refund_line_removed', messages: { uz_Cyrl: 'Супермаркет: маҳсулот олинди, қайтим', uz_Latn: 'Supermarket: mahsulot olindi, qaytim', ru: 'Супермаркет: товар удалён, возврат' } },
});
// Қўшимча ечим (фақат мижоз розилиги билан — қимматроқ алмаштириш).
const DEBIT_NOTES = Object.freeze({
  shortage_substitute: { key: 'sm_debit_substitute', messages: { uz_Cyrl: 'Супермаркет: алмаштирилган маҳсулот фарқи', uz_Latn: 'Supermarket: almaştirilgan mahsulot farqi', ru: 'Супермаркет: доплата за замену товара' } },
});
const SHORTAGE_CHOICES = Object.freeze(['substitute', 'reduce', 'remove']);
const SHORTAGE_SUBS_MAX = 3;
const SHORTAGE_ANSWER_MS = 30 * 60000; // 30 дақиқа — кейин админ қаторни олиши мумкин (мавжуд callable)
const LIST_ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
const WEEK_MS = 7 * 86400000;
const REMIND_BATCH = 400;
// Ҳафталик сават эслатмаси (эга 2026-11-21, 3 тил). Ҳеч қачон буюртма яратмайди / пул ечмайди.
const REMIND_TEXT = Object.freeze({
  uz_Cyrl: { title: 'AVA Супермаркет', body: 'AVA Супермаркет: ҳафталик саватингиз тайёр. Маҳсулотлар ва жорий нархларни кўриб чиқинг.' },
  uz_Latn: { title: 'AVA Supermarket', body: 'AVA Supermarket: haftalik savatingiz tayyor. Mahsulotlar va joriy narxlarni körib çiqing.' },
  ru: { title: 'AVA Супермаркет', body: 'AVA Супермаркет: ваша недельная корзина готова. Проверьте товары и текущие цены.' },
});
const SHORTAGE_TEXT = Object.freeze({
  uz_Cyrl: { title: 'Буюртмада битта маҳсулот етишмаяпти', body: '«{name}» етарли эмас. Алмаштириш, миқдорни камайтириш ёки олиб ташлашни танланг (30 дақиқа ичида).' },
  uz_Latn: { title: 'Buyurtmada bitta mahsulot yetişmayapti', body: '«{name}» yetarli emas. Almaştiriş, miqdorni kamaytiriş yoki olib taşlaşni tanlang (30 daqiqa içida).' },
  ru: { title: 'В заказе не хватает товара', body: '«{name}» недостаточно. Выберите замену, уменьшение количества или удаление (в течение 30 минут).' },
});

const LANGS = Object.freeze(['uz_Cyrl', 'uz_Latn', 'ru']);
const UNITS = Object.freeze(['kg', 'l', 'piece', 'pack', 'bunch']);
const STAGES = Object.freeze(['off', 'internal', 'pilot', 'public']);
const SM_STATUSES = Object.freeze(['active', 'out_of_stock', 'hidden']);
const DAYS = Object.freeze(['today', 'tomorrow']);
// 3-босқич (эга 2026-11-21); 'holiday' — туғилган кун/байрам саватчаси (эга 2026-11-26).
const ORDER_ORIGINS = Object.freeze(['catalog', 'quick', 'weekly', 'reorder', 'holiday']);
const TARIFF_VERSION = 'sm-v1'; // формула: каталог нархи × миқдор + settings/app % + тортиш ушлаб туриши
const TZ_OFFSET_MS = 5 * 3600000; // Asia/Tashkent
const DAY_MS = 86400000;

// Буюртма қатори учун эски кўриниш бирлиги (`items[].unit` — эски админ/курьер экранлари матн кутади).
const UNIT_LABELS = Object.freeze({
  kg: { uz_Cyrl: 'кг', uz_Latn: 'kg', ru: 'кг' },
  l: { uz_Cyrl: 'л', uz_Latn: 'l', ru: 'л' },
  piece: { uz_Cyrl: 'дона', uz_Latn: 'dona', ru: 'шт' },
  pack: { uz_Cyrl: 'пачка', uz_Latn: 'paçka', ru: 'уп.' },
  bunch: { uz_Cyrl: 'боғ', uz_Latn: 'boğ', ru: 'пучок' },
});

const LIMITS = Object.freeze({
  name: 60, synonym: 40, synonyms: 20, packLabel: 40, maxBytes: 200 * 1024, maxErrors: 50,
  items: 60, qtyMilliMax: 1000 * 1000, priceMax: 999999999, stockMax: 1000000,
  testers: 200, districts: 50, slots: 12, addressPart: 120, landmark: 200, reason: 300,
  offerName: 120, description: 1000, imageUrl: 500, images: 10, supplier: 120,
});

const ID_RE = /^[a-z][a-z0-9_]{1,39}$/;
const DISTRICT_RE = /^[a-z0-9_-]{2,40}$/;
const SLOT_ID_RE = /^[a-z0-9_]{1,20}$/;
const PRODUCT_ID_RE = /^[A-Za-z0-9_-]{6,64}$/;
const CLIENT_REQ_RE = /^[A-Za-z0-9_-]{8,64}$/;
const TESTER_RE = /^998\d{9}$/;

// ── Хабарлар: diagnostic code → [uz_Cyrl, uz_Latn, ru] (25-банд) ──
const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  INVALID_REQUEST: ['Маълумот нотўғри. Қайта уриниб кўринг.', "Ma'lumot notöğri. Qayta urinib köring.", 'Неверные данные. Попробуйте ещё раз.'],
  STAGE_OFF: ['Супермаркет ҳозир ёпиқ.', 'Supermarket hozir yopiq.', 'Супермаркет сейчас закрыт.'],
  NOT_TESTER: ['Супермаркет ҳозир синов режимида.', 'Supermarket hozir sinov rejimida.', 'Супермаркет сейчас в тестовом режиме.'],
  DISTRICT_NOT_SERVED: ['Бу ҳудудга ҳозирча етказиб бермаймиз.', 'Bu hududga hozirça yetkazib bermaymiz.', 'В этот район пока не доставляем.'],
  DISTRICT_REQUIRED: ['Етказиш ҳудудини танланг.', 'Yetkaziş hududini tanlang.', 'Выберите район доставки.'],
  SLOT_UNAVAILABLE: ['Бу вақт оралиғи банд ёки ўтиб кетди. Бошқасини танланг.', "Bu vaqt oralığı band yoki ötib ketdi. Boşqasini tanlang.", 'Этот интервал недоступен. Выберите другой.'],
  PRODUCT_NOT_FOUND: ['Маҳсулот топилмади.', 'Mahsulot topilmadi.', 'Товар не найден.'],
  PRODUCT_UNAVAILABLE: ['Маҳсулот ҳозир сотувда йўқ.', "Mahsulot hozir sotuvda yöq.", 'Товар сейчас недоступен.'],
  OUT_OF_STOCK: ['Маҳсулот етарли эмас.', 'Mahsulot yetarli emas.', 'Недостаточно товара.'],
  QTY_STEP_INVALID: ['Миқдор нотўғри.', "Miqdor notöğri.", 'Неверное количество.'],
  PRICE_MISSING: ['Маҳсулот нархи белгиланмаган.', 'Mahsulot narxi belgilanmagan.', 'У товара нет цены.'],
  DUPLICATE_ITEM: ['Маҳсулот саватда икки марта.', 'Mahsulot savatda ikki marta.', 'Товар в корзине дважды.'],
  INSUFFICIENT_BALANCE: ['Ҳамёнда маблағ етарли эмас. Ҳамённи тўлдиринг.', "Hamyonda mablağ yetarli emas. Hamyonni töldiring.", 'Недостаточно средств в кошельке. Пополните кошелёк.'],
  USER_NOT_FOUND: ['Ҳисоб топилмади.', 'Hisob topilmadi.', 'Аккаунт не найден.'],
  ORDER_NOT_FOUND: ['Буюртма топилмади.', 'Buyurtma topilmadi.', 'Заказ не найден.'],
  ORDER_NOT_SUPERMARKET: ['Бу супермаркет буюртмаси эмас.', 'Bu supermarket buyurtmasi emas.', 'Это не заказ супермаркета.'],
  ORDER_STATE_LOCKED: ['Буюртма ҳолати ўзгарган — бу амални бажариб бўлмайди.', "Buyurtma holati özgargan — bu amalni bajarib bölmaydi.", 'Статус заказа изменился — действие недоступно.'],
  LINE_NOT_FOUND: ['Буюртмада бу маҳсулот йўқ.', "Buyurtmada bu mahsulot yöq.", 'В заказе нет этого товара.'],
  LINE_NOT_WEIGHED: ['Бу маҳсулот тортилмайди.', 'Bu mahsulot tortilmaydi.', 'Этот товар не взвешивается.'],
  LINE_ALREADY_SETTLED: ['Бу маҳсулот аллақачон тортилган.', 'Bu mahsulot allaqaçon tortilgan.', 'Этот товар уже взвешен.'],
  LINE_ALREADY_REMOVED: ['Бу маҳсулот буюртмадан олинган.', 'Bu mahsulot buyurtmadan olingan.', 'Этот товар уже удалён из заказа.'],
  ACTUAL_QTY_INVALID: ['Тортилган миқдор нотўғри.', "Tortilgan miqdor notöğri.", 'Неверный фактический вес.'],
  ACTUAL_QTY_OVER_LIMIT: ['Тортилган миқдор рухсат этилган чегарадан ортиқ.', 'Tortilgan miqdor ruxsat etilgan çegaradan ortiq.', 'Фактический вес превышает допустимый предел.'],
  LAST_LINE: ['Охирги маҳсулотни олиб бўлмайди — буюртмани бекор қилинг.', "Oxirgi mahsulotni olib bölmaydi — buyurtmani bekor qiling.", 'Нельзя удалить последний товар — отмените заказ.'],
  REASON_REQUIRED: ['Сабабни ёзинг.', 'Sababni yozing.', 'Укажите причину.'],
  TAXONOMY_INVALID: ['Бўлимлар рўйхати нотўғри.', "Bölimlar röyxati notöğri.", 'Неверный список категорий.'],
  TAXONOMY_MISSING: ['Бўлимлар рўйхати ҳали яратилмаган.', "Bölimlar röyxati hali yaratilmagan.", 'Список категорий ещё не создан.'],
  TAXONOMY_VERSION_CONFLICT: ['Бўлимлар бошқа админ томонидан ўзгартирилган. Саҳифани янгиланг.', "Bölimlar boşqa admin tomonidan özgartirilgan. Sahifani yangilang.", 'Категории изменены другим админом. Обновите страницу.'],
  EXPECTED_VERSION_INVALID: ['Версия нотўғри.', "Versiya notöğri.", 'Неверная версия.'],
  SETTINGS_INVALID: ['Созламалар нотўғри.', "Sozlamalar notöğri.", 'Неверные настройки.'],
  SETTINGS_VERSION_CONFLICT: ['Созламалар бошқа админ томонидан ўзгартирилган. Саҳифани янгиланг.', "Sozlamalar boşqa admin tomonidan özgartirilgan. Sahifani yangilang.", 'Настройки изменены другим админом. Обновите страницу.'],
  OFFER_INVALID: ['Таклиф маълумоти нотўғри.', "Taklif ma'lumoti notöğri.", 'Неверные данные предложения.'],
  GROUP_UNKNOWN: ['Бундай гуруҳ йўқ.', "Bunday guruh yöq.", 'Такой группы нет.'],
  TARIFF_NOT_CONFIGURED: ['Етказиш нархи ҳали созланмаган. Кейинроқ уриниб кўринг.', 'Yetkaziş narxi hali sozlanmagan. Keyinroq urinib köring.', 'Стоимость доставки ещё не настроена. Попробуйте позже.'],
  INTERNAL: ['Амални бажариб бўлмади. Қайта уриниб кўринг.', "Amalni bajarib bölmadi. Qayta urinib köring.", 'Не удалось выполнить. Попробуйте ещё раз.'],
  // 2-босқич: етишмовчилик (эга 2026-11-21)
  INSUFFICIENT_FUNDS: ['Алмаштириш учун ҳамёнда маблағ етарли эмас. Ҳамённи тўлдиринг ёки бошқа вариантни танланг.', "Almaştiriş uçun hamyonda mablağ yetarli emas. Hamyonni töldiring yoki boşqa variantni tanlang.", 'Для замены недостаточно средств в кошельке. Пополните кошелёк или выберите другой вариант.'],
  LINE_SHORTAGE_PENDING: ['Бу маҳсулот бўйича мижоз жавоби кутилмоқда.', "Bu mahsulot böyiça mijoz javobi kutilmoqda.", 'По этому товару ожидается ответ клиента.'],
  LINE_NO_SHORTAGE: ['Бу маҳсулот бўйича савол йўқ.', "Bu mahsulot böyiça savol yöq.", 'По этому товару нет вопроса.'],
  LINE_SHORTAGE_RESOLVED: ['Бу маҳсулот бўйича жавоб аллақачон берилган.', "Bu mahsulot böyiça javob allaqaçon berilgan.", 'Ответ по этому товару уже дан.'],
  SUBSTITUTE_INVALID: ['Алмаштириладиган маҳсулот нотўғри ёки сотувда йўқ.', "Almaştiriladigan mahsulot notöğri yoki sotuvda yöq.", 'Товар для замены неверный или недоступен.'],
  AVAILABLE_QTY_INVALID: ['Мавжуд миқдор нотўғри.', "Mavjud miqdor notöğri.", 'Неверное доступное количество.'],
});

function messagesOf(code) {
  const m = MSG[code] || MSG.INTERNAL;
  return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] };
}

const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
function isPlainObject(v) {
  if (v == null || typeof v !== 'object' || Array.isArray(v)) return false;
  const p = Object.getPrototypeOf(v);
  return p === Object.prototype || p === null;
}
function trimDeep(v) {
  if (typeof v === 'string') return v.trim();
  if (Array.isArray(v)) return v.map(trimDeep);
  if (isPlainObject(v)) {
    const o = {};
    for (const k of Object.keys(v)) o[k] = trimDeep(v[k]);
    return o;
  }
  return v;
}
function stableStringify(v) {
  if (Array.isArray(v)) return `[${v.map(stableStringify).join(',')}]`;
  if (isPlainObject(v)) return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stableStringify(v[k])}`).join(',')}}`;
  return JSON.stringify(v === undefined ? null : v);
}

// ══════════════════════ МИҚДОР ВА ПУЛ (тоза) ══════════════════════

/** qty → милли-бирлик (бутун). Каср 3 хонадан ортиқ бўлса ёки сон бўлмаса — null. */
function toMilli(qty) {
  if (typeof qty !== 'number' || !Number.isFinite(qty)) return null;
  const m = Math.round(qty * 1000);
  if (Math.abs(qty * 1000 - m) > 1e-6) return null;
  return m;
}
const fromMilli = (m) => m / 1000;

/** Қатор суммаси: round_half_up(price × qMilli / 1000), бутун арифметика. */
function lineTotalOf(price, qMilli) {
  return Math.floor((price * qMilli + 500) / 1000);
}
/** Тортиш ушлаб туриши: ceil(line × pct / 100), бутун. */
function holdExtraOf(lineTotal, pct) {
  if (!(pct > 0) || !(lineTotal > 0)) return 0;
  return Math.floor((lineTotal * pct + 99) / 100);
}
/**
 * ЕТКАЗИШ ҲАҚИ — ЖОНЛИ `platformDeliveryFeeFromSettings` (placeOrderPostPaid, live = fix/courier-3bugs-srv
 * index.js e9e9d1e8, gcf zip билан CONFIRMED 2026-11-20) билан АЙНАН бир хил қоида:
 *   - манба: settings/app.platformDeliveryFeePercent (admin `adminSetPlatformDeliveryFeePercent`, версия +1, тарих);
 *   - hardcode fallback ЙЎҚ — йўқ/бузуқ → TARIFF_NOT_CONFIGURED (fail closed); >100 → 100;
 *   - bps = round(pct × 100); fee = floor((goods × bps + 5000) / 10000); version = platformDeliveryFeeVersion (йўқ → 0).
 * ОЧИҚ: иккала нусха битта модулга (platform_delivery_fee.js) кўчирилиши керак — fix/courier-3bugs-srv шу
 * линияга қўшилганда (7-банд). Ҳозир index.js'даги жонли функцияга тегилмади.
 */
function feeConfigFromApp(appData) {
  const raw = (appData || {}).platformDeliveryFeePercent;
  const pctIn = (typeof raw === 'number' || (typeof raw === 'string' && raw.trim() !== '')) ? Number(raw) : NaN;
  if (!Number.isFinite(pctIn) || pctIn < 0) return null;
  const percent = Math.min(pctIn, 100);
  const verRaw = Number((appData || {}).platformDeliveryFeeVersion);
  return { percent, bps: Math.round(percent * 100), version: Number.isInteger(verRaw) && verRaw > 0 ? verRaw : 0 };
}
/** Буюртмадаги сақланган % дан bps (тортиш/олишда — буюртма пайтидаги % ишлатилади, 9-банд). */
function feeBpOf(pct) {
  const n = Number(pct);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(Math.min(n, 100) * 100);
}
function feeOf(goods, bp) {
  if (!(goods > 0) || !(bp > 0)) return 0;
  return Math.floor((goods * bp + 5000) / 10000);
}
/**
 * Буюртма қаторларидан жорий «мақсад» ечим.
 * Олинган қатор — ҳисобга кирмайди; тортилмаган тортиладиган қатор — total + holdExtra;
 * тортилган — finalTotal; оддий — total. fee — goods'дан.
 */
function computeCharge(lines, bp) {
  let goods = 0;
  let extras = 0;
  for (const l of lines) {
    if (l.removed) continue;
    if (l.weighed && l.actualQty == null) {
      goods += l.total;
      extras += l.holdExtra || 0;
    } else {
      goods += l.finalTotal != null ? l.finalTotal : l.total;
    }
  }
  const fee = feeOf(goods, bp);
  return { goods, extras, fee, target: goods + extras + fee };
}

// ══════════════════════ ВАҚТ ОРАЛИҚЛАРИ ══════════════════════

function tashkentParts(nowMs) {
  const t = new Date(nowMs + TZ_OFFSET_MS);
  const pad = (n) => String(n).padStart(2, '0');
  return {
    dateKey: `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`,
    minutes: t.getUTCHours() * 60 + t.getUTCMinutes(),
  };
}

/**
 * Бугун: бошланишигача ≥ cutoffMin қолган оралиқлар (PROPOSED талқин); эртага: барчаси.
 * @returns {{today: object[], tomorrow: object[]}}
 */
function availableSlots(settings, nowMs) {
  const s = settings || {};
  const slots = Array.isArray(s.slots) ? s.slots : [];
  const cutoff = Number.isInteger(s.cutoffMin) ? s.cutoffMin : 0;
  const today = tashkentParts(nowMs);
  const tomorrow = tashkentParts(nowMs + DAY_MS);
  const view = (sl, date) => ({ id: sl.id, names: sl.names, startMin: sl.startMin, endMin: sl.endMin, date });
  return {
    today: slots.filter((sl) => today.minutes <= sl.startMin - cutoff).map((sl) => view(sl, today.dateKey)),
    tomorrow: slots.map((sl) => view(sl, tomorrow.dateKey)),
  };
}

// ══════════════════════ ДАРВОЗА (gate) ══════════════════════

/**
 * off — ҳеч ким; internal/pilot — admin + testerIds (PROPOSED: pilot = кенгайтирилган тестерлар); public — ҳамма.
 * Ҳудуд: `districtId` берилса — `districtIds` ичида бўлиши шарт; requireDistrict=true бўлса бўш ҳудуд рад.
 */
function gateDecision(settings, { uid, role, districtId, requireDistrict }) {
  const s = settings || null;
  const stage = s && STAGES.includes(s.stage) ? s.stage : 'off';
  if (stage === 'off') return { allowed: false, reason: 'STAGE_OFF', stage };
  const privileged = ADMIN_ROLES.includes(role);
  const testers = Array.isArray(s.testerIds) ? s.testerIds : [];
  if ((stage === 'internal' || stage === 'pilot') && !privileged && !testers.includes(uid)) {
    return { allowed: false, reason: 'NOT_TESTER', stage };
  }
  const d = String(districtId || '').trim();
  const districts = Array.isArray(s.districtIds) ? s.districtIds : [];
  if (!d) {
    if (requireDistrict) return { allowed: false, reason: 'DISTRICT_REQUIRED', stage };
  } else if (!districts.includes(d)) {
    return { allowed: false, reason: 'DISTRICT_NOT_SERVED', stage };
  }
  return { allowed: true, reason: '', stage };
}

// ══════════════════════ ВАЛИДАТОРЛАР ══════════════════════

function makeErr() {
  const errors = [];
  const err = (code, p) => { if (errors.length < LIMITS.maxErrors) errors.push(p ? `${code} ${p}` : code); };
  return { errors, err };
}
function checkLocalized(v, p, kind, max, err) {
  if (!isPlainObject(v)) { err(`${kind}_MISSING`, p); return; }
  for (const lang of LANGS) {
    const s = v[lang];
    if (typeof s !== 'string' || !s.trim()) err(`${kind}_MISSING`, `${p}.${lang}`);
    else if (s.length > max) err(`${kind}_TOO_LONG`, `${p}.${lang}`);
  }
  for (const k of Object.keys(v)) if (!LANGS.includes(k)) err('UNKNOWN_KEY', `${p}.${k}`);
}
function unknownKeys(o, allowed, p, err) {
  for (const k of Object.keys(o)) if (!allowed.includes(k)) err('UNKNOWN_KEY', p ? `${p}.${k}` : k);
}
/** qtyStep: 0.001..1000, 3 хонагача каср. */
function stepOk(step) {
  const m = toMilli(step);
  return m != null && m >= 1 && m <= 1000 * 1000;
}

const CATEGORY_KEYS = ['id', 'order', 'icon', 'names', 'groups'];
const GROUP_KEYS = ['id', 'order', 'names', 'unit', 'step', 'weighed', 'synonyms', 'pairs'];
const PAIRS_MAX = 10; // «бирга олинади» (cross-sell) — гуруҳга ≤10 бошқа гуруҳ (эга 2026-11-21)

/** taxonomy {categories:[...]} → {ok, errors}. Гуруҳ id'лари БУТУН таксономияда ягона (таклиф smGroupId'ни ишлатади). */
function validateSupermarketTaxonomy(obj) {
  const { errors, err } = makeErr();
  const done = () => ({ ok: errors.length === 0, errors });
  if (!isPlainObject(obj)) { err('TAXONOMY_NOT_OBJECT'); return done(); }
  let bytes;
  try { bytes = Buffer.byteLength(JSON.stringify(obj), 'utf8'); } catch (_) { err('TAXONOMY_NOT_SERIALIZABLE'); return done(); }
  if (bytes > LIMITS.maxBytes) { err('TAXONOMY_TOO_LARGE', `${bytes}`); return done(); }
  unknownKeys(obj, ['categories'], '', err);
  if (!Array.isArray(obj.categories) || obj.categories.length === 0) { err('CATEGORIES_EMPTY', 'categories'); return done(); }
  const catIds = new Set();
  const groupIds = new Set();
  const pairChecks = [];
  obj.categories.forEach((c, i) => {
    const cp = `categories[${i}]`;
    if (!isPlainObject(c)) { err('CATEGORY_NOT_OBJECT', cp); return; }
    unknownKeys(c, CATEGORY_KEYS, cp, err);
    if (typeof c.id !== 'string' || !ID_RE.test(c.id)) err('CATEGORY_ID_INVALID', `${cp}.id`);
    else if (catIds.has(c.id)) err('CATEGORY_ID_DUPLICATE', `${cp}.id`);
    else catIds.add(c.id);
    if (!Number.isInteger(c.order)) err('ORDER_INVALID', `${cp}.order`);
    if (typeof c.icon !== 'string' || !/^[a-z0-9_]{1,40}$/.test(c.icon)) err('ICON_INVALID', `${cp}.icon`);
    checkLocalized(c.names, `${cp}.names`, 'NAME', LIMITS.name, err);
    if (!Array.isArray(c.groups) || c.groups.length === 0) { err('GROUPS_EMPTY', `${cp}.groups`); return; }
    c.groups.forEach((g, j) => {
      const gp = `${cp}.groups[${j}]`;
      if (!isPlainObject(g)) { err('GROUP_NOT_OBJECT', gp); return; }
      unknownKeys(g, GROUP_KEYS, gp, err);
      if (typeof g.id !== 'string' || !ID_RE.test(g.id)) err('GROUP_ID_INVALID', `${gp}.id`);
      else if (groupIds.has(g.id)) err('GROUP_ID_DUPLICATE', `${gp}.id`);
      else groupIds.add(g.id);
      if (!Number.isInteger(g.order)) err('ORDER_INVALID', `${gp}.order`);
      checkLocalized(g.names, `${gp}.names`, 'NAME', LIMITS.name, err);
      if (!UNITS.includes(g.unit)) err('UNIT_INVALID', `${gp}.unit`);
      if (!stepOk(g.step)) err('STEP_INVALID', `${gp}.step`);
      if (typeof g.weighed !== 'boolean') err('WEIGHED_INVALID', `${gp}.weighed`);
      if (!Array.isArray(g.synonyms) || g.synonyms.length > LIMITS.synonyms) err('SYNONYMS_INVALID', `${gp}.synonyms`);
      else g.synonyms.forEach((s, k) => {
        if (typeof s !== 'string' || !s.trim() || s.length > LIMITS.synonym) err('SYNONYM_INVALID', `${gp}.synonyms[${k}]`);
      });
      // pairs — ихтиёрий; мавжуд гуруҳ id'лари (ўзи эмас, такрорсиз) — ҳамма гуруҳ йиғилгандан кейин текширилади.
      if (g.pairs !== undefined) {
        if (!Array.isArray(g.pairs) || g.pairs.length > PAIRS_MAX) err('PAIRS_INVALID', `${gp}.pairs`);
        else pairChecks.push({ gp, id: g.id, pairs: g.pairs });
      }
    });
  });
  for (const { gp, id, pairs } of pairChecks) {
    const seen = new Set();
    pairs.forEach((p, k) => {
      if (typeof p !== 'string' || !groupIds.has(p)) err('PAIR_UNKNOWN', `${gp}.pairs[${k}]`);
      else if (p === id) err('PAIR_SELF', `${gp}.pairs[${k}]`);
      else if (seen.has(p)) err('PAIR_DUPLICATE', `${gp}.pairs[${k}]`);
      else seen.add(p);
    });
  }
  return done();
}

/** {category, group} ёки null. */
function findGroup(taxonomy, groupId) {
  const cats = (taxonomy && Array.isArray(taxonomy.categories)) ? taxonomy.categories : [];
  for (const c of cats) {
    for (const g of (Array.isArray(c.groups) ? c.groups : [])) {
      if (g && g.id === groupId) return { category: c, group: g };
    }
  }
  return null;
}

const SETTINGS_KEYS = ['stage', 'testerIds', 'districtIds', 'slots', 'cutoffMin', 'weighHoldPercent', 'courierPayout'];
const COURIER_PAYOUT_MODES = Object.freeze(['percent', 'fixed']);

/**
 * Курьер тўлови созламаси (эга 2026-11-26): {mode:'percent', percent:0..100 (буюртма deliveryFee'дан)} ёки
 * {mode:'fixed', fixedAmount:≥0 сўм}. undefined/null — созланмаган. Хатолар рўйхати қайтади.
 */
function courierPayoutProblems(cp, p = 'courierPayout') {
  if (cp === undefined || cp === null) return [];
  const out = [];
  if (!isPlainObject(cp)) return [`COURIER_PAYOUT_INVALID ${p}`];
  for (const k of Object.keys(cp)) if (!['mode', 'percent', 'fixedAmount'].includes(k)) out.push(`UNKNOWN_KEY ${p}.${k}`);
  if (!COURIER_PAYOUT_MODES.includes(cp.mode)) out.push(`COURIER_PAYOUT_MODE_INVALID ${p}.mode`);
  if (cp.mode === 'percent') {
    if (!Number.isInteger(cp.percent) || cp.percent < 0 || cp.percent > 100) out.push(`COURIER_PAYOUT_PERCENT_INVALID ${p}.percent`);
    if (cp.fixedAmount !== undefined) out.push(`UNKNOWN_KEY ${p}.fixedAmount`);
  } else if (cp.mode === 'fixed') {
    if (!Number.isInteger(cp.fixedAmount) || cp.fixedAmount < 0 || cp.fixedAmount > LIMITS.priceMax) out.push(`COURIER_PAYOUT_FIXED_INVALID ${p}.fixedAmount`);
    if (cp.percent !== undefined) out.push(`UNKNOWN_KEY ${p}.percent`);
  }
  return out;
}

/**
 * Буюртма яратилганда курьер тўлови нусхаси (кейинги созлама ўзгариши эски буюртмага таъсир қилмайди, 9-банд).
 * percent → floor(deliveryFee × percent / 100); fixed → fixedAmount; созланмаган/бузуқ → amount null.
 */
function courierPayoutSnapshot(cp, deliveryFee, settingsVersion) {
  const version = Number.isInteger(settingsVersion) ? settingsVersion : 0;
  if (cp == null || courierPayoutProblems(cp).length) return { mode: null, amount: null, settingsVersion: version };
  if (cp.mode === 'percent') {
    const fee = Number.isInteger(deliveryFee) && deliveryFee > 0 ? deliveryFee : 0;
    return { mode: 'percent', percent: cp.percent, amount: Math.floor((fee * cp.percent) / 100), settingsVersion: version };
  }
  return { mode: 'fixed', fixedAmount: cp.fixedAmount, amount: cp.fixedAmount, settingsVersion: version };
}
const SLOT_KEYS = ['id', 'names', 'startMin', 'endMin'];

function validateSupermarketSettings(obj) {
  const { errors, err } = makeErr();
  const done = () => ({ ok: errors.length === 0, errors });
  if (!isPlainObject(obj)) { err('SETTINGS_NOT_OBJECT'); return done(); }
  unknownKeys(obj, SETTINGS_KEYS, '', err);
  if (!STAGES.includes(obj.stage)) err('STAGE_INVALID', 'stage');
  if (!Array.isArray(obj.testerIds) || obj.testerIds.length > LIMITS.testers) err('TESTERS_INVALID', 'testerIds');
  else {
    const seen = new Set();
    obj.testerIds.forEach((t, i) => {
      if (typeof t !== 'string' || !TESTER_RE.test(t)) err('TESTER_INVALID', `testerIds[${i}]`);
      else if (seen.has(t)) err('TESTER_DUPLICATE', `testerIds[${i}]`);
      else seen.add(t);
    });
  }
  if (!Array.isArray(obj.districtIds) || obj.districtIds.length > LIMITS.districts) err('DISTRICTS_INVALID', 'districtIds');
  else {
    const seen = new Set();
    obj.districtIds.forEach((d, i) => {
      if (typeof d !== 'string' || !DISTRICT_RE.test(d)) err('DISTRICT_INVALID', `districtIds[${i}]`);
      else if (seen.has(d)) err('DISTRICT_DUPLICATE', `districtIds[${i}]`);
      else seen.add(d);
    });
  }
  if (!Array.isArray(obj.slots) || obj.slots.length > LIMITS.slots) err('SLOTS_INVALID', 'slots');
  else {
    const seen = new Set();
    obj.slots.forEach((s, i) => {
      const sp = `slots[${i}]`;
      if (!isPlainObject(s)) { err('SLOT_NOT_OBJECT', sp); return; }
      unknownKeys(s, SLOT_KEYS, sp, err);
      if (typeof s.id !== 'string' || !SLOT_ID_RE.test(s.id)) err('SLOT_ID_INVALID', `${sp}.id`);
      else if (seen.has(s.id)) err('SLOT_ID_DUPLICATE', `${sp}.id`);
      else seen.add(s.id);
      checkLocalized(s.names, `${sp}.names`, 'NAME', 40, err);
      if (!Number.isInteger(s.startMin) || s.startMin < 0 || s.startMin > 1439) err('SLOT_START_INVALID', `${sp}.startMin`);
      if (!Number.isInteger(s.endMin) || s.endMin > 1440 || !(s.endMin > s.startMin)) err('SLOT_END_INVALID', `${sp}.endMin`);
    });
  }
  if (!Number.isInteger(obj.cutoffMin) || obj.cutoffMin < 0 || obj.cutoffMin > 720) err('CUTOFF_INVALID', 'cutoffMin');
  if (!Number.isInteger(obj.weighHoldPercent) || obj.weighHoldPercent < 0 || obj.weighHoldPercent > 50) {
    err('WEIGH_HOLD_PERCENT_INVALID', 'weighHoldPercent');
  }
  for (const e of courierPayoutProblems(obj.courierPayout)) {
    const i = e.indexOf(' ');
    err(e.slice(0, i), e.slice(i + 1));
  }
  return done();
}

// Импортда «ўзгармади» таққослаш майдонлари (upsertOfferTx).
const IMPORT_COMPARE_KEYS = Object.freeze(['name', 'price', 'unit', 'qtyStep', 'weighed', 'stock', 'smStatus', 'smGroupId',
  'smCategoryId', 'smVariety', 'smQuality', 'packLabel', 'packQty', 'packUnit', 'smImageSrc', 'imageUrl']);

const OFFER_KEYS = ['smGroupId', 'smVariety', 'smQuality', 'packLabel', 'unit', 'qtyStep', 'weighed', 'stock',
  'smStatus', 'packQty', 'packUnit', 'price', 'name', 'description', 'imageUrl', 'imageUrls'];

/** Таклиф (adminUpsertSupermarketOffer `offer`) — тоза текширув. */
function validateOffer(o) {
  const { errors, err } = makeErr();
  const done = () => ({ ok: errors.length === 0, errors });
  if (!isPlainObject(o)) { err('OFFER_NOT_OBJECT'); return done(); }
  unknownKeys(o, OFFER_KEYS, 'offer', err);
  if (typeof o.smGroupId !== 'string' || !ID_RE.test(o.smGroupId)) err('GROUP_ID_INVALID', 'offer.smGroupId');
  if (!isPlainObject(o.smVariety)) err('VARIETY_INVALID', 'offer.smVariety');
  else {
    unknownKeys(o.smVariety, ['id', 'names'], 'offer.smVariety', err);
    if (typeof o.smVariety.id !== 'string' || !ID_RE.test(o.smVariety.id)) err('VARIETY_ID_INVALID', 'offer.smVariety.id');
    checkLocalized(o.smVariety.names, 'offer.smVariety.names', 'NAME', LIMITS.name, err);
  }
  if (o.smQuality != null) checkLocalized(o.smQuality, 'offer.smQuality', 'QUALITY', 30, err);
  if (o.packLabel != null && (typeof o.packLabel !== 'string' || o.packLabel.length > LIMITS.packLabel)) err('PACK_LABEL_INVALID', 'offer.packLabel');
  if (o.unit != null && !UNITS.includes(o.unit)) err('UNIT_INVALID', 'offer.unit');
  if (o.qtyStep != null && !stepOk(o.qtyStep)) err('STEP_INVALID', 'offer.qtyStep');
  if (o.weighed != null && typeof o.weighed !== 'boolean') err('WEIGHED_INVALID', 'offer.weighed');
  // packQty + packUnit — бирга (бирлик нархи учун, масалан 1.5 л шиша → литр нархи).
  if (o.packQty != null || o.packUnit != null) {
    const pm = toMilli(o.packQty);
    if (pm == null || pm <= 0 || pm > 100000 * 1000) err('PACK_QTY_INVALID', 'offer.packQty');
    if (!PACK_UNITS.includes(o.packUnit)) err('PACK_UNIT_INVALID', 'offer.packUnit');
  }
  const sm = toMilli(o.stock);
  if (sm == null || sm < 0 || sm > LIMITS.stockMax * 1000) err('STOCK_INVALID', 'offer.stock');
  if (!SM_STATUSES.includes(o.smStatus)) err('SM_STATUS_INVALID', 'offer.smStatus');
  if (!Number.isInteger(o.price) || o.price <= 0 || o.price > LIMITS.priceMax) err('PRICE_INVALID', 'offer.price');
  if (o.name != null && (typeof o.name !== 'string' || !o.name.trim() || o.name.length > LIMITS.offerName)) err('NAME_INVALID', 'offer.name');
  if (o.description != null && (typeof o.description !== 'string' || o.description.length > LIMITS.description)) err('DESCRIPTION_INVALID', 'offer.description');
  const urlOk = (u) => typeof u === 'string' && /^https:\/\//.test(u) && u.length <= LIMITS.imageUrl;
  if (o.imageUrl != null && o.imageUrl !== '' && !urlOk(o.imageUrl)) err('IMAGE_URL_INVALID', 'offer.imageUrl');
  if (o.imageUrls != null && (!Array.isArray(o.imageUrls) || o.imageUrls.length > LIMITS.images || !o.imageUrls.every(urlOk))) {
    err('IMAGE_URLS_INVALID', 'offer.imageUrls');
  }
  return done();
}

function validateCost(c) {
  const { errors, err } = makeErr();
  if (!isPlainObject(c)) { err('COST_NOT_OBJECT'); return { ok: false, errors }; }
  unknownKeys(c, ['purchasePrice', 'supplier'], 'cost', err);
  if (!Number.isInteger(c.purchasePrice) || c.purchasePrice < 0 || c.purchasePrice > LIMITS.priceMax) err('PURCHASE_PRICE_INVALID', 'cost.purchasePrice');
  if (typeof c.supplier !== 'string' || c.supplier.length > LIMITS.supplier) err('SUPPLIER_INVALID', 'cost.supplier');
  return { ok: errors.length === 0, errors };
}

/** Таклиф қидирув токенлари: ном → нав → гуруҳ (+синоним) → сифат/қадоқ → бўлим. */
function offerSearchTokens({ name, variety, quality, packLabel, group, category }) {
  const loc = (o) => (isPlainObject(o) ? LANGS.map((l) => o[l] || '').join(' ') : '');
  return buildSearchTokens([
    String(name || ''),
    loc(variety && variety.names),
    loc(group && group.names),
    (group && Array.isArray(group.synonyms) ? group.synonyms : []).join(' '),
    `${loc(quality)} ${packLabel || ''}`,
    loc(category && category.names),
  ]);
}

// ══════════════════════ БУЮРТМА НАРХИ (тоза) ══════════════════════

/**
 * Каталогдан қайта нархлаш. products: { [productId]: data|null }.
 * @returns {{ok:true, lines, goods, extras, fee, hold, stockOps} | {ok:false, code, details}}
 */
function priceSupermarketOrder({ items, products, feeBp, weighHoldPercent }) {
  const lines = [];
  const stockOps = [];
  for (let i = 0; i < items.length; i += 1) {
    const { productId, qMilli } = items[i];
    const d = products[productId];
    if (!d) return { ok: false, code: 'PRODUCT_NOT_FOUND', details: { productId } };
    if (!d.smGroupId || d.smStatus === 'hidden' || (d.smStatus !== 'active' && d.smStatus !== 'out_of_stock')) {
      return { ok: false, code: 'PRODUCT_UNAVAILABLE', details: { productId } };
    }
    if (d.smStatus === 'out_of_stock') return { ok: false, code: 'OUT_OF_STOCK', details: { productId, available: 0 } };
    const price = d.price;
    if (!Number.isInteger(price) || price <= 0) return { ok: false, code: 'PRICE_MISSING', details: { productId } };
    const stepMilli = stepOk(d.qtyStep) ? toMilli(d.qtyStep) : 1000;
    if (qMilli % stepMilli !== 0) return { ok: false, code: 'QTY_STEP_INVALID', details: { productId, step: fromMilli(stepMilli) } };
    const stockMilli = toMilli(Number(d.stock));
    const available = stockMilli == null || stockMilli < 0 ? 0 : stockMilli;
    if (qMilli > available) return { ok: false, code: 'OUT_OF_STOCK', details: { productId, available: fromMilli(available) } };
    const unit = UNITS.includes(d.unit) ? d.unit : 'piece';
    const weighed = d.weighed === true;
    const total = lineTotalOf(price, qMilli);
    if (total <= 0) return { ok: false, code: 'QTY_STEP_INVALID', details: { productId } };
    const line = {
      productId,
      inventoryId: productId,
      name: String(d.name || productId).slice(0, LIMITS.offerName),
      price,
      qty: fromMilli(qMilli),
      unit: UNIT_LABELS[unit].uz_Cyrl,
      smUnit: unit,
      qtyStep: fromMilli(stepMilli),
      total,
      weighed,
      holdExtra: weighed ? holdExtraOf(total, weighHoldPercent) : 0,
      groupId: String(d.smGroupId),
    };
    if (d.smVariety && typeof d.smVariety.id === 'string') line.varietyId = d.smVariety.id;
    if (typeof d.packLabel === 'string' && d.packLabel) line.packLabel = d.packLabel;
    lines.push(line);
    stockOps.push({ productId, newStockMilli: available - qMilli });
  }
  const c = computeCharge(lines, feeBp);
  return { ok: true, lines, goods: c.goods, extras: c.extras, fee: c.fee, hold: c.target, stockOps };
}

/**
 * Тортиш натижасини қўллаш (тоза). lines — буюртмадаги қаторлар нусхаси.
 * @returns {{ok:true, lines, changed:boolean, stockDeltas:{[productId]:milli}} | {ok:false, code, details}}
 */
function applyWeights(lines, input, weighHoldPercent) {
  const out = lines.map((l) => ({ ...l }));
  const stockDeltas = {};
  let changed = false;
  const seen = new Set();
  for (const row of input) {
    const pid = row.productId;
    if (seen.has(pid)) return { ok: false, code: 'DUPLICATE_ITEM', details: { productId: pid } };
    seen.add(pid);
    const l = out.find((x) => x.productId === pid);
    if (!l) return { ok: false, code: 'LINE_NOT_FOUND', details: { productId: pid } };
    if (l.removed) return { ok: false, code: 'LINE_ALREADY_REMOVED', details: { productId: pid } };
    if (!l.weighed) return { ok: false, code: 'LINE_NOT_WEIGHED', details: { productId: pid } };
    if (linePending(l)) return { ok: false, code: 'LINE_SHORTAGE_PENDING', details: { productId: pid } };
    const aMilli = toMilli(row.actualQty);
    if (aMilli == null || aMilli <= 0) return { ok: false, code: 'ACTUAL_QTY_INVALID', details: { productId: pid } };
    const qMilli = toMilli(l.qty);
    const limitMilli = Math.floor(qMilli * (100 + weighHoldPercent) / 100);
    if (aMilli > limitMilli) return { ok: false, code: 'ACTUAL_QTY_OVER_LIMIT', details: { productId: pid, maxQty: fromMilli(limitMilli) } };
    if (l.actualQty != null) {
      if (toMilli(l.actualQty) === aMilli) continue; // қайта юбориш — идемпотент
      return { ok: false, code: 'LINE_ALREADY_SETTLED', details: { productId: pid, actualQty: l.actualQty } };
    }
    l.actualQty = fromMilli(aMilli);
    l.finalTotal = lineTotalOf(l.price, aMilli);
    stockDeltas[pid] = (stockDeltas[pid] || 0) + (qMilli - aMilli);
    changed = true;
  }
  return { ok: true, lines: out, changed, stockDeltas };
}

/** Жорий ечим ва мақсаддан янги ечим/қайтим. Ҳеч қачон ошмайди. */
function adjustment(charged, target) {
  const next = Math.min(charged, target);
  return { next, refund: charged - next, capDiscount: Math.max(0, target - charged) };
}

// ══════════════════════ ЕТИШМОВЧИЛИК (тоза, 2-босқич) ══════════════════════

const linePending = (l) => !!(l && !l.removed && l.shortage && l.shortage.state === 'pending');
const stepMilliOf = (l) => (stepOk(l && l.qtyStep) ? toMilli(l.qtyStep) : 1000);
const bad = (code, details) => ({ ok: false, code, details: details || {} });

/** Каталог таклифи алмаштиришга яроқлими (сотувда, нархи бор, stock > 0). */
function offerSellable(d) {
  if (!d || !d.smGroupId || d.smStatus !== 'active') return false;
  if (!Number.isInteger(d.price) || d.price <= 0) return false;
  const s = toMilli(Number(d.stock));
  return s != null && s > 0;
}

/** Мижозга кўрсатиладиган алмаштириш нусхаси (нарх — маълумот учун; жавобда каталогдан қайта олинади). */
function substituteView(offerId, d) {
  const unit = UNITS.includes(d.unit) ? d.unit : 'piece';
  const v = {
    offerId, name: String(d.name || offerId).slice(0, LIMITS.offerName), price: d.price, smUnit: unit,
    unit: UNIT_LABELS[unit].uz_Cyrl, qtyStep: stepOk(d.qtyStep) ? d.qtyStep : 1, weighed: d.weighed === true,
  };
  if (typeof d.packLabel === 'string' && d.packLabel) v.packLabel = d.packLabel;
  if (typeof d.imageUrl === 'string' && d.imageUrl) v.imageUrl = d.imageUrl;
  return v;
}

/**
 * Админ: қаторни «етишмовчилик» ҳолатига ўтказади (пулга тегмайди). subs: [{offerId, data|null}].
 * Кутилаётган ҳолатни қайта юбориш — идемпотент (changed:false).
 */
function applyShortageReport(lines, { productId, availableQty, subs, actor, nowMs }) {
  const idx = lines.findIndex((l) => l.productId === productId);
  if (idx < 0) return bad('LINE_NOT_FOUND', { productId });
  const l = lines[idx];
  if (l.removed) return bad('LINE_ALREADY_REMOVED', { productId });
  if (l.shortage && l.shortage.state !== 'pending') return bad('LINE_SHORTAGE_RESOLVED', { productId });
  if (l.weighed && l.actualQty != null) return bad('LINE_ALREADY_SETTLED', { productId });
  const qMilli = toMilli(l.qty);
  const aMilli = toMilli(availableQty);
  if (aMilli == null || aMilli < 0 || aMilli >= qMilli || aMilli % stepMilliOf(l) !== 0) {
    return bad('AVAILABLE_QTY_INVALID', { productId, qty: l.qty, step: fromMilli(stepMilliOf(l)) });
  }
  const inOrder = new Set(lines.filter((x) => !x.removed).map((x) => x.productId));
  const options = [];
  for (const { offerId, data } of subs) {
    if (offerId === productId || inOrder.has(offerId) || !offerSellable(data)) return bad('SUBSTITUTE_INVALID', { offerId });
    options.push(substituteView(offerId, data));
  }
  const core = { state: 'pending', availableQty: fromMilli(aMilli), substitutes: options };
  if (linePending(l) && stableStringify({ state: l.shortage.state, availableQty: l.shortage.availableQty, substitutes: l.shortage.substitutes }) === stableStringify(core)) {
    return { ok: true, changed: false, lines };
  }
  const next = lines.map((x, i) => (i === idx
    ? { ...x, shortage: { ...core, reportedBy: actor, reportedAtMs: nowMs, answerByMs: nowMs + SHORTAGE_ANSWER_MS } }
    : x));
  return { ok: true, changed: true, lines: next, stockDeltas: {}, pricing: 'none', info: { name: String(l.name || '') } };
}

/**
 * Мижоз жавоби (тоза). offerData — алмаштириш таклифи (транзакцияда ўқилган, ЖОРИЙ нарх/stock).
 * stockDeltas: милли-бирлик, мусбат — омборга қайтади, манфий — ечилади.
 * pricing: 'delta' — алмаштириш (фарқ ечилади ёки қайтади), 'cap' — камайтириш/олиш (adminRemove математикаси).
 */
function applyShortageChoice(lines, { productId, choice, offerId, qty, offerData, feeBp, weighHoldPercent, actor, nowMs }) {
  const idx = lines.findIndex((l) => l.productId === productId);
  if (idx < 0) {
    // Аллақачон алмаштирилган (қатор энди бошқа productId) — «жавоб берилган».
    if (lines.some((l) => l.substitutedFrom && l.substitutedFrom.productId === productId)) return bad('LINE_SHORTAGE_RESOLVED', { productId });
    return bad('LINE_NOT_FOUND', { productId });
  }
  const l = lines[idx];
  if (!l.shortage) return bad('LINE_NO_SHORTAGE', { productId });
  if (!linePending(l)) return bad('LINE_SHORTAGE_RESOLVED', { productId });
  const oldQ = toMilli(l.qty);
  const resolved = { ...l.shortage, state: 'resolved', choice, resolvedBy: actor, resolvedAtMs: nowMs };
  const replace = (nl) => lines.map((x, i) => (i === idx ? nl : x));

  if (choice === 'substitute') {
    const opt = (l.shortage.substitutes || []).find((s) => s.offerId === offerId);
    if (!opt) return bad('SUBSTITUTE_INVALID', { offerId });
    if (lines.some((x, i) => i !== idx && !x.removed && x.productId === offerId)) return bad('SUBSTITUTE_INVALID', { offerId });
    if (!offerSellable(offerData)) return bad('SUBSTITUTE_INVALID', { offerId });
    const qMilli = qty == null ? oldQ : toMilli(qty);
    if (qMilli == null || qMilli <= 0 || qMilli > LIMITS.qtyMilliMax) return bad('QTY_STEP_INVALID', { productId: offerId });
    const priced = priceSupermarketOrder({ items: [{ productId: offerId, qMilli }], products: { [offerId]: offerData }, feeBp, weighHoldPercent });
    if (!priced.ok) return bad(priced.code, priced.details);
    const nl = {
      ...priced.lines[0],
      substitutedFrom: { productId: l.productId, name: l.name, price: l.price, qty: l.qty, total: l.total },
      shortage: resolved,
    };
    return { ok: true, changed: true, lines: replace(nl), stockDeltas: { [l.productId]: oldQ, [offerId]: -qMilli }, pricing: 'delta' };
  }
  if (choice === 'reduce') {
    const aMilli = toMilli(l.shortage.availableQty);
    const qMilli = qty == null ? aMilli : toMilli(qty);
    if (qMilli == null || qMilli <= 0 || qMilli > aMilli || qMilli % stepMilliOf(l) !== 0) {
      return bad('QTY_STEP_INVALID', { productId, maxQty: fromMilli(aMilli || 0), step: fromMilli(stepMilliOf(l)) });
    }
    const total = lineTotalOf(l.price, qMilli);
    const nl = {
      ...l, qty: fromMilli(qMilli), total, holdExtra: l.weighed ? holdExtraOf(total, weighHoldPercent) : 0,
      reducedFrom: { qty: l.qty, total: l.total }, shortage: resolved,
    };
    return { ok: true, changed: true, lines: replace(nl), stockDeltas: { [productId]: oldQ - qMilli }, pricing: 'cap' };
  }
  if (choice === 'remove') {
    if (lines.filter((x) => !x.removed).length <= 1) return bad('LAST_LINE');
    const nl = { ...l, removed: { reason: 'shortage', by: actor, atMs: nowMs }, shortage: resolved };
    return { ok: true, changed: true, lines: replace(nl), stockDeltas: { [productId]: oldQ }, pricing: 'cap' };
  }
  return bad('INVALID_REQUEST');
}

/**
 * Янги ечим. 'cap' — мавжуд adjustment (ҳеч қачон ошмайди); 'delta' — charged + (янги мақсад − эски мақсад),
 * фақат мижоз танлаган алмаштиришда (ошса — ҳамёндан фарқ ечилади). Ҳеч қачон манфий эмас.
 */
function chargeAfter(charged, oldLines, newLines, bp, pricing) {
  const target = computeCharge(newLines, bp).target;
  if (pricing === 'none') return { next: charged, refund: 0, debit: 0, capDiscount: 0, target };
  if (pricing !== 'delta') {
    const a = adjustment(charged, target);
    return { next: a.next, refund: a.refund, debit: 0, capDiscount: a.capDiscount, target };
  }
  const next = Math.max(0, charged + (target - computeCharge(oldLines, bp).target));
  return { next, refund: Math.max(0, charged - next), debit: Math.max(0, next - charged), capDiscount: 0, target };
}

// ══════════════════════ ҲАФТАЛИК САВАТ (тоза, 2-босқич) ══════════════════════

/** remind ({enabled, weekday 1=Душанба..7=Якшанба, minute 0..1439}) шакли тўғрими. */
function remindOk(r) {
  return isPlainObject(r) && typeof r.enabled === 'boolean' && Number.isInteger(r.weekday) && r.weekday >= 1 && r.weekday <= 7
    && Number.isInteger(r.minute) && r.minute >= 0 && r.minute <= 1439
    && Object.keys(r).every((k) => ['enabled', 'weekday', 'minute'].includes(k));
}

/** Рўйхат ҳужжати муаммоси ('' — тўғри). rules list ичини айланолмайди — қатор шакли шу ерда. */
function listShapeProblem(d) {
  const x = d || {};
  if (typeof x.name !== 'string' || !x.name.trim() || x.name.length > 40) return 'NAME_INVALID';
  if (!Array.isArray(x.items) || x.items.length > 100) return 'ITEMS_INVALID';
  for (const it of x.items) {
    if (!isPlainObject(it) || !Object.keys(it).every((k) => ['groupId', 'varietyId', 'offerId', 'qty'].includes(k))) return 'ITEM_INVALID';
    if (typeof it.groupId !== 'string' || !ID_RE.test(it.groupId)) return 'ITEM_INVALID';
    if (it.varietyId != null && (typeof it.varietyId !== 'string' || !ID_RE.test(it.varietyId))) return 'ITEM_INVALID';
    if (it.offerId != null && (typeof it.offerId !== 'string' || !PRODUCT_ID_RE.test(it.offerId))) return 'ITEM_INVALID';
    const q = toMilli(it.qty);
    if (q == null || q <= 0 || q > LIMITS.qtyMilliMax) return 'ITEM_INVALID';
  }
  if (!remindOk(x.remind)) return 'REMIND_INVALID';
  // Байрам саватчаси (эга 2026-11-26): ихтиёрий holiday_occasions id.
  if (x.occasionId != null && (typeof x.occasionId !== 'string' || !ID_RE.test(x.occasionId))) return 'OCCASION_INVALID';
  return '';
}

/** Тошкент вақти бўйича кейинги эслатма (мс), қатъий nowMs дан кейин; ўчиқ/бузуқ — null. */
function nextRemindAtMs(remind, nowMs) {
  if (!remindOk(remind) || remind.enabled !== true) return null;
  const t = new Date(nowMs + TZ_OFFSET_MS);
  const dow = ((t.getUTCDay() + 6) % 7) + 1;
  const dayStart = Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate()) - TZ_OFFSET_MS;
  let at = dayStart + ((remind.weekday - dow + 7) % 7) * DAY_MS + remind.minute * 60000;
  if (at <= nowMs) at += WEEK_MS;
  return at;
}

/** Юборилгандан кейин: 7 кунлик қадам билан келажакдаги биринчи момент (тизим тўхтаб турса ҳам спам йўқ). */
function advanceRemindMs(dueMs, nowMs) {
  if (dueMs > nowMs) return dueMs;
  return dueMs + (Math.floor((nowMs - dueMs) / WEEK_MS) + 1) * WEEK_MS;
}

// ══════════════════════ CLOUD FUNCTIONS ══════════════════════

function attachSupermarket(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, settlementLedger, notifyUserInApp,
  } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: MODULE, ...fields }));
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };
  // Тортиш/қаторни олиш: admin + superadmin + dispatcher (эга 2026-11-20); аудитда роль сақланади.
  const requireOperator = async (context) => {
    let uid;
    try {
      uid = await requireCallerRoles(context, OPERATOR_ROLES, 'Operator role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
    const snap = await db.collection('users').doc(uid).get();
    return { uid, role: String((snap.data() || {}).role || '') };
  };
  const rethrow = (e, action, fields) => {
    const code = (e && e.details && e.details.code) || 'INTERNAL';
    log({ action, result: 'error', errorCode: code, ...fields });
    if (e instanceof HttpsError) throw e;
    console.error(JSON.stringify({ module: MODULE, action, error: String((e && e.message) || e) }));
    throw fail('internal', 'INTERNAL');
  };
  async function userDocRef(uid12) {
    const uid9 = uid12.length === 12 && uid12.startsWith('998') ? uid12.slice(3) : uid12;
    let ref = db.collection('users').doc(uid12);
    let snap = await ref.get();
    if (!snap.exists && uid9 !== uid12) {
      ref = db.collection('users').doc(uid9);
      snap = await ref.get();
    }
    return snap.exists ? { ref, data: snap.data() || {} } : null;
  }

  // ── 1. Таксономия ──
  exportsObj.adminSetSupermarketTaxonomy = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const expectedVersion = data ? data.expectedVersion : undefined;
    if (!Number.isInteger(expectedVersion) || expectedVersion < 0) throw fail('invalid-argument', 'EXPECTED_VERSION_INVALID');
    const taxonomy = trimDeep(data ? data.taxonomy : undefined);
    const v = validateSupermarketTaxonomy(taxonomy);
    if (!v.ok) {
      log({ action: 'adminSetSupermarketTaxonomy', result: 'error', errorCode: 'TAXONOMY_INVALID', userId: actor, errorCount: v.errors.length });
      throw fail('invalid-argument', 'TAXONOMY_INVALID', { errors: v.errors });
    }
    const ref = db.collection(TAXONOMY_DOC[0]).doc(TAXONOMY_DOC[1]);
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const cur = snap.exists ? (snap.data() || {}) : {};
        const currentVersion = Number.isInteger(cur.version) ? cur.version : 0;
        const same = snap.exists && stableStringify(cur.categories) === stableStringify(taxonomy.categories);
        if (same && (expectedVersion === currentVersion || expectedVersion + 1 === currentVersion)) {
          return { version: currentVersion, changed: false };
        }
        if (expectedVersion !== currentVersion) throw fail('failed-precondition', 'TAXONOMY_VERSION_CONFLICT', { currentVersion });
        const version = currentVersion + 1;
        const docs = buildTaxonomyVersionDocs({ categories: taxonomy.categories, version, previousVersion: snap.exists ? currentVersion : null, actor, ts: ts() });
        t.set(ref, docs.doc);
        t.create(db.collection(HISTORY_COLLECTION).doc(`${HISTORY_PREFIX}${version}`), docs.history);
        t.set(db.collection(ADMIN_AUDIT).doc(), docs.audit);
        return { version, changed: true };
      });
    } catch (e) {
      rethrow(e, 'adminSetSupermarketTaxonomy', { userId: actor, expectedVersion });
    }
    log({ action: 'adminSetSupermarketTaxonomy', result: 'ok', userId: actor, ...out, categories: taxonomy.categories.length, duration: Date.now() - started });
    return { ok: true, ...out };
  });

  // ── 3. Созламалар ──
  exportsObj.adminSetSupermarketSettings = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const expectedVersion = data ? data.expectedVersion : undefined;
    if (!Number.isInteger(expectedVersion) || expectedVersion < 0) throw fail('invalid-argument', 'EXPECTED_VERSION_INVALID');
    const settings = trimDeep(data ? data.settings : undefined);
    const v = validateSupermarketSettings(settings);
    if (!v.ok) throw fail('invalid-argument', 'SETTINGS_INVALID', { errors: v.errors });
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, LIMITS.reason) : '';
    const ref = db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const cur = snap.exists ? (snap.data() || {}) : {};
        const currentVersion = Number.isInteger(cur.version) ? cur.version : 0;
        const pick = (o) => Object.fromEntries(SETTINGS_KEYS.map((k) => [k, o[k] === undefined ? null : o[k]]));
        const same = snap.exists && stableStringify(pick(cur)) === stableStringify(pick(settings));
        if (same && (expectedVersion === currentVersion || expectedVersion + 1 === currentVersion)) {
          return { version: currentVersion, changed: false };
        }
        if (expectedVersion !== currentVersion) throw fail('failed-precondition', 'SETTINGS_VERSION_CONFLICT', { currentVersion });
        const version = currentVersion + 1;
        t.set(ref, { ...settings, version, updatedAt: ts(), updatedBy: actor });
        t.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'supermarket_settings_set', actor, target: `settings/supermarket v${version}`, version,
          before: snap.exists ? pick(cur) : null, after: pick(settings), reason, at: ts(),
        });
        return { version, changed: true };
      });
    } catch (e) {
      rethrow(e, 'adminSetSupermarketSettings', { userId: actor });
    }
    log({ action: 'adminSetSupermarketSettings', result: 'ok', userId: actor, ...out, stage: settings.stage });
    return { ok: true, ...out };
  });

  async function loadGateContext(uid) {
    const [settingsSnap, appSnap, user] = await Promise.all([
      db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]).get(),
      db.collection(APP_SETTINGS_DOC[0]).doc(APP_SETTINGS_DOC[1]).get(),
      userDocRef(uid),
    ]);
    return {
      settings: settingsSnap.exists ? (settingsSnap.data() || {}) : null,
      feeConfig: feeConfigFromApp(appSnap.exists ? appSnap.data() : {}),
      user,
    };
  }
  function callerUidOrThrow(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 9) throw fail('unauthenticated', 'UNAUTHENTICATED');
    return uid;
  }

  exportsObj.getSupermarketAccess = functions.https.onCall(async (data, context) => {
    const uid = callerUidOrThrow(context);
    const { settings, feeConfig, user } = await loadGateContext(uid);
    const reqDistrict = typeof (data && data.districtId) === 'string' ? data.districtId.trim() : '';
    const districtId = reqDistrict || String((user && user.data.districtId) || '').trim();
    const role = String((user && user.data.role) || 'user');
    const g = gateDecision(settings, { uid, role, districtId, requireDistrict: true });
    const slots = g.allowed ? availableSlots(settings, now()) : { today: [], tomorrow: [] };
    return {
      allowed: g.allowed,
      reason: g.reason,
      ...(g.reason ? { messages: messagesOf(g.reason) } : {}),
      districtId,
      slots,
      feePercent: feeConfig ? feeConfig.percent : null,
      ...(g.allowed && !feeConfig ? { allowed: false, reason: 'TARIFF_NOT_CONFIGURED', messages: messagesOf('TARIFF_NOT_CONFIGURED') } : {}),
      weighHoldPercent: settings && Number.isInteger(settings.weighHoldPercent) ? settings.weighHoldPercent : 10,
      tariffVersion: TARIFF_VERSION,
      // Байрам/совға (эга 2026-11-26): withDates=true бўлса — бугундан +14 кунгача санага оралиқлар.
      ...(data && data.withDates === true && g.allowed ? {
        maxAheadDays: hol().MAX_AHEAD_DAYS,
        dateSlots: Array.from({ length: hol().MAX_AHEAD_DAYS + 1 }, (_, i) => {
          const date = hol().addDays(tashkentParts(now()).dateKey, i);
          return { date, slots: hol().slotsForDate(settings, now(), date) };
        }).filter((x) => x.slots.length),
      } : {}),
    };
  });

  // ── 2. Таклиф (admin) ──
  exportsObj.adminUpsertSupermarketOffer = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const productId = typeof (data && data.productId) === 'string' ? data.productId.trim() : '';
    if (!PRODUCT_ID_RE.test(productId)) throw fail('invalid-argument', 'OFFER_INVALID', { errors: ['PRODUCT_ID_INVALID productId'] });
    const offer = trimDeep(data && data.offer);
    const v = validateOffer(offer);
    if (!v.ok) throw fail('invalid-argument', 'OFFER_INVALID', { errors: v.errors });
    const cost = data && data.cost != null ? trimDeep(data.cost) : null;
    if (cost) {
      const cv = validateCost(cost);
      if (!cv.ok) throw fail('invalid-argument', 'OFFER_INVALID', { errors: cv.errors });
    }
    let out;
    try {
      out = await db.runTransaction((t) => upsertOfferTx(t, { productId, offer, cost, actor }));
    } catch (e) {
      rethrow(e, 'adminUpsertSupermarketOffer', { userId: actor, productId });
    }
    log({ action: 'adminUpsertSupermarketOffer', result: 'ok', userId: actor, productId, ...out });
    return { ok: true, productId, ...out };
  });

  /**
   * Таклифни ёзиш — ЯГОНА йўл (callable ва Excel импорт): таксономия текшируви, searchTokens, нарх/харид аудити.
   * imp: {batchId, imageSrc} — импортдан; эски (smGroupId'сиз) ҳужжатга импорт ёзмайди (SKU_NOT_SUPERMARKET).
   */
  async function upsertOfferTx(t, { productId, offer, cost, actor, imp }) {
    const ref = db.collection(PRODUCTS).doc(productId);
    const costRef = ref.collection('private').doc('cost');
    const taxRef = db.collection(TAXONOMY_DOC[0]).doc(TAXONOMY_DOC[1]);
    const [taxSnap, snap, costSnap] = await Promise.all([t.get(taxRef), t.get(ref), t.get(costRef)]);
    if (!taxSnap.exists) throw fail('failed-precondition', 'TAXONOMY_MISSING');
    const found = findGroup(taxSnap.data() || {}, offer.smGroupId);
    if (!found) throw fail('invalid-argument', 'GROUP_UNKNOWN', { groupId: offer.smGroupId });
    const { group, category } = found;
    const cur = snap.exists ? (snap.data() || {}) : null;
    if (imp && cur && !cur.smGroupId) throw fail('failed-precondition', 'SKU_NOT_SUPERMARKET', { productId });
    const unit = offer.unit || group.unit;
    const qtyStep = offer.qtyStep != null ? offer.qtyStep : group.step;
    const weighed = offer.weighed != null ? offer.weighed : group.weighed;
    const name = offer.name || `${group.names.uz_Cyrl} ${offer.smVariety.names.uz_Cyrl}`.slice(0, LIMITS.offerName);
    const patch = {
      name,
      price: offer.price,
      unit,
      qtyStep,
      weighed,
      stock: fromMilli(toMilli(offer.stock)),
      smStatus: offer.smStatus,
      smAutoOutOfStock: false,
      smGroupId: group.id,
      smCategoryId: category.id,
      smVariety: offer.smVariety,
      smQuality: offer.smQuality || null,
      packLabel: offer.packLabel || '',
      packQty: offer.packQty != null ? fromMilli(toMilli(offer.packQty)) : null,
      packUnit: offer.packQty != null ? offer.packUnit : null,
      searchTokens: offerSearchTokens({
        name, variety: offer.smVariety, quality: offer.smQuality, packLabel: offer.packLabel, group, category,
      }),
      updatedAt: ts(),
    };
    if (offer.description != null) patch.description = offer.description;
    if (offer.imageUrls != null) {
      patch.imageUrls = offer.imageUrls;
      patch.imageUrl = offer.imageUrls[0] || '';
    } else if (offer.imageUrl != null) {
      patch.imageUrl = offer.imageUrl;
      patch.imageUrls = offer.imageUrl ? [offer.imageUrl] : [];
    }
    if (imp) {
      patch.smImageSrc = imp.imageSrc || '';
      patch.smImportBatchId = imp.batchId;
    }
    const prevCost = costSnap.exists ? (costSnap.data() || {}) : null;
    const costChanged = !!cost && (!prevCost || prevCost.purchasePrice !== cost.purchasePrice || prevCost.supplier !== cost.supplier);
    // Импорт: ҳеч нарса ўзгармаган қатор — ёзилмайди (қайта юклаш идемпотент, аудит шовқини йўқ).
    if (imp && cur && !costChanged && IMPORT_COMPARE_KEYS.every((k) => stableStringify(cur[k] === undefined ? null : cur[k]) === stableStringify(patch[k] === undefined ? null : patch[k]))) {
      return { created: false, priceChanged: false, costChanged: false, unchanged: true };
    }
    const priceChanged = !cur || cur.price !== offer.price;
    if (priceChanged) patch.priceUpdatedAt = ts();
    if (!cur) {
      // Эски Улгуржи/«Тавсия»/бозор лентаси `active == true` ни кутади — супермаркет таклифи у ерга тушмасин.
      Object.assign(patch, { active: false, showInMarket: false, featuredOnHome: false, sortOrder: 0, createdAt: ts() });
    }
    t.set(ref, patch, { merge: true });
    const src = imp ? { source: 'import', batchId: imp.batchId } : {};
    if (priceChanged) {
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'supermarket_offer_price', actor, target: `${PRODUCTS}/${productId}`,
        oldPrice: cur && Number.isInteger(cur.price) ? cur.price : null, newPrice: offer.price, ...src, at: ts(),
      });
    }
    if (costChanged) {
      t.set(costRef, { purchasePrice: cost.purchasePrice, supplier: cost.supplier, updatedAt: ts(), updatedBy: actor });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'supermarket_offer_cost', actor, target: `${PRODUCTS}/${productId}`,
        oldPurchasePrice: prevCost && Number.isInteger(prevCost.purchasePrice) ? prevCost.purchasePrice : null,
        newPurchasePrice: cost.purchasePrice,
        supplierChanged: !prevCost || prevCost.supplier !== cost.supplier, ...src, at: ts(),
      });
    }
    return { created: !cur, priceChanged, costChanged, unchanged: false };
  }

  // ── 4. Буюртма ──
  function parseAddress(a) {
    if (!isPlainObject(a)) return null;
    const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
    const districtId = str(a.districtId, 40);
    const phone = String(a.phone || '').replace(/\D/g, '');
    if (!DISTRICT_RE.test(districtId) || phone.length < 9 || phone.length > 12) return null;
    const out = {
      districtId,
      mahalla: str(a.mahalla, LIMITS.addressPart),
      street: str(a.street, LIMITS.addressPart),
      house: str(a.house, 40),
      landmark: str(a.landmark, LIMITS.landmark),
      phone: canonicalUid(phone),
    };
    const lat = Number(a.lat);
    const lng = Number(a.lng);
    if (a.lat != null && a.lng != null && Number.isFinite(lat) && Number.isFinite(lng)
        && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0)) {
      out.lat = lat;
      out.lng = lng;
    }
    return out;
  }
  function parseItems(raw) {
    if (!Array.isArray(raw) || raw.length < 1 || raw.length > LIMITS.items) return { code: 'INVALID_REQUEST' };
    const items = [];
    const seen = new Set();
    for (const it of raw) {
      const productId = isPlainObject(it) && typeof it.productId === 'string' ? it.productId.trim() : '';
      if (!productId || productId.length > 128 || productId.includes('/')) return { code: 'INVALID_REQUEST' };
      if (seen.has(productId)) return { code: 'DUPLICATE_ITEM', productId };
      seen.add(productId);
      const qMilli = toMilli(it.qty);
      if (qMilli == null || qMilli <= 0 || qMilli > LIMITS.qtyMilliMax) return { code: 'QTY_STEP_INVALID', productId };
      items.push({ productId, qMilli });
    }
    return { items };
  }

  exportsObj.placeSupermarketOrder = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = callerUidOrThrow(context);
    const d = data || {};
    const clientRequestId = typeof d.clientRequestId === 'string' ? d.clientRequestId.trim() : '';
    if (!CLIENT_REQ_RE.test(clientRequestId)) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'clientRequestId' });
    const idemRef = db.collection(IDEM).doc(`sm_order_${uid}_${clientRequestId}`);
    const prior = await idemRef.get();
    if (prior.exists) return { ...(prior.data().result || {}), duplicate: true };

    const parsed = parseItems(d.items);
    if (parsed.code) throw fail('invalid-argument', parsed.code, parsed.productId ? { productId: parsed.productId } : {});
    const address = parseAddress(d.address);
    if (!address) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'address' });
    // Сана: эски клиент — day ('today'|'tomorrow'); янги — deliveryDate 'YYYY-MM-DD' (бугун..+14 кун, эга 2026-11-26).
    const deliveryDate = d.deliveryDate == null ? null : String(d.deliveryDate);
    const day = deliveryDate == null ? String(d.day || '') : '';
    const slotId = String(d.slotId || '');
    if ((deliveryDate == null ? !DAYS.includes(day) : !hol().validDateKey(deliveryDate)) || !SLOT_ID_RE.test(slotId)) {
      throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'slot' });
    }
    // 3-босқич: буюртма манбаи (аналитика учун; эски клиент юбормайди → 'catalog').
    const origin = d.origin == null ? 'catalog' : d.origin;
    if (!ORDER_ORIGINS.includes(origin)) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'origin' });
    const occasionId = d.occasionId == null ? null : d.occasionId;
    const basketId = d.basketId == null ? null : d.basketId;
    if ((occasionId != null && (typeof occasionId !== 'string' || !ID_RE.test(occasionId)))
        || (basketId != null && (typeof basketId !== 'string' || !ID_RE.test(basketId)))) {
      throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'occasion' });
    }
    // Совға (эга 2026-11-26): олувчи исми/телефони/хабар; нарх олувчига кўрсатилмайди (hidePrice).
    const giftParsed = hol().parseGift(d.gift, canonicalUid);
    if (giftParsed.code) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'gift' });
    const gift = giftParsed.gift;
    const useIncentive = d.useIncentive === true;

    const { settings, feeConfig, user } = await loadGateContext(uid);
    if (!user) throw fail('not-found', 'USER_NOT_FOUND');
    const role = String(user.data.role || 'user');
    const gate = gateDecision(settings, { uid, role, districtId: address.districtId, requireDistrict: true });
    if (!gate.allowed) {
      log({ action: 'placeSupermarketOrder', result: 'refused', errorCode: gate.reason, userTail: uid.slice(-4) });
      throw fail('failed-precondition', gate.reason);
    }
    const slotList = deliveryDate == null ? (availableSlots(settings, now())[day] || []) : hol().slotsForDate(settings, now(), deliveryDate);
    const slot = slotList.find((s) => s.id === slotId);
    if (!slot) throw fail('failed-precondition', 'SLOT_UNAVAILABLE');
    const aheadDays = hol().daysBetween(tashkentParts(now()).dateKey, slot.date);
    const slotDay = DAYS[aheadDays] || 'scheduled';
    const weighHoldPercent = Number.isInteger(settings.weighHoldPercent) ? settings.weighHoldPercent : 10;
    if (!feeConfig) {
      console.error(JSON.stringify({ module: MODULE, action: 'placeSupermarketOrder', result: 'denied', errorCode: 'TARIFF_NOT_CONFIGURED' }));
      throw fail('failed-precondition', 'TARIFF_NOT_CONFIGURED');
    }
    const feePercent = feeConfig.percent;
    const feeBp = feeConfig.bps;
    const orderRef = db.collection(ORDERS).doc();
    const userRef = user.ref;

    let dup = null;
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const idemSnap = await t.get(idemRef);
        if (idemSnap.exists) { dup = idemSnap.data().result || {}; return null; }
        const refs = parsed.items.map((it) => db.collection(PRODUCTS).doc(it.productId));
        const snaps = await Promise.all(refs.map((r) => t.get(r)));
        const products = {};
        snaps.forEach((s, i) => { products[parsed.items[i].productId] = s.exists ? (s.data() || {}) : null; });
        const userSnap = await t.get(userRef);
        const priced = priceSupermarketOrder({ items: parsed.items, products, feeBp, weighHoldPercent });
        if (!priced.ok) throw fail('failed-precondition', priced.code, priced.details);
        // Рағбат (қариндошлар бонуси, эга 2026-11-26): фақат `supermarket` туркумли грантлар, minOrderAmount ≤ goods,
        // фақат маҳсулот суммасидан (етказиш ҳақи — ҳамёндан). Мавжуд рағбат тизимининг computeIncentivePlan'и.
        // Грант фақат канон users/998… ҳужжатига берилади (claimIncentive билан бир хил) — эски 9 хонали ҳисобда йўқ.
        let incentiveGrants = [];
        let plan = { total: 0, perGrant: [] };
        if (useIncentive && userRef.id === uid) {
          const gSnap = await t.get(db.collection('incentive_grants').where('uid', '==', uid).where('status', '==', 'active'));
          incentiveGrants = hol().supermarketGrants(gSnap.docs, priced.goods);
          plan = incentivesLib.computeIncentivePlan(incentiveGrants, [{ category: hol().BONUS_BUCKET, total: priced.goods }], now());
        }
        const incentiveApplied = plan.total;
        const walletDebit = priced.hold - incentiveApplied;
        const balance = parseInt(String((userSnap.data() || {}).bonusBalance ?? 0), 10) || 0;
        if (balance < walletDebit) throw fail('failed-precondition', 'INSUFFICIENT_BALANCE', { required: walletDebit, balance });
        const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, userRef.id, { idempotencyKey: `sm_order_${orderRef.id}` });

        // ── ёзишлар ──
        priced.stockOps.forEach((op, i) => {
          t.update(refs[i], { stock: fromMilli(op.newStockMilli), ...(op.newStockMilli === 0 ? { smStatus: 'out_of_stock', smAutoOutOfStock: true } : {}) });
        });
        if (walletDebit > 0) {
          t.set(userRef, { bonusBalance: balance - walletDebit, balanceUpdatedAt: ts() }, { merge: true });
          settlementLedger.commitBonusInTx(t, bonusCtx, {
            delta: -walletDebit, kind: 'order_wallet', refType: 'order', refId: orderRef.id,
            meta: { module: 'platform', subtype: 'supermarket', orderTotal: walletDebit, walletDebit, cashDue: 0, ...(incentiveApplied > 0 ? { incentiveApplied, grossTotal: priced.hold } : {}) },
            postedBy: userRef.id, postedRole: 'client',
          });
          t.set(userRef.collection('wallet_ledger').doc(), {
            type: 'purchase_debit', amount: -walletDebit, module: 'platform', refType: 'order', refId: orderRef.id,
            meta: { orderTotal: walletDebit, cashDue: 0, subtype: 'supermarket', weighHold: priced.extras, ...(incentiveApplied > 0 ? { incentiveApplied } : {}) },
            createdAt: ts(), createdBy: 'client',
          });
        }
        if (incentiveApplied > 0) incentivesLib.applyIncentiveSpendInTx(t, db, admin, { uid, grants: incentiveGrants, plan, orderId: orderRef.id });
        const addrText = [address.mahalla, address.street, address.house, address.landmark].filter(Boolean).join(', ');
        const order = {
          type: 'platform',
          subtype: 'supermarket',
          userName: String(user.data.name || user.data.fullName || '').trim().slice(0, 80),
          userPhone: uid,
          phone: uid,
          // Совғада — олувчи телефони (курьер мавжуд қоида бўйича буюртмадан ўқийди; харидор ўзи киритган).
          contactPhone: gift ? gift.recipientPhone : address.phone,
          address: addrText.slice(0, 300),
          addressParts: address,
          districtId: address.districtId,
          ...(user.data.regionId ? { regionId: String(user.data.regionId) } : {}),
          items: priced.lines,
          inventoryDecrements: [],
          itemsTotal: priced.goods,
          deliveryFee: priced.fee,
          deliveryFeePercent: feePercent,
          deliveryFeeVersion: feeConfig.version,
          weighHoldPercent,
          weighHold: priced.extras,
          smHold: priced.hold,
          tariffVersion: TARIFF_VERSION,
          total: walletDebit,
          balanceApplied: walletDebit,
          walletUserDocId: userRef.id,
          cashDue: 0,
          cashPaid: 0,
          status: 'new',
          fulfillmentStatus: 'pending',
          paymentStatus: 'paid',
          paymentMethod: 'wallet',
          paidAmount: walletDebit,
          paidAt: ts(),
          fulfillmentMode: 'delivery',
          slot: { id: slot.id, day: slotDay, date: slot.date, startMin: slot.startMin, endMin: slot.endMin, names: slot.names },
          smClientRequestId: clientRequestId,
          smOrigin: origin,
          ...(occasionId ? { smOccasionId: occasionId } : {}),
          ...(basketId ? { smBasketId: basketId } : {}),
          smAdjustSeq: 0,
          smWeighPending: priced.lines.some((l) => l.weighed),
          createdAt: ts(),
          statusUpdatedAt: ts(),
        };
        if (address.lat != null) { order.lat = address.lat; order.lng = address.lng; }
        if (incentiveApplied > 0) {
          // Мавжуд рағбат майдонлари (placeOrderPostPaid билан бир хил): бекор қилишда грант тикланади.
          Object.assign(order, { grossTotal: priced.hold, incentiveApplied, incentiveUid: uid, incentiveGrants: plan.perGrant });
        }
        if (gift) {
          order.gift = gift;
          // PII тозалаш (smGiftPiiSweep): етказиш санасидан кейин кўрилади, етказилгандан 7 кун ўтгач — тозаланади.
          order.giftPurgeAfter = admin.firestore.Timestamp.fromMillis(hol().startOfKeyMs(slot.date) + (hol().GIFT_PURGE_DAYS + 1) * DAY_MS);
        }
        t.set(orderRef, order);
        // Курьер тўлови нусхаси (эга 2026-11-26) — ИЧКИ харажат (14-банд): мижоз ўқийдиган буюртма ҳужжатида эмас,
        // orders/{id}/private/courier_payout (фақат админ ўқийди, ёзиш фақат CF). Пул тизимда ЮРМАЙДИ.
        t.set(orderRef.collection('private').doc('courier_payout'), {
          ...courierPayoutSnapshot(settings.courierPayout, priced.fee, settings.version), orderId: orderRef.id, createdAt: ts(),
        });
        const result = {
          ok: true, orderId: orderRef.id, itemsTotal: priced.goods, weighHold: priced.extras,
          deliveryFee: priced.fee, deliveryFeePercent: feePercent, deliveryFeeVersion: feeConfig.version, total: walletDebit, walletDebit,
          paymentStatus: 'paid', tariffVersion: TARIFF_VERSION, slotDate: slot.date,
          ...(incentiveApplied > 0 ? { grossTotal: priced.hold, incentiveApplied } : {}),
          ...(gift ? { gift: true } : {}),
        };
        t.set(idemRef, { type: 'placeSupermarketOrder', result, createdAt: ts() });
        return result;
      });
    } catch (e) {
      rethrow(e, 'placeSupermarketOrder', { userTail: uid.slice(-4), items: parsed.items.length, duration: Date.now() - started });
    }
    if (dup) return { ...dup, duplicate: true };
    let giftNotified = false;
    if (gift) giftNotified = await notifyGiftRecipient(gift, uid, slot.date);
    log({
      action: 'placeSupermarketOrder', result: 'ok', orderId: out.orderId, userTail: uid.slice(-4),
      items: parsed.items.length, total: out.total, incentive: out.incentiveApplied || 0, gift: !!gift, giftNotified, duration: Date.now() - started,
    });
    return out;
  });

  /** Совға олувчи AVA фойдаланувчиси бўлса — нархсиз ички хабар (best-effort; харидорнинг ўзи бўлса — йўқ). */
  async function notifyGiftRecipient(gift, buyerUid, date) {
    if (!gift || gift.recipientPhone === buyerUid) return false;
    try {
      const u = await userDocRef(gift.recipientPhone);
      if (!u) return false;
      const m = hol().GIFT_TEXT[normalizeLang(u.data.appLang)] || hol().GIFT_TEXT.uz_Cyrl;
      await notifyUserInApp({
        userId: gift.recipientPhone, title: m.title, body: m.body.replace('{date}', date), category: 'order', screen: 'home',
        source: 'sm_gift_received', dataType: 'sm_gift_received',
      });
      return true;
    } catch (e) {
      log({ action: 'notifyGiftRecipient', result: 'notify_error', errorCode: 'NOTIFY_FAILED' });
      return false;
    }
  }

  // ── 5. Тортиш / қаторни олиш (admin) ──
  const ADJUSTABLE_STATUSES = new Set(['new', 'accepted', 'ready']);
  const COURIER_HOLD_FS = new Set(['courier_picked', 'arrived', 'completed', 'cancelled']);

  const ADJUST_META = Object.freeze({
    weigh: { audit: 'supermarket_weigh_settle', by: 'adminSettleSupermarketWeights' },
    remove: { audit: 'supermarket_line_remove', by: 'adminRemoveSupermarketLine' },
    shortage_report: { audit: 'supermarket_shortage_report', by: 'adminReportSupermarketShortage' },
    shortage_substitute: { audit: 'supermarket_shortage_substitute', by: 'respondSupermarketShortage' },
    shortage_reduce: { audit: 'supermarket_shortage_reduce', by: 'respondSupermarketShortage' },
    shortage_remove: { audit: 'supermarket_shortage_remove', by: 'respondSupermarketShortage' },
  });

  /**
   * Умумий транзакция: қаторлар ўзгаради → қайта ҳисоб → қайтим/қўшимча ечим + stock.
   * preRead(t, od) — мутациядан олдин транзакцияда ўқиш (масалан алмаштириш таклифи);
   * authorize(od) — мижоз амали учун эгалик текшируви; idem — {ref, type}: натижа шу транзакцияда сақланади.
   */
  async function adjustOrder({ orderId, actor, actorRole, action, mutate, auditExtra, preRead, authorize, idem }) {
    const orderRef = db.collection(ORDERS).doc(orderId);
    return db.runTransaction(async (t) => {
      if (idem) {
        const prev = await t.get(idem.ref);
        if (prev.exists) return { ...(prev.data().result || {}), duplicate: true };
      }
      const snap = await t.get(orderRef);
      if (!snap.exists) throw fail('not-found', 'ORDER_NOT_FOUND');
      const od = snap.data() || {};
      if (od.type !== 'platform' || od.subtype !== 'supermarket') throw fail('failed-precondition', 'ORDER_NOT_SUPERMARKET');
      if (authorize) authorize(od);
      const status = String(od.status || '');
      const fs = String(od.fulfillmentStatus || '').toLowerCase();
      if (!ADJUSTABLE_STATUSES.has(status) || COURIER_HOLD_FS.has(fs)) throw fail('failed-precondition', 'ORDER_STATE_LOCKED', { status });
      const lines = Array.isArray(od.items) ? od.items : [];
      const extra = preRead ? await preRead(t, od) : undefined;
      const m = mutate(lines, od, extra);
      if (!m.ok) throw fail('failed-precondition', m.code, m.details || {});
      if (!m.changed) return { changed: false, refund: 0, debit: 0, total: od.balanceApplied, userId: String(od.userPhone || '') };

      const pids = Object.keys(m.stockDeltas || {}).filter((p) => m.stockDeltas[p] !== 0);
      const pRefs = pids.map((p) => db.collection(PRODUCTS).doc(p));
      const pSnaps = await Promise.all(pRefs.map((r) => t.get(r)));
      const charged = Math.max(0, Math.trunc(Number(od.balanceApplied || 0)));
      const bp = feeBpOf(od.deliveryFeePercent);
      const c = computeCharge(m.lines, bp);
      // Рағбат (эга 2026-11-26): ҳисоб брутто бўйича (ҳамён + рағбат), рағбат суммаси ўзгармайди; ҳамёндан фақат нетто.
      // Брутто мақсад рағбатдан кам бўлса — ҳамён 0, рағбат ортиғи нақдга АЙЛАНМАЙДИ (ҳамёнга қайтмайди).
      const incApplied = Number.isSafeInteger(od.incentiveApplied) && od.incentiveApplied > 0 ? od.incentiveApplied : 0;
      const adjGross = chargeAfter(charged + incApplied, lines, m.lines, bp, m.pricing || 'cap');
      const netNext = Math.max(0, adjGross.next - incApplied);
      const adj = {
        next: netNext, refund: Math.max(0, charged - netNext), debit: Math.max(0, netNext - charged),
        capDiscount: adjGross.capDiscount, gross: adjGross.next,
      };
      const seq = (Number.isInteger(od.smAdjustSeq) ? od.smAdjustSeq : 0) + 1;
      const walletDocId = String(od.walletUserDocId || '').trim();
      const moves = adj.refund > 0 || adj.debit > 0;
      let customerRef = null;
      let bal = 0;
      let bonusCtx = null;
      if (moves) {
        if (!walletDocId) throw fail('failed-precondition', 'USER_NOT_FOUND');
        customerRef = db.collection('users').doc(walletDocId);
        const customerSnap = await t.get(customerRef);
        if (!customerSnap.exists) throw fail('failed-precondition', 'USER_NOT_FOUND');
        bal = parseInt(String((customerSnap.data() || {}).bonusBalance ?? 0), 10) || 0;
        if (adj.debit > bal) throw fail('failed-precondition', 'INSUFFICIENT_FUNDS', { required: adj.debit, balance: bal });
        bonusCtx = await settlementLedger.prepareBonusInTx(t, db, walletDocId, { idempotencyKey: `sm_adjust_${orderId}_${seq}` });
      }
      // ── ёзишлар ──
      pSnaps.forEach((s, i) => {
        if (!s.exists) return;
        const delta = m.stockDeltas[pids[i]];
        const curMilli = toMilli(Number((s.data() || {}).stock)) || 0;
        const next = Math.max(0, curMilli + delta);
        const patch = { stock: fromMilli(next) };
        if (next > 0 && autoOut(s.data())) Object.assign(patch, { smStatus: 'active', smAutoOutOfStock: false });
        if (next === 0 && delta < 0 && (s.data() || {}).smStatus === 'active') Object.assign(patch, { smStatus: 'out_of_stock', smAutoOutOfStock: true });
        t.update(pRefs[i], patch);
      });
      const by = ADJUST_META[action].by;
      if (moves) {
        const delta = adj.refund > 0 ? adj.refund : -adj.debit;
        const note = adj.refund > 0 ? REFUND_NOTES[action] : DEBIT_NOTES[action];
        t.set(customerRef, { bonusBalance: bal + delta, balanceUpdatedAt: ts() }, { merge: true });
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta, kind: adj.refund > 0 ? 'sm_adjust_refund' : 'sm_adjust_debit', refType: 'order', refId: orderId,
          meta: { action, seq, chargedBefore: charged, chargedAfter: adj.next },
          postedBy: actor, postedRole: actorRole || 'admin',
        });
        t.set(customerRef.collection('wallet_ledger').doc(), {
          type: adj.refund > 0 ? 'order_partial_refund' : 'purchase_debit', amount: delta, module: 'platform', refType: 'order', refId: orderId,
          meta: { subtype: 'supermarket', action, noteKey: note.key, messages: note.messages, note: note.messages.uz_Cyrl },
          createdAt: ts(), createdBy: by,
        });
      }
      const weighPending = m.lines.some((l) => !l.removed && l.weighed && l.actualQty == null);
      const extrasLeft = c.extras;
      const feeShown = Math.max(0, adj.gross - c.goods - extrasLeft);
      t.update(orderRef, {
        ...(incApplied > 0 ? { grossTotal: adj.gross } : {}),
        items: m.lines,
        itemsTotal: c.goods,
        weighHold: extrasLeft,
        deliveryFee: feeShown,
        total: adj.next,
        balanceApplied: adj.next,
        paidAmount: adj.next,
        smAdjustSeq: seq,
        smWeighPending: weighPending,
        smShortagePending: m.lines.some(linePending),
        ...(adj.capDiscount > 0 ? { smCapDiscount: adj.capDiscount } : {}),
        smRefundedTotal: FV.increment(adj.refund),
        // 3-босқич: қайтим тури бўйича (аналитика; эски буюртмаларда йўқ → «unattributed»).
        ...(adj.refund > 0 ? { [`smRefundByAction.${action}`]: FV.increment(adj.refund) } : {}),
        ...(adj.debit > 0 ? { smExtraChargedTotal: FV.increment(adj.debit) } : {}),
        updatedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: ADJUST_META[action].audit, actor, actorRole, target: `${ORDERS}/${orderId}`,
        seq, chargedBefore: charged, chargedAfter: adj.next, refund: adj.refund, debit: adj.debit, ...auditExtra, at: ts(),
      });
      const result = { changed: true, refund: adj.refund, debit: adj.debit, total: adj.next, userId: String(od.userPhone || ''), weighPending, ...(m.info ? { info: m.info } : {}) };
      if (idem) t.set(idem.ref, { type: idem.type, result, createdAt: ts() });
      return result;
    });
  }

  /** Мижозга хабар (ўз тилида, best-effort). texts: {lang:{title, body}} — body'да {name}/{refund}. */
  async function notifyCustomer(userId, texts, params, extra) {
    try {
      // userPhone 12 хонали, ҳужжат эски 9 хонали бўлиши мумкин (userDocRef) — langOfPhone фақат 9→12 ни синайди.
      const u = await userDocRef(canonicalUid(userId));
      const lang = normalizeLang(u ? u.data.appLang : await langOfPhone(db, userId));
      const m = texts[lang] || texts.uz_Cyrl;
      const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => (params[k] === undefined ? '' : String(params[k])));
      await notifyUserInApp({ userId, title: fill(m.title), body: fill(m.body), category: 'order', screen: 'orders', ...extra });
    } catch (e) {
      log({ action: extra.source, result: 'notify_error', errorCode: 'NOTIFY_FAILED' });
    }
  }

  exportsObj.adminSettleSupermarketWeights = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const { uid: actor, role: actorRole } = await requireOperator(context);
    const orderId = typeof (data && data.orderId) === 'string' ? data.orderId.trim() : '';
    const raw = data && data.lines;
    if (!orderId || orderId.includes('/') || !Array.isArray(raw) || raw.length < 1 || raw.length > LIMITS.items) {
      throw fail('invalid-argument', 'INVALID_REQUEST');
    }
    const input = raw.map((r) => ({
      productId: isPlainObject(r) && typeof r.productId === 'string' ? r.productId.trim() : '',
      actualQty: isPlainObject(r) ? r.actualQty : null,
    }));
    if (input.some((r) => !r.productId)) throw fail('invalid-argument', 'INVALID_REQUEST');
    let out;
    try {
      out = await adjustOrder({
        orderId, actor, actorRole, action: 'weigh',
        mutate: (lines, od) => applyWeights(lines, input, Number.isInteger(od.weighHoldPercent) ? od.weighHoldPercent : 10),
        auditExtra: { lines: input.map((r) => ({ productId: r.productId, actualQty: r.actualQty })) },
      });
    } catch (e) {
      rethrow(e, 'adminSettleSupermarketWeights', { orderId, userId: actor });
    }
    log({ action: 'adminSettleSupermarketWeights', result: 'ok', orderId, userId: actor, changed: out.changed, refund: out.refund, duration: Date.now() - started });
    return { ok: true, orderId, changed: out.changed, refund: out.refund, total: out.total };
  });

  exportsObj.adminRemoveSupermarketLine = functions.https.onCall(async (data, context) => {
    const { uid: actor, role: actorRole } = await requireOperator(context);
    const orderId = typeof (data && data.orderId) === 'string' ? data.orderId.trim() : '';
    const productId = typeof (data && data.productId) === 'string' ? data.productId.trim() : '';
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, LIMITS.reason) : '';
    if (!orderId || orderId.includes('/') || !productId) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (!reason) throw fail('invalid-argument', 'REASON_REQUIRED');
    let out;
    try {
      out = await adjustOrder({
        orderId, actor, actorRole, action: 'remove',
        mutate: (lines) => {
          const idx = lines.findIndex((l) => l.productId === productId);
          if (idx < 0) return { ok: false, code: 'LINE_NOT_FOUND', details: { productId } };
          if (lines[idx].removed) return { ok: true, changed: false, lines }; // қайта юбориш — идемпотент
          if (lines.filter((l) => !l.removed).length <= 1) return { ok: false, code: 'LAST_LINE' };
          const l = lines[idx];
          const qMilli = toMilli(l.actualQty != null ? l.actualQty : l.qty);
          // Етишмовчилик жавоби келмаган (30 дақиқа) — админ олади; ҳолат тарихда қолади.
          const sh = linePending(l) ? { shortage: { ...l.shortage, state: 'admin_removed', resolvedBy: actor, resolvedAtMs: now() } } : {};
          const next = lines.map((x, i) => (i === idx ? { ...x, ...sh, removed: { reason, by: actor, atMs: now() } } : x));
          return { ok: true, changed: true, lines: next, stockDeltas: { [productId]: qMilli } };
        },
        auditExtra: { productId, reason },
      });
    } catch (e) {
      rethrow(e, 'adminRemoveSupermarketLine', { orderId, productId, userId: actor });
    }
    if (out.changed && out.userId) {
      try {
        const lang = normalizeLang(await langOfPhone(db, out.userId));
        const texts = {
          uz_Cyrl: { title: 'Буюртмадан маҳсулот олинди', body: `Битта маҳсулот ҳозир йўқ. ${out.refund} сўм ҳамёнингизга қайтарилди.` },
          uz_Latn: { title: 'Buyurtmadan mahsulot olindi', body: `Bitta mahsulot hozir yöq. ${out.refund} söm hamyoningizga qaytarildi.` },
          ru: { title: 'Товар удалён из заказа', body: `Одного товара сейчас нет. ${out.refund} сум возвращено в кошелёк.` },
        };
        const msg = texts[lang] || texts.uz_Cyrl;
        await notifyUserInApp({
          userId: out.userId, title: msg.title, body: msg.body, category: 'order', source: 'supermarket_line_removed',
          dataType: 'supermarket_line_removed', screen: 'orders', extraNews: { orderId }, extraData: { orderId },
        });
      } catch (e) {
        log({ action: 'adminRemoveSupermarketLine', result: 'notify_error', orderId, errorCode: 'NOTIFY_FAILED' });
      }
    }
    log({ action: 'adminRemoveSupermarketLine', result: 'ok', orderId, productId, userId: actor, changed: out.changed, refund: out.refund });
    return { ok: true, orderId, changed: out.changed, refund: out.refund, total: out.total };
  });

  // ── 6. Етишмовчилик (2-босқич, эга 2026-11-21): админ хабар беради → мижоз танлайди ──
  const idOk = (v, re) => typeof v === 'string' && re.test(v.trim());

  exportsObj.adminReportSupermarketShortage = functions.https.onCall(async (data, context) => {
    const { uid: actor, role: actorRole } = await requireOperator(context);
    const d = data || {};
    const orderId = typeof d.orderId === 'string' ? d.orderId.trim() : '';
    const productId = typeof d.productId === 'string' ? d.productId.trim() : '';
    const subsRaw = d.substitutes == null ? [] : d.substitutes;
    if (!orderId || orderId.includes('/') || !productId || productId.includes('/') || typeof d.availableQty !== 'number'
        || !Array.isArray(subsRaw) || subsRaw.length > SHORTAGE_SUBS_MAX || !subsRaw.every((s) => idOk(s, PRODUCT_ID_RE))) {
      throw fail('invalid-argument', 'INVALID_REQUEST');
    }
    const subs = subsRaw.map((s) => s.trim());
    if (new Set(subs).size !== subs.length) throw fail('invalid-argument', 'INVALID_REQUEST', { field: 'substitutes' });
    let out;
    try {
      out = await adjustOrder({
        orderId, actor, actorRole, action: 'shortage_report',
        preRead: async (t) => {
          const snaps = await Promise.all(subs.map((id) => t.get(db.collection(PRODUCTS).doc(id))));
          return snaps.map((s, i) => ({ offerId: subs[i], data: s.exists ? (s.data() || {}) : null }));
        },
        mutate: (lines, od, subsData) => applyShortageReport(lines, { productId, availableQty: d.availableQty, subs: subsData, actor, nowMs: now() }),
        auditExtra: { productId, availableQty: d.availableQty, substitutes: subs },
      });
    } catch (e) {
      rethrow(e, 'adminReportSupermarketShortage', { orderId, productId, userId: actor });
    }
    if (out.changed && out.userId) {
      await notifyCustomer(out.userId, SHORTAGE_TEXT, { name: (out.info && out.info.name) || '' }, {
        source: 'supermarket_shortage', dataType: 'supermarket_shortage', extraNews: { orderId, productId }, extraData: { orderId, productId },
      });
    }
    log({ action: 'adminReportSupermarketShortage', result: 'ok', orderId, productId, userId: actor, changed: out.changed });
    return { ok: true, orderId, productId, changed: out.changed, answerWithinMin: SHORTAGE_ANSWER_MS / 60000 };
  });

  exportsObj.respondSupermarketShortage = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = callerUidOrThrow(context);
    const d = data || {};
    const orderId = typeof d.orderId === 'string' ? d.orderId.trim() : '';
    const productId = typeof d.productId === 'string' ? d.productId.trim() : '';
    const choice = String(d.choice || '');
    const clientRequestId = typeof d.clientRequestId === 'string' ? d.clientRequestId.trim() : '';
    const offerId = typeof d.offerId === 'string' ? d.offerId.trim() : '';
    const qty = d.qty == null ? null : d.qty;
    if (!orderId || orderId.includes('/') || !productId || productId.includes('/') || !SHORTAGE_CHOICES.includes(choice)
        || !CLIENT_REQ_RE.test(clientRequestId) || (choice === 'substitute' && !PRODUCT_ID_RE.test(offerId))
        || (qty != null && (typeof qty !== 'number' || choice === 'remove'))) {
      throw fail('invalid-argument', 'INVALID_REQUEST');
    }
    const idemRef = db.collection(IDEM).doc(`sm_short_${uid}_${clientRequestId}`);
    let out;
    try {
      out = await adjustOrder({
        orderId, actor: uid, actorRole: 'client', action: `shortage_${choice}`,
        idem: { ref: idemRef, type: 'respondSupermarketShortage' },
        authorize: (od) => { if (canonicalUid(String(od.userPhone || '')) !== uid) throw fail('permission-denied', 'PERMISSION_DENIED'); },
        preRead: async (t) => {
          if (choice !== 'substitute') return null;
          const s = await t.get(db.collection(PRODUCTS).doc(offerId));
          return s.exists ? (s.data() || {}) : null;
        },
        mutate: (lines, od, offerData) => applyShortageChoice(lines, {
          productId, choice, offerId, qty, offerData, feeBp: feeBpOf(od.deliveryFeePercent),
          weighHoldPercent: Number.isInteger(od.weighHoldPercent) ? od.weighHoldPercent : 10, actor: uid, nowMs: now(),
        }),
        auditExtra: { productId, choice, ...(offerId ? { offerId } : {}), ...(qty != null ? { qty } : {}) },
      });
    } catch (e) {
      rethrow(e, 'respondSupermarketShortage', { orderId, productId, userTail: uid.slice(-4), choice });
    }
    log({ action: 'respondSupermarketShortage', result: 'ok', orderId, productId, userTail: uid.slice(-4), choice, refund: out.refund, debit: out.debit, duplicate: !!out.duplicate, duration: Date.now() - started });
    return { ok: true, orderId, productId, choice, refund: out.refund || 0, debit: out.debit || 0, total: out.total, ...(out.duplicate ? { duplicate: true } : {}) };
  });

  // ── 7. Ҳафталик саватлар (2-босқич): эслатма вақти — фақат сервер ҳисоблайди ──
  const TS = admin.firestore.Timestamp;
  const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);

  exportsObj.onSmListWrite = functions.firestore
    .document('users/{userId}/sm_lists/{listId}')
    .onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const ref = change.after.ref;
      const res = await db.runTransaction(async (t) => {
        const s = await t.get(ref);
        if (!s.exists) return 'gone';
        const x = s.data() || {};
        const problem = listShapeProblem(x);
        const key = !problem && x.remind.enabled === true ? `${x.remind.weekday}:${x.remind.minute}` : null;
        const cur = msOf(x.remindNextAt);
        const desired = !key ? null : (x.remindKey === key && cur != null ? cur : nextRemindAtMs(x.remind, now()));
        const patch = {};
        if (desired !== cur) patch.remindNextAt = desired == null ? FV.delete() : TS.fromMillis(desired);
        if ((x.remindKey || null) !== key) patch.remindKey = key == null ? FV.delete() : key;
        if ((x.smInvalid || null) !== (problem || null)) patch.smInvalid = problem ? problem : FV.delete();
        if (!Object.keys(patch).length) return 'noop';
        t.update(ref, patch);
        return problem ? `invalid:${problem}` : 'scheduled';
      });
      log({ action: 'onSmListWrite', listId: context.params.listId, result: res });
      return null;
    });

  async function runWeeklyReminders() {
    const nowMs = now();
    const [snap, settingsSnap] = await Promise.all([
      db.collectionGroup('sm_lists').where('remindNextAt', '<=', TS.fromMillis(nowMs)).orderBy('remindNextAt').limit(REMIND_BATCH).get(),
      db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]).get(),
    ]);
    const settings = settingsSnap.exists ? (settingsSnap.data() || {}) : null;
    let sent = 0;
    let skipped = 0;
    for (const doc of snap.docs) {
      // Даъво (claim) олдин: кейинги вақт ёзилади → бир эслатма бир марта (энг кўпи битта; push йиқилса — ўтказиб юборилади).
      const claimed = await db.runTransaction(async (t) => {
        const s = await t.get(doc.ref);
        if (!s.exists) return null;
        const x = s.data() || {};
        const due = msOf(x.remindNextAt);
        if (due == null || due > nowMs) return null;
        const valid = !listShapeProblem(x) && x.remind.enabled === true;
        t.update(doc.ref, valid
          ? { remindNextAt: TS.fromMillis(advanceRemindMs(due, nowMs)), remindLastSentAt: ts() }
          : { remindNextAt: FV.delete(), remindKey: FV.delete() });
        return valid;
      });
      if (!claimed) { skipped += 1; continue; }
      const userDocId = doc.ref.parent.parent.id;
      const userSnap = await db.collection('users').doc(userDocId).get();
      if (!userSnap.exists) { skipped += 1; continue; }
      const u = userSnap.data() || {};
      const uid = canonicalUid(userDocId);
      if (!gateDecision(settings, { uid, role: String(u.role || 'user'), districtId: '', requireDistrict: false }).allowed) { skipped += 1; continue; }
      const m = REMIND_TEXT[normalizeLang(u.appLang)] || REMIND_TEXT.uz_Cyrl;
      try {
        await notifyUserInApp({
          userId: uid, title: m.title, body: m.body, category: 'info', source: 'sm_weekly_reminder', dataType: 'sm_weekly_reminder',
          screen: 'supermarket', extraNews: { smListId: doc.id }, extraData: { smListId: doc.id },
        });
        sent += 1;
      } catch (e) {
        skipped += 1;
        log({ action: 'smWeeklyReminder', result: 'notify_error', errorCode: 'NOTIFY_FAILED', listId: doc.id });
      }
    }
    log({ action: 'smWeeklyReminder', result: 'ok', due: snap.size, sent, skipped, full: snap.size === REMIND_BATCH });
    return { due: snap.size, sent, skipped };
  }

  exportsObj.smWeeklyReminder = functions.pubsub
    .schedule('every 15 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(() => runWeeklyReminders());

  // ── Бекор/рад → stock қайтади (бир марта) ──
  exportsObj.onSupermarketOrderCancelStock = functions.firestore
    .document(`${ORDERS}/{orderId}`)
    .onUpdate(async (change, context) => {
      const after = change.after.data() || {};
      if (after.subtype !== 'supermarket' || after.smStockRestored === true) return null;
      if (!isCancelled(after) || isCancelled(change.before.data() || {})) return null;
      const orderId = context.params.orderId;
      const result = await db.runTransaction(async (t) => {
        const snap = await t.get(change.after.ref);
        const od = snap.data() || {};
        if (od.smStockRestored === true || !isCancelled(od)) return 'noop';
        const deltas = {};
        for (const l of (Array.isArray(od.items) ? od.items : [])) {
          if (l.removed) continue;
          const q = toMilli(l.actualQty != null ? l.actualQty : l.qty);
          if (q > 0) deltas[l.productId] = (deltas[l.productId] || 0) + q;
        }
        const pids = Object.keys(deltas);
        const refs = pids.map((p) => db.collection(PRODUCTS).doc(p));
        const snaps = await Promise.all(refs.map((r) => t.get(r)));
        // Рағбат гранти тикланади (эга 2026-11-26). Идемпотент: incentive_ledger/refund_{orderId}_{grantId} —
        // мавжуд бекор қилиш йўли (adminSetOrderStatus/customerCancelOrder) аввал тиклаган бўлса — ўтказиб юборилади.
        const incCtx = await incentivesLib.prepareIncentiveRefundInTx(t, db, orderId, od);
        incentivesLib.commitIncentiveRefundInTx(t, db, admin, incCtx, { actor: 'system:onSupermarketOrderCancelStock', nowMs: now() });
        snaps.forEach((s, i) => {
          if (!s.exists) return;
          const cur = toMilli(Number((s.data() || {}).stock)) || 0;
          const patch = { stock: fromMilli(cur + deltas[pids[i]]) };
          if (autoOut(s.data())) Object.assign(patch, { smStatus: 'active', smAutoOutOfStock: false });
          t.update(refs[i], patch);
        });
        t.update(change.after.ref, { smStockRestored: true });
        return 'restored';
      });
      log({ action: 'onSupermarketOrderCancelStock', orderId, result });
      return null;
    });

  // Ички API (Excel импорт модули учун — таклиф ёзиш йўли ягона бўлсин, 7-банд).
  return { upsertOfferTx, requireAdmin, fail, runWeeklyReminders };
}

/** Тизим ўзи «тугади» қилган (stock 0) — admin қўлда қўйган эмас. */
function autoOut(d) {
  const x = d || {};
  return x.smStatus === 'out_of_stock' && x.smAutoOutOfStock === true;
}

function isCancelled(od) {
  const s = String(od.status || '');
  const fs = String(od.fulfillmentStatus || '').toLowerCase();
  return s === 'rejected' || s === 'cancelled' || fs === 'cancelled';
}

/** Таксономия версияси учун 3 ҳужжат (callable ва seed бир хил шакл). */
function buildTaxonomyVersionDocs({ categories, version, previousVersion, actor, ts }) {
  const doc = { categories, version, updatedAt: ts, updatedBy: actor };
  return {
    doc,
    history: { ...doc, taxonomy: 'supermarket', previousVersion: previousVersion == null ? null : previousVersion },
    audit: { kind: 'supermarket_taxonomy_set', actor, target: `taxonomy/supermarket v${version}`, version, at: ts },
  };
}

module.exports = {
  attachSupermarket,
  // тоза (тестлар)
  toMilli, fromMilli, lineTotalOf, holdExtraOf, feeBpOf, feeOf, feeConfigFromApp, computeCharge,
  tashkentParts, availableSlots, gateDecision, validateSupermarketTaxonomy, validateSupermarketSettings,
  validateOffer, validateCost, findGroup, offerSearchTokens, priceSupermarketOrder, applyWeights, adjustment,
  buildTaxonomyVersionDocs, isCancelled, trimDeep, messagesOf,
  // 2-босқич
  offerSellable, applyShortageReport, applyShortageChoice, chargeAfter, remindOk, listShapeProblem, nextRemindAtMs, advanceRemindMs,
  stableStringify, isPlainObject, stepOk,
  DEBIT_NOTES, REMIND_TEXT, SHORTAGE_TEXT, SHORTAGE_ANSWER_MS, PAIRS_MAX, LIST_ID_RE, ID_RE, PRODUCT_ID_RE, LIMITS,
  MSG, UNITS, PACK_UNITS, OPERATOR_ROLES, REFUND_NOTES, STAGES, SM_STATUSES, LANGS, TAXONOMY_DOC, SETTINGS_DOC, HISTORY_COLLECTION, HISTORY_PREFIX,
  TARIFF_VERSION, UNIT_LABELS, ORDER_ORIGINS,
  // 3-босқич: курьер тўлови
  courierPayoutProblems, courierPayoutSnapshot, COURIER_PAYOUT_MODES,
};
