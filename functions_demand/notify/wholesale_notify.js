'use strict';

/**
 * ULGURJI «yetkazilganda karta orqali» zanjiri — xabarlar (3b, ega 2026-10-31).
 *
 * Shakl — mavjud shaxsiy inbox `admin_news` (`notifyUserInApp` / `capabilities.js`
 * `taxiDueNews` bilan bir xil: `audience: 'user'`, `targetUserId` = kanon telefon,
 * `pushDirect: true` — push shu yerda yuboriladi, `onAdminNewsCreate` qayta yubormasin)
 * + FCM (`notify/fcm.tokensFor` + `messaging.sendEach`, «best effort»).
 *
 * IDEMPOTENT: hujjat ID deterministik (`wholesale_{orderId}_{key}_{uid}`) va `create()`
 * bilan yoziladi — trigger takrorlansa ikkinchi xabar/push YO'Q (21-band).
 *
 * TIL: `users/{id}.appLang` (uz_Cyrl | uz_Latn | ru), yo'q bo'lsa uz_Cyrl —
 * `functions/notif_i18n.js` qoidasi bilan bir xil (u default codebase'da, bu yerdan
 * import qilib bo'lmaydi; Ulgurji xabarlari FAQAT shu faylda — yagona manba).
 * Matnlar — PROPOSED (ega tahrirlaydi). Matnda telefon/manzil YO'Q (40-band).
 */

const { candidateIdsFor, toCanonicalId } = require('../core/ids');
const fcm = require('./fcm');
const WO = require('../core/wholesale_orders');

const DEFAULT_LANG = 'uz_Cyrl';
const LANGS = ['uz_Cyrl', 'uz_Latn', 'ru'];
const NEWS = 'admin_news';
const ADMIN_ROLES = ['admin', 'superadmin'];
const ADMIN_LIMIT = 20;

/** Kalit → til → { title, body }; `{name}` o'rinbosarlari `render`da. */
const MESSAGES = {
  ws_card_new_order: {
    uz_Cyrl: { title: 'Янги буюртма — тўлов картангизга', body: '{product} × {qty}. Харидор етказилганда {amount} сўмни картангизга ўтказади. Пул тушгач «Пул тушди» тугмасини босинг.' },
    uz_Latn: { title: 'Yangi buyurtma — to\'lov kartangizga', body: '{product} × {qty}. Xaridor yetkazilganda {amount} so\'mni kartangizga o\'tkazadi. Pul tushgach «Pul tushdi» tugmasini bosing.' },
    ru: { title: 'Новый заказ — оплата на вашу карту', body: '{product} × {qty}. Покупатель при доставке переведёт {amount} сум на вашу карту. Когда деньги поступят, нажмите «Деньги поступили».' },
  },
  ws_card_receipt: {
    uz_Cyrl: { title: 'Харидор тўлов чекини юборди', body: '{product}: {amount} сўм. Картангизни текширинг ва «Пул тушди» ни босинг. {minutes} дақиқада тасдиқланмаса, админ кўриб чиқади.' },
    uz_Latn: { title: 'Xaridor to\'lov chekini yubordi', body: '{product}: {amount} so\'m. Kartangizni tekshiring va «Pul tushdi» ni bosing. {minutes} daqiqada tasdiqlanmasa, admin ko\'rib chiqadi.' },
    ru: { title: 'Покупатель отправил чек оплаты', body: '{product}: {amount} сум. Проверьте карту и нажмите «Деньги поступили». Если не подтвердить за {minutes} минут, заказ рассмотрит администратор.' },
  },
  ws_card_confirmed: {
    uz_Cyrl: { title: 'Тўлов тасдиқланди', body: 'Сотувчи {amount} сўм тушганини тасдиқлади. Етказиш коди буюртма саҳифасида — уни курьерга айтинг.' },
    uz_Latn: { title: 'To\'lov tasdiqlandi', body: 'Sotuvchi {amount} so\'m tushganini tasdiqladi. Yetkazish kodi buyurtma sahifasida — uni kuryerga ayting.' },
    ru: { title: 'Оплата подтверждена', body: 'Продавец подтвердил поступление {amount} сум. Код получения — на странице заказа, назовите его курьеру.' },
  },
  ws_refused_buyer: {
    uz_Cyrl: { title: 'Буюртма бекор бўлди', body: '{product}: тўлов амалга ошмагани учун товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma bekor bo\'ldi', body: '{product}: to\'lov amalga oshmagani uchun tovar sotuvchiga qaytariladi.' },
    ru: { title: 'Заказ отменён', body: '{product}: оплата не состоялась, товар возвращается продавцу.' },
  },
  ws_refused_seller: {
    uz_Cyrl: { title: 'Харидор тўламади — товар қайтарилади', body: '{product} × {qty}. Қайтариш етказиш ҳақи ҳамёнингиздан ушланади, AVA улуши қайтарилади.' },
    uz_Latn: { title: 'Xaridor to\'lamadi — tovar qaytariladi', body: '{product} × {qty}. Qaytarish yetkazish haqi hamyoningizdan ushlanadi, AVA ulushi qaytariladi.' },
    ru: { title: 'Покупатель не оплатил — товар возвращается', body: '{product} × {qty}. Стоимость обратной доставки списывается с вашего кошелька, комиссия AVA возвращается.' },
  },
  ws_dispute_admin: {
    uz_Cyrl: { title: 'Улгуржи: тўлов низоси', body: 'Буюртма {orderId}: харидор чек юборган, сотувчи {minutes} дақиқада тасдиқламади. Админ панелида ҳал қилинг.' },
    uz_Latn: { title: 'Ulgurji: to\'lov nizosi', body: 'Buyurtma {orderId}: xaridor chek yuborgan, sotuvchi {minutes} daqiqada tasdiqlamadi. Admin panelida hal qiling.' },
    ru: { title: 'Оптовый рынок: спор по оплате', body: 'Заказ {orderId}: покупатель отправил чек, продавец не подтвердил за {minutes} минут. Решите в админ-панели.' },
  },
  ws_return_debt_seller: {
    uz_Cyrl: { title: 'Қайтариш учун ҳамёнда маблағ етарли эмас', body: '{amount} сўм керак. Ҳамённи тўлдиринг — шунгача картага тўлов усули ёпиқ.' },
    uz_Latn: { title: 'Qaytarish uchun hamyonda mablag\' yetarli emas', body: '{amount} so\'m kerak. Hamyonni to\'ldiring — shungacha kartaga to\'lov usuli yopiq.' },
    ru: { title: 'Недостаточно средств для возврата товара', body: 'Нужно {amount} сум. Пополните кошелёк — до этого оплата картой при доставке недоступна.' },
  },
  ws_return_debt_admin: {
    uz_Cyrl: { title: 'Улгуржи: сотувчида қайтариш қарзи', body: 'Буюртма {orderId}: қайтариш учун {amount} сўм етишмаяпти.' },
    uz_Latn: { title: 'Ulgurji: sotuvchida qaytarish qarzi', body: 'Buyurtma {orderId}: qaytarish uchun {amount} so\'m yetishmayapti.' },
    ru: { title: 'Оптовый рынок: долг продавца за возврат', body: 'Заказ {orderId}: для возврата не хватает {amount} сум.' },
  },
  ws_return_courier: {
    uz_Cyrl: { title: 'Қайтариш иши сизга бириктирилди', body: 'Товарни сотувчига қайтаринг ({tracking}). Олиш коди буюртма саҳифасида.' },
    uz_Latn: { title: 'Qaytarish ishi sizga biriktirildi', body: 'Tovarni sotuvchiga qaytaring ({tracking}). Olish kodi buyurtma sahifasida.' },
    ru: { title: 'Вам назначен возврат товара', body: 'Верните товар продавцу ({tracking}). Код приёма — на странице заказа.' },
  },
  ws_returning_seller: {
    uz_Cyrl: { title: 'Товар сизга қайтиб келмоқда', body: '{product} × {qty}. Кузатув рақами: {tracking}.' },
    uz_Latn: { title: 'Tovar sizga qaytib kelmoqda', body: '{product} × {qty}. Kuzatuv raqami: {tracking}.' },
    ru: { title: 'Товар возвращается к вам', body: '{product} × {qty}. Номер отслеживания: {tracking}.' },
  },
  ws_returned_seller: {
    uz_Cyrl: { title: 'Товар қайтиб келди', body: '{product} × {qty} — қолдиқ тикланди.' },
    uz_Latn: { title: 'Tovar qaytib keldi', body: '{product} × {qty} — qoldiq tiklandi.' },
    ru: { title: 'Товар вернулся', body: '{product} × {qty} — остаток восстановлен.' },
  },
  // ── Yo'qolgan posilka (ega, 2026-10-31) ──
  ws_lost_buyer_wallet: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Товар пули {refund} сўм ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Tovar yetkazishda yo\'qoldi', body: '{product} × {qty}. Tovar puli {refund} so\'m hamyoningizga qaytarildi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Стоимость товара {refund} сум возвращена в ваш кошелёк.' },
  },
  ws_lost_buyer_card: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Буюртма ёпилди — сиз ҳеч нарса тўламайсиз.' },
    uz_Latn: { title: 'Tovar yetkazishda yo\'qoldi', body: '{product} × {qty}. Buyurtma yopildi — siz hech narsa to\'lamaysiz.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Заказ закрыт — вам ничего платить не нужно.' },
  },
  ws_lost_buyer_review: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Тўловингиз бўйича админ кўриб чиқади ва сиз билан боғланади.' },
    uz_Latn: { title: 'Tovar yetkazishda yo\'qoldi', body: '{product} × {qty}. To\'lovingiz bo\'yicha admin ko\'rib chiqadi va siz bilan bog\'lanadi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Администратор рассмотрит вашу оплату и свяжется с вами.' },
  },
  ws_lost_seller: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди — буюртма ёпилди', body: '{product} × {qty}. Товар қийматини масъул курьер қоплайди (логистика хабарида батафсил). Қолдиқ тикланмайди.' },
    uz_Latn: { title: 'Tovar yetkazishda yo\'qoldi — buyurtma yopildi', body: '{product} × {qty}. Tovar qiymatini mas\'ul kuryer qoplaydi (logistika xabarida batafsil). Qoldiq tiklanmaydi.' },
    ru: { title: 'Товар утерян при доставке — заказ закрыт', body: '{product} × {qty}. Стоимость товара возмещает ответственный курьер (подробности в уведомлении логистики). Остаток не восстанавливается.' },
  },
  ws_lost_review_admin: {
    uz_Cyrl: { title: 'Улгуржи: йўқолган товар — тўловни кўриб чиқинг', body: 'Буюртма {orderId}: харидор картага тўловни билдирган, товар йўқолди. Сотувчи товар қийматини курьердан олади — харидорга қайтаришни ҳал қилинг.' },
    uz_Latn: { title: 'Ulgurji: yo\'qolgan tovar — to\'lovni ko\'rib chiqing', body: 'Buyurtma {orderId}: xaridor kartaga to\'lovni bildirgan, tovar yo\'qoldi. Sotuvchi tovar qiymatini kuryerdan oladi — xaridorga qaytarishni hal qiling.' },
    ru: { title: 'Оптовый рынок: утерянный товар — проверьте оплату', body: 'Заказ {orderId}: покупатель сообщил об оплате на карту, товар утерян. Продавец получает стоимость товара от курьера — решите возврат покупателю.' },
  },
};

function render(key, lang, params) {
  const byLang = MESSAGES[key];
  if (!byLang) throw new Error(`wholesale_notify: noma'lum kalit «${key}»`);
  const m = byLang[LANGS.includes(lang) ? lang : DEFAULT_LANG];
  // `{minutes}` — nizo muddati YAGONA konstantadan (core/wholesale_orders.RECEIPT_TIMEOUT_MS).
  const all = { minutes: WO.RECEIPT_TIMEOUT_MINUTES, ...(params || {}) };
  const fill = (s) => String(s).replace(/\{(\w+)\}/g, (_, k) => {
    const v = all[k];
    return v === undefined || v === null ? '' : String(v);
  });
  return { title: fill(m.title), body: fill(m.body) };
}

/** `users/{12|9}.appLang`; yo'q — uz_Cyrl. */
async function langOf(db, uid) {
  for (const id of candidateIdsFor(uid)) {
    const s = await db.collection('users').doc(id).get();
    if (s.exists) {
      const l = (s.data() || {}).appLang;
      return LANGS.includes(l) ? l : DEFAULT_LANG;
    }
  }
  return DEFAULT_LANG;
}

const newsIdFor = (orderId, key, uid) => `wholesale_${orderId}_${key}_${uid}`;

/**
 * Bitta foydalanuvchiga: inbox (create — takror bo'lsa jim) + push.
 * @returns {{sent: boolean, duplicate?: boolean, pushed?: number}}
 */
async function notifyUser(deps, { uid, key, params, orderId }) {
  const { db, messaging = null, now: nowFn } = deps;
  const id = toCanonicalId(uid);
  if (!id || !orderId) return { sent: false };
  const lang = await langOf(db, id);
  const text = render(key, lang, params);
  const ref = db.collection(NEWS).doc(newsIdFor(orderId, key, id));
  const batch = db.batch();
  batch.create(ref, {
    title: text.title,
    body: text.body,
    category: 'order',
    audience: 'user',
    targetUserId: id,
    source: 'wholesale_orders',
    dataType: key,
    orderId,
    priority: 7,
    pushDirect: true,
    createdAt: nowFn ? nowFn() : new Date(),
  });
  try {
    await batch.commit();
  } catch (e) {
    if (e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message)))) {
      return { sent: false, duplicate: true };
    }
    throw e;
  }
  let pushed = 0;
  if (messaging) {
    try {
      const tokens = await fcm.tokensFor(db, id);
      if (tokens.length) {
        await messaging.sendEach(tokens.map((token) => ({
          token,
          notification: { title: text.title, body: text.body.slice(0, 120) },
          data: { type: 'wholesale_order', event: key, orderId, screen: 'wholesale_order' },
          android: { priority: 'high' },
        })));
        pushed = tokens.length;
      }
    } catch (e) {
      console.error(JSON.stringify({
        module: 'wholesale_orders', action: 'notify', result: 'push_failed', orderId, key, errorCode: 'PUSH_FAILED',
      }));
    }
  }
  return { sent: true, pushed };
}

/** Adminlar (`users.role in [admin, superadmin]`, eng ko'pi 20) — har biriga alohida. */
async function adminIds(db) {
  const snap = await db.collection('users').where('role', 'in', ADMIN_ROLES).limit(ADMIN_LIMIT).get();
  const out = new Set();
  for (const d of snap.docs) {
    const id = toCanonicalId(d.id);
    if (id) out.add(id);
  }
  return [...out];
}

async function notifyAdmins(deps, { key, params, orderId }) {
  const ids = await adminIds(deps.db);
  let sent = 0;
  for (const uid of ids) {
    try {
      const r = await notifyUser(deps, { uid, key, params, orderId });
      if (r.sent) sent += 1;
    } catch (e) {
      console.error(JSON.stringify({ module: 'wholesale_orders', action: 'notifyAdmins', result: 'failed', orderId, key }));
    }
  }
  return { sent, admins: ids.length };
}

module.exports = {
  MESSAGES, LANGS, DEFAULT_LANG, render, langOf, newsIdFor, notifyUser, notifyAdmins, adminIds,
};
