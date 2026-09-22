/**
 * assistant_chat.js — kunlik limit / Pro / paket sotib olish / suhbatlar /
 * xotira (trigger) mantig'i.
 *
 * Emulator KERAK EMAS: minimal in-memory Firestore taqlidi (doc/get/set/
 * delete/runTransaction/batch/orderBy+limit, ichma-ich kolleksiyalar) va
 * global `fetch` mock (OpenAI). settlementLedger ham stub.
 *
 * Ishlatish: npm run test:assistant
 */
'use strict';
const assert = require('assert');
const {
  attachAssistant, tashkentDayKey, parseMemoryFacts, fallbackTitle,
} = require('../assistant_chat');

// ---------------------------------------------------------------- fake db
class FakeTs {
  constructor(ms) { this.ms = ms; }
  toMillis() { return this.ms; }
}
const SERVER_TS = Symbol('serverTimestamp');
class Increment { constructor(n) { this.n = n; } }

function applyData(prev, data, merge) {
  const out = merge ? { ...(prev || {}) } : {};
  for (const [k, v] of Object.entries(data)) {
    if (v === SERVER_TS) out[k] = new FakeTs(Date.now());
    else if (v instanceof Increment) out[k] = (Number(out[k]) || 0) + v.n;
    else out[k] = v;
  }
  return out;
}

function makeDb() {
  const store = new Map(); // path -> data
  let autoId = 0;
  const docRef = (path) => ({
    id: path.split('/').pop(),
    path,
    async get() { return snap(path); },
    async set(data, opts) {
      store.set(path, applyData(store.get(path), data, !!(opts && opts.merge)));
    },
    async delete() { store.delete(path); },
    collection: (name) => colRef(`${path}/${name}`),
  });
  const snap = (path) => ({
    id: path.split('/').pop(),
    ref: docRef(path),
    exists: store.has(path),
    data: () => (store.has(path) ? { ...store.get(path) } : undefined),
  });
  const colRef = (path) => {
    const q = { _limit: 0, _desc: false, _orderBy: null };
    const api = {
      doc: (id) => docRef(`${path}/${id || `auto${++autoId}`}`),
      orderBy(f, dir) { q._orderBy = f; q._desc = dir === 'desc'; return api; },
      limit(n) { q._limit = n; return api; },
      async get() {
        let docs = [...store.keys()]
          .filter((k) => k.startsWith(`${path}/`) && !k.slice(path.length + 1).includes('/'))
          .map((k) => snap(k));
        if (q._orderBy) {
          docs.sort((a, b) => {
            const av = a.data()[q._orderBy]; const bv = b.data()[q._orderBy];
            const am = av && av.toMillis ? av.toMillis() : Number(av) || 0;
            const bm = bv && bv.toMillis ? bv.toMillis() : Number(bv) || 0;
            return q._desc ? bm - am : am - bm;
          });
        }
        if (q._limit) docs = docs.slice(0, q._limit);
        return { docs, empty: docs.length === 0, size: docs.length };
      },
    };
    return api;
  };
  const db = {
    _store: store,
    collection: (name) => colRef(name),
    async runTransaction(fn) {
      const t = {
        get: (ref) => ref.get(),
        set: (ref, data, opts) => { ref.set(data, opts); },
      };
      return fn(t);
    },
    batch() {
      const ops = [];
      return {
        set: (ref, data, opts) => ops.push(() => ref.set(data, opts)),
        delete: (ref) => ops.push(() => store.delete(ref.path)),
        async commit() { for (const op of ops) await op(); },
      };
    },
  };
  return db;
}

const admin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => SERVER_TS,
      increment: (n) => new Increment(n),
    },
    Timestamp: { fromMillis: (ms) => new FakeTs(ms) },
  },
};

class HttpsError extends Error {
  constructor(code, message, details) {
    super(message); this.code = code; this.details = details;
  }
}
const handlers = {};
const triggers = {};
const functionsApi = {
  https: { HttpsError, onCall: (fn) => fn },
  runWith: () => ({
    https: { onCall: (fn) => fn },
    firestore: {
      document: (pattern) => ({
        onCreate: (fn) => { triggers[pattern] = fn; return fn; },
      }),
    },
  }),
};

const ledgerCalls = [];
const settlementLedger = {
  prepareBonusInTx: async (t, db, uid, o) => ({ uid, o }),
  commitBonusInTx: (t, ctx, input) => { ledgerCalls.push(input); },
};

const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const callerPhone = (c) => (c.auth.token.phone_number || '').replace(/\D/g, '');
const canonicalUid = (v) => v;

async function expectError(promise, code, message) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `code: ${e.code} (${e.message})`);
    if (message) assert.strictEqual(e.message, message);
    return e;
  }
  assert.fail(`expected error ${code}/${message}`);
}

/** Trigger'ni qo'lda chaqirish: oxirgi yozilgan assistant xabari uchun. */
async function fireTrigger(db, uid, convId) {
  const pattern = Object.keys(triggers)[0];
  const msgs = await db.collection('users').doc(uid)
    .collection('assistant_conversations').doc(convId)
    .collection('assistant_messages').orderBy('createdAt', 'desc').limit(1).get();
  const snap = msgs.docs[0];
  await triggers[pattern](snap, { params: { uid, convId, msgId: snap.id } });
}

// ---------------------------------------------------------------- tests
async function main() {
  const UID = '998901234567';
  const db = makeDb();
  db._store.set(`users/${UID}`, { phone: UID, bonusBalance: 20000 });
  const PKGS = [{ id: 'd7', days: 7, price: 15000 }, { id: 'd15', days: 15, price: 25000 }, { id: 'd30', days: 30, price: 30000, promo: true }];
  db._store.set('settings/assistant', { freeDailyLimit: 2, proWebSearchDailyLimit: 1, memoryEveryNMessages: 1, packages: PKGS });

  let fetchCalls = [];
  global.fetch = async (url, opts) => {
    const body = JSON.parse(opts.body);
    fetchCalls.push(body);
    const output = [];
    let text;
    if (body.model === 'gpt-4.1-mini' && body.max_output_tokens === 40) {
      text = '"Salom va tanishuv"';
    } else if (body.model === 'gpt-4.1-mini') {
      text = '{"facts": ["Isimi Aziz", "Urganchda yashaydi"]}';
    } else {
      if (body.tools) output.push({ type: 'web_search_call' });
      text = `echo:${body.input.at(-1).content}`;
    }
    output.push({ type: 'message', content: [{ type: 'output_text', text }] });
    return { ok: true, status: 200, json: async () => ({ output, usage: { input_tokens: 3, output_tokens: 2 } }) };
  };
  process.env.OPENAI_API_KEY = 'sk-test';

  attachAssistant(handlers, {
    functions: functionsApi, db, admin, callerPhone, canonicalUid, settlementLedger,
  });
  assert.ok(handlers.onAssistantMessageCreated, 'trigger eksport qilingan');

  // 1) status — bepul
  let st = await handlers.assistantGetStatus({}, ctx(UID));
  assert.strictEqual(st.pro, false);
  assert.strictEqual(st.dailyLimit, 2);
  assert.strictEqual(st.packages.length, 3);
  assert.strictEqual(st.balance, 20000);

  // 2) auth talab
  await expectError(handlers.assistantChat({ text: 'hi' }, {}), 'unauthenticated');
  await expectError(handlers.assistantChat({ text: '' }, ctx(UID)), 'invalid-argument');
  await expectError(handlers.assistantChat({ text: 'x', conversationId: 'nope' }, ctx(UID)), 'not-found');

  // 3) 2 ta bepul xabar (bitta suhbat), 3-chisi daily_limit
  let r = await handlers.assistantChat({ text: 'salom' }, ctx(UID));
  assert.strictEqual(r.reply, 'echo:salom');
  assert.strictEqual(r.status.usedToday, 1);
  assert.ok(r.conversationId, 'yangi suhbat id');
  const convId = r.conversationId;
  assert.strictEqual(fetchCalls[0].tools, undefined, 'bepulda web_search yo\'q');
  const conv1 = db._store.get(`users/${UID}/assistant_conversations/${convId}`);
  assert.strictEqual(conv1.title, 'salom', 'fallback sarlavha');
  assert.ok(conv1.expiresAt.toMillis() > Date.now() + 364 * 86400000, '365 kun TTL');

  r = await handlers.assistantChat({ text: 'ikki', conversationId: convId }, ctx(UID));
  assert.strictEqual(r.conversationId, convId);
  assert.strictEqual(r.status.usedToday, 2);
  const err = await expectError(handlers.assistantChat({ text: 'uch', conversationId: convId }, ctx(UID)), 'resource-exhausted', 'daily_limit');
  assert.strictEqual(err.details.pro, false);
  assert.strictEqual(fetchCalls.length, 2, 'limitdan keyin OpenAI chaqirilmaydi');

  // tarix: 4 ta hujjat (2 user + 2 assistant), 2-so'rovda 1-suhbat kontekstga kirgan
  const hist = await db.collection('users').doc(UID).collection('assistant_conversations')
    .doc(convId).collection('assistant_messages').get();
  assert.strictEqual(hist.size, 4);
  assert.strictEqual(fetchCalls[1].input.length, 3, 'history(2) + yangi xabar');
  assert.strictEqual(fetchCalls[1].input[1].role, 'assistant');
  assert.strictEqual(db._store.get(`users/${UID}/assistant_conversations/${convId}`).messageCount, 4);

  // 4) trigger: sarlavha (1-javob) + xotira
  const before = fetchCalls.length;
  // 1-javob xabarini topib trigger'ni chaqiramiz (needsTitle=true)
  const firstBot = [...db._store.entries()].find(([k, v]) => k.includes(`/${convId}/assistant_messages/`) && v.needsTitle === true);
  assert.ok(firstBot, 'needsTitle xabari bor');
  const pattern = Object.keys(triggers)[0];
  await triggers[pattern](
    { id: firstBot[0].split('/').pop(), data: () => firstBot[1] },
    { params: { uid: UID, convId, msgId: 'x' } },
  );
  assert.strictEqual(fetchCalls.length, before + 2, 'title + memory chaqiruvi');
  assert.strictEqual(db._store.get(`users/${UID}/assistant_conversations/${convId}`).title, 'Salom va tanishuv');
  const mem = await db.collection('users').doc(UID).collection('assistant_memory').get();
  assert.strictEqual(mem.size, 2, 'xotira 2 ta fakt');
  // takror trigger — dublikat yozilmaydi
  await fireTrigger(db, UID, convId);
  assert.strictEqual((await db.collection('users').doc(UID).collection('assistant_memory').get()).size, 2);

  // 5) yangi suhbatda xotira prompt'ga kiradi
  db._store.set('settings/assistant', { freeDailyLimit: 10, proWebSearchDailyLimit: 1, memoryEveryNMessages: 1, packages: PKGS });
  r = await handlers.assistantChat({ text: 'men kimman?' }, ctx(UID));
  assert.notStrictEqual(r.conversationId, convId, 'yangi suhbat');
  const lastBody = fetchCalls.at(-1);
  assert.ok(lastBody.instructions.includes('ЭСДА ТУТИЛГАНЛАР'), 'xotira bo\'limi');
  assert.ok(lastBody.instructions.includes('Isimi Aziz'));
  assert.strictEqual(lastBody.input.length, 1, `yangi suhbat — tarix yo'q: ${JSON.stringify(lastBody.input)}`);

  // 6) rename / delete suhbat, delete memory
  await handlers.assistantRenameConversation({ conversationId: convId, title: '  Mening  chatim ' }, ctx(UID));
  assert.strictEqual(db._store.get(`users/${UID}/assistant_conversations/${convId}`).title, 'Mening chatim');
  assert.strictEqual(db._store.get(`users/${UID}/assistant_conversations/${convId}`).titleAuto, false);
  const del = await handlers.assistantDeleteConversation({ conversationId: convId }, ctx(UID));
  assert.strictEqual(del.deleted, 4);
  assert.strictEqual(db._store.has(`users/${UID}/assistant_conversations/${convId}`), false);
  const memId = (await db.collection('users').doc(UID).collection('assistant_memory').get()).docs[0].id;
  await handlers.assistantDeleteMemory({ memoryId: memId }, ctx(UID));
  assert.strictEqual((await db.collection('users').doc(UID).collection('assistant_memory').get()).size, 1);
  await handlers.assistantDeleteMemory({ memoryId: '*' }, ctx(UID));
  assert.strictEqual((await db.collection('users').doc(UID).collection('assistant_memory').get()).size, 0);

  // 7) paket: noma'lum id / idempotencyKey yo'q / balans yetmaydi
  await expectError(handlers.assistantBuyPackage({ packageId: 'x', idempotencyKey: 'k1' }, ctx(UID)), 'invalid-argument', 'unknown_package');
  await expectError(handlers.assistantBuyPackage({ packageId: 'd7' }, ctx(UID)), 'invalid-argument');
  const ins = await expectError(handlers.assistantBuyPackage({ packageId: 'd30', idempotencyKey: 'k2' }, ctx(UID)), 'failed-precondition', 'insufficient_balance');
  assert.strictEqual(ins.details.balance, 20000);

  // 8) d7 sotib olish — balans 5000, Pro 7 kun; idempotent
  const t0 = Date.now();
  const buy = await handlers.assistantBuyPackage({ packageId: 'd7', idempotencyKey: 'k3' }, ctx(UID));
  assert.strictEqual(buy.balance, 5000);
  assert.ok(buy.paidUntil >= t0 + 7 * 86400000 - 5);
  assert.strictEqual(ledgerCalls.length, 1);
  assert.strictEqual(ledgerCalls[0].refType, 'assistant_package');
  const dup = await handlers.assistantBuyPackage({ packageId: 'd7', idempotencyKey: 'k3' }, ctx(UID));
  assert.strictEqual(dup.balance, 5000);
  assert.strictEqual(ledgerCalls.length, 1);

  // 9) Pro: web_search 1 marta, keyin o'chadi
  st = await handlers.assistantGetStatus({}, ctx(UID));
  assert.strictEqual(st.pro, true);
  assert.strictEqual(st.webSearchLimit, 1);
  r = await handlers.assistantChat({ text: 'ob-havo' }, ctx(UID));
  assert.deepStrictEqual(fetchCalls.at(-1).tools, [{ type: 'web_search' }]);
  assert.strictEqual(r.webSearches, 1);
  r = await handlers.assistantChat({ text: 'yana' }, ctx(UID));
  assert.strictEqual(fetchCalls.at(-1).tools, undefined, 'web search limiti tugadi');

  // 10) OpenAI xatosi — xabar hisobi qaytariladi
  const usedBefore = r.status.usedToday;
  global.fetch = async () => ({ ok: false, status: 500, json: async () => ({ error: { message: 'boom' } }) });
  await expectError(handlers.assistantChat({ text: 'x' }, ctx(UID)), 'unavailable', 'upstream_error');
  assert.strictEqual(db._store.get(`users/${UID}/assistant_usage/${tashkentDayKey()}`).messages, usedBefore, 'refund');

  // 11) API kaliti yo'q
  delete process.env.OPENAI_API_KEY;
  await expectError(handlers.assistantChat({ text: 'x' }, ctx(UID)), 'failed-precondition', 'api_key_missing');

  // 12a) default paket — bir martalik 25 000 (once, 3650 kun)
  db._store.set('settings/assistant', {});
  const dst = await handlers.assistantGetStatus({}, ctx(UID));
  assert.deepStrictEqual(dst.packages, [{ id: 'once', days: 3650, price: 25000, promo: false, oneTime: true }]);

  // 12) freeProPhones — paketsiz doimiy Pro
  const OWNER = '998912778777';
  db._store.set(`users/${OWNER}`, { phone: OWNER, bonusBalance: 0 });
  const ost = await handlers.assistantGetStatus({}, ctx(OWNER));
  assert.strictEqual(ost.pro, true);
  assert.strictEqual(ost.unlimited, true);
  assert.strictEqual(ost.paidUntil, null);

  // 13) yordamchilar
  assert.strictEqual(tashkentDayKey(Date.UTC(2026, 8, 21, 20, 30)), '2026-09-22');
  assert.deepStrictEqual(parseMemoryFacts('text {"facts":["a b c", ""]} tail'), ['a b c']);
  assert.deepStrictEqual(parseMemoryFacts('garbage'), []);
  assert.strictEqual(fallbackTitle('  bir  ikki uch to\'rt besh olti yetti '), 'bir ikki uch to\'rt besh olti');
  const { needsCyrillicFix } = require('../assistant_chat');
  assert.strictEqual(needsCyrillicFix('Python ва JavaScript фарқи?',
    'Quyida Python va JavaScript asosiy farqlari — qisqa jadval ko‘rinishida:\n| Xususiyat | Python | JavaScript |\n| Turlanish | dinamik, o‘qish oson | dinamik, brauzerda ishlaydi |'), true);
  assert.strictEqual(needsCyrillicFix('Python ва JavaScript фарқи?', 'Python ва JavaScript фарқлари:\n```js\nconst a = 1;\n```\n- Python динамик'), false, 'kod bloki hisobga olinmaydi');
  assert.strictEqual(needsCyrillicFix('Salom, qanday?', 'Salom! Yaxshi.'), false, 'lotin savol — tegilmaydi');

  console.log('assistant_chat.test.js: OK (13 bo\'lim)');
}

main().catch((e) => { console.error(e); process.exit(1); });
