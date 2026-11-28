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
  // ── Сотувчи қабули (ega, 2026-11-13). {deadline} — Тошкент вақтида «кк.ОО СС:дд» (2 иш куни).
  // Сабаб матни (сотувчи ёзган) хабарга ҚЎЙИЛМАЙДИ — эркин матнда шахсий маълумот бўлиши мумкин (40-банд).
  ws_seller_decide: {
    uz_Cyrl: { title: 'Янги буюртма — қабул қилинг', body: '{product} × {qty}, {amount} сўм. Буюртмани {deadline} гача қабул қилинг ёки рад этинг. Жавоб бўлмаса, буюртма бекор бўлади.' },
    uz_Latn: { title: 'Yangi buyurtma — qabul qiling', body: '{product} × {qty}, {amount} söm. Buyurtmani {deadline} gaça qabul qiling yoki rad eting. Javob bölmasa, buyurtma bekor böladi.' },
    ru: { title: 'Новый заказ — примите его', body: '{product} × {qty}, {amount} сум. Примите или отклоните заказ до {deadline}. Без ответа заказ будет отменён.' },
  },
  ws_seller_accepted_buyer: {
    uz_Cyrl: { title: 'Сотувчи буюртмани қабул қилди', body: '{product} × {qty}. Етказиш тайёрланмоқда — ҳолатини буюртма саҳифасида кузатинг.' },
    uz_Latn: { title: 'Sotuvçi buyurtmani qabul qildi', body: '{product} × {qty}. Yetkaziş tayyorlanmoqda — holatini buyurtma sahifasida kuzating.' },
    ru: { title: 'Продавец принял заказ', body: '{product} × {qty}. Доставка готовится — следите за статусом на странице заказа.' },
  },
  ws_seller_rejected_buyer: {
    uz_Cyrl: { title: 'Сотувчи буюртмани рад этди', body: '{product} × {qty}. Буюртма бекор қилинди. Ҳамёндан тўлаган бўлсангиз, пул ҳамёнингизга қайтарилади.' },
    uz_Latn: { title: 'Sotuvçi buyurtmani rad etdi', body: '{product} × {qty}. Buyurtma bekor qilindi. Hamyondan tölagan bölsangiz, pul hamyoningizga qaytariladi.' },
    ru: { title: 'Продавец отклонил заказ', body: '{product} × {qty}. Заказ отменён. Если вы оплатили из кошелька, деньги вернутся в кошелёк.' },
  },
  ws_seller_timeout_buyer: {
    uz_Cyrl: { title: 'Буюртма бекор бўлди', body: '{product} × {qty}. Сотувчи белгиланган муддатда жавоб бермади. Ҳамёндан тўлаган бўлсангиз, пул ҳамёнингизга қайтарилади.' },
    uz_Latn: { title: 'Buyurtma bekor böldi', body: '{product} × {qty}. Sotuvçi belgilangan muddatda javob bermadi. Hamyondan tölagan bölsangiz, pul hamyoningizga qaytariladi.' },
    ru: { title: 'Заказ отменён', body: '{product} × {qty}. Продавец не ответил в установленный срок. Если вы оплатили из кошелька, деньги вернутся в кошелёк.' },
  },
  ws_seller_timeout_seller: {
    uz_Cyrl: { title: 'Буюртма муддати ўтди — бекор қилинди', body: '{product} × {qty}. Буюртма {deadline} гача қабул қилинмагани учун бекор бўлди.' },
    uz_Latn: { title: 'Buyurtma muddati ötdi — bekor qilindi', body: '{product} × {qty}. Buyurtma {deadline} gaça qabul qilinmagani uçun bekor böldi.' },
    ru: { title: 'Срок истёк — заказ отменён', body: '{product} × {qty}. Заказ отменён, так как не был принят до {deadline}.' },
  },
  // ── Банк ўтказмаси (ega, 2026-11-13/14). Товар пули иловадан ТАШҚАРИДА — матнларда товар пулини
  // «қайтариш» ҳақида гап ЙЎҚ (ega, 2026-11-14). {goods} — товар суммаси, {bankDeadline} — қабул + 5 иш куни
  // (Тошкент вақти), {refund}/{left} — фақат етказиш ҳақи (йўқолганда, масъул курьердан).
  ws_bank_await_buyer: {
    uz_Cyrl: { title: 'Сотувчи қабул қилди — тўловни ўтказинг', body: '{product} × {qty}. Товар суммаси {goods} сўмни сотувчи берадиган ҳисоб-фактура бўйича банк орқали {bankDeadline} гача ўтказинг. Сотувчи пул тушганини тасдиқлагач, етказиш бошланади. Муддатда тасдиқланмаса, буюртма бекор бўлади ва етказиш ҳақи ҳамёнингизга қайтади.' },
    uz_Latn: { title: 'Sotuvçi qabul qildi — tölovni ötkazing', body: '{product} × {qty}. Tovar summasi {goods} sömni sotuvçi beradigan hisob-faktura böyiça bank orqali {bankDeadline} gaça ötkazing. Sotuvçi pul tuşganini tasdiqlagaç, yetkaziş boşlanadi. Muddatda tasdiqlanmasa, buyurtma bekor böladi va yetkaziş haqi hamyoningizga qaytadi.' },
    ru: { title: 'Продавец принял заказ — оплатите', body: '{product} × {qty}. Переведите {goods} сум за товар банковским переводом по счёту продавца до {bankDeadline}. Доставка начнётся после того, как продавец подтвердит поступление. Если подтверждения не будет в срок, заказ отменится, а стоимость доставки вернётся в кошелёк.' },
  },
  ws_bank_await_seller: {
    uz_Cyrl: { title: 'Банк ўтказмасини кутинг', body: '{product} × {qty}. Харидорга {goods} сўмга ҳисоб-фактура беринг. Пул ҳисобингизга тушгач, {bankDeadline} гача «Пул тушди» ни босинг — шундан кейин етказиш бошланади. Муддатда тасдиқланмаса, буюртма бекор бўлади.' },
    uz_Latn: { title: 'Bank ötkazmasini kuting', body: '{product} × {qty}. Xaridorga {goods} sömga hisob-faktura bering. Pul hisobingizga tuşgaç, {bankDeadline} gaça «Pul tuşdi» ni bosing — şundan keyin yetkaziş boşlanadi. Muddatda tasdiqlanmasa, buyurtma bekor böladi.' },
    ru: { title: 'Ожидайте банковский перевод', body: '{product} × {qty}. Выставьте покупателю счёт на {goods} сум. Когда деньги поступят на ваш счёт, нажмите «Деньги поступили» до {bankDeadline} — после этого начнётся доставка. Без подтверждения в срок заказ будет отменён.' },
  },
  ws_bank_confirmed_buyer: {
    uz_Cyrl: { title: 'Сотувчи тўловни тасдиқлади', body: '{product} × {qty}. Етказиш тайёрланмоқда — ҳолатини буюртма саҳифасида кузатинг.' },
    uz_Latn: { title: 'Sotuvçi tölovni tasdiqladi', body: '{product} × {qty}. Yetkaziş tayyorlanmoqda — holatini buyurtma sahifasida kuzating.' },
    ru: { title: 'Продавец подтвердил оплату', body: '{product} × {qty}. Доставка готовится — следите за статусом на странице заказа.' },
  },
  ws_bank_timeout_buyer: {
    uz_Cyrl: { title: 'Буюртма бекор бўлди', body: '{product} × {qty}. Сотувчи {bankDeadline} гача тўлов тушганини тасдиқламади. Етказиш ҳақи ҳамёнингизга қайтарилади.' },
    uz_Latn: { title: 'Buyurtma bekor böldi', body: '{product} × {qty}. Sotuvçi {bankDeadline} gaça tölov tuşganini tasdiqlamadi. Yetkaziş haqi hamyoningizga qaytariladi.' },
    ru: { title: 'Заказ отменён', body: '{product} × {qty}. Продавец не подтвердил поступление оплаты до {bankDeadline}. Стоимость доставки вернётся в ваш кошелёк.' },
  },
  ws_bank_timeout_seller: {
    uz_Cyrl: { title: 'Буюртма бекор қилинди', body: '{product} × {qty}. Тўлов тушгани {bankDeadline} гача тасдиқланмагани учун буюртма бекор бўлди.' },
    uz_Latn: { title: 'Buyurtma bekor qilindi', body: '{product} × {qty}. Tölov tuşgani {bankDeadline} gaça tasdiqlanmagani uçun buyurtma bekor böldi.' },
    ru: { title: 'Заказ отменён', body: '{product} × {qty}. Заказ отменён, так как поступление оплаты не было подтверждено до {bankDeadline}.' },
  },
  ws_bank_buyer_cancelled_seller: {
    uz_Cyrl: { title: 'Харидор буюртмани бекор қилди', body: '{product} × {qty}. Банк ўтказмаси кутилаётган буюртма ёпилди.' },
    uz_Latn: { title: 'Xaridor buyurtmani bekor qildi', body: '{product} × {qty}. Bank ötkazmasi kutilayotgan buyurtma yopildi.' },
    ru: { title: 'Покупатель отменил заказ', body: '{product} × {qty}. Заказ, ожидавший банковского перевода, закрыт.' },
  },
  ws_bank_lost_buyer: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Етказиш ҳақи {refund} сўм ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Yetkaziş haqi {refund} söm hamyoningizga qaytarildi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Стоимость доставки {refund} сум возвращена в ваш кошелёк.' },
  },
  ws_bank_lost_buyer_partial: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Етказиш ҳақидан {refund} сўм ҳамёнингизга қайтарилди, қолган {left} сўм масъул курьер тўлагач қайтарилади.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Yetkaziş haqidan {refund} söm hamyoningizga qaytarildi, qolgan {left} söm mas\'ul kuryer tölagaç qaytariladi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Из стоимости доставки в кошелёк возвращено {refund} сум, оставшиеся {left} сум вернутся после оплаты ответственным курьером.' },
  },
  // ── Сотувчининг ўз етказиши (S4, ega 2026-11-13/14). Ички атамалар (LEG, зона) кўрсатилмайди (45-банд).
  // {goods} — товар суммаси, {amount} — картага тўланадиган сумма (фақат товар).
  ws_self_accepted_buyer: {
    uz_Cyrl: { title: 'Сотувчи қабул қилди — ўзи етказади', body: '{product} × {qty}. Сотувчи товарни ўзи олиб келади. Йўлга чиққанда хабар келади.' },
    uz_Latn: { title: 'Sotuvçi qabul qildi — özi yetkazadi', body: '{product} × {qty}. Sotuvçi tovarni özi olib keladi. Yölga çiqqanda xabar keladi.' },
    ru: { title: 'Продавец принял заказ — доставит сам', body: '{product} × {qty}. Продавец привезёт товар сам. Когда он выедет, придёт уведомление.' },
  },
  ws_self_start_seller: {
    uz_Cyrl: { title: 'Буюртмани ўзингиз етказасиз', body: '{product} × {qty}. Йўлга чиққанда буюртма саҳифасида «Етказишни бошлаш» ни босинг. Топширганда харидор айтган кодни киритинг.' },
    uz_Latn: { title: 'Buyurtmani özingiz yetkazasiz', body: '{product} × {qty}. Yölga çiqqanda buyurtma sahifasida «Yetkazişni boşlaş» ni bosing. Topşirganda xaridor aytgan kodni kiriting.' },
    ru: { title: 'Вы доставляете заказ сами', body: '{product} × {qty}. Когда выедете, нажмите «Начать доставку» на странице заказа. При передаче введите код, который назовёт покупатель.' },
  },
  ws_self_started_buyer: {
    uz_Cyrl: { title: 'Сотувчи йўлга чиқди', body: '{product} × {qty}. Товарни олганингизда буюртма саҳифасидаги етказиш кодини сотувчига айтинг.' },
    uz_Latn: { title: 'Sotuvçi yölga çiqdi', body: '{product} × {qty}. Tovarni olganingizda buyurtma sahifasidagi yetkaziş kodini sotuvçiga ayting.' },
    ru: { title: 'Продавец выехал', body: '{product} × {qty}. При получении товара назовите продавцу код со страницы заказа.' },
  },
  ws_self_started_buyer_card: {
    uz_Cyrl: { title: 'Сотувчи йўлга чиқди', body: '{product} × {qty}. Товарни олганда {amount} сўмни сотувчи картасига ўтказинг. Сотувчи пул тушганини тасдиқлагач, етказиш коди буюртма саҳифасида чиқади — уни сотувчига айтинг.' },
    uz_Latn: { title: 'Sotuvçi yölga çiqdi', body: '{product} × {qty}. Tovarni olganda {amount} sömni sotuvçi kartasiga ötkazing. Sotuvçi pul tuşganini tasdiqlagaç, yetkaziş kodi buyurtma sahifasida çiqadi — uni sotuvçiga ayting.' },
    ru: { title: 'Продавец выехал', body: '{product} × {qty}. При получении переведите {amount} сум на карту продавца. После подтверждения оплаты на странице заказа появится код — назовите его продавцу.' },
  },
  ws_self_delivered_buyer: {
    uz_Cyrl: { title: 'Буюртма топширилди', body: '{product} × {qty}. Харидингиз учун раҳмат!' },
    uz_Latn: { title: 'Buyurtma topşirildi', body: '{product} × {qty}. Xaridingiz uçun rahmat!' },
    ru: { title: 'Заказ получен', body: '{product} × {qty}. Спасибо за покупку!' },
  },
  ws_self_delivered_seller: {
    uz_Cyrl: { title: 'Буюртма топширилди', body: '{product} × {qty}. Етказиш тасдиқланди.' },
    uz_Latn: { title: 'Buyurtma topşirildi', body: '{product} × {qty}. Yetkaziş tasdiqlandi.' },
    ru: { title: 'Заказ передан', body: '{product} × {qty}. Доставка подтверждена.' },
  },
  ws_self_refused_buyer_wallet: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: сотувчи товар топширилмади деб белгилади. Товар суммаси ҳамёнингизга қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: sotuvçi tovar topşirilmadi deb belgiladi. Tovar summasi hamyoningizga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: продавец отметил, что товар не передан. Сумма за товар вернётся в ваш кошелёк.' },
  },
  ws_self_refused_buyer: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: сотувчи товар топширилмади деб белгилади. Буюртма ёпилди.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: sotuvçi tovar topşirilmadi deb belgiladi. Buyurtma yopildi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: продавец отметил, что товар не передан. Заказ закрыт.' },
  },
  // ── Карта, етказиш ҳақини харидор тўлайди (S6, ega 2026-11-13).
  ws_refused_seller_newcard: {
    uz_Cyrl: { title: 'Товар етказилмади — сизга қайтарилади', body: '{product} × {qty}. Қайтариш етказиш ҳақини сиз тўламайсиз, AVA улуши ҳамёнингизга қайтарилади.' },
    uz_Latn: { title: 'Tovar yetkazilmadi — sizga qaytariladi', body: '{product} × {qty}. Qaytariş yetkaziş haqini siz tölamaysiz, AVA uluşi hamyoningizga qaytariladi.' },
    ru: { title: 'Товар не доставлен — возвращается к вам', body: '{product} × {qty}. Обратную доставку вы не оплачиваете, комиссия AVA возвращается в ваш кошелёк.' },
  },
  ws_refused_buyer_card_fee: {
    uz_Cyrl: { title: 'Қайтариш ҳақи ушланди', body: '{product}: товар етказилмади. Қайтариш етказиш ҳақи {returnFee} сўм ҳамёнингиздан ушланди. Етказиш ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Qaytariş haqi uşlandi', body: '{product}: tovar yetkazilmadi. Qaytariş yetkaziş haqi {returnFee} söm hamyoningizdan uşlandi. Yetkaziş haqi qaytarilmaydi.' },
    ru: { title: 'Списана стоимость обратной доставки', body: '{product}: товар не доставлен. С вашего кошелька списано {returnFee} сум за обратную доставку. Стоимость доставки не возвращается.' },
  },
  ws_lost_buyer_card_fee: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Буюртма ёпилди — товар учун тўламайсиз. Етказиш ҳақи {feeRefund} сўм ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Buyurtma yopildi — tovar uçun tölamaysiz. Yetkaziş haqi {feeRefund} söm hamyoningizga qaytarildi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Заказ закрыт — за товар платить не нужно. Стоимость доставки {feeRefund} сум возвращена в ваш кошелёк.' },
  },
  ws_lost_buyer_card_fee_partial: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Буюртма ёпилди — товар учун тўламайсиз. Етказиш ҳақидан {feeRefund} сўм қайтарилди, қолган {left} сўм масъул курьер тўлагач қайтарилади.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Buyurtma yopildi — tovar uçun tölamaysiz. Yetkaziş haqidan {feeRefund} söm qaytarildi, qolgan {left} söm mas\'ul kuryer tölagaç qaytariladi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Заказ закрыт — за товар платить не нужно. Из стоимости доставки возвращено {feeRefund} сум, оставшиеся {left} сум вернутся после оплаты ответственным курьером.' },
  },
  ws_card_new_order: {
    uz_Cyrl: { title: 'Янги буюртма — тўлов картангизга', body: '{product} × {qty}. Харидор етказилганда {amount} сўмни картангизга ўтказади. Пул тушгач «Пул тушди» тугмасини босинг.' },
    uz_Latn: { title: 'Yangi buyurtma — tölov kartangizga', body: '{product} × {qty}. Xaridor yetkazilganda {amount} sömni kartangizga ötkazadi. Pul tuşgaç «Pul tuşdi» tugmasini bosing.' },
    ru: { title: 'Новый заказ — оплата на вашу карту', body: '{product} × {qty}. Покупатель при доставке переведёт {amount} сум на вашу карту. Когда деньги поступят, нажмите «Деньги поступили».' },
  },
  ws_card_receipt: {
    uz_Cyrl: { title: 'Харидор тўлов чекини юборди', body: '{product}: {amount} сўм. Картангизни текширинг ва «Пул тушди» ни босинг. {minutes} дақиқада тасдиқланмаса, админ кўриб чиқади.' },
    uz_Latn: { title: 'Xaridor tölov çekini yubordi', body: '{product}: {amount} söm. Kartangizni tekşiring va «Pul tuşdi» ni bosing. {minutes} daqiqada tasdiqlanmasa, admin körib çiqadi.' },
    ru: { title: 'Покупатель отправил чек оплаты', body: '{product}: {amount} сум. Проверьте карту и нажмите «Деньги поступили». Если не подтвердить за {minutes} минут, заказ рассмотрит администратор.' },
  },
  ws_card_confirmed: {
    uz_Cyrl: { title: 'Тўлов тасдиқланди', body: 'Сотувчи {amount} сўм тушганини тасдиқлади. Етказиш коди буюртма саҳифасида — уни курьерга айтинг.' },
    uz_Latn: { title: 'Tölov tasdiqlandi', body: 'Sotuvçi {amount} söm tuşganini tasdiqladi. Yetkaziş kodi buyurtma sahifasida — uni kuryerga ayting.' },
    ru: { title: 'Оплата подтверждена', body: 'Продавец подтвердил поступление {amount} сум. Код получения — на странице заказа, назовите его курьеру.' },
  },
  ws_refused_buyer: {
    uz_Cyrl: { title: 'Буюртма бекор бўлди', body: '{product}: тўлов амалга ошмагани учун товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma bekor böldi', body: '{product}: tölov amalga oşmagani uçun tovar sotuvçiga qaytariladi.' },
    ru: { title: 'Заказ отменён', body: '{product}: оплата не состоялась, товар возвращается продавцу.' },
  },
  // ── Рад этилгач харидорга — САБАБГА қараб (ega, 2026-11-01). `ws_refused_buyer` (тўлов амалга ошмади) —
  // фақат админ низони рад этганда (карта) ва сабаб коди йўқ эски ёзувда.
  ws_refused_buyer_absent: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: курьер сизни топа олмади, буюртма «етказилмади» деб ёпилди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: kuryer sizni topa olmadi, buyurtma «yetkazilmadi» deb yopildi. Tovar sotuvçiga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: курьеру не удалось вас застать, заказ закрыт как «не доставлен». Товар возвращается продавцу.' },
  },
  ws_refused_buyer_refused: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: товар қабул қилинмади, буюртма «етказилмади» деб ёпилди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: tovar qabul qilinmadi, buyurtma «yetkazilmadi» deb yopildi. Tovar sotuvçiga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: получение товара не состоялось, заказ закрыт как «не доставлен». Товар возвращается продавцу.' },
  },
  ws_refused_buyer_courier: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: курьер сабабли товар етказилмади. Буюртма ёпилди, товар сотувчига қайтарилади. Сиздан пул олинмайди.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: kuryer sababli tovar yetkazilmadi. Buyurtma yopildi, tovar sotuvçiga qaytariladi. Sizdan pul olinmaydi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: товар не доставлен по причине со стороны курьера. Заказ закрыт, товар возвращается продавцу. Деньги с вас не списываются.' },
  },
  ws_refused_buyer_other: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '{product}: товар етказилмади, буюртма ёпилди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '{product}: tovar yetkazilmadi, buyurtma yopildi. Tovar sotuvçiga qaytariladi.' },
    ru: { title: 'Заказ закрыт', body: '{product}: товар не доставлен, заказ закрыт. Товар возвращается продавцу.' },
  },
  // Ҳамён буюртмаси — пул ҳисоблангач (default `settleWalletRefusalInTx`, `refundStatus: done`):
  // {refund} — қайтган товар суммаси, {returnFee} — ушланган қайтариш ҳақи.
  ws_refused_buyer_wallet: {
    uz_Cyrl: { title: 'Буюртма ёпилди — пул ҳамёнингизда', body: '{product}: товар етказилмади. Товар суммаси {refund} сўм ҳамёнингизга қайтарилди, қайтариш етказиш ҳақи {returnFee} сўм ушланди. Етказиш ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Buyurtma yopildi — pul hamyoningizda', body: '{product}: tovar yetkazilmadi. Tovar summasi {refund} söm hamyoningizga qaytarildi, qaytariş yetkaziş haqi {returnFee} söm uşlandi. Yetkaziş haqi qaytarilmaydi.' },
    ru: { title: 'Заказ закрыт — деньги в кошельке', body: '{product}: товар не доставлен. На ваш кошелёк возвращено {refund} сум за товар, удержано {returnFee} сум за обратную доставку. Стоимость доставки не возвращается.' },
  },
  ws_refused_buyer_wallet_courier: {
    uz_Cyrl: { title: 'Буюртма ёпилди — пул ҳамёнингизда', body: '{product}: курьер сабабли товар етказилмади. Товар суммаси {refund} сўм ҳамёнингизга қайтарилди. Қайтариш ҳақини курьер тўлайди, етказиш ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Buyurtma yopildi — pul hamyoningizda', body: '{product}: kuryer sababli tovar yetkazilmadi. Tovar summasi {refund} söm hamyoningizga qaytarildi. Qaytariş haqini kuryer tölaydi, yetkaziş haqi qaytarilmaydi.' },
    ru: { title: 'Заказ закрыт — деньги в кошельке', body: '{product}: товар не доставлен по причине со стороны курьера. На ваш кошелёк возвращено {refund} сум за товар. Обратную доставку оплачивает курьер, стоимость доставки не возвращается.' },
  },
  ws_refused_seller_wallet: {
    uz_Cyrl: { title: 'Товар етказилмади — сизга қайтарилади', body: '{product} × {qty}. Харидор ҳамёндан тўлаган буюртма: товар пули харидорга қайтарилади, қайтариш ҳақини сиз тўламайсиз.' },
    uz_Latn: { title: 'Tovar yetkazilmadi — sizga qaytariladi', body: '{product} × {qty}. Xaridor hamyondan tölagan buyurtma: tovar puli xaridorga qaytariladi, qaytariş haqini siz tölamaysiz.' },
    ru: { title: 'Товар не доставлен — возвращается к вам', body: '{product} × {qty}. Заказ оплачен из кошелька покупателя: деньги за товар возвращаются покупателю, обратную доставку вы не оплачиваете.' },
  },
  ws_return_fee_courier: {
    uz_Cyrl: { title: 'Қайтариш ҳақи ушланди', body: '{product}: «етказилмади» сабаби — курьер. Қайтариш етказиш ҳақи {returnFee} сўм ҳамёнингиздан ушланди.' },
    uz_Latn: { title: 'Qaytariş haqi uşlandi', body: '{product}: «yetkazilmadi» sababi — kuryer. Qaytariş yetkaziş haqi {returnFee} söm hamyoningizdan uşlandi.' },
    ru: { title: 'Списана стоимость обратной доставки', body: '{product}: причина «не доставлено» — курьер. С вашего кошелька списано {returnFee} сум за обратную доставку.' },
  },
  // Ҳамён рад, курьер айби, ҳамён етмади (ega, 2026-11-01): қолгани курьер қарзига, AVA вақтинча тўлади,
  // товар дарҳол қайтарилади. {returnFeeTotal} — қайтариш нархи, {returnFee} — ҳамёндан, {courierDebt} — қарз.
  ws_return_courier_debt: {
    uz_Cyrl: { title: 'Қайтариш ҳақи қарзингизга ёзилди', body: '{product}: «етказилмади» сабаби — курьер. Қайтариш етказиш ҳақи {returnFeeTotal} сўм: ҳамёнингиздан {returnFee} сўм ушланди, қолган {courierDebt} сўм қарзингизга ёзилди (AVA вақтинча тўлади).' },
    uz_Latn: { title: 'Qaytariş haqi qarzingizga yozildi', body: '{product}: «yetkazilmadi» sababi — kuryer. Qaytariş yetkaziş haqi {returnFeeTotal} söm: hamyoningizdan {returnFee} söm uşlandi, qolgan {courierDebt} söm qarzingizga yozildi (AVA vaqtinça töladi).' },
    ru: { title: 'Стоимость возврата записана в ваш долг', body: '{product}: причина «не доставлено» — курьер. Обратная доставка — {returnFeeTotal} сум: с кошелька списано {returnFee} сум, остаток {courierDebt} сум записан в ваш долг (временно оплачивается AVA).' },
  },
  ws_return_courier_debt_admin: {
    uz_Cyrl: { title: 'Улгуржи: курьер қарзи (қайтариш ҳақи)', body: 'Буюртма {orderId} (ҳамён): курьерда {courierDebt} сўм етмади — қарзига ёзилди, AVA вақтинча тўлади, товар қайтарилмоқда.' },
    uz_Latn: { title: 'Ulgurji: kuryer qarzi (qaytariş haqi)', body: 'Buyurtma {orderId} (hamyon): kuryerda {courierDebt} söm yetmadi — qarziga yozildi, AVA vaqtinça töladi, tovar qaytarilmoqda.' },
    ru: { title: 'Оптовый рынок: долг курьера (возврат)', body: 'Заказ {orderId} (кошелёк): у курьера не хватило {courierDebt} сум — записано в долг, временно оплачивается AVA, товар возвращается.' },
  },
  ws_return_debt_buyer: {
    uz_Cyrl: { title: 'Қайтариш ҳақи учун маблағ етмади', body: '{product}: яна {amount} сўм керак. Ҳамённи тўлдиринг — товар сотувчига шундан кейин қайтарилади.' },
    uz_Latn: { title: 'Qaytariş haqi uçun mablağ yetmadi', body: '{product}: yana {amount} söm kerak. Hamyonni töldiring — tovar sotuvçiga şundan keyin qaytariladi.' },
    ru: { title: 'Не хватает средств на обратную доставку', body: '{product}: нужно ещё {amount} сум. Пополните кошелёк — после этого товар вернётся продавцу.' },
  },
  ws_return_debt_courier: {
    uz_Cyrl: { title: 'Қайтариш ҳақи учун ҳамёнда маблағ етмади', body: '{product}: «етказилмади» сабаби — курьер. Яна {amount} сўм керак — ҳамённи тўлдиринг, товар сотувчига шундан кейин қайтарилади.' },
    uz_Latn: { title: 'Qaytariş haqi uçun hamyonda mablağ yetmadi', body: '{product}: «yetkazilmadi» sababi — kuryer. Yana {amount} söm kerak — hamyonni töldiring, tovar sotuvçiga şundan keyin qaytariladi.' },
    ru: { title: 'Не хватает средств на обратную доставку', body: '{product}: причина «не доставлено» — курьер. Нужно ещё {amount} сум — пополните кошелёк, после этого товар вернётся продавцу.' },
  },
  ws_return_debt_admin_buyer: {
    uz_Cyrl: { title: 'Улгуржи: харидорда қайтариш қарзи', body: 'Буюртма {orderId} (ҳамён): қайтариш учун харидорда {amount} сўм етишмаяпти.' },
    uz_Latn: { title: 'Ulgurji: xaridorda qaytariş qarzi', body: 'Buyurtma {orderId} (hamyon): qaytariş uçun xaridorda {amount} söm yetişmayapti.' },
    ru: { title: 'Оптовый рынок: долг покупателя за возврат', body: 'Заказ {orderId} (кошелёк): у покупателя не хватает {amount} сум на возврат.' },
  },
  ws_return_debt_admin_courier: {
    uz_Cyrl: { title: 'Улгуржи: курьерда қайтариш қарзи', body: 'Буюртма {orderId} (ҳамён): қайтариш учун курьерда {amount} сўм етишмаяпти.' },
    uz_Latn: { title: 'Ulgurji: kuryerda qaytariş qarzi', body: 'Buyurtma {orderId} (hamyon): qaytariş uçun kuryerda {amount} söm yetişmayapti.' },
    ru: { title: 'Оптовый рынок: долг курьера за возврат', body: 'Заказ {orderId} (кошелёк): у курьера не хватает {amount} сум на возврат.' },
  },
  ws_refused_seller: {
    uz_Cyrl: { title: 'Харидор тўламади — товар қайтарилади', body: '{product} × {qty}. Қайтариш етказиш ҳақи ҳамёнингиздан ушланади, AVA улуши қайтарилади.' },
    uz_Latn: { title: 'Xaridor tölamadi — tovar qaytariladi', body: '{product} × {qty}. Qaytariş yetkaziş haqi hamyoningizdan uşlanadi, AVA uluşi qaytariladi.' },
    ru: { title: 'Покупатель не оплатил — товар возвращается', body: '{product} × {qty}. Стоимость обратной доставки списывается с вашего кошелька, комиссия AVA возвращается.' },
  },
  // ── «Етказилмади» — харидор тасдиғи (ega, 2026-11-01; api/wholesale_failed.js). `{timeout}` —
  // server_config/customer_confirm.failedTimeoutMin (`{minutes}` — чек низоси, бошқа муддат).
  ws_df_buyer_confirm: {
    uz_Cyrl: { title: 'Курьер: товар етказилмади', body: '{product}: курьер товарни етказиб бўлмади деб белгилади. Буюртма саҳифасида тасдиқланг ёки «Олмоқчиман» ни босинг. {timeout} дақиқада жавоб бўлмаса, сотувчи ҳал қилади.' },
    uz_Latn: { title: 'Kuryer: tovar yetkazilmadi', body: '{product}: kuryer tovarni yetkazib bölmadi deb belgiladi. Buyurtma sahifasida tasdiqlang yoki «Olmoqçiman» ni bosing. {timeout} daqiqada javob bölmasa, sotuvçi hal qiladi.' },
    ru: { title: 'Курьер: товар не доставлен', body: '{product}: по отметке курьера товар не удалось доставить. Подтвердите на странице заказа или нажмите «Хочу получить». Если не ответить за {timeout} минут, решит продавец.' },
  },
  // ── S57: нақд етказиш ҳақи (ega 2026-11-14). {cashTotal} — етказиш + қайтариш ҳақи (сервер ҳисоби),
  // {deliveryFee} — етказиш ҳақи, {cashDebt} — тўланмаган қарз, {goodsRefund} — ҳамёнга қайтган товар суммаси.
  ws_df_buyer_confirm_cash_paid: {
    uz_Cyrl: { title: 'Курьер: товар етказилмади', body: '{product}: курьер товарни етказиб бўлмади ва сиздан етказиш ҳамда қайтариш ҳақи {cashTotal} сўм нақд олинди деб белгилади. Буюртма саҳифасида тасдиқланг ёки «Олмоқчиман» ни босинг. {timeout} дақиқада жавоб бўлмаса, сотувчи ҳал қилади.' },
    uz_Latn: { title: 'Kuryer: tovar yetkazilmadi', body: '{product}: kuryer tovarni yetkazib bölmadi va sizdan yetkaziş hamda qaytariş haqi {cashTotal} söm naqd olindi deb belgiladi. Buyurtma sahifasida tasdiqlang yoki «Olmoqçiman» ni bosing. {timeout} daqiqada javob bölmasa, sotuvçi hal qiladi.' },
    ru: { title: 'Курьер: товар не доставлен', body: '{product}: по отметке курьера товар не доставлен, с вас наличными получено {cashTotal} сум за доставку и возврат. Подтвердите на странице заказа или нажмите «Хочу получить». Если не ответить за {timeout} минут, решит продавец.' },
  },
  ws_df_buyer_confirm_cash_unpaid: {
    uz_Cyrl: { title: 'Курьер: товар етказилмади', body: '{product}: курьер товарни етказиб бўлмади деб белгилади. Етказиш ва қайтариш ҳақи {cashTotal} сўм тўланмаган — тасдиқласангиз, у сизнинг қарзингиз бўлиб ёзилади. Буюртма саҳифасида тасдиқланг ёки «Олмоқчиман» ни босинг.' },
    uz_Latn: { title: 'Kuryer: tovar yetkazilmadi', body: '{product}: kuryer tovarni yetkazib bölmadi deb belgiladi. Yetkaziş va qaytariş haqi {cashTotal} söm tölanmagan — tasdiqlasangiz, u sizning qarzingiz bölib yoziladi. Buyurtma sahifasida tasdiqlang yoki «Olmoqçiman» ni bosing.' },
    ru: { title: 'Курьер: товар не доставлен', body: '{product}: по отметке курьера товар не доставлен. Доставка и возврат ({cashTotal} сум) не оплачены — после подтверждения сумма будет записана как ваш долг. Подтвердите на странице заказа или нажмите «Хочу получить».' },
  },
  ws_cash_open_buyer: {
    uz_Cyrl: { title: 'Етказиш бошланди — ҳақни курьерга нақд тўлайсиз', body: '{product} × {qty}. Товарни олганингизда етказиш ҳақи {deliveryFee} сўмни курьерга нақд тўлайсиз.' },
    uz_Latn: { title: 'Yetkaziş boşlandi — haqni kuryerga naqd tölaysiz', body: '{product} × {qty}. Tovarni olganingizda yetkaziş haqi {deliveryFee} sömni kuryerga naqd tölaysiz.' },
    ru: { title: 'Доставка началась — оплата курьеру наличными', body: '{product} × {qty}. При получении товара оплатите курьеру доставку {deliveryFee} сум наличными.' },
  },
  ws_cash_refusal_paid_buyer: {
    uz_Cyrl: { title: 'Буюртма рад этилди', body: '{product} × {qty}. Етказиш ва қайтариш ҳақи {cashTotal} сўм курьерга нақд тўланди. Товар сотувчига қайтарилади.' },
    uz_Latn: { title: 'Buyurtma rad etildi', body: '{product} × {qty}. Yetkaziş va qaytariş haqi {cashTotal} söm kuryerga naqd tölandi. Tovar sotuvçiga qaytariladi.' },
    ru: { title: 'Заказ отклонён', body: '{product} × {qty}. Доставка и возврат ({cashTotal} сум) оплачены курьеру наличными. Товар вернётся продавцу.' },
  },
  ws_cash_refused_goods_refund_buyer: {
    uz_Cyrl: { title: 'Товар суммаси ҳамёнга қайтди', body: '{product} × {qty}. Рад этилган буюртманинг товар суммаси {goodsRefund} сўм ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Tovar summasi hamyonga qaytdi', body: '{product} × {qty}. Rad etilgan buyurtmaning tovar summasi {goodsRefund} söm hamyoningizga qaytarildi.' },
    ru: { title: 'Сумма за товар возвращена', body: '{product} × {qty}. Сумма за товар отклонённого заказа {goodsRefund} сум возвращена в ваш кошелёк.' },
  },
  ws_cash_debt_buyer: {
    uz_Cyrl: { title: 'Етказиш ҳақи бўйича қарзингиз бор', body: '{product}: рад этилган буюртманинг етказиш ва қайтариш ҳақи {cashDebt} сўм тўланмади. Қарз тўлангунча етказиш ҳақини нақд тўлаш усули ёпиқ.' },
    uz_Latn: { title: 'Yetkaziş haqi böyiça qarzingiz bor', body: '{product}: rad etilgan buyurtmaning yetkaziş va qaytariş haqi {cashDebt} söm tölanmadi. Qarz tölangunça yetkaziş haqini naqd tölaş usuli yopiq.' },
    ru: { title: 'У вас долг за доставку', body: '{product}: доставка и возврат отклонённого заказа ({cashDebt} сум) не оплачены. Пока долг не погашен, оплата доставки наличными недоступна.' },
  },
  ws_cash_debt_admin: {
    uz_Cyrl: { title: 'Улгуржи: харидорда нақд етказиш қарзи', body: 'Буюртма {orderId}: харидор рад этди ва {cashDebt} сўм (етказиш + қайтариш) тўламади. AVA олдинги курьерлар ва қайтаришни қоплади.' },
    uz_Latn: { title: 'Ulgurji: xaridorda naqd yetkaziş qarzi', body: 'Buyurtma {orderId}: xaridor rad etdi va {cashDebt} söm (yetkaziş + qaytariş) tölamadi. AVA oldingi kuryerlar va qaytarişni qopladi.' },
    ru: { title: 'Оптовый рынок: долг покупателя за доставку', body: 'Заказ {orderId}: покупатель отказался и не оплатил {cashDebt} сум (доставка + возврат). AVA покрыла предыдущих курьеров и возврат.' },
  },
  ws_chain_expired_buyer: {
    uz_Cyrl: { title: 'Буюртма бекор бўлди — курьер топилмади', body: '{product} × {qty}. Белгиланган муддатда етказиш занжири учун курьерлар топилмади. Ҳамёндан тўлаган бўлсангиз, пул ҳамёнингизга қайтарилади.' },
    uz_Latn: { title: 'Buyurtma bekor böldi — kuryer topilmadi', body: '{product} × {qty}. Belgilangan muddatda yetkaziş zanjiri uçun kuryerlar topilmadi. Hamyondan tölagan bölsangiz, pul hamyoningizga qaytariladi.' },
    ru: { title: 'Заказ отменён — курьеры не найдены', body: '{product} × {qty}. За отведённое время не удалось собрать курьеров для доставки. Если вы платили из кошелька, деньги вернутся в кошелёк.' },
  },
  ws_chain_expired_seller: {
    uz_Cyrl: { title: 'Буюртма бекор бўлди — курьер топилмади', body: '{product} × {qty}. Етказиш учун курьерлар муддатда топилмади, буюртма бекор қилинди. Товар қолдиғи тикланади.' },
    uz_Latn: { title: 'Buyurtma bekor böldi — kuryer topilmadi', body: '{product} × {qty}. Yetkaziş uçun kuryerlar muddatda topilmadi, buyurtma bekor qilindi. Tovar qoldiği tiklanadi.' },
    ru: { title: 'Заказ отменён — курьеры не найдены', body: '{product} × {qty}. Курьеры для доставки не найдены вовремя, заказ отменён. Остаток товара будет восстановлен.' },
  },
  ws_df_courier_wait: {
    uz_Cyrl: { title: 'Харидор тасдиғи кутилмоқда', body: '{product}: харидор {timeout} дақиқа ичида жавоб беради, кейин сотувчи ҳал қилади. Посилкани ўзингизда сақланг.' },
    uz_Latn: { title: 'Xaridor tasdiği kutilmoqda', body: '{product}: xaridor {timeout} daqiqa içida javob beradi, keyin sotuvçi hal qiladi. Posilkani özingizda saqlang.' },
    ru: { title: 'Ожидаем подтверждения покупателя', body: '{product}: покупатель ответит в течение {timeout} минут, затем решит продавец. Посылку держите при себе.' },
  },
  ws_df_courier_continue: {
    uz_Cyrl: { title: 'Етказишни давом эттиринг', body: '{product}: товар етказилсин деб қарор қилинди. Харидорга топширинг.' },
    uz_Latn: { title: 'Yetkazişni davom ettiring', body: '{product}: tovar yetkazilsin deb qaror qilindi. Xaridorga topşiring.' },
    ru: { title: 'Продолжайте доставку', body: '{product}: решено доставить товар. Передайте его покупателю.' },
  },
  ws_df_buyer_continue: {
    uz_Cyrl: { title: 'Товар етказилади', body: '{product}: курьер етказишни давом эттиради.' },
    uz_Latn: { title: 'Tovar yetkaziladi', body: '{product}: kuryer yetkazişni davom ettiradi.' },
    ru: { title: 'Товар будет доставлен', body: '{product}: курьер продолжит доставку.' },
  },
  ws_df_decide_seller: {
    uz_Cyrl: { title: 'Етказилмади — қарорингиз керак', body: '{product} × {qty}: харидор {timeout} дақиқада жавоб бермади. Буюртма саҳифасида «Етказилмади» ёки «Етказилсин» ни танланг.' },
    uz_Latn: { title: 'Yetkazilmadi — qaroringiz kerak', body: '{product} × {qty}: xaridor {timeout} daqiqada javob bermadi. Buyurtma sahifasida «Yetkazilmadi» yoki «Yetkazilsin» ni tanlang.' },
    ru: { title: 'Не доставлено — нужно ваше решение', body: '{product} × {qty}: ответа покупателя нет уже {timeout} минут. На странице заказа выберите «Не доставлено» или «Доставить».' },
  },
  ws_df_decide_admin: {
    uz_Cyrl: { title: 'Улгуржи: етказилмади — қарор', body: 'Буюртма {orderId}: харидор жавоб бермади. Сотувчи ёки админ ҳал қилади («Етказилмади — қарор»).' },
    uz_Latn: { title: 'Ulgurji: yetkazilmadi — qaror', body: 'Buyurtma {orderId}: xaridor javob bermadi. Sotuvçi yoki admin hal qiladi («Yetkazilmadi — qaror»).' },
    ru: { title: 'Оптовый рынок: не доставлено — решение', body: 'Заказ {orderId}: ответа покупателя нет. Решает продавец или администратор («Не доставлено — решение»).' },
  },
  ws_dispute_admin: {
    uz_Cyrl: { title: 'Улгуржи: тўлов низоси', body: 'Буюртма {orderId}: харидор чек юборган, сотувчи {minutes} дақиқада тасдиқламади. Админ панелида ҳал қилинг.' },
    uz_Latn: { title: 'Ulgurji: tölov nizosi', body: 'Buyurtma {orderId}: xaridor çek yuborgan, sotuvçi {minutes} daqiqada tasdiqlamadi. Admin panelida hal qiling.' },
    ru: { title: 'Оптовый рынок: спор по оплате', body: 'Заказ {orderId}: покупатель отправил чек, продавец не подтвердил за {minutes} минут. Решите в админ-панели.' },
  },
  ws_return_debt_seller: {
    uz_Cyrl: { title: 'Қайтариш учун ҳамёнда маблағ етарли эмас', body: '{amount} сўм керак. Ҳамённи тўлдиринг — шунгача картага тўлов усули ёпиқ.' },
    uz_Latn: { title: 'Qaytariş uçun hamyonda mablağ yetarli emas', body: '{amount} söm kerak. Hamyonni töldiring — şungaça kartaga tölov usuli yopiq.' },
    ru: { title: 'Недостаточно средств для возврата товара', body: 'Нужно {amount} сум. Пополните кошелёк — до этого оплата картой при доставке недоступна.' },
  },
  ws_return_debt_admin: {
    uz_Cyrl: { title: 'Улгуржи: сотувчида қайтариш қарзи', body: 'Буюртма {orderId}: қайтариш учун {amount} сўм етишмаяпти.' },
    uz_Latn: { title: 'Ulgurji: sotuvçida qaytariş qarzi', body: 'Buyurtma {orderId}: qaytariş uçun {amount} söm yetişmayapti.' },
    ru: { title: 'Оптовый рынок: долг продавца за возврат', body: 'Заказ {orderId}: для возврата не хватает {amount} сум.' },
  },
  ws_return_courier: {
    uz_Cyrl: { title: 'Қайтариш иши сизга бириктирилди', body: 'Товарни сотувчига қайтаринг ({tracking}). Олиш коди буюртма саҳифасида.' },
    uz_Latn: { title: 'Qaytariş işi sizga biriktirildi', body: 'Tovarni sotuvçiga qaytaring ({tracking}). Oliş kodi buyurtma sahifasida.' },
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
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Tovar puli {refund} söm hamyoningizga qaytarildi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Стоимость товара {refund} сум возвращена в ваш кошелёк.' },
  },
  // Yetkazish haqi ham qaytdi (ega, 2026-10-31) — `{refund}` = tovar puli + qaytgan yetkazish haqi.
  ws_lost_buyer_wallet_full: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Тўлаганингиз тўлиқ — товар пули ва етказиш ҳақи, жами {refund} сўм — ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Tölaganingiz töliq — tovar puli va yetkaziş haqi, jami {refund} söm — hamyoningizga qaytarildi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Вся оплата — стоимость товара и доставки, всего {refund} сум — возвращена в ваш кошелёк.' },
  },
  ws_lost_buyer_wallet_partial: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Ҳамёнингизга {refund} сўм қайтарилди. Етказиш ҳақининг қолган {left} сўми масъул курьер тўлагач қайтарилади.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Hamyoningizga {refund} söm qaytarildi. Yetkaziş haqining qolgan {left} sömi mas\'ul kuryer tölagaç qaytariladi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. В ваш кошелёк возвращено {refund} сум. Оставшиеся {left} сум за доставку вернутся, когда ответственный курьер их оплатит.' },
  },
  ws_lost_fee_done_buyer: {
    uz_Cyrl: { title: 'Етказиш ҳақи тўлиқ қайтарилди', body: '{product} × {qty}. Йўқолган товар бўйича етказиш ҳақи ({fee} сўм) тўлиқ ҳамёнингизга қайтарилди.' },
    uz_Latn: { title: 'Yetkaziş haqi töliq qaytarildi', body: '{product} × {qty}. Yöqolgan tovar böyiça yetkaziş haqi ({fee} söm) töliq hamyoningizga qaytarildi.' },
    ru: { title: 'Стоимость доставки возвращена полностью', body: '{product} × {qty}. Стоимость доставки утерянного товара ({fee} сум) полностью возвращена в ваш кошелёк.' },
  },
  ws_lost_fee_admin: {
    uz_Cyrl: { title: 'Улгуржи: йўқолган товар — етказиш ҳақи қолдиғи', body: 'Буюртма {orderId}: харидорга етказиш ҳақидан {left} сўм қайтарилмади (курьер ҳамёни етмади ёки текширув керак). Курьер тўлагач, тўловни ёзинг.' },
    uz_Latn: { title: 'Ulgurji: yöqolgan tovar — yetkaziş haqi qoldiği', body: 'Buyurtma {orderId}: xaridorga yetkaziş haqidan {left} söm qaytarilmadi (kuryer hamyoni yetmadi yoki tekşiruv kerak). Kuryer tölagaç, tölovni yozing.' },
    ru: { title: 'Оптовый рынок: утерянный товар — остаток за доставку', body: 'Заказ {orderId}: покупателю не возвращено {left} сум за доставку (не хватило средств курьера или нужна проверка). Когда курьер оплатит, внесите платёж.' },
  },
  ws_lost_buyer_card: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Буюртма ёпилди — сиз ҳеч нарса тўламайсиз.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Buyurtma yopildi — siz heç narsa tölamaysiz.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Заказ закрыт — вам ничего платить не нужно.' },
  },
  ws_lost_buyer_review: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди', body: '{product} × {qty}. Тўловингиз бўйича админ кўриб чиқади ва сиз билан боғланади.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi', body: '{product} × {qty}. Tölovingiz böyiça admin körib çiqadi va siz bilan boğlanadi.' },
    ru: { title: 'Товар утерян при доставке', body: '{product} × {qty}. Администратор рассмотрит вашу оплату и свяжется с вами.' },
  },
  ws_lost_seller: {
    uz_Cyrl: { title: 'Товар етказишда йўқолди — буюртма ёпилди', body: '{product} × {qty}. Товар қийматини масъул курьер қоплайди (логистика хабарида батафсил). Қолдиқ тикланмайди.' },
    uz_Latn: { title: 'Tovar yetkazişda yöqoldi — buyurtma yopildi', body: '{product} × {qty}. Tovar qiymatini mas\'ul kuryer qoplaydi (logistika xabarida batafsil). Qoldiq tiklanmaydi.' },
    ru: { title: 'Товар утерян при доставке — заказ закрыт', body: '{product} × {qty}. Стоимость товара возмещает ответственный курьер (подробности в уведомлении логистики). Остаток не восстанавливается.' },
  },
  ws_lost_review_admin: {
    uz_Cyrl: { title: 'Улгуржи: йўқолган товар — тўловни кўриб чиқинг', body: 'Буюртма {orderId}: харидор картага тўловни билдирган, товар йўқолди. Сотувчи товар қийматини курьердан олади — харидорга қайтаришни ҳал қилинг.' },
    uz_Latn: { title: 'Ulgurji: yöqolgan tovar — tölovni körib çiqing', body: 'Buyurtma {orderId}: xaridor kartaga tölovni bildirgan, tovar yöqoldi. Sotuvçi tovar qiymatini kuryerdan oladi — xaridorga qaytarişni hal qiling.' },
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
