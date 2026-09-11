/**
 * T1 SPIKE — mahalliy end-to-end tekshiruv (video-core audit, HLS feasibility).
 * `hlsSpikeTranscode`/`deleteHlsSpike`ning REAL deploy qilingan kodini
 * (index.js) mahalliy chaqiradi (service-account.json orqali, xuddi
 * boshqa `tools/*.js` skriptlar kabi), real bitta tv_clip'ni HLS'ga
 * o'giradi, natija manifestini HTTP orqali tekshiradi, so'ng
 * hls_spike/ va vaqtinchalik test-user hujjatini tozalaydi.
 *
 * Ishlatish: node tools/t1_spike_local_test.js
 */
const path = require('path');
const https = require('https');

// `index.js` o'zi `admin.initializeApp()`ni argumentsiz chaqiradi — shuning
// uchun bu yerda ADC'ni env var orqali beramiz va index.js'ni BIRINCHI
// initializer qilib qoldiramiz (aks holda "app already exists" xatosi).
process.env.GOOGLE_APPLICATION_CREDENTIALS =
    path.join(__dirname, '..', 'service-account.json');

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const FAKE_UID = 't1_spike_local_tester';

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`GET ${url} -> ${res.statusCode}`));
        return;
      }
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve(body));
    }).on('error', reject);
  });
}

function headOk(url) {
  return new Promise((resolve) => {
    const req = https.request(url, {method: 'HEAD'}, (res) => {
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.end();
  });
}

async function main() {
  console.log('=== T1 SPIKE local E2E ===\n');

  console.log('[1/6] Aktiv tv_clip qidirilmoqda...');
  const snap = await db.collection('tv_clips')
      .where('status', '==', 'active')
      .limit(1)
      .get();
  if (snap.empty) {
    throw new Error('Aktiv tv_clip topilmadi — spike uchun kamida 1 ta kerak.');
  }
  const clipDoc = snap.docs[0];
  const clip = clipDoc.data();
  const clipId = clipDoc.id;
  const videoUrl = clip.videoUrl;
  console.log(`      clipId=${clipId}  title="${clip.title || ''}"`);
  if (!videoUrl) throw new Error('Tanlangan klipda videoUrl yo\'q.');

  console.log('[2/6] Vaqtinchalik admin test-user yaratilmoqda...');
  await db.collection('users').doc(FAKE_UID).set({
    role: 'admin',
    note: 't1_spike_local_test — vaqtinchalik, avtomatik o\'chiriladi',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const context = {auth: {uid: FAKE_UID}};

  let result;
  try {
    console.log('[3/6] hlsSpikeTranscode ishga tushmoqda (ffmpeg, 1-3 daqiqa)...');
    result = await fns.hlsSpikeTranscode.run({clipId, videoUrl}, context);
    console.log(`      masterUrl: ${result.masterUrl}`);

    console.log('[4/6] Manifest tuzilishi tekshirilmoqda...');
    const masterText = await fetchText(result.masterUrl);
    const streamInfCount = (masterText.match(/#EXT-X-STREAM-INF/g) || []).length;
    const bandwidths = [...masterText.matchAll(/BANDWIDTH=(\d+)/g)].map((m) => Number(m[1]));
    console.log(`      master.m3u8: ${streamInfCount} ta variant, BANDWIDTH=${bandwidths.join(', ')}`);
    if (streamInfCount < 2) {
      throw new Error(`Kutilgan >=2 variant, topildi: ${streamInfCount}`);
    }
    if (bandwidths.length < 2 || bandwidths[0] === bandwidths[1]) {
      throw new Error('BANDWIDTH qiymatlari yo\'q yoki bir xil — ABR uchun farqli bo\'lishi shart.');
    }

    const variantEntries = Object.entries(result.variantUrls);
    for (const [name, url] of variantEntries) {
      const variantText = await fetchText(url);
      const segCount = (variantText.match(/#EXTINF/g) || []).length;
      const firstSegMatch = variantText.match(/https:\/\/[^\s]+\.ts[^\s"]*/);
      console.log(`      ${name}: ${segCount} segment, prog.m3u8 OK`);
      if (segCount < 1 || !firstSegMatch) {
        throw new Error(`${name}: segment topilmadi`);
      }
      const segOk = await headOk(firstSegMatch[0]);
      console.log(`      ${name}: birinchi segment reachable = ${segOk}`);
      if (!segOk) throw new Error(`${name}: birinchi segment HEAD != 200`);
    }

    console.log('[5/6] NATIJA: PASS — HLS multi-bitrate manifest yaroqli, ');
    console.log('      barcha variant/segment fayllar reachable.');
    console.log('      (video_player/ExoPlayer real qurilmada ABR qilishini');
    console.log('       bu skript TEKSHIRMAYDI — bu qism qurilma-darajasida.)');
  } finally {
    if (process.env.KEEP === '1') {
      console.log('[6/6] KEEP=1 — hls_spike/ saqlab qolindi (qurilmada ');
      console.log('      qo\'lda video_player sinovi uchun), faqat test-user o\'chirildi.');
      await db.collection('users').doc(FAKE_UID).delete();
    } else {
      console.log('[6/6] Tozalash: hls_spike/ va vaqtinchalik test-user...');
      try {
        await fns.deleteHlsSpike.run({clipId}, context);
      } catch (e) {
        console.error('      deleteHlsSpike xato:', e.message || e);
      }
      await db.collection('users').doc(FAKE_UID).delete();
      console.log('      Tozalandi.');
    }
  }
}

main().then(() => {
  console.log('\n=== DONE ===');
  process.exit(0);
}).catch((e) => {
  console.error('\n=== FAIL ===');
  console.error(e.message || e);
  process.exit(1);
});
