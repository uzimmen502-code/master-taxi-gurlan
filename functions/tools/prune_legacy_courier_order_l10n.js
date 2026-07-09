#!/usr/bin/env node
/** C-5: Remove legacy courier_order l10n keys (keep active orders-flow keys). */
const fs = require('fs');
const path = require('path');

const KEEP = new Set(['courier_order_total_line', 'courier_orders_total']);

const langDir = path.join(__dirname, '..', '..', 'assets', 'lang');
for (const file of fs.readdirSync(langDir).filter((f) => f.endsWith('.json'))) {
  const p = path.join(langDir, file);
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  let removed = 0;
  for (const key of Object.keys(data)) {
    if (
      (key.startsWith('courier_order_') || key.startsWith('courier_orders_')) &&
      !KEEP.has(key)
    ) {
      delete data[key];
      removed += 1;
    }
  }
  fs.writeFileSync(p, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  console.log(file, 'removed', removed);
}
