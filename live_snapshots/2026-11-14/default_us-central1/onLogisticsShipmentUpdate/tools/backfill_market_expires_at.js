/**
 * Аҳоли бозори — `expiresAt` майдони йўқ эълонларга уни қўйиш.
 *
 * НЕГА КЕРАК: `expirePendingTrips` муддати тугаганларни
 * `.where('expiresAt', '<', now)` билан топади. Firestore эса бу МАЙДОНИ
 * ЙЎҚ ҳужжатни бундай сўровда УМУМАН қайтармайди — яъни `expiresAt`сиз
 * эълон ҳеч қачон тугамайди, абадий фаол туради (аудит, 2026-09-27).
 *
 * Бу эълонлар TTL сиёсати киритилишидан ОЛДИН яратилган.
 *
 * ИККИ РЕЖИМ — натижаси кескин фарқ қилади, шунинг учун ошкора танланади:
 *
 *   --mode=restart  (ТАВСИЯ) `expiresAt = ҳозир + 60 кун`.
 *       Эълонлар жойида қолади ва бугундан оддий циклга тушади.
 *       Ҳеч ким кутилмаганда эълонидан айрилмайди.
 *
 *   --mode=strict   `expiresAt = publishedAt + 60 кун`.
 *       Сиёсат орқага қараб қўлланади. 60 кундан ошганлари 1 дақиқа
 *       ичида `inactive` бўлади ВА эгаларига «муддати тугади» push
 *       кетади (`onAdUpdate`). Бир йўла кўп эълон лентадан тушади.
 *
 * Ишлатиш:
 *   node functions/tools/backfill_market_expires_at.js                    # dry run
 *   node functions/tools/backfill_market_expires_at.js --mode=restart --apply
 */
const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const sa = path.join(__dirname, '..', 'service-account.json');
  admin.initializeApp({credential: admin.credential.cert(require(sa))});
}
const db = admin.firestore();
db.settings({preferRest: true});

const APPLY = process.argv.includes('--apply');
const MODE = (process.argv.find((a) => a.startsWith('--mode=')) || '--mode=restart')
    .split('=')[1];
const TTL_DAYS = 60;
const DAY_MS = 24 * 60 * 60 * 1000;

if (!['restart', 'strict'].includes(MODE)) {
  console.error(`Номаълум режим: ${MODE}. Фақат restart ёки strict.`);
  process.exit(1);
}

async function main() {
  console.log('=== Аҳоли бозори: expiresAt backfill ===');
  console.log(`режим: ${MODE}`);
  console.log(APPLY ? 'APPLY — ёзилади' : 'DRY RUN — ҳеч нарса ёзилмайди');
  console.log('');

  const snap = await db.collection('ads')
      .where('type', '==', 'cheap_product')
      .get();

  const todo = [];
  let bor = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (d.expiresAt) {
      bor++;
      continue;
    }
    const basePub = d.publishedAt || d.createdAt;
    const base = basePub && typeof basePub.toDate === 'function'
        ? basePub.toDate()
        : new Date();
    const when = MODE === 'strict'
        ? new Date(base.getTime() + TTL_DAYS * DAY_MS)
        : new Date(Date.now() + TTL_DAYS * DAY_MS);
    todo.push({
      ref: doc.ref,
      id: doc.id,
      status: String(d.status || ''),
      title: String(d.title || '').slice(0, 28),
      ageDays: Math.floor((Date.now() - base.getTime()) / DAY_MS),
      when,
      darhol: when.getTime() < Date.now(),
    });
  }

  console.log(`жами cheap_product : ${snap.size}`);
  console.log(`expiresAt аллақачон бор: ${bor}`);
  console.log(`ёзилади            : ${todo.length}`);
  const darhol = todo.filter((t) => t.darhol && t.status === 'active').length;
  if (darhol > 0) {
    console.log('');
    console.log(`⚠️  ${darhol} та ФАОЛ эълоннинг муддати ЎТМИШДА бўлади —`);
    console.log('    улар 1 дақиқа ичида `inactive` бўлади ва эгаларига');
    console.log('    «муддати тугади» хабари кетади.');
  }
  console.log('');
  for (const t of todo.slice(0, 10)) {
    console.log(`  ${t.status.padEnd(9)} ${String(t.ageDays).padStart(4)} кун  ` +
        `→ ${t.when.toISOString().slice(0, 10)}${t.darhol ? '  (ДАРҲОЛ тугайди)' : ''}  ${t.title}`);
  }
  if (todo.length > 10) console.log(`  … яна ${todo.length - 10} та`);

  if (!APPLY) {
    console.log('');
    console.log('Бажариш учун: --mode=<restart|strict> --apply');
    return;
  }

  let batch = db.batch();
  let n = 0;
  for (const t of todo) {
    batch.update(t.ref, {
      expiresAt: admin.firestore.Timestamp.fromDate(t.when),
      // `updatedAt` АТАЙЛАБ тегилмайди: бу техник тузатиш, мазмун
      // ўзгариши эмас — «Менинг эълонларим» тартибини бузмасин.
      expiresBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    n++;
    if (n % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (n % 400 !== 0) await batch.commit();
  console.log('');
  console.log(`✅ ${n} та эълонга expiresAt ёзилди.`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
