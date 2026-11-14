#!/usr/bin/env node
/**
 * C-0: READ-ONLY audit of legacy `courier_orders` collection.
 *
 * Usage:
 *   $env:NODE_OPTIONS="--use-system-ca"
 *   node functions/tools/audit_courier_orders_collection.js
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require(keyPath)),
    preferRest: true,
  });
}

const db = admin.firestore();

function ts(v) {
  try {
    if (!v) return null;
    if (typeof v.toDate === 'function') return v.toDate();
    return null;
  } catch (_) {
    return null;
  }
}

function daysAgo(d) {
  if (!d) return null;
  return Math.floor((Date.now() - d.getTime()) / 86400000);
}

async function main() {
  const snap = await db.collection('courier_orders').get();
  const total = snap.size;
  console.log('=== courier_orders audit (READ-ONLY) ===');
  console.log(`Total documents: ${total}`);

  if (total === 0) {
    console.log('\nVerdict: EMPTY — safe to remove Flutter + CF + rules write paths.');
    return;
  }

  const byStatus = {};
  let activeLast90 = 0;
  let newest = null;
  let oldest = null;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const status = String(d.status || '(none)');
    byStatus[status] = (byStatus[status] || 0) + 1;

    const created = ts(d.createdAt) || ts(d.updatedAt);
    if (created) {
      if (!newest || created > newest) newest = created;
      if (!oldest || created < oldest) oldest = created;
      const age = daysAgo(created);
      if (age !== null && age <= 90) activeLast90 += 1;
    }
  }

  console.log('\nBy status:');
  Object.entries(byStatus)
    .sort((a, b) => b[1] - a[1])
    .forEach(([s, c]) => console.log(`  ${s}: ${c}`));

  console.log(`\nCreated/updated in last 90 days: ${activeLast90}`);
  if (oldest) console.log(`Oldest: ${oldest.toISOString()}`);
  if (newest) console.log(`Newest: ${newest.toISOString()}`);

  const nonTerminal = snap.docs.filter((doc) => {
    const s = String((doc.data() || {}).status || '');
    return s !== 'delivered' && s !== 'cancelled';
  });
  console.log(`\nNon-terminal (not delivered/cancelled): ${nonTerminal.length}`);
  nonTerminal.slice(0, 10).forEach((doc) => {
    const d = doc.data() || {};
    console.log(`  • ${doc.id} status=${d.status} courier=${d.courierId || '-'} customer=${d.customerPhone || '-'}`);
  });

  if (activeLast90 === 0 && nonTerminal.length === 0) {
    console.log('\nVerdict: HISTORICAL ONLY — safe to deprecate/remove CF; keep read-only rules optional.');
  } else if (nonTerminal.length > 0) {
    console.log('\nVerdict: ACTIVE/STUCK ORDERS — resolve before CF removal.');
  } else {
    console.log('\nVerdict: RECENT ACTIVITY — review before removal.');
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
