/**
 * Settlement Ledger — migratsiya (bir martalik): opening balances.
 *
 * Har bir `users/{uid}.bonusBalance > 0` uchun ochilish jurnal yozuvi:
 *   Debit  admin_clearing            (bonusBalance)
 *   Credit passenger_credit:{uid}    (bonusBalance)
 *   kind: 'opening_balance', idempotencyKey: 'opening:{uid}'
 *
 * MUHIM: mirrorBonus = false — bonusBalance ALLAQACHON to'g'ri, uni
 * o'zgartirmaymiz. Faqat double-entry "backing"ni o'rnatamiz, shunda
 * passenger_credit.balance == bonusBalance bo'ladi (proeksiya invarianti).
 *
 * Idempotent: qayta ishga tushirilsa, mavjud yozuvlar qayta yozilmaydi.
 *
 * Ishlatish:
 *   node tools/settlement_opening_balances.js --dry     # faqat ko'rsatadi
 *   node tools/settlement_opening_balances.js           # haqiqiy yozuv
 *
 * To'liq dizayn: docs/settlement_ledger_v1_uz.md
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const DRY = process.argv.includes('--dry');

async function main() {
  console.log(`=== Settlement opening balances ${DRY ? '(DRY-RUN)' : '(LIVE)'} ===`);

  const snap = await db.collection('users').where('bonusBalance', '>', 0).get();
  console.log(`bonusBalance > 0 bo'lgan foydalanuvchilar: ${snap.size}`);

  let posted = 0;
  let skippedIdempotent = 0;
  let total = 0;
  const exceptions = [];

  for (const doc of snap.docs) {
    const uid = doc.id;
    const raw = (doc.data() || {}).bonusBalance;
    const bal = Number(raw);

    if (!Number.isFinite(bal) || bal <= 0) {
      exceptions.push({ uid, reason: `noto'g'ri qiymat: ${raw}` });
      continue;
    }
    if (Math.floor(bal) !== bal) {
      exceptions.push({ uid, reason: `kasrli balans (so'mda butun emas): ${bal}` });
      continue;
    }

    if (DRY) {
      console.log(`  [dry] opening:${uid}  +${bal}`);
      total += bal;
      posted++;
      continue;
    }

    try {
      const res = await ledger.postEntry(db, {
        idempotencyKey: `opening:${uid}`,
        kind: 'opening_balance',
        refType: 'migration',
        refId: 'opening_balances_v1',
        postedBy: 'migration',
        postedRole: 'system',
        legs: [
          { account: 'admin_clearing', dr: bal },
          { account: ledger.passengerCreditAccount(uid), cr: bal },
        ],
      }, { mirrorBonus: false });

      if (res.idempotent) {
        skippedIdempotent++;
      } else {
        posted++;
        total += bal;
        console.log(`  ✓ opening:${uid}  +${bal}`);
      }
    } catch (e) {
      exceptions.push({ uid, reason: e.message });
    }
  }

  console.log('\n=== Natija ===');
  console.log(`  Yangi yozuvlar: ${posted}`);
  console.log(`  Allaqachon mavjud (idempotent): ${skippedIdempotent}`);
  console.log(`  Jami summa: ${total}`);
  if (exceptions.length) {
    console.log(`  ⚠️ Istisnolar (${exceptions.length}):`);
    for (const x of exceptions) console.log(`     - ${x.uid}: ${x.reason}`);
  }

  if (!DRY) {
    console.log('\n=== Sverka (reconcile) ===');
    const rep = await ledger.reconcile(db);
    console.log(JSON.stringify(rep, null, 2));
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
