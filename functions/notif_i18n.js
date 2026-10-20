/**
 * Серверда ёзиладиган хабарлар — УЧ ТИЛДА (uz_Cyrl / uz_Latn / ru).
 *
 * Тил қоидаси (эга, 2026-10-15): матн ўзгарса учала тил бирга. Фойдаланувчи
 * тили ИЛОВАДА сақланади; сервер уни `users/{id}.appLang` дан ўқийди
 * (илова `fcm_service`/тил ўзгарганда ёзади). Майдон йўқ (эски илова) —
 * `uz_Cyrl` (аввалги ҳолат, тахмин қилинмайди).
 *
 * Фақат ҳозирча ўтказилган хабарлар шу ерда: шаҳарлараро автоматик суриш.
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

module.exports = { MESSAGES, LANGS, DEFAULT_LANG, normalizeLang, render, langOfPhone };
