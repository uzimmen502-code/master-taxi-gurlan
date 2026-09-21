/**
 * assistant_chat.js — kunlik limit / Pro / paket sotib olish mantig'i.
 *
 * Emulator KERAK EMAS: minimal in-memory Firestore taqlidi (doc/get/set/
 * runTransaction/batch/orderBy+limit) va global `fetch` mock (OpenAI).
 * settlementLedger ham stub — faqat chaqirilganini tekshiradi.
 *
 * Ishlatish: npm run test:assistant
 */
'use strict';
const assert = require('assert');
const { attachAssistant, tashkentDayKey } = require('../assistant_chat');

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
const functions = {
  https: {
    HttpsError,
    onCall: (fn) => fn,
  },
  runWith: () => ({ https: { onCall: (fn) => fn } }),
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

// ---------------------------------------------------------------- tests
async function main() {
  const UID = '998901234567';
  const db = makeDb();
  db._store.set(`users/${UID}`, { phone: UID, bonusBalance: 20000 });
  db._store.set('settings/assistant', { freeDailyLimit: 2, proWebSearchDailyLimit: 1 });

  let fetchCalls = [];
  global.fetch = async (url, opts) => {
    const body = JSON.parse(opts.body);
    fetchCalls.push(body);
    const output = [];
    if (body.tools) output.push({ type: 'web_search_call' });
    output.push({ type: 'message', content: [{ type: 'output_text', text: `echo:${body.input.at(-1).content}` }] });
    return { ok: true, status: 200, json: async () => ({ output, usage: { input_tokens: 3, output_tokens: 2 } }) };
  };
  process.env.OPENAI_API_KEY = 'sk-test';

  attachAssistant(handlers, { functions, db, admin, callerPhone, canonicalUid, settlementLedger });

  // 1) status — bepul
  let st = await handlers.assistantGetStatus({}, ctx(UID));
  assert.strictEqual(st.pro, false);
  assert.strictEqual(st.dailyLimit, 2);
  assert.strictEqual(st.packages.length, 3);
  assert.strictEqual(st.balance, 20000);

  // 2) auth talab
  await expectError(handlers.assistantChat({ text: 'hi' }, {}), 'unauthenticated');
  await expectError(handlers.assistantChat({ text: '' }, ctx(UID)), 'invalid-argument');

  // 3) 2 ta bepul xabar o'tadi, 3-chisi daily_limit
  let r = await handlers.assistantChat({ text: 'salom' }, ctx(UID));
  assert.strictEqual(r.reply, 'echo:salom');
  assert.strictEqual(r.status.usedToday, 1);
  assert.strictEqual(fetchCalls[0].tools, undefined, 'bepulda web_search yo\'q');
  r = await handlers.assistantChat({ text: 'ikki' }, ctx(UID));
  assert.strictEqual(r.status.usedToday, 2);
  const err = await expectError(handlers.assistantChat({ text: 'uch' }, ctx(UID)), 'resource-exhausted', 'daily_limit');
  assert.strictEqual(err.details.pro, false);
  assert.strictEqual(fetchCalls.length, 2, 'limitdan keyin OpenAI chaqirilmaydi');

  // tarix: 4 ta hujjat (2 user + 2 assistant), 2-so'rovda 1-suhbat kontekstga kirgan
  const hist = await db.collection('users').doc(UID).collection('assistant_messages').get();
  assert.strictEqual(hist.size, 4);
  assert.strictEqual(fetchCalls[1].input.length, 3, 'history(2) + yangi xabar');
  assert.strictEqual(fetchCalls[1].input[1].role, 'assistant');

  // 4) paket: noma'lum id / idempotencyKey yo'q
  await expectError(handlers.assistantBuyPackage({ packageId: 'x', idempotencyKey: 'k1' }, ctx(UID)), 'invalid-argument', 'unknown_package');
  await expectError(handlers.assistantBuyPackage({ packageId: 'd7' }, ctx(UID)), 'invalid-argument');

  // 5) balans yetmaydi (d30 = 30000 > 20000)
  const ins = await expectError(handlers.assistantBuyPackage({ packageId: 'd30', idempotencyKey: 'k2' }, ctx(UID)), 'failed-precondition', 'insufficient_balance');
  assert.strictEqual(ins.details.balance, 20000);

  // 6) d7 sotib olish — balans 5000, Pro 7 kun
  const before = Date.now();
  const buy = await handlers.assistantBuyPackage({ packageId: 'd7', idempotencyKey: 'k3' }, ctx(UID));
  assert.strictEqual(buy.ok, true);
  assert.strictEqual(buy.balance, 5000);
  assert.ok(buy.paidUntil >= before + 7 * 86400000 - 5 && buy.paidUntil <= Date.now() + 7 * 86400000 + 5);
  assert.strictEqual(ledgerCalls.length, 1);
  assert.strictEqual(ledgerCalls[0].delta, -15000);
  assert.strictEqual(ledgerCalls[0].refType, 'assistant_package');
  const userAfter = db._store.get(`users/${UID}`);
  assert.strictEqual(userAfter.bonusBalance, 5000);
  const ledgerDocs = await db.collection('users').doc(UID).collection('wallet_ledger').get();
  assert.strictEqual(ledgerDocs.size, 1);
  assert.strictEqual(ledgerDocs.docs[0].data().amount, -15000);

  // 7) idempotent takror — qayta yechilmaydi
  const dup = await handlers.assistantBuyPackage({ packageId: 'd7', idempotencyKey: 'k3' }, ctx(UID));
  assert.strictEqual(dup.balance, 5000);
  assert.strictEqual(db._store.get(`users/${UID}`).bonusBalance, 5000);
  assert.strictEqual(ledgerCalls.length, 1);

  // 8) Pro: limit endi 300, web_search 1 marta ruxsat, keyin o'chadi
  st = await handlers.assistantGetStatus({}, ctx(UID));
  assert.strictEqual(st.pro, true);
  assert.strictEqual(st.dailyLimit, 300);
  assert.strictEqual(st.webSearchLimit, 1);
  r = await handlers.assistantChat({ text: 'ob-havo' }, ctx(UID));
  assert.deepStrictEqual(fetchCalls[2].tools, [{ type: 'web_search' }]);
  assert.strictEqual(r.webSearches, 1);
  assert.strictEqual(r.status.webSearchesToday, 1);
  r = await handlers.assistantChat({ text: 'yana' }, ctx(UID));
  assert.strictEqual(fetchCalls[3].tools, undefined, 'web search limiti tugadi');
  assert.strictEqual(r.status.usedToday, 4);

  // 9) OpenAI xatosi — xabar hisobi qaytariladi
  global.fetch = async () => ({ ok: false, status: 500, json: async () => ({ error: { message: 'boom' } }) });
  await expectError(handlers.assistantChat({ text: 'x' }, ctx(UID)), 'unavailable', 'upstream_error');
  const usage = db._store.get(`users/${UID}/assistant_usage/${tashkentDayKey()}`);
  assert.strictEqual(usage.messages, 4, 'refund');

  // 10) API kaliti yo'q
  delete process.env.OPENAI_API_KEY;
  await expectError(handlers.assistantChat({ text: 'x' }, ctx(UID)), 'failed-precondition', 'api_key_missing');
  assert.strictEqual(db._store.get(`users/${UID}/assistant_usage/${tashkentDayKey()}`).messages, 4);

  // 11) tarixni tozalash
  const cleared = await handlers.assistantClearHistory({}, ctx(UID));
  assert.strictEqual(cleared.deleted, 8);
  const after = await db.collection('users').doc(UID).collection('assistant_messages').get();
  assert.strictEqual(after.size, 0);

  // 13) freeProPhones — paketsiz doimiy Pro (default: 998912778777)
  const OWNER = '998912778777';
  db._store.set(`users/${OWNER}`, { phone: OWNER, bonusBalance: 0 });
  global.fetch = async (url, opts) => ({ ok: true, status: 200, json: async () => ({
    output: [{ type: 'message', content: [{ type: 'output_text', text: 'ok' }] }], usage: {} }) });
  process.env.OPENAI_API_KEY = 'sk-test';
  const ost = await handlers.assistantGetStatus({}, ctx(OWNER));
  assert.strictEqual(ost.pro, true);
  assert.strictEqual(ost.unlimited, true);
  assert.strictEqual(ost.paidUntil, null);
  assert.strictEqual(ost.dailyLimit, 300);
  for (let i = 0; i < 3; i += 1) await handlers.assistantChat({ text: `q${i}` }, ctx(OWNER));
  const ost2 = await handlers.assistantGetStatus({}, ctx(OWNER));
  assert.strictEqual(ost2.usedToday, 3);
  assert.strictEqual(ost2.pro, true);

  // 12) Tashkent kun kaliti (UTC 20:30 → ertangi kun)
  assert.strictEqual(tashkentDayKey(Date.UTC(2026, 8, 21, 20, 30)), '2026-09-22');
  assert.strictEqual(tashkentDayKey(Date.UTC(2026, 8, 21, 18, 30)), '2026-09-21');

  console.log('assistant_chat.test.js: OK (12 bo\'lim)');
}

main().catch((e) => { console.error(e); process.exit(1); });
