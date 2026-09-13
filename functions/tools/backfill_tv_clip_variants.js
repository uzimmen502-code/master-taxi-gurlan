/**
 * Мавжуд TV клипларни қайта transcode қилиш — янги вариант поғонаси
 * (360p) ва bitrate шифти эски клипларга ҳам тегсин.
 *
 * Бу скрипт ВИДЕОНИ ЎЗИ ИШЛАМАЙДИ. У фақат Firestore'да `backfillVariantsAt`
 * белгисини қўяди; оғир ffmpeg иши булутдаги `onTvClipBackfillRequested`
 * trigger'ида (us-central1, 4GiB/2vCPU, bucket ёнида) бажарилади. Шунинг
 * учун бу ерда интернет трафиги деярли йўқ — фақат Firestore ёзувлари.
 *
 * Хавфсизлик: ҳар югуришда чекланган сонда клип белгиланади ва улар
 * орасида пауза бор — акс ҳолда юзлаб Cloud Run instance бир вақтда
 * кўтарилиб, харажат кескин ошиб кетарди.
 *
 * Такрор ишга туширса бўлади: аллақачон 360p олган клиплар рўйхатга
 * тушмайди, шунинг учун скрипт ўзи тўхтаган жойидан давом этади.
 *
 * Ишлатиш:
 *   node functions/tools/backfill_tv_clip_variants.js              # dry run
 *   node functions/tools/backfill_tv_clip_variants.js --apply --limit 10
 *   node functions/tools/backfill_tv_clip_variants.js --apply --limit 50 --delay 30000
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

function argValue(name, fallback) {
  const i = process.argv.indexOf(name);
  if (i < 0 || i + 1 >= process.argv.length) return fallback;
  const n = Number(process.argv[i + 1]);
  return Number.isFinite(n) ? n : fallback;
}

// Бир югуришда нечта клип белгиланади ва улар орасидаги пауза (мс).
// Дефолтлар ататйин эҳтиёткор: 25 та клип × 20с = ~8 дақиқа, яъни бир
// вақтда бир нечтадан ортиқ transcode кўтарилмайди.
const LIMIT = argValue('--limit', 25);
const DELAY_MS = argValue('--delay', 20000);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function needsBackfill(d) {
  const variants = d.videoVariants || {};
  return !variants['360p'];
}

async function main() {
  console.log('=== TV clip variant backfill ===');
  console.log(APPLY
    ? `APPLY — limit ${LIMIT}, delay ${DELAY_MS}ms`
    : 'DRY RUN — ҳеч нарса ёзилмайди (--apply билан ишга туширинг)');
  console.log('');

  // Фақат `active`: `expired` клипларнинг Storage файллари
  // `expireTvContent` томонидан ўчирилган (манба йўқ), `blocked`/`pending`
  // эса лентада кўринмайди — уларга пул сарфлашнинг маъноси йўқ.
  const snap = await db.collection('tv_clips')
      .where('status', '==', 'active')
      .get();

  const todo = [];
  let already = 0;
  let noVideo = 0;
  let errored = 0;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (!needsBackfill(d)) {
      already++;
      continue;
    }
    if (!d.videoUrl) {
      noVideo++;
      continue;
    }
    // Аввал йиқилган клип — манбаси бузуқ бўлиши мумкин, ҳар югуришда
    // қайта уриниб пул сарфламаймиз. Керак бўлса қўлда белгиланг.
    if (d.processingStatus === 'error') {
      errored++;
      continue;
    }
    todo.push({ref: doc.ref, id: doc.id, title: d.title || '', d});
  }

  const knownSeconds = todo
      .reduce((sum, t) => sum + (Number(t.d.duration) || 0), 0);

  console.log(`active клиплар:        ${snap.size}`);
  console.log(`360p аллақачон бор:    ${already}`);
  console.log(`videoUrl йўқ:          ${noVideo}`);
  console.log(`processingStatus=error:${errored} (ўтказиб юборилди)`);
  console.log(`BACKFILL КЕРАК:        ${todo.length}`);
  if (knownSeconds > 0) {
    console.log(`маълум умумий давомийлик: ~${Math.round(knownSeconds / 60)} дақиқа`);
  }
  console.log('');

  if (todo.length === 0) {
    console.log('Ҳаммаси тайёр — қиладиган иш йўқ.');
    return;
  }

  const batch = todo.slice(0, LIMIT);
  if (!APPLY) {
    console.log(`Биринчи ${batch.length} та (шу югуришда белгиланарди):`);
    for (const t of batch) {
      console.log(`  ${t.id}  ${t.title.slice(0, 50)}`);
    }
    console.log('');
    console.log(`Бажариш учун: node functions/tools/backfill_tv_clip_variants.js --apply --limit ${LIMIT}`);
    return;
  }

  let marked = 0;
  for (const t of batch) {
    try {
      await t.ref.update({
        backfillVariantsAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      marked++;
      console.log(`  [${marked}/${batch.length}] белгиланди ${t.id}  ${t.title.slice(0, 40)}`);
    } catch (e) {
      console.error(`  ХАТО ${t.id}: ${e.message || e}`);
    }
    if (marked < batch.length) await sleep(DELAY_MS);
  }

  const left = todo.length - marked;
  console.log('');
  console.log(`${marked} та клип белгиланди. Transcode булутда фонда кетмоқда`);
  console.log('(Firebase Console → Functions → onTvClipBackfillRequested логлари).');
  if (left > 0) {
    console.log('');
    console.log(`Қолди: ${left} та. Аввалгилари тугаганини логдан текшириб,`);
    console.log(`кейин яна ишга туширинг (аллақачон бўлганлари ўтказиб юборилади).`);
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
