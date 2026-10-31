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
  // ── Рад этилгач харидорга — САБАБГА қараб (ega, 2026-11-01). `ws_refused_buyer` (тўлов амалга ошмади) —
  // фақат админ низони рад этганда (карта) ва сабаб коди йўқ эски ёзувда.
  ws_refused_buyer_absent: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: курьер сизни топа олмади, буюртма «етказилмади» деб ёпилди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: kuryer sizni topa olmadi, buyurtma «yetkazilmadi» deb yopildi. Tovar sotuvchiga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: курьеру не удалось вас застать, заказ закрыт как «не доставлен». Товар возвращается продавцу.' },
  },
  ws_refused_buyer_refused: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: товар қабул қилинмади, буюртма «етказилмади» деб ёпилди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: tovar qabul qilinmadi, buyurtma «yetkazilmadi» deb yopildi. Tovar sotuvchiga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: получение товара не состоялось, заказ закрыт как «не доставлен». Товар возвращается продавцу.' },
  },
  ws_refused_buyer_courier: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: курьер сабабли товар етказилмади. Буюртма ёпилди, товар сотувчига қайтарилади. Сиздан пул олинмайди.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: kuryer sababli tovar yetkazilmadi. Buyurtma yopildi, tovar sotuvchiga qaytariladi. Sizdan pul olinmaydi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: товар не доставлен по причине со стороны курьера. Заказ закрыт, товар возвращается продавцу. Деньги с вас не списываются.' },
  },
  ws_refused_buyer_other: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: товар етказилмади, буюртма ёпилди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: tovar yetkazilmadi, buyurtma yopildi. Tovar sotuvchiga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: товар не доставлен, заказ закрыт. Товар возвращается продавцу.' },
  },
  // Ҳамён буюртмаси — пул ҳисоблангач (default `settleWalletRefusalInTx`, `refundStatus: done`):
  // {refund} — қайтган товар суммаси, {returnFee} — ушланган қайтариш ҳақи.
  ws_refused_buyer_wallet: {
    uz_Cyrl: { title: 'Буюртма ёпилди — пул ҳамёнингизда', body: '{product}: товар етказилмади. Товар суммаси {refund} сўм ҳамёнингизга қайтарилди, қайтариш етказиш ҳақи {returnFee} сўм ушланди. Етказиш ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Buyurtma yopildi — pul hamyoningizda', body: '{product}: tovar yetkazilmadi. Tovar summasi {refund} so\'m hamyoningizga qaytarildi, qaytarish yetkazish haqi {returnFee} so\'m ushlandi. Yetkazish haqi qaytarilmaydi.' },
    ru: { title: 'Заказ закрыт — деньги в кошельке', body: '{product}: товар не доставлен. На ваш кошелёк возвращено {refund} сум за товар, удержано {returnFee} сум за обратную доставку. Стоимость доставки не возвращается.' },
  },
  ws_refused_buyer_wallet_courier: {
    uz_Cyrl: { title: 'Буюртма ёпилди — пул ҳамёнингизда', body: '{product}: курьер сабабли товар етказилмади. Товар суммаси {refund} сўм ҳамёнингизга қайтарилди. Қайтариш ҳақини курьер тўлайди, етказиш ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Buyurtma yopildi — pul hamyoningizda', body: '{product}: kuryer sababli tovar yetkazilmadi. Tovar summasi {refund} so\'m hamyoningizga qaytarildi. Qaytarish haqini kuryer to\'laydi, yetkazish haqi qaytarilmaydi.' },
    ru: { title: 'Заказ закрыт — деньги в кошельке', body: '{product}: товар не доставлен по причине со стороны курьера. На ваш кошелёк возвращено {refund} сум за товар. Обратную доставку оплачивает курьер, стоимость доставки не возвращается.' },
  },
  ws_refused_seller_wallet: {
    uz_Cyrl: { title: 'Товар етказилмади — сизга қайтарилади', body: '{product} × {qty}. Харидор ҳамёндан тўлаган буюртма: товар пули харидорга қайтарилади, қайтариш ҳақини сиз тўламайсиз.' },
    uz_Latn: { title: 'Tovar yetkazilmadi — sizga qaytariladi', body: '{product} × {qty}. Xaridor hamyondan to\'lagan buyurtma: tovar puli xaridorga qaytariladi, qaytarish haqini siz to\'lamaysiz.' },
    ru: { title: 'Товар не доставлен — возвращается к вам', body: '{product} × {qty}. Заказ оплачен из кошелька покупателя: деньги за товар возвращаются покупателю, обратную доставку вы не оплачиваете.' },
  },
  ws_return_fee_courier: {
    uz_Cyrl: { title: 'Қайтариш ҳақи ушланди', body: '{product}: «етказилмади» сабаби — курьер. Қайтариш етказиш ҳақи {returnFee} сўм ҳамёнингиздан ушланди.' },
    uz_Latn: { title: 'Qaytarish haqi ushlandi', body: '{product}: «yetkazilmadi» sababi — kuryer. Qaytarish yetkazish haqi {returnFee} so\'m hamyoningizdan ushlandi.' },
    ru: { title: 'Списана стоимость обратной доставки', body: '{product}: причина «не доставлено» — курьер. С вашего кошелька списано {returnFee} сум за обратную доставку.' },
  },
  ws_return_debt_buyer: {
    uz_Cyrl: { title: 'Қайтариш ҳақи учун маблағ етмади', body: '{product}: яна {amount} сўм керак. Ҳамённи тўлдиринг — товар сотувчига шундан кейин қайтарилади.' },
    uz_Latn: { title: 'Qaytarish haqi uchun mablag\' yetmadi', body: '{product}: yana {amount} so\'m kerak. Hamyonni to\'ldiring — tovar sotuvchiga shundan keyin qaytariladi.' },
    ru: { title: 'Не хватает средств на обратную доставку', body: '{product}: нужно ещё {amount} сум. Пополните кошелёк — после этого товар вернётся продавцу.' },
  },
  ws_return_debt_courier: {
    uz_Cyrl: { title: 'Қайтариш ҳақи учун ҳамёнда маблағ етмади', body: '{product}: «етказилмади» сабаби — курьер. Яна {amount} сўм керак — ҳамённи тўлдиринг, товар сотувчига шундан кейин қайтарилади.' },
    uz_Latn: { title: 'Qaytarish haqi uchun hamyonda mablag\' yetmadi', body: '{product}: «yetkazilmadi» sababi — kuryer. Yana {amount} so\'m kerak — hamyonni to\'ldiring, tovar sotuvchiga shundan keyin qaytariladi.' },
    ru: { title: 'Не хватает средств на обратную доставку', body: '{product}: причина «не доставлено» — курьер. Нужно ещё {amount} сум — пополните кошелёк, после этого товар вернётся продавцу.' },
  },
  ws_return_debt_admin_buyer: {
    uz_Cyrl: { title: 'Улгуржи: харидорда қайтариш қарзи', body: 'Буюртма {orderId} (ҳамён): қайтариш учун харидорда {amount} сўм етишмаяпти.' },
    uz_Latn: { title: 'Ulgurji: xaridorda qaytarish qarzi', body: 'Buyurtma {orderId} (hamyon): qaytarish uchun xaridorda {amount} so\'m yetishmayapti.' },
    ru: { title: 'Оптовый рынок: долг покупателя за возврат', body: 'Заказ {orderId} (кошелёк): у покупателя не хватает {amount} сум на возврат.' },
  },
  ws_return_debt_admin_courier: {
    uz_Cyrl: { title: 'Улгуржи: курьерда қайтариш қарзи', body: 'Буюртма {orderId} (ҳамён): қайтариш учун курьерда {amount} сўм етишмаяпти.' },
    uz_Latn: { title: 'Ulgurji: kuryerda qaytarish qarzi', body: 'Buyurtma {orderId} (hamyon): qaytarish uchun kuryerda {amount} so\'m yetishmayapti.' },
    ru: { title: 'Оптовый рынок: долг курьера за возврат', body: 'Заказ {orderId} (кошелёк): у курьера не хватает {amount} сум на возврат.' },
  },
  ws_refused_seller: {
    uz_Cyrl: { title: 'Харидор тўламади — товар қайтарилади', body: '{product} × {qty}. Қайтариш етказиш ҳақи ҳамёнингиздан ушланади, AVA улуши қайтарилади.' },
    uz_Latn: { title: 'Xaridor to\'lamadi — tovar qaytariladi', body: '{product} × {qty}. Qaytarish yetkazish haqi hamyoningizdan ushlanadi, AVA ulushi qaytariladi.' },
    ru: { title: 'Покупатель не оплатил — товар возвращается', body: '{product} × {qty}. Стоимость обратной доставки списывается с вашего кошелька, комиссия AVA возвращается.' },
  },
  // ── «Етказилмади» — харидор тасдиғи (ega, 2026-11-01; api/wholesale_failed.js). `{timeout}` —
  // server_config/customer_confirm.failedTimeoutMin (`{minutes}` — чек низоси, бошқа муддат).
  ws_df_buyer_confirm: {
    uz_Cyrl: { title: 'Курьер: товар етказилмади', body: '{product}: курьер товарни етказиб бўлмади деб белгилади. Буюртма саҳифасида тасдиқланг ёки «Олмоқчиман» ни босинг. {timeout} дақиқада жавоб бўлмаса, сотувчи ҳал қилади.' },
    uz_Latn: { title: 'Kuryer: tovar yetkazilmadi', body: '{product}: kuryer tovarni yetkazib bo\'lmadi deb belgiladi. Buyurtma sahifasida tasdiqlang yoki «Olmoqchiman» ni bosing. {timeout} daqiqada javob bo\'lmasa, sotuvchi hal qiladi.' },
    ru: { title: 'Курьер: товар не доставлен', body: '{product}: по отметке курьера товар не удалось доставить. Подтвердите на странице заказа или нажмите «Хочу получить». Если не ответить за {timeout} минут, решит продавец.' },
  },
  ws_df_courier_wait: {
    uz_Cyrl: { title: 'Харидор тасдиғи кутилмоқда', body: '{product}: харидор {timeout} дақиқа ичида жавоб беради, кейин сотувчи ҳал қилади. Посилкани ўзингизда сақланг.' },
    uz_Latn: { title: 'Xaridor tasdig\'i kutilmoqda', body: '{product}: xaridor {timeout} daqiqa ichida javob beradi, keyin sotuvchi hal qiladi. Posilkani o\'zingizda saqlang.' },
    ru: { title: 'Ожидаем подтверждения покупателя', body: '{product}: покупатель ответит в течение {timeout} минут, затем решит продавец. Посылку держите при себе.' },
  },
  ws_df_courier_continue: {
    uz_Cyrl: { title: 'Етказишни давом эттиринг', body: '{product}: товар етказилсин деб қарор қилинди. Харидорга топширинг.' },
    uz_Latn: { title: 'Yetkazishni davom ettiring', body: '{product}: tovar yetkazilsin deb qaror qilindi. Xaridorga topshiring.' },
    ru: { title: 'Продолжайте доставку', body: '{product}: решено доставить товар. Передайте его покупателю.' },
  },
  ws_df_buyer_continue: {
    uz_Cyrl: { title: 'Товар етказилади', body: '{product}: курьер етказишни давом эттиради.' },
    uz_Latn: { title: 'Tovar yetkaziladi', body: '{product}: kuryer yetkazishni davom ettiradi.' },
    ru: { title: 'Товар будет доставлен', body: '{product}: курьер продолжит доставку.' },
  },
  ws_df_decide_seller: {
    uz_Cyrl: { title: 'Етказилмади — қарорингиз керак', body: '{product} × {qty}: харидор {timeout} дақиқада жавоб бермади. Буюртма саҳифасида «Етказилмади» ёки «Етказилсин» ни танланг.' },
    uz_Latn: { title: 'Yetkazilmadi — qaroringiz kerak', body: '{product} × {qty}: xaridor {timeout} daqiqada javob bermadi. Buyurtma sahifasida «Yetkazilmadi» yoki «Yetkazilsin» ni tanlang.' },
    ru: { title: 'Не доставлено — нужно ваше решение', body: '{product} × {qty}: ответа покупателя нет уже {timeout} минут. На странице заказа выберите «Не доставлено» или «Доставить».' },
  },
  ws_df_decide_admin: {
    uz_Cyrl: { title: 'Улгуржи: етказилмади — қарор', body: 'Буюртма {orderId}: харидор жавоб бермади. Сотувчи ёки админ ҳал қилади («Етказилмади — қарор»).' },
    uz_Latn: { title: 'Ulgurji: yetkazilmadi — qaror', body: 'Buyurtma {orderId}: xaridor javob bermadi. Sotuvchi yoki admin hal qiladi («Yetkazilmadi — qaror»).' },
    ru: { title: 'Оптовый рынок: не доставлено — решение', body: 'Заказ {orderId}: ответа покупателя нет. Решает продавец или администратор («Не доставлено — решение»).' },
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
async function notifyUser(deps, { uid, key, params, orderId, idSuffix }) {
  const { db, messaging = null, now: nowFn } = deps;
  const id = toCanonicalId(uid);
  if (!id || !orderId) return { sent: false };
  const lang = await langOf(db, id);
  const text = render(key, lang, params);
  // `idSuffix` — bir buyurtmada takrorlanadigan hodisa (masalan «етказилмади» n-urinish): har urinishga
  // bitta xabar, o'sha urinish qayta chaqirilsa — yo'q. Yo'q bo'lsa ID avvalgidek (eski xabarlar o'zgarmaydi).
  const suffix = /^[A-Za-z0-9]{1,16}$/.test(String(idSuffix || '')) ? `_${idSuffix}` : '';
  const ref = db.collection(NEWS).doc(`${newsIdFor(orderId, key, id)}${suffix}`);
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

async function notifyAdmins(deps, { key, params, orderId, idSuffix }) {
  const ids = await adminIds(deps.db);
  let sent = 0;
  for (const uid of ids) {
    try {
      const r = await notifyUser(deps, { uid, key, params, orderId, idSuffix });
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
