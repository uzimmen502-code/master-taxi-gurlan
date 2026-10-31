/**
 * Серверда ёзиладиган хабарлар — УЧ ТИЛДА (uz_Cyrl / uz_Latn / ru).
 *
 * Тил қоидаси (эга, 2026-10-15): матн ўзгарса учала тил бирга. Фойдаланувчи
 * тили ИЛОВАДА сақланади; сервер уни `users/{id}.appLang` дан ўқийди
 * (илова `fcm_service`/тил ўзгарганда ёзади). Майдон йўқ (эски илова) —
 * `uz_Cyrl` (аввалги ҳолат, тахмин қилинмайди).
 *
 * Фақат ҳозирча ўтказилган хабарлар шу ерда: шаҳарлараро автоматик суриш ва
 * йўқолган посилка (`lost_*`, AVA Logistics).
 * Калит → тил → { title, body }; `{name}` ўринбосарлар `render`да.
 */
'use strict';

const DEFAULT_LANG = 'uz_Cyrl';
const LANGS = ['uz_Cyrl', 'uz_Latn', 'ru'];

const MESSAGES = {
  auto_shift_driver: {
    uz_Cyrl: { title: '⏱ Рейс {hours} соатга сурилди', body: 'Салон тўлмади. Янги жўнаш вақти {time} ({n}/{max}).' },
    uz_Latn: { title: '⏱ Reys {hours} soatga surildi', body: 'Salon to\'lmadi. Yangi jo\'nash vaqti {time} ({n}/{max}).' },
    ru: { title: '⏱ Рейс перенесён на {hours} ч.', body: 'Салон не заполнен. Новое время отправления {time} ({n}/{max}).' },
  },
  auto_shift_passenger: {
    uz_Cyrl: { title: '🕐 Рейс вақти ўзгарди', body: 'Жўнаш {time} га сурилди. Қулай бўлмаса бронни бекор қилишингиз мумкин.' },
    uz_Latn: { title: '🕐 Reys vaqti o\'zgardi', body: 'Jo\'nash {time} ga surildi. Qulay bo\'lmasa bronni bekor qilishingiz mumkin.' },
    ru: { title: '🕐 Время рейса изменилось', body: 'Отправление перенесено на {time}. Если неудобно, можно отменить бронь.' },
  },
  auto_shift_stop_cap: {
    uz_Cyrl: { title: '⏱ Рейс автоматик сурилмайди', body: 'Бугунги суриш лимити ({max} марта) тугади. Янги вақтни ўзингиз белгиланг ёки рейсни тугатинг.' },
    uz_Latn: { title: '⏱ Reys avtomatik surilmaydi', body: 'Bugungi surish limiti ({max} marta) tugadi. Yangi vaqtni o\'zingiz belgilang yoki reysni tugating.' },
    ru: { title: '⏱ Рейс больше не переносится автоматически', body: 'Лимит переносов на сегодня ({max}) исчерпан. Укажите новое время сами или завершите рейс.' },
  },
  china_quote_ready: {
    uz_Cyrl: { title: '🇨🇳 Хитой сўровингизга таклиф келди', body: '{refNo} бўйича таклифни иловада кўришингиз мумкин.' },
    uz_Latn: { title: '🇨🇳 Xitoy so\'rovingizga taklif keldi', body: '{refNo} bo\'yicha taklifni ilovada ko\'rishingiz mumkin.' },
    ru: { title: '🇨🇳 Получено предложение по запросу в Китай', body: 'Предложение по {refNo} можно посмотреть в приложении.' },
  },
  auto_shift_stop_midnight: {
    uz_Cyrl: { title: '⏱ Рейс автоматик сурилмайди', body: 'Жўнаш вақти кеч бўлгани учун рейс бугун яна сурилмайди. Янги кунга кўчиринг ёки тугатинг.' },
    uz_Latn: { title: '⏱ Reys avtomatik surilmaydi', body: 'Jo\'nash vaqti kech bo\'lgani uchun reys bugun yana surilmaydi. Yangi kunga ko\'chiring yoki tugating.' },
    ru: { title: '⏱ Рейс больше не переносится автоматически', body: 'Время отправления слишком позднее, поэтому рейс сегодня больше не переносится. Перенесите на другой день или завершите.' },
  },

  // ── Ҳайдовчи рейсни қўлда кўчирди (`rescheduleTaxiTrip`, audit H6, 2026-10). Матн PROPOSED —
  // эга тасдиқлайди (рус тили ҳам). `{date}` — КК.ОО, `{time}` — СС:ДД (Тошкент).
  reschedule_passenger: {
    uz_Cyrl: { title: '🕐 Рейс вақти ўзгарди', body: 'Рейс {date} куни соат {time} га кўчирилди. Қулай бўлмаса бронни бекор қилишингиз мумкин.' },
    uz_Latn: { title: '🕐 Reys vaqti o\'zgardi', body: 'Reys {date} kuni soat {time} ga ko\'chirildi. Qulay bo\'lmasa bronni bekor qilishingiz mumkin.' },
    ru: { title: '🕐 Время рейса изменилось', body: 'Отправление перенесено на {date}, {time}. Если неудобно, можно отменить бронь.' },
  },

  // ── Йўқолган посилка (AVA Logistics, D1, 2026-10-16). Матнлар PROPOSED — эга тасдиқлайди
  // (рус тили ҳам ҳали эга кўриб чиқмаган). `{amount}` — посилка қиймати G, `{left}` — қолган қарз.
  lost_customer_full: {
    uz_Cyrl: { title: 'Жўнатма йўқолди — пул қайтарилди', body: '{tracking} жўнатмаси йўқолган деб топилди. Посилка қиймати {amount} сўм ҳисобингизга қайтарилди. Етказиб бериш хизмати ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Jo\'natma yo\'qoldi — pul qaytarildi', body: '{tracking} jo\'natmasi yo\'qolgan deb topildi. Posilka qiymati {amount} so\'m hisobingizga qaytarildi. Yetkazib berish xizmati haqi qaytarilmaydi.' },
    ru: { title: 'Посылка утеряна — деньги возвращены', body: 'Посылка {tracking} признана утерянной. Стоимость посылки {amount} сум возвращена на ваш счёт. Плата за доставку не возвращается.' },
  },
  lost_customer_partial: {
    uz_Cyrl: { title: 'Жўнатма йўқолди — пул қисман қайтарилди', body: '{tracking} жўнатмаси йўқолган деб топилди. Посилка қийматидан {amount} сўм ҳисобингизга қайтарилди. Қолган {left} сўм курьер тўлаганидан кейин қўшилади. Етказиб бериш хизмати ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Jo\'natma yo\'qoldi — pul qisman qaytarildi', body: '{tracking} jo\'natmasi yo\'qolgan deb topildi. Posilka qiymatidan {amount} so\'m hisobingizga qaytarildi. Qolgan {left} so\'m kuryer to\'laganidan keyin qo\'shiladi. Yetkazib berish xizmati haqi qaytarilmaydi.' },
    ru: { title: 'Посылка утеряна — деньги возвращены частично', body: 'Посылка {tracking} признана утерянной. Из стоимости посылки {amount} сум возвращено на ваш счёт. Оставшиеся {left} сум будут добавлены после оплаты курьером. Плата за доставку не возвращается.' },
  },
  lost_customer_none: {
    uz_Cyrl: { title: 'Жўнатма йўқолди', body: '{tracking} жўнатмаси йўқолган деб топилди. Посилка қиймати ({amount} сўм) курьер тўлаганидан кейин ҳисобингизга қайтарилади. Етказиб бериш хизмати ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Jo\'natma yo\'qoldi', body: '{tracking} jo\'natmasi yo\'qolgan deb topildi. Posilka qiymati ({amount} so\'m) kuryer to\'laganidan keyin hisobingizga qaytariladi. Yetkazib berish xizmati haqi qaytarilmaydi.' },
    ru: { title: 'Посылка утеряна', body: 'Посылка {tracking} признана утерянной. Стоимость посылки ({amount} сум) будет возвращена на ваш счёт после оплаты курьером. Плата за доставку не возвращается.' },
  },
  lost_customer_payment: {
    uz_Cyrl: { title: 'Ҳисобингизга пул қўшилди', body: '{tracking} жўнатмаси бўйича {amount} сўм ҳисобингизга қайтарилди. Қолган: {left} сўм.' },
    uz_Latn: { title: 'Hisobingizga pul qo\'shildi', body: '{tracking} jo\'natmasi bo\'yicha {amount} so\'m hisobingizga qaytarildi. Qolgan: {left} so\'m.' },
    ru: { title: 'На ваш счёт поступили деньги', body: 'По посылке {tracking} на ваш счёт возвращено {amount} сум. Осталось: {left} сум.' },
  },
  lost_customer_done: {
    uz_Cyrl: { title: 'Посилка қиймати тўлиқ қайтарилди', body: '{tracking} жўнатмаси бўйича посилка қиймати тўлиқ қайтарилди (жами {total} сўм).' },
    uz_Latn: { title: 'Posilka qiymati to\'liq qaytarildi', body: '{tracking} jo\'natmasi bo\'yicha posilka qiymati to\'liq qaytarildi (jami {total} so\'m).' },
    ru: { title: 'Стоимость посылки возвращена полностью', body: 'По посылке {tracking} стоимость возвращена полностью (всего {total} сум).' },
  },
  lost_courier: {
    uz_Cyrl: { title: 'Жўнатма йўқолган деб белгиланди', body: '{tracking} жўнатмаси сизда йўқолган деб белгиланди. Ҳисобингиздан {taken} сўм ечилди. Қолган қарз: {left} сўм.' },
    uz_Latn: { title: 'Jo\'natma yo\'qolgan deb belgilandi', body: '{tracking} jo\'natmasi sizda yo\'qolgan deb belgilandi. Hisobingizdan {taken} so\'m yechildi. Qolgan qarz: {left} so\'m.' },
    ru: { title: 'Посылка отмечена как утерянная', body: 'Посылка {tracking} отмечена как утерянная у вас. С вашего счёта списано {taken} сум. Остаток долга: {left} сум.' },
  },

  // ── Мижоз тасдиғи («Олдим» / «Бердим», D2/D7, 2026-10-16). Курьер қадамини мижоз ўз қурилмасида
  // тасдиқлайди (`customer_confirm.js`). Матнлар PROPOSED — эга тасдиқлайди (рус тили ҳам).
  // Мижозга ички атамалар (LEG, зона, settlement…) кўрсатилмайди (45-банд).
  // `{summary}` — маҳсулот ва миқдор, `{amount}` — жами сўм (бўшлиқ билан).
  confirm_restaurant_received: {
    uz_Cyrl: { title: 'Буюртмани олдингизми?', body: 'Курьер буюртмани етказдим деб белгилади. Буюртмани олганингизни тасдиқланг.' },
    uz_Latn: { title: 'Buyurtmani oldingizmi?', body: 'Kuryer buyurtmani yetkazdim deb belgiladi. Buyurtmani olganingizni tasdiqlang.' },
    ru: { title: 'Вы получили заказ?', body: 'Курьер отметил, что доставил заказ. Подтвердите, что вы его получили.' },
  },
  confirm_carpet_pickup: {
    uz_Cyrl: { title: 'Гиламни курьерга бердингизми?', body: 'Курьер гиламни олдим деб белгилади. Гиламни курьерга берганингизни тасдиқланг.' },
    uz_Latn: { title: 'Gilamni kuryerga berdingizmi?', body: 'Kuryer gilamni oldim deb belgiladi. Gilamni kuryerga berganingizni tasdiqlang.' },
    ru: { title: 'Вы передали ковёр курьеру?', body: 'Курьер отметил, что забрал ковёр. Подтвердите, что вы передали ковёр курьеру.' },
  },
  confirm_carpet_return: {
    uz_Cyrl: { title: 'Гиламингизни олдингизми?', body: 'Курьер гиламни етказдим деб белгилади. Гиламни қайтиб олганингизни тасдиқланг.' },
    uz_Latn: { title: 'Gilamingizni oldingizmi?', body: 'Kuryer gilamni yetkazdim deb belgiladi. Gilamni qaytib olganingizni tasdiqlang.' },
    ru: { title: 'Вы получили ковёр обратно?', body: 'Курьер отметил, что доставил ковёр. Подтвердите, что вы получили его обратно.' },
  },
  confirm_agro_pickup: {
    uz_Cyrl: { title: 'Маҳсулотни курьерга бердингизми?', body: 'Курьер маҳсулотни олдим деб белгилади. Курьерга берганингизни тасдиқланг.' },
    uz_Latn: { title: 'Mahsulotni kuryerga berdingizmi?', body: 'Kuryer mahsulotni oldim deb belgiladi. Kuryerga berganingizni tasdiqlang.' },
    ru: { title: 'Вы передали продукцию курьеру?', body: 'Курьер отметил, что забрал продукцию. Подтвердите, что вы передали её курьеру.' },
  },
  confirm_collection_finalize: {
    uz_Cyrl: { title: 'Курьер ёзган миқдорни тасдиқлайсизми?', body: 'Курьер қуйидагини ёзди: {summary}. Жами: {amount} сўм. Тўғри бўлса, тасдиқланг — шундан кейин ҳисоб-китоб амалга ошади.' },
    uz_Latn: { title: 'Kuryer yozgan miqdorni tasdiqlaysizmi?', body: 'Kuryer quyidagini yozdi: {summary}. Jami: {amount} so\'m. To\'g\'ri bo\'lsa, tasdiqlang — shundan keyin hisob-kitob amalga oshadi.' },
    ru: { title: 'Подтверждаете количество, указанное курьером?', body: 'Курьер указал: {summary}. Итого: {amount} сум. Если всё верно, подтвердите — после этого будет произведён расчёт.' },
  },
};

/** Номаълум/бўш → `uz_Cyrl`. */
function normalizeLang(v) {
  const s = String(v || '');
  return LANGS.includes(s) ? s : DEFAULT_LANG;
}

function render(key, lang, params = {}) {
  const m = MESSAGES[key];
  if (!m) throw new Error(`notif_i18n: unknown key ${key}`);
  const t = m[normalizeLang(lang)];
  const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => (params[k] === undefined ? `{${k}}` : String(params[k])));
  return { title: fill(t.title), body: fill(t.body) };
}

/** `users/{999…|9 рақам}` ҳужжатидан тил (бир марта ўқиш; хато — default). */
async function langOfPhone(db, phone) {
  const d = String(phone || '').replace(/\D/g, '');
  const ids = d.length === 9 ? [`998${d}`, d] : [d];
  for (const id of ids) {
    try {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return normalizeLang((s.data() || {}).appLang);
    } catch (_) { /* default */ }
  }
  return DEFAULT_LANG;
}

/** `langOfPhone`нинг транзакция ичидаги варианти (ёзишдан ОЛДИН чақирилади). */
async function langOfPhoneTx(tx, db, phone) {
  const d = String(phone || '').replace(/\D/g, '');
  const ids = d.length === 9 ? [`998${d}`, d] : [d];
  for (const id of ids) {
    const s = await tx.get(db.collection('users').doc(id));
    if (s.exists) return normalizeLang((s.data() || {}).appLang);
  }
  return DEFAULT_LANG;
}

module.exports = { MESSAGES, LANGS, DEFAULT_LANG, normalizeLang, render, langOfPhone, langOfPhoneTx };
