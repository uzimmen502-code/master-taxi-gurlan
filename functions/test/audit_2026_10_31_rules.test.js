/**
 * Аудит 2026-10-31 (rules): HIGH-1 клип файли эга папкасидан, HIGH-2 treeComponentId,
 * HIGH-3 клипнинг сервер майдонлари, MEDIUM-1 эълон type, MEDIUM-3 yuk_local_drivers create.
 *   RULES_FILE=<path> firebase emulators:exec --only firestore --project demo-audit-1031 \
 *     "node functions/test/audit_2026_10_31_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const OWNER = '998901112233';
const OWNER_PLUS = '+998901112233';
const OTHER = '998907778899';
const BASE = 'https://firebasestorage.googleapis.com/v0/b/master-taxi-gurlan.firebasestorage.app/o/';
const url = (p) => `${BASE}${encodeURIComponent(p)}?alt=media&token=t`;

function clip(owner, extra = {}) {
  return {
    ownerPhone: owner, title: 't', category: 'product', status: 'pending',
    videoUrl: url(`tv_clips/${owner}/1_ab.mp4`), posterUrl: url(`tv_clips/${owner}/poster_1_ab.jpg`),
    likeCount: 0, viewCount: 0, commentCount: 0, ...extra,
  };
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-audit-1031',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => env.authenticatedContext(phone, { phone_number: '+' + phone.replace(/^\+/, '') }).firestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${OWNER}`).set({ phone: OWNER, role: 'user' });
    await db.doc(`users/${OTHER}`).set({ phone: OTHER, role: 'user' });
    await db.doc('settings/app').set({ tvAutoApprove: false });
    await db.doc('tv_clips/c1').set({ ...clip(OWNER), status: 'active', hlsUrl: url(`tv_clips_out/c1/master.m3u8`) });
    await db.doc('tv_clips/cplus').set({ ...clip(OWNER_PLUS), status: 'active' });
    await db.doc('ads/a1').set({ type: 'work', authorPhone: OWNER, authorName: 'A', text: 'x', title: 'y', status: 'active' });
  });

  // ── HIGH-1: create ──
  await check('H1 create: own folder OK', () => assertSucceeds(as(OWNER).collection('tv_clips').add(clip(OWNER))));
  await check('H1 create: empty poster OK', () => assertSucceeds(as(OWNER).collection('tv_clips').add(clip(OWNER, { posterUrl: '' }))));
  await check('H1 create: foreign poster path DENIED', () => assertFails(as(OWNER).collection('tv_clips').add(clip(OWNER, { posterUrl: url(`tv_clips/${OTHER}/x.jpg`) }))));
  await check('H1 create: other bucket folder DENIED', () => assertFails(as(OWNER).collection('tv_clips').add(clip(OWNER, { videoUrl: url('restaurant_images/r1/menu.jpg') }))));
  await check('H1 create: nested path DENIED', () => assertFails(as(OWNER).collection('tv_clips').add(clip(OWNER, { videoUrl: url(`tv_clips/${OWNER}/sub/a.mp4`) }))));
  await check('H1 create: non-firebase url DENIED', () => assertFails(as(OWNER).collection('tv_clips').add(clip(OWNER, { videoUrl: 'https://evil.example/a.mp4' }))));
  // ── HIGH-3: create with server media keys ──
  await check('H3 create: hlsUrl DENIED', () => assertFails(as(OWNER).collection('tv_clips').add(clip(OWNER, { hlsUrl: 'https://x/m3u8' }))));
  await check('H3 create: processingStatus DENIED', () => assertFails(as(OWNER).collection('tv_clips').add(clip(OWNER, { processingStatus: 'ready' }))));
  // ── HIGH-1/3: update ──
  await check('H3 update: title edit OK', () => assertSucceeds(as(OWNER).doc('tv_clips/c1').update({ title: 'new' })));
  await check('H3 update: hlsUrl DENIED', () => assertFails(as(OWNER).doc('tv_clips/c1').update({ hlsUrl: 'https://evil/m3u8' })));
  await check('H3 update: viewCount jump DENIED', () => assertFails(as(OWNER).doc('tv_clips/c1').update({ viewCount: 99999 })));
  await check('H1 update: replace video in own folder OK', () => assertSucceeds(as(OWNER).doc('tv_clips/c1').update({ videoUrl: url(`tv_clips/${OWNER}/2_cd.mp4`) })));
  await check('H1 update: replace video with foreign path DENIED', () => assertFails(as(OWNER).doc('tv_clips/c1').update({ videoUrl: url(`tv_clips/${OTHER}/2_cd.mp4`) })));

  // ── HIGH-2 ──
  await check('H2 owner sets treeComponentId DENIED', () => assertFails(as(OWNER).doc(`users/${OWNER}`).update({ treeComponentId: `cmp_${OTHER}` })));
  await check('H2 owner other field OK', () => assertSucceeds(as(OWNER).doc(`users/${OWNER}`).update({ name: 'Ali' })));

  // ── MEDIUM-1 ──
  await check('M1 job ad type -> cheap_product DENIED', () => assertFails(as(OWNER).doc('ads/a1').update({ type: 'cheap_product', editedAt: 1 })));
  await check('M1 job ad type -> service OK', () => assertSucceeds(as(OWNER).doc('ads/a1').update({ type: 'service', editedAt: 2 })));

  // ── MEDIUM-3 ──
  const yuk = (extra = {}) => ({
    ownerId: OWNER, vehicleType: 'small', phone: OWNER, ownerName: 'A', lat: 41.0, lng: 60.0,
    workStartMinutes: 480, workEndMinutes: 1200, loadStatus: 'empty', rating: 0, completedLoads: 0,
    expiresAt: Timestamp.fromMillis(Date.now() + 60 * 86400000), ...extra,
  });
  await check('M3 yuk create normal OK', () => assertSucceeds(as(OWNER).collection('yuk_local_drivers').add(yuk())));
  const noExp = yuk();
  delete noExp.expiresAt;
  await check('M3 yuk create without expiresAt (old app) OK', () => assertSucceeds(as(OWNER).collection('yuk_local_drivers').add(noExp)));
  await check('M3 yuk create rating 5 DENIED', () => assertFails(as(OWNER).collection('yuk_local_drivers').add(yuk({ rating: 5 }))));
  await check('M3 yuk create completedLoads DENIED', () => assertFails(as(OWNER).collection('yuk_local_drivers').add(yuk({ completedLoads: 40 }))));
  await check('M3 yuk create expiresAt 1 year DENIED', () => assertFails(as(OWNER).collection('yuk_local_drivers').add(yuk({ expiresAt: Timestamp.fromMillis(Date.now() + 365 * 86400000) }))));

  await env.cleanup();
  const ok = results.filter(Boolean).length;
  console.log(`\n${ok}/${results.length} passed`);
  process.exit(ok === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
