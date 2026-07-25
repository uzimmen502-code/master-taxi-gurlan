/**
 * AVA Zona — Telegram Wallet Bot (Phase 0)
 * Docs: docs/telegram_wallet_bot_architecture.md
 *
 * Bot = UI only. Money via Settlement Ledger (cashExchange / walletToCash).
 */
'use strict';

const TOPUP_COL = 'wallet_topup_requests';
const WITHDRAW_COL = 'wallet_withdraw_requests';
const LINK_COL = 'telegram_links';
const CODE_COL = 'telegram_link_codes';
const SESSION_COL = 'telegram_bot_sessions';
const SETTINGS_DOC = 'settings/wallet_bot';

const DEFAULT_MAX_TOPUP = 500000;
const DEFAULT_DAILY_TOPUP = 1000000;
const DEFAULT_MAX_WITHDRAW = 500000;
/** Админ танлайдиган ечиш авто-лимитлари (сўм). */
const WITHDRAW_AUTO_LIMITS = [20000, 50000, 100000];
const DEFAULT_WITHDRAW_AUTO_LIMIT = 20000;
const LINK_TTL_MS = 10 * 60 * 1000;
const REQUEST_TTL_MS = 24 * 60 * 60 * 1000;

function normalizeWithdrawAutoLimit(v) {
  const n = Math.trunc(Number(v) || 0);
  return WITHDRAW_AUTO_LIMITS.includes(n) ? n : DEFAULT_WITHDRAW_AUTO_LIMIT;
}

function attachTelegramWalletBot(exports, deps) {
  const {
    functions,
    db,
    admin,
    settlementLedger,
    requireCallerRoles,
    canonicalUid,
    notifyUserInApp,
    isIdentifiedUser,
  } = deps;

  function tgConfig() {
    // Modern env (functions/.env) — functions.config() deprecated (EOL Mar 2027).
    return {
      token: String(process.env.TELEGRAM_WALLET_BOT_TOKEN || '').trim(),
      username: String(process.env.TELEGRAM_WALLET_BOT_USERNAME || '')
          .trim()
          .replace(/^@/, ''),
      secret: String(process.env.TELEGRAM_WALLET_WEBHOOK_SECRET || '').trim(),
    };
  }

  async function loadBotSettings() {
    const snap = await db.doc(SETTINGS_DOC).get();
    const d = snap.exists ? (snap.data() || {}) : {};
    return {
      enabled: d.enabled !== false,
      depositCardNumber: String(d.depositCardNumber || '').trim(),
      depositCardFirstName: String(d.depositCardFirstName || '').trim(),
      depositCardLastName: String(d.depositCardLastName || '').trim(),
      // Legacy single field — used if first/last empty.
      depositCardHolder: String(d.depositCardHolder || '').trim(),
      depositInstructions: String(d.depositInstructions || '').trim(),
      maxTopUp: Math.trunc(Number(d.maxTopUp) || DEFAULT_MAX_TOPUP),
      dailyTopUpLimit: Math.trunc(Number(d.dailyTopUpLimit) || DEFAULT_DAILY_TOPUP),
      maxWithdraw: Math.trunc(Number(d.maxWithdraw) || DEFAULT_MAX_WITHDRAW),
      // manual (default) | auto — чек келгач админсиз ҳамёнга ёзиш
      topUpApproveMode:
          String(d.topUpApproveMode || 'manual').toLowerCase() === 'auto'
            ? 'auto'
            : 'manual',
      // manual (default) | auto — лимит ичида админсиз walletToCash
      withdrawApproveMode:
          String(d.withdrawApproveMode || 'manual').toLowerCase() === 'auto'
            ? 'auto'
            : 'manual',
      withdrawAutoLimit: normalizeWithdrawAutoLimit(d.withdrawAutoLimit),
    };
  }

  async function creditTopUpRequest({
    requestId, req, callerUid, auto = false,
  }) {
    const amount = Math.trunc(Number(req.amount || 0));
    const uid = canonicalUid(req.uid);
    const tgChat = req.telegramChatId || req.telegramUserId;
    if (!uid || amount <= 0) {
      throw new Error('So\'rov buzilgan');
    }
    const opId = `topup_${requestId}`;
    await runCashExchangeInternal({
      callerUid,
      userUid12: uid,
      amount,
      opId,
      meta: {
        topupRequestId: requestId,
        channel: 'telegram_card_manual',
        approveMode: auto ? 'auto' : 'manual',
      },
    });

    const ref = db.collection(TOPUP_COL).doc(requestId);
    await ref.set({
      status: 'credited',
      reviewedBy: callerUid,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      creditedAt: admin.firestore.FieldValue.serverTimestamp(),
      ledgerOpId: opId,
      approveMode: auto ? 'auto' : 'manual',
    }, { merge: true });

    if (tgChat) {
      await tgSend(tgChat,
          `✅ Ҳамёнга <b>+${amount}</b> сўм тушди.\nСўров: <code>${requestId}</code>` +
          (auto ? '\n(авто тасдиқ)' : ''));
    }
    try {
      await notifyUserInApp({
        userId: uid,
        title: 'Ҳамён тўлдирилди',
        body: `+${amount} сўм (Telegram)`,
        category: 'wallet',
        source: 'wallet_telegram_topup',
        dataType: 'wallet_topup_credited',
        screen: 'wallet',
        extraData: { requestId, amount: String(amount) },
      });
    } catch (_) { /* ignore */ }

    const userSnap = await db.collection('users').doc(uid).get();
    const bonusBalance = userSnap.exists
        ? (parseInt(String((userSnap.data() || {}).bonusBalance ?? 0), 10) || 0)
        : 0;
    return { ok: true, status: 'credited', amount, bonusBalance };
  }

  async function tgApi(method, body) {
    const { token } = tgConfig();
    if (!token) throw new Error('Telegram wallet bot token not configured');
    const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    const json = await res.json();
    if (!json.ok) {
      console.error('tgApi', method, json);
      throw new Error(json.description || 'telegram api error');
    }
    return json.result;
  }

  async function tgSend(chatId, text, extra = {}) {
    try {
      await tgApi('sendMessage', {
        chat_id: chatId,
        text: String(text || '').slice(0, 4000),
        parse_mode: 'HTML',
        ...extra,
      });
    } catch (e) {
      console.error('tgSend:', e.message || e);
    }
  }

  async function resolveUidByTelegram(tgId) {
    const id = String(tgId || '').trim();
    if (!id) return null;
    const snap = await db.collection(LINK_COL).doc(id).get();
    if (!snap.exists) return null;
    const d = snap.data() || {};
    if (d.status && d.status !== 'active') return null;
    return canonicalUid(d.uid);
  }

  async function getSession(tgId) {
    const snap = await db.collection(SESSION_COL).doc(String(tgId)).get();
    return snap.exists ? (snap.data() || {}) : {};
  }

  async function setSession(tgId, patch) {
    await db.collection(SESSION_COL).doc(String(tgId)).set({
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  async function clearSession(tgId) {
    await db.collection(SESSION_COL).doc(String(tgId)).delete().catch(() => {});
  }

  async function sumCreditedTopUpsToday(uid) {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const snap = await db.collection(TOPUP_COL)
        .where('uid', '==', uid)
        .where('status', '==', 'credited')
        .limit(200)
        .get();
    let sum = 0;
    const startMs = start.getTime();
    snap.forEach((doc) => {
      const x = doc.data() || {};
      const t = x.creditedAt && x.creditedAt.toMillis ? x.creditedAt.toMillis() : 0;
      if (t && t < startMs) return;
      sum += parseInt(String(x.amount ?? 0), 10) || 0;
    });
    return sum;
  }

  async function runCashExchangeInternal({
    callerUid, userUid12, amount, opId, meta = {},
  }) {
    const pcAcc = settlementLedger.passengerCreditAccount(userUid12);
    await settlementLedger.postEntry(db, {
      idempotencyKey: `cashExchange_in:${opId}`,
      kind: 'cash_in',
      refType: 'cash_exchange',
      refId: opId,
      postedBy: callerUid,
      postedRole: 'finance',
      legs: [
        { account: 'admin_cash', dr: amount },
        { account: 'admin_clearing', cr: amount },
      ],
    }, {
      mirrorBonus: false,
      meta: { userUid: userUid12, amount, step: 'cash_in', ...meta },
    });

    await settlementLedger.postEntry(db, {
      idempotencyKey: `cashExchange_wallet:${opId}`,
      kind: 'cash_to_wallet',
      refType: 'cash_exchange',
      refId: opId,
      postedBy: callerUid,
      postedRole: 'finance',
      legs: [
        { account: 'admin_clearing', dr: amount },
        { account: pcAcc, cr: amount },
      ],
    }, {
      mirrorBonus: true,
      walletLedgerType: 'cash_to_wallet',
      meta: {
        userUid: userUid12,
        amount,
        step: 'cash_to_wallet',
        source: 'telegram',
        ...meta,
      },
    });
  }

  async function runWalletToCashInternal({
    callerUid, userUid12, amount, opId, meta = {},
  }) {
    const pcAcc = settlementLedger.passengerCreditAccount(userUid12);
    await settlementLedger.postEntry(db, {
      idempotencyKey: `walletToCash:${opId}`,
      kind: 'wallet_to_cash',
      refType: 'wallet_to_cash',
      refId: opId,
      postedBy: callerUid,
      postedRole: 'finance',
      legs: [
        { account: pcAcc, dr: amount },
        { account: 'admin_cash', cr: amount },
      ],
    }, {
      mirrorBonus: true,
      walletLedgerType: 'wallet_to_cash',
      meta: { userUid: userUid12, amount, source: 'telegram', ...meta },
      assert: ({ accounts }) => {
        const pc = accounts.get(pcAcc);
        if (pc && pc.next < 0) {
          throw new functions.https.HttpsError(
              'failed-precondition',
              'Hamyon yetarli emas (manfiy taqiqlangan)');
        }
      },
    });
  }

  function shouldAutoApproveWithdraw(settings, amount) {
    return settings.withdrawApproveMode === 'auto'
        && amount > 0
        && amount <= settings.withdrawAutoLimit;
  }

  /** pending → approved/paid + walletToCash (manual yoki auto). */
  async function approveWithdrawInternal({
    requestId, req, callerUid, markPaid = false, auto = false,
  }) {
    const amount = Math.trunc(Number(req.amount || 0));
    const uid = canonicalUid(req.uid);
    const tgChat = req.telegramChatId || req.telegramUserId;
    if (!uid || amount <= 0) {
      throw new Error('So\'rov buzilgan');
    }
    const opId = `withdraw_${requestId}`;
    await runWalletToCashInternal({
      callerUid,
      userUid12: uid,
      amount,
      opId,
      meta: {
        withdrawRequestId: requestId,
        channel: req.source || 'telegram',
        approveMode: auto ? 'auto' : 'manual',
      },
    });

    const ref = db.collection(WITHDRAW_COL).doc(requestId);
    await ref.set({
      status: markPaid ? 'paid' : 'approved',
      reviewedBy: callerUid,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      ledgerOpId: opId,
      approveMode: auto ? 'auto' : 'manual',
      ...(markPaid
        ? {
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          paidBy: callerUid,
        }
        : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    if (tgChat) {
      await tgSend(tgChat, markPaid
          ? `💸 Ечиш тасдиқланди ва тўланди: <b>${amount}</b> сўм.`
          : (`✅ Ечиш тасдиқланди: <b>${amount}</b> сўм. Тўлов йўналтирилади.`
              + (auto ? '\n(авто тасдиқ)' : '')));
    }
    try {
      await notifyUserInApp({
        userId: uid,
        title: 'Ечиш тасдиқланди',
        body: `${amount} сўм` + (auto ? ' (авто)' : ''),
        category: 'wallet',
        source: auto ? 'wallet_withdraw_auto' : 'wallet_withdraw',
        dataType: 'wallet_withdraw_approved',
        screen: 'wallet',
        extraData: { requestId },
      });
    } catch (_) { /* ignore */ }

    return { ok: true, status: markPaid ? 'paid' : 'approved', amount, auto };
  }

  async function maybeAutoApproveWithdraw(requestId, settings) {
    if (!settings || settings.withdrawApproveMode !== 'auto') return null;
    const snap = await db.collection(WITHDRAW_COL).doc(requestId).get();
    if (!snap.exists) return null;
    const req = snap.data() || {};
    if (req.status !== 'pending') return null;
    const amount = Math.trunc(Number(req.amount || 0));
    if (!shouldAutoApproveWithdraw(settings, amount)) return null;
    try {
      return await approveWithdrawInternal({
        requestId,
        req,
        callerUid: 'wallet_withdraw_auto',
        markPaid: false,
        auto: true,
      });
    } catch (e) {
      console.error('auto withdraw approve failed', requestId, e);
      return null;
    }
  }

  async function downloadTelegramFileToStorage(fileId, storagePath) {
    const { token } = tgConfig();
    const file = await tgApi('getFile', { file_id: fileId });
    const filePath = file.file_path;
    if (!filePath) throw new Error('no file_path');
    const url = `https://api.telegram.org/file/bot${token}/${filePath}`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`download failed ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    const bucket = admin.storage().bucket();
    const contentType = filePath.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    const f = bucket.file(storagePath);
    await f.save(buf, { contentType, metadata: { cacheControl: 'private' } });
    return storagePath;
  }

  // ─── Callable: create link code (from Flutter app) ───────────────
  exports.createTelegramLinkCode = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const tokenPhone = String(
        (context.auth.token && context.auth.token.phone_number) || '')
        .replace(/\D/g, '');
    const uid = canonicalUid(
        (data && (data.phone || data.userPhone)) || tokenPhone);
    if (!uid || uid.length < 12) {
      throw new functions.https.HttpsError('invalid-argument', 'phone kerak');
    }
    // Faqat o'z telefoni uchun kod.
    if (tokenPhone) {
      const tokenUid = canonicalUid(tokenPhone);
      if (tokenUid && tokenUid !== uid) {
        throw new functions.https.HttpsError(
            'permission-denied', 'Faqat o\'z raqamingiz');
      }
    }
    if (!(await isIdentifiedUser(uid))) {
      throw new functions.https.HttpsError(
          'failed-precondition', 'Avval ilovada ro\'yxatdan o\'ting');
    }
    // Invalidate previous unused codes for this uid (best-effort).
    const old = await db.collection(CODE_COL)
        .where('uid', '==', uid)
        .where('used', '==', false)
        .limit(10)
        .get();
    const batch = db.batch();
    old.forEach((d) => batch.update(d.ref, { used: true, revoked: true }));
    await batch.commit().catch(() => {});

    let code = '';
    for (let i = 0; i < 8; i++) {
      code = String(Math.floor(100000 + Math.random() * 900000));
      const exists = await db.collection(CODE_COL).doc(code).get();
      if (!exists.exists) break;
    }
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + LINK_TTL_MS);
    await db.collection(CODE_COL).doc(code).set({
      uid,
      used: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    });
    const { username } = tgConfig();
    return {
      ok: true,
      code,
      expiresInSec: Math.floor(LINK_TTL_MS / 1000),
      botUsername: username || null,
      deepLink: username ? `https://t.me/${username}?start=link_${code}` : null,
    };
  });

  // ─── Callable: app withdraw request (own wallet → cash via admin) ─
  exports.requestWalletWithdraw = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const tokenPhone = String(
        (context.auth.token && context.auth.token.phone_number) || '')
        .replace(/\D/g, '');
    const uid = canonicalUid(
        (data && (data.phone || data.userPhone)) || tokenPhone);
    if (!uid || uid.length < 12) {
      throw new functions.https.HttpsError('invalid-argument', 'phone kerak');
    }
    if (tokenPhone) {
      const tokenUid = canonicalUid(tokenPhone);
      if (tokenUid && tokenUid !== uid) {
        throw new functions.https.HttpsError(
            'permission-denied', 'Faqat o\'z raqamingiz');
      }
    }
    if (!(await isIdentifiedUser(uid))) {
      throw new functions.https.HttpsError(
          'failed-precondition', 'Avval ilovada ro\'yxatdan o\'ting');
    }

    const settings = await loadBotSettings();
    const amount = Math.trunc(Number((data && data.amount) || 0));
    if (amount <= 0 || amount > settings.maxWithdraw) {
      throw new functions.https.HttpsError(
          'invalid-argument',
          `Сумма 1…${settings.maxWithdraw} оралиғида бўлсин`);
    }

    const card = String((data && data.payoutCardNumber) || '')
        .replace(/\D/g, '');
    const holder = String((data && data.payoutCardHolder) || '')
        .trim()
        .slice(0, 80);
    if (card.length < 16 || card.length > 19 || !holder) {
      throw new functions.https.HttpsError(
          'invalid-argument', 'Карта рақами ва эгаси керак');
    }

    const userSnap = await db.collection('users').doc(uid).get();
    const bal = userSnap.exists
        ? (parseInt(String((userSnap.data() || {}).bonusBalance ?? 0), 10) || 0)
        : 0;
    if (amount > bal) {
      throw new functions.https.HttpsError(
          'failed-precondition', `Yetarli emas. Баланс: ${bal} сўм`);
    }

    const pending = await db.collection(WITHDRAW_COL)
        .where('uid', '==', uid)
        .where('status', '==', 'pending')
        .limit(1)
        .get();
    if (!pending.empty) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'Аллақачон кутилаётган ечиш аризаси бор');
    }

    const ref = db.collection(WITHDRAW_COL).doc();
    await ref.set({
      uid,
      amount,
      currency: 'UZS',
      status: 'pending',
      source: 'app',
      payoutCardNumber: card,
      payoutCardHolder: holder,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const autoRes = await maybeAutoApproveWithdraw(ref.id, settings);
    if (autoRes && autoRes.ok) {
      return {
        ok: true,
        requestId: ref.id,
        amount,
        status: autoRes.status,
        auto: true,
      };
    }

    try {
      await notifyUserInApp({
        userId: uid,
        title: 'Ечиш аризаси',
        body: `${amount} сўм — админ текширувида`,
        category: 'wallet',
        source: 'wallet_app_withdraw',
        dataType: 'wallet_withdraw_pending',
        screen: 'wallet',
        extraData: { requestId: ref.id },
      });
    } catch (_) { /* ignore */ }

    return { ok: true, requestId: ref.id, amount, status: 'pending' };
  });

  // ─── Callable: bot settings ──────────────────────────────────────
  exports.adminGetWalletBotSettings = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(
        context, ['superadmin', 'finance'], 'Finance role required');
    const settings = await loadBotSettings();
    const { username } = tgConfig();
    return { ok: true, settings, botUsername: username || null };
  });

  exports.adminSetWalletBotSettings = functions.https.onCall(async (data, context) => {
    const caller = await requireCallerRoles(
        context, ['superadmin', 'finance'], 'Finance role required');
    const patch = {};
    if (data && typeof data.enabled === 'boolean') patch.enabled = data.enabled;
    if (data && data.depositCardNumber != null) {
      patch.depositCardNumber = String(data.depositCardNumber).replace(/\s+/g, '');
    }
    if (data && data.depositCardFirstName != null) {
      patch.depositCardFirstName =
          String(data.depositCardFirstName).trim().slice(0, 40);
    }
    if (data && data.depositCardLastName != null) {
      patch.depositCardLastName =
          String(data.depositCardLastName).trim().slice(0, 40);
    }
    if (data && (data.depositCardFirstName != null || data.depositCardLastName != null)) {
      const cur = await loadBotSettings();
      const first = String(
          data.depositCardFirstName != null
            ? data.depositCardFirstName
            : cur.depositCardFirstName).trim().slice(0, 40);
      const last = String(
          data.depositCardLastName != null
            ? data.depositCardLastName
            : cur.depositCardLastName).trim().slice(0, 40);
      patch.depositCardHolder = [first, last].filter(Boolean).join(' ').slice(0, 80);
    } else if (data && data.depositCardHolder != null) {
      patch.depositCardHolder = String(data.depositCardHolder).trim().slice(0, 80);
    }
    if (data && data.depositInstructions != null) {
      patch.depositInstructions = String(data.depositInstructions).trim().slice(0, 500);
    }
    if (data && data.maxTopUp != null) {
      patch.maxTopUp = Math.max(1000, Math.trunc(Number(data.maxTopUp) || DEFAULT_MAX_TOPUP));
    }
    if (data && data.dailyTopUpLimit != null) {
      patch.dailyTopUpLimit = Math.max(
          1000, Math.trunc(Number(data.dailyTopUpLimit) || DEFAULT_DAILY_TOPUP));
    }
    if (data && data.maxWithdraw != null) {
      patch.maxWithdraw = Math.max(
          1000, Math.trunc(Number(data.maxWithdraw) || DEFAULT_MAX_WITHDRAW));
    }
    if (data && data.topUpApproveMode != null) {
      const m = String(data.topUpApproveMode).toLowerCase();
      patch.topUpApproveMode = m === 'auto' ? 'auto' : 'manual';
    }
    if (data && data.withdrawApproveMode != null) {
      const m = String(data.withdrawApproveMode).toLowerCase();
      patch.withdrawApproveMode = m === 'auto' ? 'auto' : 'manual';
    }
    if (data && data.withdrawAutoLimit != null) {
      patch.withdrawAutoLimit = normalizeWithdrawAutoLimit(data.withdrawAutoLimit);
    }
    patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    patch.updatedBy = caller;
    await db.doc(SETTINGS_DOC).set(patch, { merge: true });
    return { ok: true, settings: await loadBotSettings() };
  });

  // ─── Callable: admin review top-up ───────────────────────────────
  exports.adminReviewWalletTopUp = functions.https.onCall(async (data, context) => {
    const callerUid = await requireCallerRoles(
        context, ['superadmin', 'finance'], 'Finance role required');
    const requestId = String((data && data.requestId) || '').trim();
    const accept = !!(data && (data.accept === true || data.approve === true));
    const rejectReason = String((data && data.rejectReason) || '').trim().slice(0, 200);
    if (!requestId) {
      throw new functions.https.HttpsError('invalid-argument', 'requestId kerak');
    }

    const ref = db.collection(TOPUP_COL).doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'So\'rov topilmadi');
    }
    const req = snap.data() || {};
    if (req.status === 'credited') {
      return { ok: true, status: 'credited', idempotent: true };
    }
    if (req.status !== 'awaiting_review') {
      throw new functions.https.HttpsError(
          'failed-precondition', `Holat: ${req.status}`);
    }

    const amount = Math.trunc(Number(req.amount || 0));
    const uid = canonicalUid(req.uid);
    const tgChat = req.telegramChatId || req.telegramUserId;

    if (!accept) {
      await ref.set({
        status: 'rejected',
        rejectReason: rejectReason || 'Rad etildi',
        reviewedBy: callerUid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      if (tgChat) {
        await tgSend(tgChat,
            `❌ Тўлдириш рад этилди (${amount} сўм).\n${rejectReason || ''}`.trim());
      }
      try {
        await notifyUserInApp({
          userId: uid,
          title: 'Тўлдириш рад этилди',
          body: rejectReason || `${amount} сўм`,
          category: 'wallet',
          source: 'wallet_telegram_topup',
          dataType: 'wallet_topup_rejected',
          screen: 'wallet',
          extraData: { requestId },
        });
      } catch (_) { /* ignore */ }
      return { ok: true, status: 'rejected' };
    }

    return creditTopUpRequest({
      requestId,
      req,
      callerUid,
      auto: false,
    });
  });

  // ─── Callable: admin review withdraw ─────────────────────────────
  exports.adminReviewWalletWithdraw = functions.https.onCall(async (data, context) => {
    const callerUid = await requireCallerRoles(
        context, ['superadmin', 'finance'], 'Finance role required');
    const requestId = String((data && data.requestId) || '').trim();
    const accept = !!(data && (data.accept === true || data.approve === true));
    const rejectReason = String((data && data.rejectReason) || '').trim().slice(0, 200);
    const markPaid = !!(data && data.markPaid === true);
    if (!requestId) {
      throw new functions.https.HttpsError('invalid-argument', 'requestId kerak');
    }

    const ref = db.collection(WITHDRAW_COL).doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'So\'rov topilmadi');
    }
    const req = snap.data() || {};
    const amount = Math.trunc(Number(req.amount || 0));
    const uid = canonicalUid(req.uid);
    const tgChat = req.telegramChatId || req.telegramUserId;

    if (req.status === 'paid' || req.status === 'approved') {
      if (markPaid && req.status === 'approved') {
        await ref.set({
          status: 'paid',
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          paidBy: callerUid,
        }, { merge: true });
        if (tgChat) {
          await tgSend(tgChat, `💸 Ечиш тўланди: <b>${amount}</b> сўм.`);
        }
        return { ok: true, status: 'paid' };
      }
      return { ok: true, status: req.status, idempotent: true };
    }

    if (req.status !== 'pending') {
      throw new functions.https.HttpsError(
          'failed-precondition', `Holat: ${req.status}`);
    }

    if (!accept) {
      await ref.set({
        status: 'rejected',
        rejectReason: rejectReason || 'Rad etildi',
        reviewedBy: callerUid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      if (tgChat) {
        await tgSend(tgChat,
            `❌ Ечиш рад этилди (${amount} сўм).\n${rejectReason || ''}`.trim());
      }
      try {
        await notifyUserInApp({
          userId: uid,
          title: 'Ечиш рад этилди',
          body: `${amount} сўм. ${rejectReason || ''}`.trim(),
          category: 'wallet',
          source: 'wallet_withdraw',
          dataType: 'wallet_withdraw_rejected',
          screen: 'wallet',
          extraData: { requestId },
        });
      } catch (_) { /* ignore */ }
      return { ok: true, status: 'rejected' };
    }

    return approveWithdrawInternal({
      requestId,
      req,
      callerUid,
      markPaid,
      auto: false,
    });
  });

  // ─── Callable: signed receipt URL ────────────────────────────────
  exports.getWalletTopUpReceiptUrl = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(
        context, ['superadmin', 'finance'], 'Finance role required');
    const requestId = String((data && data.requestId) || '').trim();
    if (!requestId) {
      throw new functions.https.HttpsError('invalid-argument', 'requestId kerak');
    }
    const snap = await db.collection(TOPUP_COL).doc(requestId).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'So\'rov topilmadi');
    }
    const path = String((snap.data() || {}).receiptStoragePath || '').trim();
    if (!path) {
      throw new functions.https.HttpsError('failed-precondition', 'Chek yo\'q');
    }
    const file = admin.storage().bucket().file(path);
    const [url] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });
    return { ok: true, url, expiresInSec: 900 };
  });

  // ─── Bot command handlers ────────────────────────────────────────
  async function cmdStart(chatId, tgUser, startPayload) {
    const settings = await loadBotSettings();
    if (!settings.enabled) {
      await tgSend(chatId, '⏸ Ҳамён боти вақтинча ўчиқ.');
      return;
    }
    if (startPayload && String(startPayload).startsWith('link_')) {
      const code = String(startPayload).slice(5);
      await cmdLink(chatId, tgUser, code);
      return;
    }
    const uid = await resolveUidByTelegram(tgUser.id);
    if (!uid) {
      await tgSend(chatId,
          '👋 <b>AVA ҳамён боти</b>\n\n' +
          'Иловадаги Кошелёк → «Ҳамённи тўлдириш» тугмасини босинг.\n' +
          'Бот ўзи боғланади. Қўлда: <code>/link 123456</code>');
      return;
    }
    await tgSend(chatId,
        '✅ Аккаунт боғланган.\n\n' +
        'Командалар:\n' +
        '/deposit — ҳамён тўлдириш\n' +
        '/withdraw — ечиш аризаси\n' +
        '/balance — баланс\n' +
        '/history — тариx\n' +
        '/status — охирги сўров\n' +
        '/cancel — бекор қилиш\n' +
        '/support — ёрдам');
  }

  async function cmdLink(chatId, tgUser, codeRaw) {
    const code = String(codeRaw || '').replace(/\D/g, '');
    if (code.length !== 6) {
      await tgSend(chatId, 'Формат: <code>/link 123456</code>');
      return;
    }
    const ref = db.collection(CODE_COL).doc(code);
    const snap = await ref.get();
    if (!snap.exists) {
      await tgSend(chatId, '❌ Код топилмади.');
      return;
    }
    const d = snap.data() || {};
    if (d.used) {
      await tgSend(chatId, '❌ Код аллақачон ишлатилган.');
      return;
    }
    const exp = d.expiresAt && d.expiresAt.toMillis ? d.expiresAt.toMillis() : 0;
    if (exp && exp < Date.now()) {
      await tgSend(chatId, '❌ Код муддати ўтган. Иловадан янги код олинг.');
      return;
    }
    const uid = canonicalUid(d.uid);
    const tgId = String(tgUser.id);

    // One telegram → one uid
    const existing = await db.collection(LINK_COL).doc(tgId).get();
    if (existing.exists) {
      const oldUid = canonicalUid((existing.data() || {}).uid);
      if (oldUid && oldUid !== uid) {
        await tgSend(chatId,
            '❌ Бу Telegram бошқа ҳамёнга боғланган. Админга мурожаат қилинг.');
        return;
      }
    }

    // One uid → preferably one telegram (revoke old)
    const otherLinks = await db.collection(LINK_COL)
        .where('uid', '==', uid)
        .where('status', '==', 'active')
        .limit(5)
        .get();
    const batch = db.batch();
    otherLinks.forEach((doc) => {
      if (doc.id !== tgId) {
        batch.set(doc.ref, {
          status: 'revoked',
          revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    });
    batch.set(db.collection(LINK_COL).doc(tgId), {
      uid,
      status: 'active',
      telegramUsername: tgUser.username || '',
      linkedAt: admin.firestore.FieldValue.serverTimestamp(),
      linkedBy: 'bot',
    }, { merge: true });
    batch.set(ref, {
      used: true,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      telegramUserId: tgId,
    }, { merge: true });
    batch.set(db.collection('users').doc(uid), {
      telegramId: tgId,
      telegramUsername: tgUser.username || '',
      telegramLinkedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();

    await tgSend(chatId,
        `✅ Боғланди: <code>+${uid}</code>\nЭнди /deposit орқали тўлдиришингиз мумкин.`);
  }

  async function cmdBalance(chatId, tgUser) {
    const uid = await resolveUidByTelegram(tgUser.id);
    if (!uid) {
      await tgSend(chatId, 'Аввал /link билан боғланг.');
      return;
    }
    const snap = await db.collection('users').doc(uid).get();
    const bal = snap.exists
        ? (parseInt(String((snap.data() || {}).bonusBalance ?? 0), 10) || 0)
        : 0;
    await tgSend(chatId, `💼 Баланс: <b>${bal.toLocaleString('uz-UZ')}</b> сўм`);
  }

  async function cmdHistory(chatId, tgUser) {
    const uid = await resolveUidByTelegram(tgUser.id);
    if (!uid) {
      await tgSend(chatId, 'Аввал /link билан боғланг.');
      return;
    }
    const snap = await db.collection('users').doc(uid)
        .collection('wallet_ledger')
        .orderBy('createdAt', 'desc')
        .limit(5)
        .get();
    if (snap.empty) {
      await tgSend(chatId, 'Тариx бўш.');
      return;
    }
    const lines = [];
    snap.forEach((doc) => {
      const x = doc.data() || {};
      const amt = parseInt(String(x.amount ?? 0), 10) || 0;
      const sign = amt >= 0 ? '+' : '';
      lines.push(`• ${x.type || 'op'}: ${sign}${amt}`);
    });
    await tgSend(chatId, '📋 Охирги операциялар:\n' + lines.join('\n'));
  }

  async function cmdDepositStart(chatId, tgUser, amountRaw) {
    const settings = await loadBotSettings();
    if (!settings.enabled) {
      await tgSend(chatId, '⏸ Бот ўчиқ.');
      return;
    }
    const uid = await resolveUidByTelegram(tgUser.id);
    if (!uid) {
      await tgSend(chatId, 'Аввал /link билан боғланг.');
      return;
    }
    if (!settings.depositCardNumber) {
      await tgSend(chatId, '⚠️ Карта ҳали созланмаган. Админга мурожаат қилинг.');
      return;
    }

    let amount = Math.trunc(Number(String(amountRaw || '').replace(/\D/g, '')) || 0);
    if (!amount) {
      await setSession(tgUser.id, { expect: 'deposit_amount' });
      await tgSend(chatId,
          `💵 Суммани юборинг (макс ${settings.maxTopUp.toLocaleString('uz-UZ')} сўм):`);
      return;
    }
    await createTopUpRequest(chatId, tgUser, uid, amount, settings);
  }

  async function createTopUpRequest(chatId, tgUser, uid, amount, settings) {
    if (!Number.isInteger(amount) || amount <= 0) {
      await tgSend(chatId, 'Сумма нотўғри.');
      return;
    }
    if (amount > settings.maxTopUp) {
      await tgSend(chatId, `Макс бир сўров: ${settings.maxTopUp} сўм`);
      return;
    }
    const spent = await sumCreditedTopUpsToday(uid);
    if (spent + amount > settings.dailyTopUpLimit) {
      await tgSend(chatId,
          `Кунлик лимит: ${settings.dailyTopUpLimit} сўм (бугун ${spent})`);
      return;
    }

    const ref = db.collection(TOPUP_COL).doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + REQUEST_TTL_MS);
    await ref.set({
      uid,
      telegramUserId: String(tgUser.id),
      telegramChatId: String(chatId),
      telegramUsername: tgUser.username || '',
      amount,
      currency: 'UZS',
      channel: 'telegram_card_manual',
      status: 'awaiting_transfer',
      source: 'telegram',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    });

    await setSession(tgUser.id, {
      expect: 'deposit_receipt',
      topupRequestId: ref.id,
      amount,
    });

    const card = settings.depositCardNumber;
    const holderName = [settings.depositCardFirstName, settings.depositCardLastName]
        .filter(Boolean)
        .join(' ')
        || settings.depositCardHolder;
    const holder = holderName
        ? `\nОлувчи: <b>${holderName}</b>`
        : '';
    const hint = settings.depositInstructions
        ? `\n\n${settings.depositInstructions}`
        : '';
    await tgSend(chatId,
        `💳 <b>Тўлдириш сўрови</b>\n` +
        `Сумма: <b>${amount.toLocaleString('uz-UZ')}</b> сўм\n` +
        `ID: <code>${ref.id}</code>\n\n` +
        `Карта: <code>${card}</code>${holder}${hint}\n\n` +
        `Пул ўтказгач, <b>чек расмини</b> шу чатга юборинг.`);
  }

  async function handleDepositReceipt(chatId, tgUser, photoSizes) {
    const session = await getSession(tgUser.id);
    if (session.expect !== 'deposit_receipt' || !session.topupRequestId) {
      await tgSend(chatId, 'Аввал /deposit билан сўров яратинг.');
      return;
    }
    const requestId = session.topupRequestId;
    const ref = db.collection(TOPUP_COL).doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) {
      await clearSession(tgUser.id);
      await tgSend(chatId, 'Сўров топилмади. Қайта /deposit қилинг.');
      return;
    }
    const req = snap.data() || {};
    if (req.status !== 'awaiting_transfer') {
      await tgSend(chatId, `Сўров ҳолати: ${req.status}`);
      return;
    }

    const best = photoSizes[photoSizes.length - 1];
    const storagePath = `topup_receipts/${req.uid}/${requestId}.jpg`;
    try {
      await downloadTelegramFileToStorage(best.file_id, storagePath);
    } catch (e) {
      console.error('receipt upload', e);
      await tgSend(chatId, 'Чекни юклаб бўлмади. Қайта юборинг.');
      return;
    }

    await ref.set({
      status: 'awaiting_review',
      receiptStoragePath: storagePath,
      receiptUploadedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await clearSession(tgUser.id);

    const settings = await loadBotSettings();
    if (settings.topUpApproveMode === 'auto') {
      try {
        // Refresh req with receipt path for audit.
        const fresh = (await ref.get()).data() || req;
        await creditTopUpRequest({
          requestId,
          req: fresh,
          callerUid: 'telegram_bot_auto',
          auto: true,
        });
        return;
      } catch (e) {
        console.error('auto topUp credit failed', e);
        await tgSend(chatId,
            '📎 Чек қабул қилинди, лекин авто тасдиқда хато.\n' +
            'Админ қўлда текширади. /status');
        return;
      }
    }

    await tgSend(chatId,
        '📎 Чек қабул қилинди. Админ текширгач ҳамёнга тушади.\n' +
        `/status — ҳолатни кўриш`);
  }

  async function cmdWithdraw(chatId, tgUser, amountRaw) {
    const settings = await loadBotSettings();
    const uid = await resolveUidByTelegram(tgUser.id);
    if (!uid) {
      await tgSend(chatId, 'Аввал /link билан боғланг.');
      return;
    }
    let amount = Math.trunc(Number(String(amountRaw || '').replace(/\D/g, '')) || 0);
    if (!amount) {
      await setSession(tgUser.id, { expect: 'withdraw_amount' });
      await tgSend(chatId,
          `💸 Ечиш суммасини юборинг (макс ${settings.maxWithdraw.toLocaleString('uz-UZ')}):`);
      return;
    }
    await createWithdrawRequest(chatId, tgUser, uid, amount, settings);
  }

  async function createWithdrawRequest(chatId, tgUser, uid, amount, settings) {
    if (amount <= 0 || amount > settings.maxWithdraw) {
      await tgSend(chatId, `Сумма 1…${settings.maxWithdraw} оралиғида бўлсин.`);
      return;
    }
    const userSnap = await db.collection('users').doc(uid).get();
    const bal = userSnap.exists
        ? (parseInt(String((userSnap.data() || {}).bonusBalance ?? 0), 10) || 0)
        : 0;
    if (amount > bal) {
      await tgSend(chatId, `Yetarli emas. Баланс: ${bal} сўм`);
      return;
    }

    const ref = db.collection(WITHDRAW_COL).doc();
    await ref.set({
      uid,
      telegramUserId: String(tgUser.id),
      telegramChatId: String(chatId),
      amount,
      currency: 'UZS',
      status: 'pending',
      source: 'telegram',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await clearSession(tgUser.id);

    const autoRes = await maybeAutoApproveWithdraw(ref.id, settings);
    if (autoRes && autoRes.ok) {
      return;
    }

    const autoHint = settings.withdrawApproveMode === 'auto'
        ? `\n(Авто лимит: ${settings.withdrawAutoLimit.toLocaleString('uz-UZ')} сўм — ортиқча сумма админ текширувида)`
        : '';
    await tgSend(chatId,
        `📤 Ечиш аризаси қабул қилинди.\n` +
        `Сумма: <b>${amount}</b> сўм\n` +
        `ID: <code>${ref.id}</code>\n` +
        `Админ тасдиғидан кейин тўланади.` + autoHint);
  }

  async function cmdStatus(chatId, tgUser) {
    const uid = await resolveUidByTelegram(tgUser.id);
    if (!uid) {
      await tgSend(chatId, 'Аввал /link билан боғланг.');
      return;
    }
    const top = await db.collection(TOPUP_COL)
        .where('uid', '==', uid)
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
    const wd = await db.collection(WITHDRAW_COL)
        .where('uid', '==', uid)
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
    const lines = [];
    if (!top.empty) {
      const x = top.docs[0].data();
      lines.push(`Тўлдириш: ${x.status} · ${x.amount} сўм · ${top.docs[0].id}`);
    }
    if (!wd.empty) {
      const x = wd.docs[0].data();
      lines.push(`Ечиш: ${x.status} · ${x.amount} сўм · ${wd.docs[0].id}`);
    }
    await tgSend(chatId, lines.length ? lines.join('\n') : 'Сўров йўқ.');
  }

  async function cmdCancel(chatId, tgUser) {
    const uid = await resolveUidByTelegram(tgUser.id);
    await clearSession(tgUser.id);
    if (!uid) {
      await tgSend(chatId, 'Сессия тозаланди.');
      return;
    }
    const pending = await db.collection(TOPUP_COL)
        .where('uid', '==', uid)
        .where('status', '==', 'awaiting_transfer')
        .limit(5)
        .get();
    const batch = db.batch();
    pending.forEach((d) => {
      batch.set(d.ref, {
        status: 'cancelled',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    await batch.commit();
    await tgSend(chatId, 'Бекор қилинди.');
  }

  async function cmdSupport(chatId) {
    await tgSend(chatId,
        '🆘 Ёрдам: AVA Zona иловасидаги чат қўллаб-қувватлашга ёзинг.\n' +
        'Ёки админ телефон орқали боғланинг.');
  }

  async function handleTextMessage(chatId, tgUser, text) {
    const t = String(text || '').trim();
    const session = await getSession(tgUser.id);
    const settings = await loadBotSettings();

    if (session.expect === 'deposit_amount') {
      const amount = Math.trunc(Number(t.replace(/\D/g, '')) || 0);
      const uid = await resolveUidByTelegram(tgUser.id);
      if (!uid) {
        await tgSend(chatId, 'Аввал /link.');
        return;
      }
      await createTopUpRequest(chatId, tgUser, uid, amount, settings);
      return;
    }
    if (session.expect === 'withdraw_amount') {
      const amount = Math.trunc(Number(t.replace(/\D/g, '')) || 0);
      const uid = await resolveUidByTelegram(tgUser.id);
      if (!uid) {
        await tgSend(chatId, 'Аввал /link.');
        return;
      }
      await createWithdrawRequest(chatId, tgUser, uid, amount, settings);
      return;
    }

    if (t.startsWith('/')) {
      const [cmd, ...rest] = t.split(/\s+/);
      const arg = rest.join(' ').trim();
      const c = cmd.split('@')[0].toLowerCase();
      switch (c) {
        case '/start':
          await cmdStart(chatId, tgUser, arg);
          break;
        case '/link':
          await cmdLink(chatId, tgUser, arg);
          break;
        case '/deposit':
          await cmdDepositStart(chatId, tgUser, arg);
          break;
        case '/withdraw':
          await cmdWithdraw(chatId, tgUser, arg);
          break;
        case '/balance':
          await cmdBalance(chatId, tgUser);
          break;
        case '/history':
          await cmdHistory(chatId, tgUser);
          break;
        case '/status':
          await cmdStatus(chatId, tgUser);
          break;
        case '/cancel':
          await cmdCancel(chatId, tgUser);
          break;
        case '/support':
          await cmdSupport(chatId);
          break;
        case '/help':
          await cmdStart(chatId, tgUser, '');
          break;
        default:
          await tgSend(chatId, 'Номаълум команда. /help');
      }
      return;
    }

    await tgSend(chatId, 'Командалар: /help');
  }

  async function processUpdate(update) {
    const msg = update.message || update.edited_message;
    if (!msg || !msg.chat || !msg.from) return;
    const chatId = msg.chat.id;
    const tgUser = msg.from;

    if (msg.photo && msg.photo.length) {
      await handleDepositReceipt(chatId, tgUser, msg.photo);
      return;
    }
    if (msg.document && msg.document.mime_type &&
        String(msg.document.mime_type).startsWith('image/')) {
      await handleDepositReceipt(chatId, tgUser, [{
        file_id: msg.document.file_id,
      }]);
      return;
    }
    if (msg.text) {
      await handleTextMessage(chatId, tgUser, msg.text);
    }
  }

  // ─── HTTP webhook ────────────────────────────────────────────────
  exports.telegramWalletBotWebhook = functions.https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('POST only');
      return;
    }
    const { token, secret } = tgConfig();
    if (!token) {
      res.status(503).send('bot not configured');
      return;
    }
    if (secret) {
      const q = String((req.query && req.query.key) || '');
      const h = String(req.get('x-telegram-bot-api-secret-token') || '');
      if (q !== secret && h !== secret) {
        res.status(403).send('forbidden');
        return;
      }
    }
    try {
      await processUpdate(req.body || {});
      res.status(200).send('ok');
    } catch (e) {
      console.error('telegramWalletBotWebhook', e);
      res.status(200).send('ok'); // avoid telegram retries storm on logic bugs
    }
  });
}

module.exports = { attachTelegramWalletBot };
