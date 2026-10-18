/**
 * Ҳамённи тўлдириш (Telegram бот, «Phase 0» — қўлда тасдиқ): ёрдамчи мантиқ.
 *
 *  1) Депозит картаси рақами текширилади (`cardIsValid`): аввал сервер ҳар
 *     қандай матнни қабул қиларди ва у фойдаланувчиларга «пулни шу картага
 *     ўтказинг» деб кўрсатиларди — битта хато рақам пулни нотўғри картага
 *     йўналтирарди.
 *  2) Тайёрлик ҳолати (`topUpReadiness`): бот ўчиқ ёки карта йўқ/нотўғри бўлса
 *     иловада фойдаланувчи ботга боришдан ОЛДИН билади («Карта ҳали
 *     созланмаган» деган боғланмайдиган йўл ўрнига).
 *  3) Молия навбати хабари (`makeFinanceNotifier`): чек ёки ечиш аризаси
 *     келганда молия/супер-админга хабар (иловада + push + Telegram, боғланган
 *     бўлса). Аввал сигнал йўқ эди — навбатни ўзи очиб кузатиш керак эди.
 */
'use strict';

/** 16 рақам + Луна алгоритми (Uzcard/Humo/Visa/MC ҳаммаси ўтади). */
function cardIsValid(raw) {
  const s = String(raw == null ? '' : raw).replace(/[\s-]/g, '');
  if (!/^\d{16}$/.test(s)) return false;
  let sum = 0;
  for (let i = 0; i < 16; i += 1) {
    let d = Number(s[15 - i]);
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 === 0;
}

/**
 * `settings` — `loadBotSettings()` натижаси. `reason`: `ok` | `bot_disabled` |
 * `card_missing` | `card_invalid`.
 *
 * `card_invalid` (Луна текширувидан ўтмаган, аввал текширувсиз сақланган
 * карта) тўлдиришни БЛОКЛАМАЙДИ (`ready: true`): production'даги ишлаётган
 * карта нотўғри деб топилса, тўлдириш тўсатдан тўхтаб қолмасин. Ҳолат
 * админ панелда қизил огоҳлантириш бўлиб кўринади; янги қиймат эса
 * `adminSetWalletBotSettings`да текширилади.
 */
function topUpReadiness(settings) {
  const s = settings || {};
  if (s.enabled === false) return { ready: false, reason: 'bot_disabled' };
  const card = String(s.depositCardNumber || '').replace(/\s+/g, '');
  if (!card) return { ready: false, reason: 'card_missing' };
  if (!cardIsValid(card)) return { ready: true, reason: 'card_invalid' };
  return { ready: true, reason: 'ok' };
}

const FINANCE_ROLES = ['finance', 'superadmin'];
const MAX_RECIPIENTS = 20;

const money = (n) => Number(n || 0).toLocaleString('uz-UZ');

/**
 * Молия навбатига хабар берувчи (`notifyFinanceQueue`).
 *
 * `kind`: `topup` (чек текширув кутмоқда) | `withdraw` (ечиш аризаси).
 * Хабарда телефон/карта йўқ — фақат сумма ва сўров ID'си. Ҳар қабул
 * қилувчига алоҳида `try/catch`: биттасининг хатоси қолганларга ва асосий
 * оқимга (чек қабул қилиш) таъсир қилмайди.
 */
function makeFinanceNotifier({ db, notifyUserInApp, sendTelegram }) {
  return async function notifyFinanceQueue({ kind, requestId, amount }) {
    const snap = await db.collection('users')
      .where('role', 'in', FINANCE_ROLES)
      .limit(MAX_RECIPIENTS)
      .get();
    const isTopUp = kind === 'topup';
    const title = isTopUp ? 'Тўлдириш чеки текширув кутмоқда' : 'Янги ечиш аризаси';
    const body = `${money(amount)} сўм · ${String(requestId).slice(0, 8)}`;
    const tgText = isTopUp
      ? `🧾 <b>Янги чек</b> — ${money(amount)} сўм\nID: <code>${requestId}</code>\n`
        + 'Админ → Молия → Telegram ҳамён → «Тўлдириш» навбати.'
      : `📤 <b>Ечиш аризаси</b> — ${money(amount)} сўм\nID: <code>${requestId}</code>\n`
        + 'Админ → Молия → Telegram ҳамён → «Ечиш» навбати.';

    let notified = 0;
    await Promise.all(snap.docs.map(async (doc) => {
      const d = doc.data() || {};
      try {
        await notifyUserInApp({
          userId: doc.id,
          title,
          body,
          category: 'wallet_finance',
          source: 'wallet_finance_queue',
          dataType: 'wallet_finance_queue',
          screen: 'news',
          extraData: { requestId: String(requestId), kind: String(kind) },
        });
        notified += 1;
      } catch (_) { /* best-effort */ }
      const tg = String(d.telegramId || '').trim();
      if (tg && sendTelegram) {
        try { await sendTelegram(tg, tgText); } catch (_) { /* best-effort */ }
      }
    }));
    return { notified, recipients: snap.size };
  };
}

module.exports = {
  cardIsValid,
  topUpReadiness,
  makeFinanceNotifier,
  FINANCE_ROLES,
};
