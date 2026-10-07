/**
 * Bir martalik migratsiya: Ulgurji bozorida qolib ketgan 2 ta Xitoy
 * mahsulotini Xitoy bozoriga ko'chirish (`wholesale_products`).
 *
 *   NODE_OPTIONS="--use-system-ca" node functions/tools/migrate_wholesale_legacy_china.js             # faqat ko'rsatadi
 *   NODE_OPTIONS="--use-system-ca" node functions/tools/migrate_wholesale_legacy_china.js --apply     # yozadi
 *   NODE_OPTIONS="--use-system-ca" node functions/tools/migrate_wholesale_legacy_china.js --rollback  # qaytaradi
 *
 * NEGA KERAK. Bu ikki yozuv 2026-09-21 da, Xitoy bozori (2026-09-28)
 * ochilishidan OLDIN yaratilgan — o'shanda `market` maydoni yo'q edi, shu
 * sabab ilova ularni Ulgurji deb ko'rsatadi. Aslida ular Xitoy
 * mahsuloti: sotuvchining Xitoy bozoridagi qolgan 7 ta mahsuloti kabi
 * traktor, tavsifida «хитойда», narxi 3800 — dollarda (ilovada esa
 * «3 800 сўм» bo'lib chiqyapti). Audit: 2026-10-07.
 *
 * Firestore Rules admin'ga ham, egaga ham `market`ni o'zgartirishga
 * ruxsat bermaydi (ataylab) — shuning uchun Admin SDK bilan, aniq ID
 * ro'yxati bo'yicha. Umumiy «market yo'q → china» qoidasi YO'Q: haqiqiy
 * Ulgurji mahsuloti adashib ko'chib ketmasin.
 *
 * Xavfsizlik:
 *  - har yozuv tranzaksiyada: hali `market` va `currency` YO'Q bo'lsagina
 *    yoziladi (ikki marta ishga tushsa — ikkinchisi hech narsa qilmaydi);
 *  - yozishdan oldin to'liq nusxa OS temp papkasiga saqlanadi (repo'ga
 *    emas — unda sotuvchi telefoni bor);
 *  - audit belgisi: `marketMigratedFrom` + `marketMigratedAt`;
 *  - `--rollback` faqat shu skript belgilagan yozuvlarni qaytaradi.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');
const sa = require('../service-account.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
db.settings({ preferRest: true });
const { FieldValue } = admin.firestore;

/** Ega tasdiqlagan ro'yxat — boshqa hech qaysi yozuvga tegilmaydi. */
const TARGET_IDS = ['xim6q1OrTb8j4TCg84Oa', 'TMWDLz5unxMYyxKc2RN5'];

/** Sotuvchining Xitoy bozoridagi qolgan mahsulotlari bilan bir xil. */
const CURRENCY = '$';
const MIGRATION_TAG = 'legacy-missing-2026-10-07';

const APPLY = process.argv.includes('--apply');
const ROLLBACK = process.argv.includes('--rollback');

function brief(id, d) {
  const tiers = (d.priceTiers || []).map((t) => `${t.minQty}+:${t.price}`).join(',');
  return `${id} «${d.title}» (${d.description || ''}) narx[${tiers}]`
    + ` market=${d.market === undefined ? '—' : d.market}`
    + ` currency=${d.currency === undefined ? '—' : JSON.stringify(d.currency)}`
    + ` status=${d.status}`;
}

async function backup(snaps) {
  const file = path.join(
    os.tmpdir(),
    `wholesale_legacy_china_backup_${new Date().toISOString().replace(/[:.]/g, '-')}.json`,
  );
  const out = snaps.map((s) => ({ id: s.id, exists: s.exists, data: s.data() || null }));
  fs.writeFileSync(file, JSON.stringify(out, null, 2), 'utf8');
  console.log(`Nusxa: ${file}`);
}

async function migrate() {
  const refs = TARGET_IDS.map((id) => db.collection('wholesale_products').doc(id));
  const before = await db.getAll(...refs);
  for (const s of before) {
    console.log(s.exists ? `  ${brief(s.id, s.data())}` : `  ?  ${s.id} — topilmadi`);
  }
  if (!APPLY) {
    console.log(`\nKo'rsatish rejimi. Yozish uchun: --apply`);
    return;
  }
  await backup(before);

  let moved = 0;
  let skipped = 0;
  for (const ref of refs) {
    const res = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) return 'topilmadi';
      const d = s.data();
      if (d.market !== undefined) return `market allaqachon bor (${d.market})`;
      if (d.currency !== undefined && d.currency !== '') {
        return `currency allaqachon bor (${d.currency})`;
      }
      tx.update(ref, {
        market: 'china',
        currency: CURRENCY,
        marketMigratedFrom: MIGRATION_TAG,
        marketMigratedAt: FieldValue.serverTimestamp(),
      });
      return 'ok';
    });
    if (res === 'ok') {
      moved += 1;
      console.log(`  →  ${ref.id} — Xitoy bozoriga ko'chirildi`);
    } else {
      skipped += 1;
      console.log(`  =  ${ref.id} — tegilmadi: ${res}`);
    }
  }

  // Tekshiruv — yozilganini qayta o'qib isbotlash.
  const after = await db.getAll(...refs);
  let bad = 0;
  for (const s of after) {
    const d = s.data() || {};
    const ok = d.market === 'china' && d.currency === CURRENCY;
    if (!ok) bad += 1;
    console.log(`  ${ok ? 'OK ' : 'XATO'} ${brief(s.id, d)}`);
  }
  console.log(`\nKo'chirildi: ${moved} · tegilmadi: ${skipped} · tekshiruv xatosi: ${bad}`);
  if (bad > 0) process.exitCode = 2;
}

async function rollback() {
  let reverted = 0;
  for (const id of TARGET_IDS) {
    const ref = db.collection('wholesale_products').doc(id);
    const res = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) return 'topilmadi';
      if (s.data().marketMigratedFrom !== MIGRATION_TAG) {
        return 'bu skript ko\'chirmagan';
      }
      tx.update(ref, {
        market: FieldValue.delete(),
        currency: FieldValue.delete(),
        marketMigratedFrom: FieldValue.delete(),
        marketMigratedAt: FieldValue.delete(),
      });
      return 'ok';
    });
    if (res === 'ok') reverted += 1;
    console.log(`  ${res === 'ok' ? '←' : '='}  ${id} — ${res === 'ok' ? 'qaytarildi' : res}`);
  }
  console.log(`\nQaytarildi: ${reverted}`);
}

(async () => {
  console.log(
    `${ROLLBACK ? 'QAYTARISH' : APPLY ? 'YOZISH' : 'KO\'RSATISH'} rejimi`
    + ` · ${TARGET_IDS.length} ta yozuv\n`,
  );
  if (APPLY && ROLLBACK) throw new Error('--apply va --rollback birga emas');
  if (ROLLBACK) await rollback();
  else await migrate();
  process.exit(process.exitCode || 0);
})().catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
