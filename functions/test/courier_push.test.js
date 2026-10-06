/**
 * `functions/courier_push.js` — kuryerga push manbalari (13.6.4, D-CLEAN-1).
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida (Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-courier-push \
 *     "node functions/test/courier_push.test.js"
 *
 * D-CLEAN-1 dan keyin: token FAQAT `users.fcmToken`, onlayn ro'yxat FAQAT
 * `provider_presence` (module == courier, 120 s ichida). Legacy `couriers`
 * UMUMAN o'qilmaydi — bu test shuni ham qulflaydi.
 */
'use strict';
const admin = require('firebase-admin');
const { createCourierPush } = require('../courier_push');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-push';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { Timestamp } = admin.firestore;

function canonicalUid(v) {
  const d = String(v || '').replace(/[^\d]/g, '');
  return d.length === 9 ? `998${d}` : d;
}
const NOW = new Date('2026-10-06T10:00:00.000Z');
const push = createCourierPush({ db, canonicalUid, now: () => NOW });
const agoSec = (s) => Timestamp.fromMillis(NOW.getTime() - s * 1000);

const A = '998901110001';
const B = '998902220002';
const C9 = '903330003';
const C12 = '998903330003';
const tok = (s) => `${s}${'x'.repeat(142 - s.length)}`;

const results = [];
const check = (name, pass, detail) => { results.push({ name, pass }); console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`); };
async function expectEq(name, got, want) {
  const g = JSON.stringify(got); const w = JSON.stringify(want);
  check(name, g === w, g === w ? '' : `kutilgan ${w}, olingan ${g}`);
}
async function wipe(col) { const s = await db.collection(col).get(); await Promise.all(s.docs.map((d) => d.ref.delete())); }
const reset = () => Promise.all(['users', 'couriers', 'provider_presence'].map(wipe));
const presence = (id, over = {}) => db.collection('provider_presence').doc(id).set({
  providerId: id, module: 'courier', isOnline: true, updatedAt: agoSec(10), ...over,
});

async function main() {
  // ── token: faqat users ──────────────────────────────────────────────
  await reset();
  await db.collection('users').doc(A).set({ fcmToken: tok('users_A') });
  await db.collection('couriers').doc(A).set({ isOnline: true, fcmToken: tok('couriers_A') });
  await expectEq('token `users.fcmToken` dan', await push.resolveToken(A), tok('users_A'));

  await reset();
  await db.collection('couriers').doc(A).set({ fcmToken: tok('couriers_A') });
  await expectEq('D-CLEAN-1: `couriers.fcmToken` O\'QILMAYDI', await push.resolveToken(A), '');

  await reset();
  await db.collection('users').doc(A).set({ fcmToken: 'qisqa' });
  await expectEq('qisqa token qaytarilmaydi', await push.resolveToken(A), '');
  await expectEq('hujjat yo\'q — bo\'sh satr', await push.resolveToken(B), '');
  await expectEq('bo\'sh courierId — bo\'sh satr', await push.resolveToken(''), '');

  await reset();
  await db.collection('users').doc(C9).set({ fcmToken: tok('users_C9') });
  await expectEq('12 xonali so\'rov 9 xonali `users` hujjatini topadi', await push.resolveToken(C12), tok('users_C9'));
  await reset();
  await db.collection('users').doc(C12).set({ fcmToken: tok('users_C12') });
  await expectEq('9 xonali so\'rov 12 xonalini topadi', await push.resolveToken(C9), tok('users_C12'));
  await expectEq('formatlangan raqam ham ishlaydi', await push.resolveToken('+998 90 333-00-03'), tok('users_C12'));

  // ── onlayn: faqat presence ──────────────────────────────────────────
  await reset();
  await presence(A);
  await db.collection('couriers').doc(B).set({ isOnline: true, fcmToken: tok('couriers_B'), updatedAt: agoSec(10) });
  await expectEq('onlayn ro\'yxat FAQAT presence dan (couriers e\'tiborga olinmaydi)', await push.onlineCourierIds(), [A]);

  await reset();
  await presence(A, { isOnline: false });
  await expectEq('offline presence olinmaydi', await push.onlineCourierIds(), []);
  await reset();
  await presence(A, { module: 'taxi' });
  await expectEq('boshqa modul kuryer push\'iga tushmaydi', await push.onlineCourierIds(), []);
  await reset();
  await presence(A, { updatedAt: agoSec(121) });
  await expectEq('ESKIRGAN presence push olmaydi (120 s)', await push.onlineCourierIds(), []);
  await reset();
  await presence(A, { updatedAt: agoSec(119) });
  await expectEq('chegara ichidagi presence push oladi', await push.onlineCourierIds(), [A]);
  await reset();
  await db.collection('provider_presence').doc(A).set({ providerId: A, module: 'courier', isOnline: true });
  await expectEq('`updatedAt` yo\'q presence ishonchsiz', await push.onlineCourierIds(), []);

  // ── kimlik faqat kalitdan ───────────────────────────────────────────
  await reset();
  await db.collection('users').doc(A).set({ fcmToken: tok('users_A') });
  await db.collection('users').doc(B).set({ fcmToken: tok('users_B') });
  await presence(A, { providerId: B });
  await expectEq('soxta `providerId` MAYDONI inkor qilinadi (18-qoida)', await push.onlineCourierIds(), [A]);
  await expectEq('push A ning tokeniga ketadi, B ga EMAS', await push.onlineCourierTokens(), [tok('users_A')]);

  // ── takrorsizlik va tokensiz ────────────────────────────────────────
  await reset();
  await db.collection('users').doc(C12).set({ fcmToken: tok('users_C') });
  await presence(C9);
  await presence(C12);
  await expectEq('9 va 12 xonali presence BITTA odam', await push.onlineCourierIds(), [C12]);
  await expectEq('token bir marta', (await push.onlineCourierTokens()).length, 1);

  await reset();
  await presence(A);
  await expectEq('tokeni yo\'q kuryer ro\'yxatda, push ro\'yxatida emas',
    [(await push.onlineCourierIds()).length, (await push.onlineCourierTokens()).length], [1, 0]);
  await reset();
  await expectEq('bo\'sh bazada xato tashlamaydi', await push.onlineCourierTokens(), []);

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} courier_push checks passed.`);
  if (failed.length) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
