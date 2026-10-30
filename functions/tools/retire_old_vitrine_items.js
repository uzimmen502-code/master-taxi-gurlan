#!/usr/bin/env node
/**
 * Эски «витрина» товарларини ва уларнинг видеоларини ЮМШОҚ ўчириш (эга, 2026-10-30, Q-5:
 * «Код ўчади + 6 та фаол товар status=deleted қилинади (backup + rollback билан, видеолар барчаси ўчирилади)»).
 *
 * Эски витрина = `tv_shop_items` да `businessId` бўш ва `createdAt` < CUTOFF (2026-10-24 12:40Z — ягона
 * маҳсулот омбори [Business.ownShop] жонли бўлган вақт; ундан кейинги `businessId` бўш товарлар — асосий
 * дўконнинг янги маҳсулотлари, уларга ТЕГИЛМАЙДИ).
 * Видеолар = шу товарларга `shopItemId` орқали боғланган `tv_clips` (товари аллақачон ўчирилганлари ҳам).
 *
 * Ўчириш = `status: 'deleted'` (+ retiredAt/retiredBy/prevStatus). Ҳужжат ва файллар ҚОЛАДИ —
 * `onTvClipDeleted` (файлларни бутунлай ўчирувчи) ишга тушмайди, rollback мумкин.
 * `active → deleted` да ҳеч бир триггер ишламайди (onTvClipRejected фақат `blocked`, ижтимоий нашр фақат
 * `→ active`). ROLLBACK `deleted → active` қилади — ижтимоий нашр триггери ишлаши мумкин, шунинг учун
 * rollback олдин `socialPostedAt` борлигини ҳисоботда кўрсатади.
 *
 * Ишлатиш (functions/ ичидан):
 *   node tools/retire_old_vitrine_items.js               # dry-run (ҳеч нарса ёзилмайди)
 *   node tools/retire_old_vitrine_items.js --apply       # backup → batch → текширув
 *   node tools/retire_old_vitrine_items.js --rollback <runId>
 */
'use strict';

const fs = require('fs');
const path = require('path');

const CUTOFF_MS = Date.parse('2026-10-24T12:40:00Z');
const ACTOR = 'tool:retire_old_vitrine_items';

/** Соф танлов (тест учун): қайси товар ва клиплар ўчирилади. */
function selectTargets(items, clips, cutoffMs = CUTOFF_MS) {
  const oldItems = items.filter((i) => !String(i.businessId || '') && Number(i.createdAtMs) < cutoffMs);
  const oldIds = new Set(oldItems.map((i) => i.id));
  return {
    items: oldItems.filter((i) => i.status !== 'deleted'),
    clips: clips.filter((c) => oldIds.has(String(c.shopItemId || '')) && c.status !== 'deleted'),
    skippedNewItems: items.filter((i) => !String(i.businessId || '') && !(Number(i.createdAtMs) < cutoffMs)).length,
  };
}

async function main() {
  const admin = require('firebase-admin');
  const args = process.argv.slice(2);
  const APPLY = args.includes('--apply');
  const rbIdx = args.indexOf('--rollback');
  const ROLLBACK = rbIdx >= 0 ? String(args[rbIdx + 1] || '') : '';
  const keyPath = path.join(__dirname, '..', 'service-account.json');
  if (!fs.existsSync(keyPath)) {
    console.error('service-account.json topilmadi:', keyPath);
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  const db = admin.firestore();
  const backupDir = path.join(__dirname, 'backup');

  if (ROLLBACK) {
    const file = path.join(backupDir, `old_vitrine_${ROLLBACK}.json`);
    const b = JSON.parse(fs.readFileSync(file, 'utf8'));
    const batch = db.batch();
    for (const it of b.items) batch.update(db.collection('tv_shop_items').doc(it.id), { status: it.status, retiredAt: admin.firestore.FieldValue.delete(), retiredBy: admin.firestore.FieldValue.delete() });
    for (const c of b.clips) batch.update(db.collection('tv_clips').doc(c.id), { status: c.status, retiredAt: admin.firestore.FieldValue.delete(), retiredBy: admin.firestore.FieldValue.delete() });
    batch.create(db.collection('admin_audit').doc(), { kind: 'old_vitrine_rollback', actor: ACTOR, actorRole: 'script', source: 'script', runId: ROLLBACK, items: b.items.length, clips: b.clips.length, at: admin.firestore.FieldValue.serverTimestamp() });
    await batch.commit();
    console.log(JSON.stringify({ action: 'rollback', runId: ROLLBACK, items: b.items.length, clips: b.clips.length, socialPostedClips: b.clips.filter((c) => c.socialPostedAt).length }));
    return;
  }

  const itemSnap = await db.collection('tv_shop_items').get();
  const items = itemSnap.docs.map((d) => {
    const x = d.data();
    return { id: d.id, businessId: x.businessId || '', status: x.status || '', title: x.title || '', ownerPhone: String(x.ownerPhone || ''), createdAtMs: x.createdAt && x.createdAt.toMillis ? x.createdAt.toMillis() : NaN };
  });
  const oldIds = items.filter((i) => !i.businessId && i.createdAtMs < CUTOFF_MS).map((i) => i.id);
  const clips = [];
  for (let k = 0; k < oldIds.length; k += 10) {
    const s = await db.collection('tv_clips').where('shopItemId', 'in', oldIds.slice(k, k + 10)).get();
    s.docs.forEach((d) => { const x = d.data(); clips.push({ id: d.id, shopItemId: x.shopItemId || '', status: x.status || '', title: x.title || '', ownerPhone: String(x.ownerPhone || ''), socialPostedAt: x.socialPostedAt ? true : false }); });
  }
  const t = selectTargets(items, clips);
  const mask = (p) => '***' + String(p).slice(-4);
  const report = {
    items: t.items.map((i) => ({ id: i.id, title: i.title, owner: mask(i.ownerPhone), status: i.status })),
    clips: t.clips.map((c) => ({ id: c.id, title: c.title, owner: mask(c.ownerPhone), status: c.status })),
    newItemsUntouched: t.skippedNewItems,
  };
  console.log(JSON.stringify(report, null, 1));
  if (!APPLY) {
    console.log('DRY-RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');
    return;
  }
  if (t.items.length + t.clips.length > 400) throw new Error('кутилмаган кўп ҳужжат — тўхтатилди');

  const runId = new Date().toISOString().replace(/[:.]/g, '-');
  fs.mkdirSync(backupDir, { recursive: true });
  const backupFile = path.join(backupDir, `old_vitrine_${runId}.json`);
  fs.writeFileSync(backupFile, JSON.stringify({ runId, cutoff: new Date(CUTOFF_MS).toISOString(), items: t.items, clips: t.clips }, null, 1));

  const ts = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  for (const i of t.items) batch.update(db.collection('tv_shop_items').doc(i.id), { status: 'deleted', retiredAt: ts, retiredBy: ACTOR });
  for (const c of t.clips) batch.update(db.collection('tv_clips').doc(c.id), { status: 'deleted', retiredAt: ts, retiredBy: ACTOR });
  batch.create(db.collection('admin_audit').doc(), {
    kind: 'old_vitrine_retired', actor: ACTOR, actorRole: 'script', source: 'script', runId,
    reason: 'owner 2026-10-30 Q-5', items: t.items.map((i) => i.id), clips: t.clips.map((c) => c.id), at: ts,
  });
  await batch.commit();

  let bad = 0;
  for (const i of t.items) if ((await db.collection('tv_shop_items').doc(i.id).get()).get('status') !== 'deleted') bad++;
  for (const c of t.clips) if ((await db.collection('tv_clips').doc(c.id).get()).get('status') !== 'deleted') bad++;
  console.log(JSON.stringify({ action: 'applied', runId, items: t.items.length, clips: t.clips.length, verifyFailed: bad, backup: path.relative(process.cwd(), backupFile), rollback: `node tools/retire_old_vitrine_items.js --rollback ${runId}` }));
  if (bad) process.exitCode = 2;
}

module.exports = { selectTargets, CUTOFF_MS };

if (require.main === module) {
  main().catch((e) => { console.error(e && e.message); process.exit(1); });
}
