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
 * ChatGPT каби (эга талаби, 2026-09-22):
 *   - Суҳбатлар алоҳида сақланади, автоматик сарлавҳа, «Янги суҳбат»
 *     эскисини ўчирмайди; фойдаланувчи ўзи ўчириши/қайта номлаши мумкин.
 *   - 365 кун сақлаш: ҳар ҳужжатда `expiresAt` + Firestore TTL сиёсати
 *     (`assistant_conversations`, `assistant_messages` collection group).
 *   - Хотира: ҳар жавобдан кейин фонда (`onAssistantMessageCreated`)
 *     арзон модель суҳбатдан фойдаланувчи ҳақидаги доимий фактларни
 *     ажратади → `assistant_memory`; кейинги ҳар суҳбатда prompt'га қўшилади.
 *
 * Firestore:
 *   settings/assistant                                  — конфиг (админ)
 *   users/{uid}.assistantPaidUntil                      — Pro муддати
 *   users/{uid}/assistant_usage/{YYYY-MM-DD}            — кунлик ҳисоблагич
 *   users/{uid}/assistant_conversations/{convId}        — суҳбат (title …)
 *     …/assistant_messages/{id}                         — хабарлар
 *   users/{uid}/assistant_memory/{id}                   — хотира фактлари
 *   users/{uid}/assistant_packages/{idem}               — сотиб олинган пакетлар
 *   wallet_idempotency/{idem}                           — debitForOrder билан бир хил
 *
 * Callables: assistantGetStatus, assistantChat, assistantBuyPackage,
 *   assistantDeleteConversation, assistantRenameConversation,
 *   assistantDeleteMemory. Trigger: onAssistantMessageCreated.
 *
 * API калити: functions/.env → OPENAI_API_KEY (git'га тушмайди).
 */

const {
  DEFAULT_SYSTEM_PROMPT,
  TITLE_PROMPT,
  MEMORY_PROMPT,
  CYRILLIC_FIX_PROMPT,
} = require('./assistant_prompt');

const OPENAI_RESPONSES_URL = 'https://api.openai.com/v1/responses';
const TASHKENT_OFFSET_MS = 5 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

const ASSISTANT_DEFAULTS = {
  enabled: true,
  // gpt-5-mini: web search натижасини хом кўчирмайди (4.1-mini кўчиради,
  // 4.1 — `citeturn0…` қолдиқ чиқаради) — 2026-09-21 синови.
  model: 'gpt-5-mini',
  reasoningEffort: 'low',
  // Сарлавҳа/хотира — арзон, reasoning'сиз.
  utilityModel: 'gpt-4.1-mini',
  freeDailyLimit: 10,
  proDailyLimit: 300,
  proWebSearchDailyLimit: 10,
  perMinuteLimit: 8,
  maxHistoryMessages: 20,
  maxInputChars: 4000,
  maxOutputTokens: 2000,
  requestTimeoutMs: 90 * 1000,
  retentionDays: 365,
  maxMemoryFacts: 60,
  // Хотира ажратиш — ҳар N-чи фойдаланувчи хабаридан кейин.
  memoryEveryNMessages: 1,
  // Пакетсиз доимий Pro (эга/синов рақамлари). `settings/assistant.freeProPhones`
  // массиви билан кенгайтирилади (998… рақамли формат).
  freeProPhones: ['998912778777'],
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

/**
 * Ёзув аниқлаш: код блоклари, inline код ва URL'ларсиз матнда кирилл ва
 * лотин ҳарфлар улуши. `{ cyr, lat }` — 0..1 (ҳарфлар ичида).
 */
function scriptRatio(text) {
  const stripped = String(text || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/https?:\/\/\S+/g, ' ');
  const cyr = (stripped.match(/[Ѐ-ӿ]/g) || []).length;
  const lat = (stripped.match(/[A-Za-z]/g) || []).length;
  const total = cyr + lat;
  if (!total) return { cyr: 0, lat: 0 };
  return { cyr: cyr / total, lat: lat / total };
}

/**
 * Фойдаланувчи кириллда ёзган, жавоб эса асосан лотинда (модель баъзан
 * ўзбек лотинига "сирғалиб" кетади) — транслитерация керакми?
 */
function needsCyrillicFix(userText, replyText) {
  const u = scriptRatio(userText);
  if (u.cyr < 0.3) return false; // фойдаланувчи кирилл ёзмаган
  // Жавобда кичик ҳарф билан бошланган лотин сўзлар (бренд номлари одатда
  // катта ҳарф: Python, JavaScript) кирилл сўзлардан кўп бўлса — сирғалган.
  const stripped = String(replyText || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/https?:\/\/\S+/g, ' ');
  const latWords = (stripped.match(/(^|[^A-Za-zЀ-ӿ])[a-z][a-z'‘’ʻ]+/g) || []).length;
  const cyrWords = (stripped.match(/[Ѐ-ӿ]+/g) || []).length;
  return latWords >= 5 && latWords > cyrWords;
}

/** Сарлавҳа фолбэки — биринчи хабардан 6 сўз. */
function fallbackTitle(text) {
  const words = String(text || '').replace(/\s+/g, ' ').trim().split(' ');
  const t = words.slice(0, 6).join(' ');
  return (t.length > 48 ? `${t.slice(0, 45)}…` : t) || 'Янги суҳбат';
}

/** Хотира JSON'ини хавфсиз ўқиш ({"facts": [...]}). */
function parseMemoryFacts(text) {
  try {
    const m = String(text || '').match(/\{[\s\S]*\}/);
    if (!m) return [];
    const obj = JSON.parse(m[0]);
    if (!Array.isArray(obj.facts)) return [];
    return obj.facts
      .map((f) => String(f || '').replace(/\s+/g, ' ').trim())
      .filter((f) => f.length >= 3 && f.length <= 200)
      .slice(0, 4);
  } catch (_) {
    return [];
  }
}

function attachAssistant(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, settlementLedger } = deps;
  const { HttpsError } = functions.https;
  const FieldValue = admin.firestore.FieldValue;
  const Timestamp = admin.firestore.Timestamp;

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
    const D = ASSISTANT_DEFAULTS;
    const cfg = {
      enabled: raw.enabled === undefined ? D.enabled : !!raw.enabled,
      model: String(raw.model || D.model).trim() || D.model,
      reasoningEffort: String(raw.reasoningEffort || D.reasoningEffort).trim(),
      utilityModel: String(raw.utilityModel || D.utilityModel).trim() || D.utilityModel,
      freeDailyLimit: intOr(raw.freeDailyLimit, D.freeDailyLimit),
      proDailyLimit: intOr(raw.proDailyLimit, D.proDailyLimit),
      proWebSearchDailyLimit: intOr(raw.proWebSearchDailyLimit, D.proWebSearchDailyLimit),
      perMinuteLimit: intOr(raw.perMinuteLimit, D.perMinuteLimit),
      maxHistoryMessages: intOr(raw.maxHistoryMessages, D.maxHistoryMessages),
      maxInputChars: intOr(raw.maxInputChars, D.maxInputChars),
      maxOutputTokens: intOr(raw.maxOutputTokens, D.maxOutputTokens),
      requestTimeoutMs: D.requestTimeoutMs,
      retentionDays: intOr(raw.retentionDays, D.retentionDays) || D.retentionDays,
      maxMemoryFacts: intOr(raw.maxMemoryFacts, D.maxMemoryFacts),
      memoryEveryNMessages: intOr(raw.memoryEveryNMessages, D.memoryEveryNMessages) || 1,
      packages: normalizePackages(raw.packages),
      freeProPhones: new Set([
        ...D.freeProPhones,
        ...(Array.isArray(raw.freeProPhones)
          ? raw.freeProPhones.map((p) => String(p || '').replace(/\D/g, '')).filter(Boolean)
          : []),
      ]),
      systemPrompt: String(raw.systemPrompt || '').trim() || DEFAULT_SYSTEM_PROMPT,
      extraKnowledge: String(raw.extraKnowledge || '').trim(),
    };
    if (cfg.extraKnowledge) {
      cfg.systemPrompt = `${cfg.systemPrompt}\n\n=== ҚЎШИМЧА МАЪЛУМОТ ===\n${cfg.extraKnowledge}`;
    }
    return cfg;
  }

  const userRef = (uid) => db.collection('users').doc(uid);
  const usageRef = (uid, dayKey) => userRef(uid).collection('assistant_usage').doc(dayKey);
  const convsCol = (uid) => userRef(uid).collection('assistant_conversations');
  const msgsCol = (uid, convId) => convsCol(uid).doc(convId).collection('assistant_messages');
  const memoryCol = (uid) => userRef(uid).collection('assistant_memory');
  const expiresAtFor = (cfg, nowMs) => Timestamp.fromMillis(nowMs + cfg.retentionDays * DAY_MS);

  /** Pro: пакет муддати ўтмаган ёки рақам `freeProPhones` рўйхатида. */
  function isPro(cfg, uid, userData, nowMs) {
    if (cfg.freeProPhones.has(uid)) return true;
    return tsToMs((userData || {}).assistantPaidUntil) > nowMs;
  }

  /** Клиентга қайтариладиган ҳолат (лимит/Pro/пакетлар/баланс). */
  function buildStatus(cfg, uid, userData, usageData, nowMs) {
    const paidUntilMs = tsToMs((userData || {}).assistantPaidUntil);
    const pro = isPro(cfg, uid, userData, nowMs);
    const u = usageData || {};
    return {
      enabled: cfg.enabled,
      pro,
      // Доимий Pro (freeProPhones) — муддат йўқ, клиент "Pro фаол" деб кўрсатади.
      paidUntil: paidUntilMs > nowMs ? paidUntilMs : null,
      unlimited: cfg.freeProPhones.has(uid),
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

  /** Умумий OpenAI Responses чақируви. `opts.quiet` — трigger'да throw ўрнига null. */
  async function openAiResponses(body, timeoutMs, quiet = false) {
    const apiKey = String(process.env.OPENAI_API_KEY || '').trim();
    if (!apiKey) {
      console.error('assistant: OPENAI_API_KEY is not set (functions/.env)');
      if (quiet) return null;
      throw new HttpsError('failed-precondition', 'api_key_missing');
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
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
      if (quiet) return null;
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
      if (quiet) return null;
      if (res.status === 429) throw new HttpsError('unavailable', 'upstream_rate_limited');
      if (res.status === 401) throw new HttpsError('failed-precondition', 'api_key_invalid');
      throw new HttpsError('unavailable', 'upstream_error');
    }
    return parseResponsesOutput(json);
  }

  async function callOpenAi(cfg, systemPrompt, history, userText, allowWebSearch) {
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
      instructions: systemPrompt,
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
    const parsed = await openAiResponses(body, cfg.requestTimeoutMs);
    if (!parsed.text) {
      console.error('assistant: empty output');
      throw new HttpsError('unavailable', 'empty_reply');
    }
    // Ёзув назорати: кирилл саволга лотин жавоб — арзон модель кириллга
    // ўгиради (Markdown/код/URL/бренд ўзгармайди). Хато бўлса — асл жавоб.
    if (needsCyrillicFix(userText, parsed.text)) {
      const fixed = await openAiResponses({
        model: cfg.utilityModel,
        instructions: CYRILLIC_FIX_PROMPT,
        input: parsed.text,
        max_output_tokens: Math.max(cfg.maxOutputTokens, 2000),
        store: false,
      }, 45000, true);
      if (fixed && fixed.text && scriptRatio(fixed.text).cyr >= 0.5) {
        console.log('assistant: reply transliterated to Cyrillic');
        parsed.text = fixed.text;
        parsed.inputTokens += fixed.inputTokens;
        parsed.outputTokens += fixed.outputTokens;
      }
    }
    return parsed;
  }

  /** Хотира фактлари → prompt бўлими (бўш бўлса ''). */
  async function loadMemoryBlock(cfg, uid) {
    if (cfg.maxMemoryFacts <= 0) return '';
    const snap = await memoryCol(uid)
      .orderBy('createdAt', 'desc')
      .limit(cfg.maxMemoryFacts)
      .get();
    if (snap.empty) return '';
    const lines = snap.docs
      .map((d) => String((d.data() || {}).text || '').trim())
      .filter(Boolean)
      .reverse()
      .map((t) => `- ${t}`);
    if (!lines.length) return '';
    return `\n\n=== ФОЙДАЛАНУВЧИ ҲАҚИДА ЭСДА ТУТИЛГАНЛАР (аввалги суҳбатлардан) ===\n${lines.join('\n')}`;
  }

  // ---------------------------------------------------------------------
  // assistantGetStatus
  // ---------------------------------------------------------------------
  exportsObj.assistantGetStatus = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const nowMs = Date.now();
    const cfg = await loadConfig();
    const [userSnap, usageSnap] = await Promise.all([
      userRef(uid).get(),
      usageRef(uid, tashkentDayKey(nowMs)).get(),
    ]);
    return buildStatus(cfg, uid, userSnap.data(), usageSnap.data(), nowMs);
  });

  // ---------------------------------------------------------------------
  // assistantChat — { text, conversationId? } → { reply, conversationId, … }
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
      let convId = String((data && data.conversationId) || '').trim();
      if (convId && !/^[A-Za-z0-9_-]{1,64}$/.test(convId)) {
        throw new HttpsError('invalid-argument', 'conversationId');
      }

      const nowMs = Date.now();
      const dayKey = tashkentDayKey(nowMs);
      const minKey = minuteKey(nowMs);
      const uRef = usageRef(uid, dayKey);

      // 0) Суҳбат: мавжуд (эгалик текширилади) ёки янги — лимит ҳисобидан
      //    ОЛДИН, топилмаса хабар сарфланмасин.
      let convRef;
      let convData = null;
      if (convId) {
        convRef = convsCol(uid).doc(convId);
        const convSnap = await convRef.get();
        if (!convSnap.exists) {
          throw new HttpsError('not-found', 'conversation_not_found');
        }
        convData = convSnap.data() || {};
      } else {
        convRef = convsCol(uid).doc();
        convId = convRef.id;
      }

      // 1) Лимитни текшириш + хабарни олдиндан ҳисоблаш (транзакция —
      //    параллел сўровлар лимитдан ошиб кетмасин).
      const gate = await db.runTransaction(async (t) => {
        const [userSnap, usageSnap] = await Promise.all([t.get(userRef(uid)), t.get(uRef)]);
        if (!userSnap.exists) {
          throw new HttpsError('not-found', 'user not found');
        }
        const userData = userSnap.data() || {};
        const usage = usageSnap.exists ? (usageSnap.data() || {}) : {};
        const pro = isPro(cfg, uid, userData, nowMs);
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

      // 2) Суҳбат тарихи (охирги N хабар, хронологик) + хотира.
      let history = [];
      if (convData && cfg.maxHistoryMessages > 0) {
        const histSnap = await msgsCol(uid, convId)
          .orderBy('createdAt', 'desc')
          .limit(cfg.maxHistoryMessages)
          .get();
        history = histSnap.docs.map((d) => d.data() || {}).reverse();
      }
      let memoryBlock = '';
      try {
        memoryBlock = await loadMemoryBlock(cfg, uid);
      } catch (e) {
        console.error('assistant: memory load failed', e);
      }

      // 4) OpenAI. Хато бўлса — олдиндан ҳисобланган хабарни қайтарамиз.
      let reply;
      try {
        reply = await callOpenAi(
          cfg, cfg.systemPrompt + memoryBlock, history, text, gate.allowWebSearch);
      } catch (e) {
        await uRef.set({ messages: FieldValue.increment(-1) }, { merge: true })
          .catch((err) => console.error('assistant: usage refund failed', err));
        throw e;
      }

      // 5) Ёзиш: суҳбат (янги бўлса — фолбэк сарлавҳа, trigger яхшилайди),
      //    2 та хабар, ҳисоблагич.
      const expiresAt = expiresAtFor(cfg, nowMs);
      const batch = db.batch();
      const userMsgRef = msgsCol(uid, convId).doc();
      const botMsgRef = msgsCol(uid, convId).doc();
      const userMsgCount = intOr(convData && convData.userMessageCount, 0) + 1;
      batch.set(userMsgRef, {
        role: 'user',
        text,
        createdAt: Timestamp.fromMillis(nowMs),
        expiresAt,
      });
      batch.set(botMsgRef, {
        role: 'assistant',
        text: reply.text,
        createdAt: Timestamp.fromMillis(nowMs + 1),
        expiresAt,
        model: cfg.model,
        webSearches: reply.webSearches,
        // Trigger учун: сарлавҳа керакми, хотира ажратиш вақти келдими.
        userMessageCount: userMsgCount,
        needsTitle: !convData,
      });
      const convUpdate = {
        updatedAt: Timestamp.fromMillis(nowMs + 1),
        lastMessageAt: Timestamp.fromMillis(nowMs + 1),
        lastText: reply.text.slice(0, 140),
        messageCount: FieldValue.increment(2),
        userMessageCount: userMsgCount,
        expiresAt,
      };
      if (!convData) {
        Object.assign(convUpdate, {
          title: fallbackTitle(text),
          titleAuto: true,
          createdAt: Timestamp.fromMillis(nowMs),
        });
      }
      batch.set(convRef, convUpdate, { merge: true });
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
        conversationId: convId,
        messageId: botMsgRef.id,
        webSearches: reply.webSearches,
        status: buildStatus(cfg, uid, gate.userData, usageAfter, nowMs),
      };
    });

  // ---------------------------------------------------------------------
  // onAssistantMessageCreated — фонда: сарлавҳа (биринчи жавобда) ва
  // хотира (ҳар N-чи фойдаланувчи хабарида). Фойдаланувчи кутмайди.
  // ---------------------------------------------------------------------
  exportsObj.onAssistantMessageCreated = functions
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .firestore
    .document('users/{uid}/assistant_conversations/{convId}/assistant_messages/{msgId}')
    .onCreate(async (snap, ctx) => {
      const m = snap.data() || {};
      if (m.role !== 'assistant') return null;
      const { uid, convId } = ctx.params;
      const cfg = await loadConfig();
      const userCount = intOr(m.userMessageCount, 0);
      const wantTitle = m.needsTitle === true;
      const wantMemory = cfg.maxMemoryFacts > 0
        && userCount > 0 && userCount % cfg.memoryEveryNMessages === 0;
      if (!wantTitle && !wantMemory) return null;

      // Охирги 8 хабар (сарлавҳа ва хотира учун етарли контекст).
      const histSnap = await msgsCol(uid, convId)
        .orderBy('createdAt', 'desc')
        .limit(8)
        .get();
      const history = histSnap.docs.map((d) => d.data() || {}).reverse();
      const transcript = history
        .map((h) => `${h.role === 'assistant' ? 'Ёрдамчи' : 'Фойдаланувчи'}: ${String(h.text || '').slice(0, 1200)}`)
        .join('\n\n');

      const jobs = [];
      if (wantTitle) {
        jobs.push((async () => {
          const out = await openAiResponses({
            model: cfg.utilityModel,
            instructions: TITLE_PROMPT,
            input: transcript,
            max_output_tokens: 40,
            store: false,
          }, 20000, true);
          const title = out && out.text
            ? out.text.replace(/^["'«»\s]+|["'«»\s.]+$/g, '').replace(/\s+/g, ' ').slice(0, 60)
            : '';
          if (!title) return;
          // Фойдаланувчи қўлда номлаган бўлса (titleAuto=false) — тегмаймиз.
          const convRef = convsCol(uid).doc(convId);
          await db.runTransaction(async (t) => {
            const c = await t.get(convRef);
            if (!c.exists || (c.data() || {}).titleAuto === false) return;
            t.set(convRef, { title, titleAuto: true }, { merge: true });
          });
        })().catch((e) => console.error('assistant: title failed', e)));
      }

      if (wantMemory) {
        jobs.push((async () => {
          const memSnap = await memoryCol(uid)
            .orderBy('createdAt', 'desc')
            .limit(cfg.maxMemoryFacts)
            .get();
          const existing = memSnap.docs.map((d) => String((d.data() || {}).text || ''));
          const out = await openAiResponses({
            model: cfg.utilityModel,
            instructions: MEMORY_PROMPT,
            input: `МАВЖУД ХОТИРА:\n${existing.length ? existing.map((e) => `- ${e}`).join('\n') : '(бўш)'}\n\nСУҲБАТ:\n${transcript}`,
            max_output_tokens: 300,
            store: false,
          }, 25000, true);
          const facts = out ? parseMemoryFacts(out.text) : [];
          if (!facts.length) return;
          const lower = new Set(existing.map((e) => e.toLowerCase()));
          const batch = db.batch();
          let added = 0;
          for (const f of facts) {
            if (lower.has(f.toLowerCase())) continue;
            batch.set(memoryCol(uid).doc(), {
              text: f,
              sourceConversationId: convId,
              createdAt: FieldValue.serverTimestamp(),
            });
            added += 1;
          }
          if (added) await batch.commit();
          // Чегарадан ошса — энг эскиларини ўчирамиз.
          const total = existing.length + added;
          if (total > cfg.maxMemoryFacts) {
            const old = await memoryCol(uid)
              .orderBy('createdAt', 'asc')
              .limit(total - cfg.maxMemoryFacts)
              .get();
            const del = db.batch();
            old.docs.forEach((d) => del.delete(d.ref));
            await del.commit();
          }
        })().catch((e) => console.error('assistant: memory failed', e)));
      }
      await Promise.all(jobs);
      return null;
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

    const uRef = userRef(uid);
    const ledgerRef = uRef.collection('wallet_ledger').doc();
    const pkgRef = uRef.collection('assistant_packages').doc(idempotencyKey);

    const result = await db.runTransaction(async (t) => {
      const idemSnap = await t.get(idemRef);
      if (idemSnap.exists) {
        return idemSnap.data().result || { ok: true, duplicate: true };
      }
      const userSnap = await t.get(uRef);
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
      const newUntil = Timestamp.fromMillis(newUntilMs);

      // Ledger ko'zgusi (READ fazasi).
      const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
        idempotencyKey: idemKey,
      });

      t.set(uRef, {
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
        paidFrom: Timestamp.fromMillis(base),
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
  // Суҳбатни бошқариш — фақат эга, атайлаб (ChatGPT каби).
  // ---------------------------------------------------------------------
  function requireConvId(data) {
    const id = String((data && data.conversationId) || '').trim();
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
      throw new HttpsError('invalid-argument', 'conversationId');
    }
    return id;
  }

  exportsObj.assistantDeleteConversation = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const convId = requireConvId(data);
    const convRef = convsCol(uid).doc(convId);
    let deleted = 0;
    for (let i = 0; i < 20; i += 1) {
      const snap = await msgsCol(uid, convId).limit(400).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      deleted += snap.size;
      if (snap.size < 400) break;
    }
    await convRef.delete();
    return { ok: true, deleted };
  });

  exportsObj.assistantRenameConversation = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const convId = requireConvId(data);
    const title = String((data && data.title) || '').replace(/\s+/g, ' ').trim().slice(0, 80);
    if (!title) {
      throw new HttpsError('invalid-argument', 'title required');
    }
    const convRef = convsCol(uid).doc(convId);
    const snap = await convRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'conversation_not_found');
    }
    await convRef.set({ title, titleAuto: false }, { merge: true });
    return { ok: true, title };
  });

  exportsObj.assistantDeleteMemory = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const id = String((data && data.memoryId) || '').trim();
    if (id === '*') {
      const snap = await memoryCol(uid).limit(400).get();
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      return { ok: true, deleted: snap.size };
    }
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
      throw new HttpsError('invalid-argument', 'memoryId');
    }
    await memoryCol(uid).doc(id).delete();
    return { ok: true, deleted: 1 };
  });
}

module.exports = {
  attachAssistant,
  ASSISTANT_DEFAULTS,
  tashkentDayKey,
  parseResponsesOutput,
  normalizePackages,
  parseMemoryFacts,
  fallbackTitle,
  scriptRatio,
  needsCyrillicFix,
};
