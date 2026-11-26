/* eslint-disable no-console */
// Оила боғланиши (эга 2026-11-28) — тоза функциялар. node test/family_links_pure.test.js
const assert = require('assert');
const f = require('../family_links');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const N = { uz_Cyrl: 'Т', uz_Latn: 'T', ru: 'Т' };
const P = { title: N, stage: 'off', internalPhones: [], pilotDistrictIds: [], amount: 5000, minOrderAmount: 0, maxOrderSharePct: 100, validityDays: 30, budgetTotal: 1000000 };

check('F1 шахс калити: +998…, 998…, эски 9 хонали — бир шахс; бошқа — null; жуфтлик калити тартибли', () => {
  assert.strictEqual(f.personKeyOf('+998 90 123 45 67'), '998901234567');
  assert.strictEqual(f.personKeyOf('901234567'), '998901234567');
  assert.strictEqual(f.personKeyOf('12345'), null);
  assert.strictEqual(f.personKeyOf('7901234567'), null);
  assert.strictEqual(f.pairKeyOf('998902', '998901'), '998901_998902');
  assert.strictEqual(f.pairKeyOf('998901', '998902'), f.pairKeyOf('998902', '998901'));
});

check('F2 тескари муносабат: жинс бўйича; номаълум — умумий; турмуш ўртоғи ↔ турмуш ўртоғи', () => {
  assert.strictEqual(f.reverseRelation('spouse', ''), 'spouse');
  assert.strictEqual(f.reverseRelation('father', 'male'), 'son');
  assert.strictEqual(f.reverseRelation('mother', 'female'), 'daughter');
  assert.strictEqual(f.reverseRelation('mother', ''), 'child');
  assert.strictEqual(f.reverseRelation('brother', 'female'), 'sister');
  assert.strictEqual(f.reverseRelation('sister', ''), 'sibling');
  assert.strictEqual(f.reverseRelation('son', 'female'), 'mother');
  assert.strictEqual(f.reverseRelation('daughter', 'male'), 'father');
  assert.strictEqual(f.reverseRelation('son', ''), null, 'ота/она номаълум — рад');
  assert.strictEqual(f.reverseRelation('uncle', 'male'), null, 'бир оиладан ташқари — йўқ');
  assert.ok(!f.INVITE_RELATIONS.includes('uncle'));
});

check('F3 чегаралар: ота-она ≤2, ака-ука/опа-сингил ≤15 (сукут, эга); дастурдан ўзгаради; турмуш ўртоғи ҳисобланмайди', () => {
  const caps = f.capsOf(null);
  assert.deepStrictEqual([caps.parents, caps.siblings], [2, 15]);
  assert.ok(f.capAllows({ parents: 1 }, 'father', caps));
  assert.ok(!f.capAllows({ parents: 2 }, 'mother', caps));
  assert.ok(f.capAllows({ siblings: 14 }, 'brother', caps));
  assert.ok(!f.capAllows({ siblings: 15 }, 'sister', caps));
  assert.ok(f.capAllows({ parents: 99 }, 'spouse', caps));
  assert.deepStrictEqual(f.capsOf({ maxParents: 1, maxSiblings: 3 }).siblings, 3);
  assert.strictEqual(f.counterOf('daughter'), 'children');
});

check('F4 кунлик таклиф: турмуш ўртоғи 3, қариндош 10; янги кун — нолдан', () => {
  const t0 = Date.UTC(2026, 10, 28, 6);
  let st = {};
  for (let i = 0; i < 3; i++) { const r = f.rateCheck(st, 'spouse', t0); assert.ok(r.ok); st = r.next; }
  assert.strictEqual(f.rateCheck(st, 'spouse', t0).ok, false);
  assert.ok(f.rateCheck(st, 'relative', t0).ok, 'алоҳида ҳисоб');
  assert.ok(f.rateCheck(st, 'spouse', t0 + 86400000).ok, 'эртага');
});

check('F5 туғилган сана: ҳақиқий, 1900..бугун; users.birthDate иккала шакли', () => {
  assert.ok(f.birthKeyOk('1990-02-28'));
  assert.ok(!f.birthKeyOk('1990-02-30'));
  assert.ok(!f.birthKeyOk('1899-01-01'));
  assert.ok(!f.birthKeyOk('2999-01-01'));
  assert.strictEqual(f.userBirthKey('5.3.1991'), '1991-03-05');
  assert.strictEqual(f.userBirthKey('1991-03-05'), '1991-03-05');
  assert.strictEqual(f.userBirthKey('x'), null);
  assert.strictEqual(new Date(f.birthMsOf('1991-03-05') + 5 * 3600000).toISOString().slice(0, 10), '1991-03-05');
});

check('F6 дастур валидатори: иккала дастур; чегаралар фақат relative_link; номаълум калит/сумма — рад', () => {
  assert.ok(f.validateFamilyProgram('spouse_link', { ...P, amount: 10000 }).ok);
  assert.ok(f.validateFamilyProgram('relative_link', { ...P, maxParents: 2, maxSiblings: 15 }).ok);
  assert.ok(!f.validateFamilyProgram('spouse_link', { ...P, maxSiblings: 3 }).ok);
  assert.ok(!f.validateFamilyProgram('relatives_birthdays', P).ok);
  assert.ok(!f.validateFamilyProgram('relative_link', { ...P, amount: 0 }).ok);
  assert.ok(!f.validateFamilyProgram('relative_link', { ...P, evil: 1 }).ok);
  assert.ok(!f.validateFamilyProgram('relative_link', { ...P, maxSiblings: 51 }).ok);
});

check('F7 грант id: турмуш ўртоғи — шахсга умрбод бир; қариндош — жуфтлик бўйича ҳар томонга бир', () => {
  assert.strictEqual(f.grantIdFor('spouse_link', '998901', '998901_998902'), 'spouse_link_998901');
  assert.strictEqual(f.grantIdFor('relative_link', '998901', '998901_998902'), 'relative_link_998901_998901_998902');
  assert.notStrictEqual(f.grantIdFor('relative_link', '998901', 'a'), f.grantIdFor('relative_link', '998902', 'a'));
});

check('F8 босқич: off — ҳеч ким, internal — рўйхат, pilot — туман, public — ҳамма', () => {
  assert.ok(!f.stageAllows({ stage: 'off' }, '998901'));
  assert.ok(f.stageAllows({ stage: 'internal', internalPhones: ['998901'] }, '998901'));
  assert.ok(!f.stageAllows({ stage: 'internal', internalPhones: [] }, '998901'));
  assert.ok(f.stageAllows({ stage: 'pilot', internalPhones: [], pilotDistrictIds: ['gurlan'] }, '998901', 'gurlan'));
  assert.ok(f.stageAllows({ stage: 'public' }, '998901'));
});

check('F9 матнлар 3 тилда, uz_Latn янги алифбода; бонус хабари сумма ва кун билан', () => {
  for (const k of Object.keys(f.NOTICE)) {
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(f.NOTICE[k][l].title && f.NOTICE[k][l].body, `${k} ${l}`);
    assert.ok(!/o'|g'|sh|ch/i.test(f.NOTICE[k].uz_Latn.body + f.NOTICE[k].uz_Latn.title), k);
  }
  assert.ok(f.NOTICE.bonus.uz_Cyrl.body.includes('{amount}') && f.NOTICE.bonus.uz_Cyrl.body.includes('{days}'));
  assert.ok(f.NOTICE.invite_spouse.uz_Cyrl.body.startsWith('{name} сизни турмуш ўртоғи деб кўрсатди'));
  for (const c of ['SPOUSE_EXISTS', 'CAP_REACHED', 'RATE_LIMITED']) assert.ok(!/o'|g'|sh|ch/i.test(f.messagesOf(c).uz_Latn), c);
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
