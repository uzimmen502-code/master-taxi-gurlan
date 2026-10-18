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
/** Молия ходимларининг ҳаммасига: иловада + push + (боғланган бўлса) Telegram. */
async function broadcastToFinance({ db, notifyUserInApp, sendTelegram, title, body, tgText, extraData }) {
  const snap = await db.collection('users')
    .where('role', 'in', FINANCE_ROLES)
    .limit(MAX_RECIPIENTS)
    .get();
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
        extraData,
      });
      notified += 1;
    } catch (_) { /* best-effort */ }
    const tg = String(d.telegramId || '').trim();
    if (tg && sendTelegram) {
      try { await sendTelegram(tg, tgText); } catch (_) { /* best-effort */ }
    }
  }));
  return { notified, recipients: snap.size };
}

function makeFinanceNotifier({ db, notifyUserInApp, sendTelegram }) {
  return async function notifyFinanceQueue({ kind, requestId, amount }) {
    const isTopUp = kind === 'topup';
    const title = isTopUp ? 'Тўлдириш чеки текширув кутмоқда' : 'Янги ечиш аризаси';
    const body = `${money(amount)} сўм · ${String(requestId).slice(0, 8)}`;
    const tgText = isTopUp
      ? `🧾 <b>Янги чек</b> — ${money(amount)} сўм\nID: <code>${requestId}</code>\n`
        + 'Админ → Молия → Telegram ҳамён → «Тўлдириш» навбати.'
      : `📤 <b>Ечиш аризаси</b> — ${money(amount)} сўм\nID: <code>${requestId}</code>\n`
        + 'Админ → Молия → Telegram ҳамён → «Ечиш» навбати.';
    return broadcastToFinance({
      db, notifyUserInApp, sendTelegram, title, body, tgText,
      extraData: { requestId: String(requestId), kind: String(kind) },
    });
  };
}

/** «…4821» — картанинг охирги 4 рақами (тўлиқ рақам ҳеч қаерда кўрсатилмайди). */
function cardLast4(raw) {
  const s = String(raw == null ? '' : raw).replace(/\D/g, '');
  return s.length >= 4 ? s.slice(-4) : '';
}

/**
 * Депозит картаси ўзгарганда молия ходимларига огоҳлантириш: картани
 * тасодифан ёки ёвуз ниятда алмаштирса, бошқа ходимлар дарҳол билади.
 * Хабарда ТЎЛИҚ рақам йўқ — фақат охирги 4 рақам (push ва Telegram'га ўтади).
 * `actor` — ўзгартирувчининг кўринадиган номи (исм ва роль).
 */
function makeCardChangeNotifier({ db, notifyUserInApp, sendTelegram }) {
  return async function notifyCardChanged({ oldCard, newCard, actor }) {
    const from = cardLast4(oldCard);
    const to = cardLast4(newCard);
    const fromTxt = from ? `…${from}` : 'йўқ';
    const toTxt = to ? `…${to}` : 'олиб ташланди';
    const who = String(actor || 'номаълум');
    const title = 'Депозит картаси ўзгартирилди';
    const body = `${fromTxt} → ${toTxt} · ${who}`;
    const tgText = `💳 <b>Депозит картаси ўзгартирилди</b>\nЭски: ${fromTxt} → Янги: ${toTxt}\n`
      + `Ким: ${who}\nАгар бу сиз эмасдингиз, дарҳол супер-админга хабар беринг.`;
    return broadcastToFinance({
      db, notifyUserInApp, sendTelegram, title, body, tgText,
      extraData: { kind: 'card_changed' },
    });
  };
}

const TOPUP_COL = 'wallet_topup_requests';

/**
 * Ботга илова берган сумма: `t.me/<бот>?start=deposit_150000` → `/start
 * deposit_150000`. Фақат ТАКЛИФ — лимитларни (`maxTopUp`, кунлик) бот барибир
 * `createTopUpRequest`да текширади. Нотўғри/бўш → 0.
 */
function parseDepositPayload(payload) {
  const m = /^deposit_(\d{1,9})$/.exec(String(payload == null ? '' : payload).trim());
  return m ? Number(m[1]) : 0;
}

/**
 * Иловадан келган кутилаётган сумма (боғлаш коди билан бирга сақланади).
 * Бутун сон, 1..max; акс ҳолда 0 (сумма ЭЪТИБОРСИЗ қолдирилади, хато эмас:
 * боғлаш йўли суммадаги нуқсон туфайли бузилмасин).
 */
function sanitizePendingAmount(v, max) {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return 0;
  return n <= Number(max) ? n : 0;
}

/**
 * Чек юборилмаган эски сўровларни `expired` қилади (sweeper).
 *
 * Нега: бот `awaiting_transfer` сўровга `expiresAt` (24 соат) ёзади, лекин уни
 * ҳеч ким ўзгартирмасди — иловада «муддати тугади» ҳисоблаб кўрсатилар
 * (`effectiveStatus`), омборда эса сўров абадий «кутилмоқда» қолар эди.
 *
 * Хавфсизлик:
 *  - пул ЎЗГАРМАЙДИ: фақат `awaiting_transfer` (чек ҳали келмаган, ҳамёнга
 *    ҳеч нарса тушмаган) → `expired`;
 *  - ҳар ҳужжат ТРАНЗАКЦИЯДА қайта текширилади: шу пайт чек келиб
 *    `awaiting_review` бўлган бўлса тегилмайди (рейс ҳолати);
 *  - идемпотент: қайта ишга тушса `expired` ҳужжатни қайта сўрамайди
 *    (сўров `status == awaiting_transfer` бўйича);
 *  - мавжуд индекс (`status` ASC, `createdAt` DESC) ишлатилади — янги индекс
 *    керак эмас. ⚠️ Йўналиш аниқ шу бўлиши шарт: композит индекс тескари
 *    йўналишда ишламайди (production'да `createdAt ASC` сўрови
 *    FAILED_PRECONDITION берди; Firestore эмулятори индексни текширмайди,
 *    шунинг учун тест буни ушлай олмайди).
 *
 * `createdAt` камайиш тартибида (янгилари биринчи) саҳифалаб ўтилади:
 * `awaiting_transfer` ҳужжатлар оз (тозаланиб туради), шунинг учун ҳаммасини
 * `startAfter` курсори билан кўриб чиқиш арзон.
 */
async function sweepExpiredTopUps({
  db, admin, nowMs = Date.now(), ttlMs, batchSize = 200, maxRounds = 10,
}) {
  let expired = 0;
  let skipped = 0;
  let scanned = 0;
  let cursor = null;
  for (let round = 0; round < maxRounds; round += 1) {
    let q = db.collection(TOPUP_COL)
      .where('status', '==', 'awaiting_transfer')
      .orderBy('createdAt', 'desc')
      .limit(batchSize);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    scanned += snap.size;
    cursor = snap.docs[snap.docs.length - 1];

    const dueOf = (data) => {
      const exp = data.expiresAt && data.expiresAt.toMillis ? data.expiresAt.toMillis() : 0;
      if (exp) return exp <= nowMs;
      const created = data.createdAt && data.createdAt.toMillis ? data.createdAt.toMillis() : 0;
      return created > 0 && ttlMs > 0 && created + ttlMs <= nowMs;
    };

    const due = snap.docs.filter((d) => dueOf(d.data() || {}));
    for (const doc of due) {
      const done = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        const data = fresh.exists ? (fresh.data() || {}) : null;
        if (!data || data.status !== 'awaiting_transfer' || !dueOf(data)) return false;
        tx.update(doc.ref, {
          status: 'expired',
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (done) expired += 1; else skipped += 1;
    }
    if (snap.size < batchSize) break;
  }
  return { expired, skipped, scanned };
}

module.exports = {
  cardIsValid,
  topUpReadiness,
  makeFinanceNotifier,
  makeCardChangeNotifier,
  cardLast4,
  sweepExpiredTopUps,
  parseDepositPayload,
  sanitizePendingAmount,
  FINANCE_ROLES,
};
