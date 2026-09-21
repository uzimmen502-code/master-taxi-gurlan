'use strict';

/**
 * «AVA ёрдамчиси» — илова ичидаги AI чат (В-1, OpenAI API орқали).
 *
 * Custom GPT йўли ёпилди (OpenAI 2026-09: шахсий аккаунтларда GPT яратиш
 * йўқ, 2026-12-11 дан GPT'лар ишламайди) — шунинг учун ёрдамчи Cloud
 * Function орқали тўғридан-тўғри OpenAI Responses API'га уланади.
 *
 * Тарифлар:
 *   - Бепул: кунига `freeDailyLimit` хабар (default 10), web search йўқ.
 *   - Pro (пакет ҳамёндан сотиб олинади): `proDailyLimit` юмшоқ чегара
 *     (default 300 — суиистеъмолдан ҳимоя, фойдаланувчи сезмайди) +
 *     web search кунига `proWebSearchDailyLimit` (default 10).
 *
 * Firestore:
 *   settings/assistant                       — конфиг (админ, релизсиз)
 *   users/{uid}.assistantPaidUntil           — Pro муддати (Timestamp)
 *   users/{uid}/assistant_usage/{YYYY-MM-DD} — кунлик ҳисоблагич (Тошкент)
 *   users/{uid}/assistant_messages/{id}      — суҳбат тарихи (клиент ўқийди)
 *   users/{uid}/assistant_packages/{idem}    — сотиб олинган пакетлар
 *   wallet_idempotency/{idem}                — debitForOrder билан бир хил
 *
 * Callables (default region, index.js'даги бошқа onCall'лар каби):
 *   assistantGetStatus, assistantChat, assistantBuyPackage,
 *   assistantClearHistory
 *
 * API калити: functions/.env → OPENAI_API_KEY (git'га тушмайди).
 */

const { DEFAULT_SYSTEM_PROMPT } = require('./assistant_prompt');

const OPENAI_RESPONSES_URL = 'https://api.openai.com/v1/responses';
const TASHKENT_OFFSET_MS = 5 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

const ASSISTANT_DEFAULTS = {
  enabled: true,
  // gpt-5-mini: web search натижасини хом кўчирмайди (4.1-mini кўчиради,
  // 4.1 — `citeturn0…` қолдиқ чиқаради) — 2026-09-21 синови.
  model: 'gpt-5-mini',
  reasoningEffort: 'low',
  freeDailyLimit: 10,
  proDailyLimit: 300,
  proWebSearchDailyLimit: 10,
  perMinuteLimit: 8,
  maxHistoryMessages: 12,
  maxInputChars: 2000,
  maxOutputTokens: 1600,
  requestTimeoutMs: 60 * 1000,
  packages: [
    { id: 'd7', days: 7, price: 15000, promo: false },
    { id: 'd15', days: 15, price: 25000, promo: false },
    { id: 'd30', days: 30, price: 30000, promo: true },
  ],
};

/** Тошкент вақти бўйича кун калити (`YYYY-MM-DD`). */
function tashkentDayKey(nowMs = Date.now()) {
  return new Date(nowMs + TASHKENT_OFFSET_MS).toISOString().slice(0, 10);
}

/** Минут калити — тезлик чегараси учун. */
function minuteKey(nowMs = Date.now()) {
  return Math.floor(nowMs / 60000);
}

function intOr(v, def) {
  const n = parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) && n >= 0 ? n : def;
}

function normalizePackages(raw) {
  if (!Array.isArray(raw)) return ASSISTANT_DEFAULTS.packages;
  const out = [];
  for (const p of raw) {
    if (!p || typeof p !== 'object') continue;
    const id = String(p.id || '').trim();
    const days = intOr(p.days, 0);
    const price = intOr(p.price, 0);
    if (!id || days <= 0 || price <= 0) continue;
    out.push({ id, days, price, promo: !!p.promo });
  }
  return out.length ? out : ASSISTANT_DEFAULTS.packages;
}

function tsToMs(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** OpenAI Responses API жавобидан матн ва web_search сонини ажратиш. */
function parseResponsesOutput(json) {
  const output = Array.isArray(json && json.output) ? json.output : [];
  let text = '';
  let webSearches = 0;
  for (const item of output) {
    if (!item || typeof item !== 'object') continue;
    if (item.type === 'web_search_call') {
      webSearches += 1;
      continue;
    }
    if (item.type === 'message' && Array.isArray(item.content)) {
      for (const part of item.content) {
        if (part && part.type === 'output_text' && typeof part.text === 'string') {
          text += part.text;
        }
      }
    }
  }
  const usage = (json && json.usage) || {};
  return {
    text: text.trim(),
    webSearches,
    inputTokens: intOr(usage.input_tokens, 0),
    outputTokens: intOr(usage.output_tokens, 0),
  };
}

function attachAssistant(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, settlementLedger } = deps;
  const { HttpsError } = functions.https;
  const FieldValue = admin.firestore.FieldValue;

  function requireUid(context) {
    if (!context || !context.auth) {
      throw new HttpsError('unauthenticated', 'Login required');
    }
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 9) {
      throw new HttpsError('permission-denied', 'Phone required');
    }
    return uid;
  }

  async function loadConfig() {
    let raw = {};
    try {
      const snap = await db.collection('settings').doc('assistant').get();
      raw = snap.exists ? (snap.data() || {}) : {};
    } catch (e) {
      console.error('assistant: settings/assistant read failed', e);
    }
    const cfg = {
      enabled: raw.enabled === undefined ? ASSISTANT_DEFAULTS.enabled : !!raw.enabled,
      model: String(raw.model || ASSISTANT_DEFAULTS.model).trim() || ASSISTANT_DEFAULTS.model,
      reasoningEffort: String(raw.reasoningEffort || ASSISTANT_DEFAULTS.reasoningEffort).trim(),
      freeDailyLimit: intOr(raw.freeDailyLimit, ASSISTANT_DEFAULTS.freeDailyLimit),
      proDailyLimit: intOr(raw.proDailyLimit, ASSISTANT_DEFAULTS.proDailyLimit),
      proWebSearchDailyLimit: intOr(
        raw.proWebSearchDailyLimit, ASSISTANT_DEFAULTS.proWebSearchDailyLimit),
      perMinuteLimit: intOr(raw.perMinuteLimit, ASSISTANT_DEFAULTS.perMinuteLimit),
      maxHistoryMessages: intOr(raw.maxHistoryMessages, ASSISTANT_DEFAULTS.maxHistoryMessages),
      maxInputChars: intOr(raw.maxInputChars, ASSISTANT_DEFAULTS.maxInputChars),
      maxOutputTokens: intOr(raw.maxOutputTokens, ASSISTANT_DEFAULTS.maxOutputTokens),
      requestTimeoutMs: ASSISTANT_DEFAULTS.requestTimeoutMs,
      packages: normalizePackages(raw.packages),
      systemPrompt: String(raw.systemPrompt || '').trim() || DEFAULT_SYSTEM_PROMPT,
      extraKnowledge: String(raw.extraKnowledge || '').trim(),
    };
    if (cfg.extraKnowledge) {
      cfg.systemPrompt = `${cfg.systemPrompt}\n\n=== ҚЎШИМЧА МАЪЛУМОТ ===\n${cfg.extraKnowledge}`;
    }
    return cfg;
  }

  function usageRef(uid, dayKey) {
    return db.collection('users').doc(uid).collection('assistant_usage').doc(dayKey);
  }

  function messagesCol(uid) {
    return db.collection('users').doc(uid).collection('assistant_messages');
  }

  /** Клиентга қайтариладиган ҳолат (лимит/Pro/пакетлар/баланс). */
  function buildStatus(cfg, userData, usageData, nowMs) {
    const paidUntilMs = tsToMs((userData || {}).assistantPaidUntil);
    const pro = paidUntilMs > nowMs;
    const u = usageData || {};
    return {
      enabled: cfg.enabled,
      pro,
      paidUntil: pro ? paidUntilMs : null,
      usedToday: intOr(u.messages, 0),
      dailyLimit: pro ? cfg.proDailyLimit : cfg.freeDailyLimit,
      freeDailyLimit: cfg.freeDailyLimit,
      webSearchesToday: intOr(u.webSearches, 0),
      webSearchLimit: pro ? cfg.proWebSearchDailyLimit : 0,
      balance: intOr((userData || {}).bonusBalance, 0),
      packages: cfg.packages,
      dayKey: tashkentDayKey(nowMs),
    };
  }

  async function callOpenAi(cfg, history, userText, allowWebSearch) {
    const apiKey = String(process.env.OPENAI_API_KEY || '').trim();
    if (!apiKey) {
      console.error('assistant: OPENAI_API_KEY is not set (functions/.env)');
      throw new HttpsError('failed-precondition', 'api_key_missing');
    }

    const input = [];
    for (const m of history) {
      const role = m.role === 'assistant' ? 'assistant' : 'user';
      const text = String(m.text || '').trim();
      if (!text) continue;
      input.push({ role, content: text });
    }
    input.push({ role: 'user', content: userText });

    const body = {
      model: cfg.model,
      instructions: cfg.systemPrompt,
      input,
      max_output_tokens: cfg.maxOutputTokens,
      store: false,
    };
    // Reasoning моделлар (gpt-5*, o*) — effort паст бўлса тез ва арзон;
    // max_output_tokens reasoning токенларини ҳам қамрайди.
    if (/^(gpt-5|o\d)/.test(cfg.model) && cfg.reasoningEffort) {
      body.reasoning = { effort: cfg.reasoningEffort };
    }
    if (allowWebSearch) {
      body.tools = [{ type: 'web_search' }];
      body.tool_choice = 'auto';
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), cfg.requestTimeoutMs);
    let res;
    try {
      res = await fetch(OPENAI_RESPONSES_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (e) {
      console.error('assistant: OpenAI request failed', e && e.message);
      throw new HttpsError('unavailable', 'upstream_unavailable');
    } finally {
      clearTimeout(timer);
    }

    let json = null;
    try {
      json = await res.json();
    } catch (_) {
      json = null;
    }
    if (!res.ok) {
      const msg = json && json.error && json.error.message;
      console.error(`assistant: OpenAI HTTP ${res.status}: ${msg || ''}`);
      if (res.status === 429) throw new HttpsError('unavailable', 'upstream_rate_limited');
      if (res.status === 401) throw new HttpsError('failed-precondition', 'api_key_invalid');
      throw new HttpsError('unavailable', 'upstream_error');
    }
    const parsed = parseResponsesOutput(json);
    if (!parsed.text) {
      console.error('assistant: empty output', JSON.stringify(json).slice(0, 500));
      throw new HttpsError('unavailable', 'empty_reply');
    }
    return parsed;
  }

  // ---------------------------------------------------------------------
  // assistantGetStatus
  // ---------------------------------------------------------------------
  exportsObj.assistantGetStatus = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const nowMs = Date.now();
    const cfg = await loadConfig();
    const [userSnap, usageSnap] = await Promise.all([
      db.collection('users').doc(uid).get(),
      usageRef(uid, tashkentDayKey(nowMs)).get(),
    ]);
    return buildStatus(cfg, userSnap.data(), usageSnap.data(), nowMs);
  });

  // ---------------------------------------------------------------------
  // assistantChat
  // ---------------------------------------------------------------------
  exportsObj.assistantChat = functions
    .runWith({ timeoutSeconds: 120, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const uid = requireUid(context);
      const cfg = await loadConfig();
      if (!cfg.enabled) {
        throw new HttpsError('unavailable', 'assistant_disabled');
      }

      const text = String((data && data.text) || '').trim();
      if (!text) {
        throw new HttpsError('invalid-argument', 'text required');
      }
      if (text.length > cfg.maxInputChars) {
        throw new HttpsError('invalid-argument', 'text_too_long');
      }

      const nowMs = Date.now();
      const dayKey = tashkentDayKey(nowMs);
      const minKey = minuteKey(nowMs);
      const userRef = db.collection('users').doc(uid);
      const uRef = usageRef(uid, dayKey);

      // 1) Лимитни текшириш + хабарни олдиндан ҳисоблаш (транзакция —
      //    параллел сўровлар лимитдан ошиб кетмасин).
      const gate = await db.runTransaction(async (t) => {
        const [userSnap, usageSnap] = await Promise.all([t.get(userRef), t.get(uRef)]);
        if (!userSnap.exists) {
          throw new HttpsError('not-found', 'user not found');
        }
        const userData = userSnap.data() || {};
        const usage = usageSnap.exists ? (usageSnap.data() || {}) : {};
        const pro = tsToMs(userData.assistantPaidUntil) > nowMs;
        const used = intOr(usage.messages, 0);
        const dailyLimit = pro ? cfg.proDailyLimit : cfg.freeDailyLimit;
        if (used >= dailyLimit) {
          throw new HttpsError('resource-exhausted', 'daily_limit', {
            reason: 'daily_limit',
            pro,
            usedToday: used,
            dailyLimit,
          });
        }
        const sameMinute = intOr(usage.minuteKey, 0) === minKey;
        const minuteCount = sameMinute ? intOr(usage.minuteCount, 0) : 0;
        if (minuteCount >= cfg.perMinuteLimit) {
          throw new HttpsError('resource-exhausted', 'too_fast', { reason: 'too_fast' });
        }
        const webSearchesToday = intOr(usage.webSearches, 0);
        const allowWebSearch = pro && webSearchesToday < cfg.proWebSearchDailyLimit;

        t.set(uRef, {
          messages: used + 1,
          minuteKey: minKey,
          minuteCount: minuteCount + 1,
          lastAt: FieldValue.serverTimestamp(),
          pro,
        }, { merge: true });

        return { userData, usage, pro, allowWebSearch };
      });

      // 2) Суҳбат тарихи (охирги N хабар, хронологик тартибда).
      let history = [];
      if (cfg.maxHistoryMessages > 0) {
        const histSnap = await messagesCol(uid)
          .orderBy('createdAt', 'desc')
          .limit(cfg.maxHistoryMessages)
          .get();
        history = histSnap.docs.map((d) => d.data() || {}).reverse();
      }

      // 3) OpenAI. Хато бўлса — олдиндан ҳисобланган хабарни қайтарамиз.
      let reply;
      try {
        reply = await callOpenAi(cfg, history, text, gate.allowWebSearch);
      } catch (e) {
        await uRef.set({ messages: FieldValue.increment(-1) }, { merge: true })
          .catch((err) => console.error('assistant: usage refund failed', err));
        throw e;
      }

      // 4) Тарих + ҳисоблагич (web search, токенлар).
      const batch = db.batch();
      const userMsgRef = messagesCol(uid).doc();
      const botMsgRef = messagesCol(uid).doc();
      const createdAt = admin.firestore.Timestamp.fromMillis(nowMs);
      batch.set(userMsgRef, {
        role: 'user',
        text,
        createdAt,
      });
      batch.set(botMsgRef, {
        role: 'assistant',
        text: reply.text,
        createdAt: admin.firestore.Timestamp.fromMillis(nowMs + 1),
        model: cfg.model,
        webSearches: reply.webSearches,
      });
      batch.set(uRef, {
        webSearches: FieldValue.increment(reply.webSearches),
        inputTokens: FieldValue.increment(reply.inputTokens),
        outputTokens: FieldValue.increment(reply.outputTokens),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      await batch.commit();

      const usageAfter = {
        ...gate.usage,
        messages: intOr(gate.usage.messages, 0) + 1,
        webSearches: intOr(gate.usage.webSearches, 0) + reply.webSearches,
      };
      return {
        ok: true,
        reply: reply.text,
        messageId: botMsgRef.id,
        webSearches: reply.webSearches,
        status: buildStatus(cfg, gate.userData, usageAfter, nowMs),
      };
    });

  // ---------------------------------------------------------------------
  // assistantBuyPackage — ҳамёндан (bonusBalance) ечиб Pro муддатини узайтиради.
  // debitForOrder билан бир хил идемпотентлик + settlement ledger кўзгуси.
  // ---------------------------------------------------------------------
  exportsObj.assistantBuyPackage = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const cfg = await loadConfig();
    const packageId = String((data && data.packageId) || '').trim();
    const idempotencyKey = String((data && data.idempotencyKey) || '').trim();
    if (!idempotencyKey) {
      throw new HttpsError('invalid-argument', 'idempotencyKey required');
    }
    const pkg = cfg.packages.find((p) => p.id === packageId);
    if (!pkg) {
      throw new HttpsError('invalid-argument', 'unknown_package');
    }

    const idemKey = `assistant_pkg_${uid}_${idempotencyKey}`;
    const idemRef = db.collection('wallet_idempotency').doc(idemKey);
    const existing = await idemRef.get();
    if (existing.exists) {
      return existing.data().result || { ok: true, duplicate: true };
    }

    const userRef = db.collection('users').doc(uid);
    const ledgerRef = userRef.collection('wallet_ledger').doc();
    const pkgRef = userRef.collection('assistant_packages').doc(idempotencyKey);

    const result = await db.runTransaction(async (t) => {
      const idemSnap = await t.get(idemRef);
      if (idemSnap.exists) {
        return idemSnap.data().result || { ok: true, duplicate: true };
      }
      const userSnap = await t.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError('not-found', 'user not found');
      }
      const ud = userSnap.data() || {};
      const prev = intOr(ud.bonusBalance, 0);
      if (prev < pkg.price) {
        throw new HttpsError('failed-precondition', 'insufficient_balance', {
          reason: 'insufficient_balance',
          balance: prev,
          price: pkg.price,
        });
      }
      const nowMs = Date.now();
      const currentUntil = tsToMs(ud.assistantPaidUntil);
      const base = currentUntil > nowMs ? currentUntil : nowMs;
      const newUntilMs = base + pkg.days * DAY_MS;
      const newUntil = admin.firestore.Timestamp.fromMillis(newUntilMs);

      // Ledger ko'zgusi (READ fazasi).
      const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
        idempotencyKey: idemKey,
      });

      t.set(userRef, {
        bonusBalance: prev - pkg.price,
        assistantPaidUntil: newUntil,
        balanceUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });

      t.set(ledgerRef, {
        type: 'purchase_debit',
        amount: -pkg.price,
        module: 'assistant',
        refType: 'assistant_package',
        refId: pkg.id,
        meta: { days: pkg.days, packageId: pkg.id, note: 'AVA ёрдамчиси Pro' },
        createdAt: FieldValue.serverTimestamp(),
        createdBy: uid,
      });

      t.set(pkgRef, {
        packageId: pkg.id,
        days: pkg.days,
        price: pkg.price,
        paidFrom: admin.firestore.Timestamp.fromMillis(base),
        paidUntil: newUntil,
        createdAt: FieldValue.serverTimestamp(),
      });

      // Ledger ko'zgusi (WRITE fazasi) — Dr passenger_credit / Cr admin_clearing.
      settlementLedger.commitBonusInTx(t, bonusCtx, {
        delta: -pkg.price,
        kind: 'purchase_debit',
        refType: 'assistant_package',
        refId: pkg.id,
        meta: { module: 'assistant', days: pkg.days },
        postedBy: uid,
        postedRole: 'user',
      });

      const out = {
        ok: true,
        debited: pkg.price,
        days: pkg.days,
        paidUntil: newUntilMs,
        balance: prev - pkg.price,
      };
      t.set(idemRef, {
        type: 'assistantBuyPackage',
        result: out,
        createdAt: FieldValue.serverTimestamp(),
      });
      return out;
    });

    return result;
  });

  // ---------------------------------------------------------------------
  // assistantClearHistory — «Янги суҳбат»: тарихни ўчиради (лимитга тегмайди).
  // ---------------------------------------------------------------------
  exportsObj.assistantClearHistory = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const col = messagesCol(uid);
    let deleted = 0;
    // 500 тадан ошмайди (batch чегараси) — одатда бир айланиш етарли.
    for (let i = 0; i < 10; i += 1) {
      const snap = await col.limit(400).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      deleted += snap.size;
      if (snap.size < 400) break;
    }
    return { ok: true, deleted };
  });
}

module.exports = {
  attachAssistant,
  ASSISTANT_DEFAULTS,
  tashkentDayKey,
  parseResponsesOutput,
  normalizePackages,
};
