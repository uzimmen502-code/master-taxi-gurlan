/**
 * Ҳамённи тўлдириш ёрдамчилари — `functions/wallet_topup_support.js`.
 *
 *   npm run test:wallet-topup-support   (functions/ ичидан)
 */
'use strict';
const assert = require('assert');
const {cardIsValid, topUpReadiness, makeFinanceNotifier} = require('../wallet_topup_support');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}
async function checkAsync(name, fn) {
  try { await fn(); check(name, true); } catch (e) { console.log(`       ${e.message}`); check(name, false); }
}

// ── карта ──
check('Луна: тўғри 16 рақамли карта', cardIsValid('4111111111111111') && cardIsValid('4111 1111 1111 1111') && cardIsValid('4111-1111-1111-1111'));
check('Луна: бир рақами хато — рад', !cardIsValid('4111111111111112'));
check('16 рақам эмас (қисқа/узун/ҳарф) — рад', !cardIsValid('411111111111111') && !cardIsValid('41111111111111111') && !cardIsValid('41111111111111ab') && !cardIsValid(''));
check('null/undefined/рақам — йиқилмайди', cardIsValid(null) === false && cardIsValid(undefined) === false && cardIsValid(4111111111111111) === true);

// ── тайёрлик ──
const OK = '4111111111111111';
check('тайёр: бот ёқиқ ва карта тўғри', JSON.stringify(topUpReadiness({enabled: true, depositCardNumber: OK})) === JSON.stringify({ready: true, reason: 'ok'}));
check('бот ўчиқ — тайёр эмас', JSON.stringify(topUpReadiness({enabled: false, depositCardNumber: OK})) === JSON.stringify({ready: false, reason: 'bot_disabled'}));
check('карта йўқ/бўш/бўшлиқ — тайёр эмас',
    ['', '   ', undefined].every((c) => JSON.stringify(topUpReadiness({enabled: true, depositCardNumber: c})) === JSON.stringify({ready: false, reason: 'card_missing'})));
check('нотўғри (Луна) карта БЛОКЛАМАЙДИ, лекин сабаб айтилади (production узилмасин)',
    JSON.stringify(topUpReadiness({enabled: true, depositCardNumber: '8600000000000001'})) === JSON.stringify({ready: true, reason: 'card_invalid'}));
check('созлама йўқ (бўш ҳужжат) — карта йўқ', topUpReadiness({}).reason === 'card_missing' && topUpReadiness(null).reason === 'card_missing');

// ── молияга хабар ──
function fakeDb(users) {
  return {
    collection(name) {
      assert.strictEqual(name, 'users');
      return {
        where(field, op, roles) {
          assert.strictEqual(field, 'role');
          assert.strictEqual(op, 'in');
          return {
            limit: (n) => ({
              get: async () => {
                const docs = users.filter((u) => roles.includes(u.role)).slice(0, n)
                    .map((u) => ({id: u.id, data: () => u}));
                return {docs, size: docs.length};
              },
            }),
          };
        },
      };
    },
  };
}

(async () => {
  const USERS = [
    {id: '998905000001', role: 'finance', telegramId: '111'},
    {id: '998905000002', role: 'superadmin'},
    {id: '998901000001', role: 'user', telegramId: '999'},
    {id: '998905000003', role: 'dispatcher', telegramId: '888'},
  ];

  await checkAsync('чек: фақат finance ва superadmin; Telegram фақат боғланганга', async () => {
    const inApp = [];
    const tg = [];
    const notify = makeFinanceNotifier({
      db: fakeDb(USERS),
      notifyUserInApp: async (m) => { inApp.push(m); },
      sendTelegram: async (chat, text) => { tg.push({chat, text}); },
    });
    const r = await notify({kind: 'topup', requestId: 'REQ1234567890', amount: 150000});
    assert.deepStrictEqual(inApp.map((m) => m.userId).sort(), ['998905000001', '998905000002']);
    assert.strictEqual(r.notified, 2);
    assert.deepStrictEqual(tg.map((t) => t.chat), ['111']);
    assert.ok(tg[0].text.includes('150'), 'сумма матнда');
    assert.ok(tg[0].text.includes('REQ1234567890'), 'сўров ID матнда');
    assert.strictEqual(inApp[0].extraData.kind, 'topup');
    assert.strictEqual(inApp[0].source, 'wallet_finance_queue');
  });

  await checkAsync('хабарда телефон ва карта рақами ЙЎҚ (фақат сумма ва ID)', async () => {
    const inApp = [];
    const tg = [];
    const notify = makeFinanceNotifier({
      db: fakeDb(USERS),
      notifyUserInApp: async (m) => { inApp.push(m); },
      sendTelegram: async (chat, text) => { tg.push(text); },
    });
    await notify({kind: 'withdraw', requestId: 'W-1', amount: 20000});
    const all = JSON.stringify([inApp, tg]);
    assert.ok(!/998901000001/.test(all), 'фойдаланувчи телефони чиқмаслиги керак');
    assert.ok(!/\d{16}/.test(all), 'карта рақами чиқмаслиги керак');
    assert.strictEqual(inApp[0].dataType, 'wallet_finance_queue');
    assert.ok(/ечиш/i.test(inApp[0].title));
  });

  await checkAsync('битта қабул қилувчининг хатоси қолганларга таъсир қилмайди', async () => {
    const ok = [];
    const notify = makeFinanceNotifier({
      db: fakeDb(USERS),
      notifyUserInApp: async (m) => {
        if (m.userId === '998905000001') throw new Error('fcm down');
        ok.push(m.userId);
      },
      sendTelegram: async () => { throw new Error('tg down'); },
    });
    const r = await notify({kind: 'topup', requestId: 'X', amount: 1});
    assert.deepStrictEqual(ok, ['998905000002']);
    assert.strictEqual(r.notified, 1);
  });

  await checkAsync('молия ходими йўқ — йиқилмайди', async () => {
    const notify = makeFinanceNotifier({db: fakeDb([{id: '1', role: 'user'}]), notifyUserInApp: async () => {}, sendTelegram: async () => {}});
    const r = await notify({kind: 'topup', requestId: 'X', amount: 1});
    assert.deepStrictEqual(r, {notified: 0, recipients: 0});
  });

  await checkAsync('Telegram йўқ (sendTelegram берилмаган) — фақат иловада', async () => {
    const inApp = [];
    const notify = makeFinanceNotifier({db: fakeDb(USERS), notifyUserInApp: async (m) => { inApp.push(m); }});
    await notify({kind: 'topup', requestId: 'X', amount: 1});
    assert.strictEqual(inApp.length, 2);
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
})();
