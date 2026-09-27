/**
 * AVAGram HAQIQATDA ishlatiladimi — faqat O'QIYDI.
 *
 * NEGA KERAK: "videodan voz kechaylikmi?" degan qaror taxminga emas,
 * o'lchovga asoslanishi kerak. Har bir klip hujjatida `playbackStats`
 * bor (`recordPlaybackStats` yozadi) — ya'ni javob allaqachon bazada.
 *
 * Nimani ko'rsatadi:
 *   - jami ko'rishlar va jami tomosha vaqti
 *   - completion (oxirigacha ko'rilgani) ulushi — qiziqarlimi?
 *   - rebuffer ulushi va birinchi kadr vaqti — sifat yetarlimi?
 *   - bir ko'rishga o'rtacha trafik va 500 000 foydalanuvchiga prognoz
 *
 * Ishlatish:
 *   node functions/tools/audit_avagram_usage.js
 */
const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const sa = path.join(__dirname, '..', 'service-account.json');
  admin.initializeApp({credential: admin.credential.cert(require(sa))});
}
const db = admin.firestore();
db.settings({preferRest: true});

/** Variant zinapoyasi (functions/index.js TV_CLIP_VARIANT_SPECS). */
const BITRATES_KBPS = {720: 3000, 480: 1500, 360: 600};

function fmtDur(ms) {
  const s = Math.round(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h} soat ${m} daq` : `${m} daq ${s % 60} son`;
}

function pct(a, b) {
  return b > 0 ? `${((a / b) * 100).toFixed(1)}%` : '—';
}

(async () => {
  const snap = await db.collection('tv_clips').get();
  console.log(`=== AVAGram ishlatilishi — ${snap.size} ta klip ===\n`);

  let views = 0;
  let completed = 0;
  let watchedMs = 0;
  let bufferMs = 0;
  let bufferEvents = 0;
  let ffSum = 0;
  let ffSamples = 0;
  let clipsWithViews = 0;
  let clipsTranscoded = 0;
  const owners = new Set();

  let oldest = null;
  let newest = null;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    // Maydon nomlari `TvClip` modelidan: egasi `ownerPhone`, tayyorlik
    // belgisi `variantLadder` (transcode zinapoyasi versiyasi).
    if (d.variantLadder) clipsTranscoded++;
    if (d.ownerPhone) owners.add(String(d.ownerPhone));

    const t = d.createdAt;
    if (t && t.toDate) {
      const dt = t.toDate();
      if (!oldest || dt < oldest) oldest = dt;
      if (!newest || dt > newest) newest = dt;
    }

    const p = d.playbackStats || {};
    const v = Number(p.views || 0);
    if (v > 0) clipsWithViews++;
    views += v;
    completed += Number(p.completedViews || 0);
    watchedMs += Number(p.watchedMs || 0);
    bufferMs += Number(p.bufferMs || 0);
    bufferEvents += Number(p.bufferEvents || 0);
    ffSum += Number(p.firstFrameMsSum || 0);
    ffSamples += Number(p.firstFrameSamples || 0);
  }

  console.log('--- Kontent ---');
  console.log(`  klip jami        : ${snap.size}`);
  console.log(`  transcode bo'lgan : ${clipsTranscoded}`);
  console.log(`  klip egalari     : ${owners.size} ta foydalanuvchi`);
  if (oldest && newest) {
    const kun = Math.max(
        1, Math.round((newest - oldest) / (24 * 3600 * 1000)));
    console.log(`  davr             : ${oldest.toISOString().slice(0, 10)}` +
        ` … ${newest.toISOString().slice(0, 10)} (${kun} kun)`);
    console.log(`  yuklash tezligi  : ${(snap.size / kun).toFixed(1)} klip/kun`);
  }

  console.log('\n--- Ko\'rishlar ---');
  console.log(`  jami ko'rish     : ${views}`);
  console.log(`  ko'rilgan klip   : ${clipsWithViews} / ${snap.size}` +
      ` (${pct(clipsWithViews, snap.size)})`);
  console.log(`  jami tomosha     : ${fmtDur(watchedMs)}`);
  if (views > 0) {
    console.log(`  bir ko'rish      : ${(watchedMs / views / 1000).toFixed(1)} son`);
    console.log(`  oxirigacha       : ${completed} (${pct(completed, views)})`);
  }

  console.log('\n--- Sifat (bugungi ishimiz natijasi) ---');
  if (ffSamples > 0) {
    console.log(`  birinchi kadr    : ${Math.round(ffSum / ffSamples)} ms` +
        ` (${ffSamples} o'lchov)`);
  } else {
    console.log('  birinchi kadr    : o\'lchov yo\'q');
  }
  if (watchedMs > 0) {
    console.log(`  buferlanish      : ${pct(bufferMs, watchedMs)} vaqtdan`);
    console.log(`  buferlanish soni : ${bufferEvents}` +
        (views > 0 ? ` (${(bufferEvents / views).toFixed(2)} / ko'rish)` : ''));
  }

  // --- Trafik prognozi ---
  console.log('\n--- Trafik ---');
  const watchedSec = watchedMs / 1000;
  for (const [h, kbps] of Object.entries(BITRATES_KBPS)) {
    const gb = (watchedSec * kbps * 1000) / 8 / 1e9;
    console.log(`  hammasi ${h}p bo'lsa : ${gb.toFixed(2)} GB`);
  }

  console.log('\n(Faqat o\'qildi, hech narsa yozilmadi.)');
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
