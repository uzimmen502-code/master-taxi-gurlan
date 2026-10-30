/**
 * `functions/tools/retire_old_vitrine_items.js` — соф танлов (Firestore керак эмас).
 *   node test/retire_old_vitrine_items_tool.test.js
 */
'use strict';
const assert = require('assert');
const { selectTargets, CUTOFF_MS } = require('../tools/retire_old_vitrine_items');

const before = CUTOFF_MS - 1000;
const after = CUTOFF_MS + 1000;
const items = [
  { id: 'old_active', businessId: '', status: 'active', createdAtMs: before },
  { id: 'old_deleted', businessId: '', status: 'deleted', createdAtMs: before },
  { id: 'new_own_shop', businessId: '', status: 'active', createdAtMs: after },
  { id: 'biz_old', businessId: 'b1', status: 'active', createdAtMs: before },
  { id: 'boundary', businessId: '', status: 'active', createdAtMs: CUTOFF_MS },
];
const clips = [
  { id: 'c1', shopItemId: 'old_active', status: 'active' },
  { id: 'c2', shopItemId: 'old_deleted', status: 'active' },
  { id: 'c3', shopItemId: 'new_own_shop', status: 'active' },
  { id: 'c4', shopItemId: 'biz_old', status: 'active' },
  { id: 'c5', shopItemId: 'old_active', status: 'deleted' },
  { id: 'c6', shopItemId: '', status: 'active' },
];

const t = selectTargets(items, clips);
// Позитив: эски фаол товар ва эски товарларнинг (ўчирилганиники ҳам) фаол клиплари.
assert.deepStrictEqual(t.items.map((i) => i.id), ['old_active']);
assert.deepStrictEqual(t.clips.map((c) => c.id).sort(), ['c1', 'c2']);
// Негатив: янги асосий дўкон товари, бизнес товари, боғланмаган клип тегилмайди.
assert.ok(!t.clips.some((c) => ['c3', 'c4', 'c6'].includes(c.id)));
// Чегара: CUTOFF ning ўзи — янги ҳисобланади.
assert.ok(!t.items.some((i) => i.id === 'boundary'));
assert.strictEqual(t.skippedNewItems, 2);
// Иккинчи марта ишга туширилса (идемпотент): ўчирилганлар қайта танланмайди.
const again = selectTargets(items.map((i) => (i.id === 'old_active' ? { ...i, status: 'deleted' } : i)), clips.map((c) => (['c1', 'c2'].includes(c.id) ? { ...c, status: 'deleted' } : c)));
assert.strictEqual(again.items.length + again.clips.length, 0);
console.log('retire_old_vitrine_items_tool: 6/6 OK');
