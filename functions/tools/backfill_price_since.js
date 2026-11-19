/**
 * Карточка белгиси (эга 2026-11-19): мавжуд tv_shop_items / wholesale_products да нарх кузатувини бошлаш.
 *
 * НЕГА: «−N%» учун эски нарх ≥ 7 кун турган бўлиши керак. Триггер (onShopItemPromoWrite / onWholesaleProductPromoWrite)
 * кузатувни ҳужжатнинг БИРИНЧИ ёзувида бошлайди; ёзилмаган эски ҳужжатларда соат ҳеч қачон бошланмайди. Бу скрипт
 * `priceTracked` (жорий нарх) + `priceSince` (= ИШГА ТУШИРИЛГАН ВАҚТ, консерватив: аввалги тарих номаълум) ёзади.
 * Фақат `priceTracked` майдони ЙЎҚ ҳужжатлар. Бошқа майдонга тегилмайди.
 *
 *   node tools/backfill_price_since.js                 # dry-run (ҳеч нарса ёзилмайди)
 *   node tools/backfill_price_since.js --apply         # ёзиш (ID рўйхати backup JSON га)
 *   node tools/backfill_price_since.js --rollback <backup.json>
 *
 * Production'да ФАҚАТ эга рухсати билан (CLAUDE.md 28). Функциялар deploy қилингандан КЕЙИН ишга туширилади.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const { priceOf } = require('../product_promo');

const COLLECTIONS = ['tv_shop_items', 'wholesale_products'];
const PAGE = 400;

async function run({ db, apply, nowMs = Date.now(), log = console.log }) {
  const at = admin.firestore.Timestamp.fromMillis(nowMs);
  const touched = [];
  const stats = {};
  for (const col of COLLECTIONS) {
    stats[col] = { scanned: 0, toWrite: 0 };
    let last = null;
    for (;;) {
      let q = db.collection(col).orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      const batch = db.batch();
      let n = 0;
      for (const doc of snap.docs) {
        stats[col].scanned += 1;
        const d = doc.data() || {};
        if ('priceTracked' in d) continue;
        stats[col].toWrite += 1;
        touched.push({ col, id: doc.id });
        if (apply) { batch.update(doc.ref, { priceTracked: priceOf(col, d), priceSince: at }, { lastUpdateTime: doc.updateTime }); n += 1; }
      }
      if (apply && n) await batch.commit();
      last = snap.docs[snap.docs.length - 1];
      log(JSON.stringify({ action: 'backfill_price_since', col, ...stats[col], apply }));
      if (snap.size < PAGE) break;
    }
  }
  return { stats, touched };
}

async function rollback({ db, file }) {
  const list = JSON.parse(fs.readFileSync(file, 'utf8'));
  const del = admin.firestore.FieldValue.delete();
  for (let i = 0; i < list.length; i += PAGE) {
    const batch = db.batch();
    list.slice(i, i + PAGE).forEach(({ col, id }) => batch.update(db.collection(col).doc(id), { priceTracked: del, priceSince: del }));
    await batch.commit();
  }
  return list.length;
}

if (require.main === module) {
  (async () => {
    admin.initializeApp();
    const db = admin.firestore();
    const ri = process.argv.indexOf('--rollback');
    if (ri > 0) {
      console.log(`rollback: ${await rollback({ db, file: process.argv[ri + 1] })}`);
      return;
    }
    const apply = process.argv.includes('--apply');
    const res = await run({ db, apply });
    if (apply) {
      const f = path.join(__dirname, 'backup', `price_since_backfill_${Date.now()}.json`);
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, JSON.stringify(res.touched));
      console.log(`backup: ${f}`);
    }
    console.log(JSON.stringify(res.stats));
  })().catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { run, rollback };
