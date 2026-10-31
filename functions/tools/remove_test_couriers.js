/**
 * Тест курьерларни ўчириш (эга, 2026-10-31: «ҳозиргилар тест учун қўйилганлар, уларни ўчириб ташлаймиз»;
 * рўйхат эгага кўрсатилди ва тасдиқланди: «3 та couriers ёзуви ва битта ҳуқуқнинг фақат курьерлик қисми
 * ўчирилади, backup билан. Фойдаланувчи ҳисоблари, ҳамёнлар ва буюртма тарихига тегилмайди»).
 *
 * Нима қилади:
 *   1. `couriers/*` — эски реестр ҳужжатлари (кутилган сон: 3) ўчирилади.
 *   2. `provider_capabilities/{ACCOUNT}` — ФАҚАТ курьер қисми: `courier`, `status.courier`, `review.courier`,
 *      `suspend.courier`, `window.courier` (бўлса). `identity`, такси ва бошқа хизматлар ҚОЛАДИ.
 *      `capability_audit` га ёзув (append-only) — шу транзакцияда.
 * Нимага тегмайди: `users`, ҳамён/ledger, буюртмалар, маршрутлар.
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN стандарт; `--apply` ёзади.
 *   - Тўхтайди, агар: `couriers` сони кутилгандан бошқа, бирортаси онлайн, курьерда фаол маршрут/вазифа бор.
 *   - Backup: `functions/tools/backup/test-couriers-backup-<ts>.json` (ўчиришдан ОЛДИН).
 *   - Қайтариш: backup'дан ҳужжатларни қайта ёзиш.
 *
 * Ишлатиш: node functions/tools/remove_test_couriers.js [--apply]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const ACCOUNT = 'accqv4g0Xlj1bYdduRmrf9H';
const EXPECTED_COURIERS = 3;
const ACTOR = 'script:remove_test_couriers';

const ser = (v) => JSON.parse(JSON.stringify(v, (k, x) => (x && typeof x.toDate === 'function' ? x.toDate().toISOString() : x)));

async function main() {
  admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
  const db = admin.firestore();
  const apply = process.argv.includes('--apply');

  const couriers = await db.collection('couriers').get();
  if (couriers.size !== EXPECTED_COURIERS) throw new Error(`couriers: ${couriers.size} ta, kutilgan ${EXPECTED_COURIERS} — to'xtadi`);
  for (const d of couriers.docs) if ((d.data() || {}).isOnline === true) throw new Error(`couriers/${d.id} onlayn — to'xtadi`);

  const capRef = db.collection('provider_capabilities').doc(ACCOUNT);
  const cap = await capRef.get();
  if (!cap.exists) throw new Error('capability hujjati yo\'q — to\'xtadi');
  const c = cap.data() || {};
  const uid = String((c.identity && c.identity.primaryUid) || '');
  for (const id of [...new Set([uid, uid.length === 12 ? uid.slice(3) : uid])].filter(Boolean)) {
    const r = await db.collection('delivery_routes').where('courierId', '==', id).where('status', 'in', ['ready', 'active']).get();
    const t = await db.collection('collection_tasks').where('courierId', '==', id).where('status', 'in', ['assigned', 'collecting']).get();
    if (r.size || t.size) throw new Error(`faol ish bor (routes ${r.size}, tasks ${t.size}) — to'xtadi`);
  }
  const fromStatus = String((c.status && c.status.courier) || '');

  const backup = {
    takenAt: new Date().toISOString(),
    couriers: Object.fromEntries(couriers.docs.map((d) => [d.id, ser(d.data())])),
    provider_capabilities: { [ACCOUNT]: ser(c) },
  };
  const file = path.join(__dirname, 'backup', `test-couriers-backup-${backup.takenAt.replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(backup, null, 2));

  const plan = {
    deleteCouriers: couriers.docs.map((d) => d.id.slice(-4)),
    capability: { account: ACCOUNT, removeFields: ['courier', 'status.courier', 'review.courier', 'suspend.courier', 'window.courier'], fromStatus },
    backup: file,
  };
  if (!apply) {
    console.log(JSON.stringify({ mode: 'DRY RUN', ...plan }, null, 2));
    console.log('DRY RUN: hech narsa yozilmadi. Yozish uchun --apply.');
    return;
  }

  const del = admin.firestore.FieldValue.delete();
  const ts = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (t) => {
    const snap = await t.get(capRef);
    const cur = snap.data() || {};
    if (String((cur.status && cur.status.courier) || '') !== fromStatus) throw new Error('holat o\'zgardi — to\'xtadi');
    t.update(capRef, {
      courier: del, 'status.courier': del, 'review.courier': del, 'suspend.courier': del, 'window.courier': del,
      updatedAt: ts,
    });
    t.create(db.collection('capability_audit').doc(), {
      accountId: ACCOUNT, service: 'courier', from: fromStatus, to: 'not_registered',
      reason: 'test_courier_removed_by_owner_2026-10-31', by: ACTOR, at: ts, kind: 'removed',
    });
  });
  const batch = db.batch();
  for (const d of couriers.docs) batch.delete(d.ref);
  await batch.commit();
  console.log(JSON.stringify({ mode: 'APPLIED', ...plan }, null, 2));
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
