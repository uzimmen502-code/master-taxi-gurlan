#!/usr/bin/env node
/**
 * Кўчмас мулк: ОЧИҚ `addressText`ни ЁПИҚ `private/detail`га кўчириш
 * (эга қарори 2026-10-08 — кўча/уй пакетдан кейин кўринади).
 *
 * Янги/таҳрирланган эълонлар аллақачон тўғри ёзилади (`realty.js`).
 * Бу скрипт ЭСКИ ёзувлар учун: улардаги очиқ манзилни ҳар ким ўқий
 * олади (`realty_listings` — `allow read: if isAuth()`).
 *
 * ⚠️ PRODUCTION'да фақат эга рухсати билан (28-қоида). Тартиб (27-қоида):
 *
 *   node functions/tools/realty_move_address.js
 *       DRY-RUN: нечта ёзувда очиқ манзил бор (манзилнинг ўзи чиқмайди)
 *   node functions/tools/realty_move_address.js --execute --backup <файл.json>
 *       аввал BACKUP файл ёзилади (ичида манзиллар — PII, репога
 *       КОММИТ ҚИЛМАНГ), кейин 200 тадан batch, кейин текширув
 *   node functions/tools/realty_move_address.js --rollback <файл.json>
 *       очиқ манзилни backup'дан тиклайди; ёпиқда аввал манзил йўқ
 *       бўлган бўлса, у ердан олиб ташлайди (аввалги ҳолат айнан)
 *
 * Тартиб муҳим: аввал `realty.js` (янги илова манзилни ёпиқдан ўқийди)
 * deploy, кейин илова, кейин шу скрипт — акс ҳолда эски илова очган
 * харидор манзилни кўрмай қолади (у фақат очиқ ҳужжатни ўқийди).
 *
 * Emulator: FIRESTORE_EMULATOR_HOST берилса service-account ишлатилмайди.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const BATCH_DOCS = 200;

/** Очиқ манзили бор эълонлар. */
async function plan(db) {
  const out = [];
  let last = null;
  for (;;) {
    let q = db.collection('realty_listings')
      .orderBy(admin.firestore.FieldPath.documentId()).limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const a = String((doc.data() || {}).addressText || '').trim();
      if (a) out.push({ id: doc.id, addressText: a });
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
  return out;
}

async function execute(db, backupPath, log = console.log) {
  const items = await plan(db);
  // BACKUP — ёзувдан ОЛДИН. Ёпиқ ҳужжатдаги аввалги ҳолат ҳам сақланади.
  const backup = [];
  for (const it of items) {
    const priv = await db.doc(`realty_listings/${it.id}/private/detail`).get();
    backup.push({
      id: it.id,
      addressText: it.addressText,
      privateAddressBefore: String((priv.data() || {}).addressText || ''),
      privateExists: priv.exists,
    });
  }
  fs.writeFileSync(backupPath, JSON.stringify({ at: new Date().toISOString(), items: backup }, null, 2));
  log(`backup: ${backup.length} ta -> ${backupPath}`);

  let done = 0;
  for (let i = 0; i < backup.length; i += BATCH_DOCS) {
    const batch = db.batch();
    for (const b of backup.slice(i, i + BATCH_DOCS)) {
      const pubRef = db.doc(`realty_listings/${b.id}`);
      // Ёпиқда янгироқ манзил бўлса (таҳрирдан) — у ТЕГИЛМАЙДИ.
      if (!b.privateAddressBefore) {
        batch.set(pubRef.collection('private').doc('detail'),
          { addressText: b.addressText }, { merge: true });
      }
      batch.update(pubRef, { addressText: admin.firestore.FieldValue.delete() });
    }
    await batch.commit();
    done = Math.min(backup.length, i + BATCH_DOCS);
    log(`progress: ${done}/${backup.length}`);
  }

  // Текширув.
  const left = await plan(db);
  let privMissing = 0;
  for (const b of backup) {
    const p = await db.doc(`realty_listings/${b.id}/private/detail`).get();
    if (!String((p.data() || {}).addressText || '').trim()) privMissing += 1;
  }
  log(`verify: ochiq manzil qoldi=${left.length}, yopiqda manzilsiz=${privMissing}`);
  return { moved: backup.length, leftPublic: left.length, privMissing };
}

async function rollback(db, backupPath, log = console.log) {
  const { items } = JSON.parse(fs.readFileSync(backupPath, 'utf8'));
  for (let i = 0; i < items.length; i += BATCH_DOCS) {
    const batch = db.batch();
    for (const b of items.slice(i, i + BATCH_DOCS)) {
      const pubRef = db.doc(`realty_listings/${b.id}`);
      const pub = await pubRef.get();
      if (!pub.exists) continue; // орада ўчирилган (муддат) — тиклаш йўқ
      batch.update(pubRef, { addressText: b.addressText });
      if (!b.privateAddressBefore) {
        const privRef = pubRef.collection('private').doc('detail');
        if (b.privateExists) {
          batch.set(privRef, { addressText: admin.firestore.FieldValue.delete() }, { merge: true });
        } else {
          batch.delete(privRef);
        }
      }
    }
    await batch.commit();
  }
  log(`rollback: ${items.length} ta tiklandi`);
  return { restored: items.length };
}

module.exports = { plan, execute, rollback };

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const argAfter = (k) => {
      const i = args.indexOf(k);
      return i >= 0 ? String(args[i + 1] || '') : '';
    };
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-realty' });
    } else {
      const keyPath = path.join(__dirname, '..', 'service-account.json');
      if (!fs.existsSync(keyPath)) {
        console.error('service-account.json topilmadi:', keyPath);
        process.exit(1);
      }
      admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
    }
    const db = admin.firestore();

    if (args.includes('--rollback')) {
      await rollback(db, argAfter('--rollback'));
      return;
    }
    if (args.includes('--execute')) {
      const backup = argAfter('--backup');
      if (!backup) {
        console.error('--execute uchun --backup <fayl.json> majburiy');
        process.exit(1);
      }
      const r = await execute(db, backup);
      if (r.leftPublic || r.privMissing) process.exitCode = 2;
      return;
    }
    const items = await plan(db);
    console.log(`DRY-RUN: ochiq manzili bor e'lonlar = ${items.length}`);
    console.log('namuna id:', items.slice(0, 5).map((x) => x.id).join(', ') || '—');
  })().catch((e) => { console.error(e); process.exit(1); });
}
