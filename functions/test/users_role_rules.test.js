/**
 * `users/{id}.role` — ўзига `driver` ролини ёзиш (ҳамён аудити 2026-10-07, K-6).
 *
 * `usersWebLooseDriverPromotion()` исталган аутентификацияланган (аноним
 * ҳам) сессияга ИСТАЛГАН `users` ҳужжатида `role: 'driver'` ёзишга рухсат
 * берарди. `creditChange` шу ролга ишонгани учун бу ҳар кимга чексиз кредит
 * эди. Клиент бу ёзувни 2026-06-14 (`a6a0ac3`) дан бери ишлатмайди —
 * ҳайдовчи ролини сервер (Admin SDK) тасдиқда беради.
 *
 * Тест тешикни ҳам, ҚОНУНИЙ оқимларни ҳам қулфлайди: эга профилини
 * ўзгартириши, ҳайдовчининг ўзи `user`га қайтиши. Админ ролни фақат CF
 * (`setUserRoleByAdmin`) орқали беради — rules'да `role` клиентдан
 * ўзгармайди (52115b3).
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/users_role_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const ATTACKER = '998902223344';
const VICTIM = '998906667788';
const DRIVER = '998903334455';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-users-role',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  async function check(name, fn) {
    try {
      await fn();
      results.push(true);
      console.log(`PASS - ${name}`);
    } catch (e) {
      results.push(false);
      console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }

  async function seed() {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc(`users/${ADMIN}`).set({ phone: ADMIN, role: 'admin' });
      await db.doc(`users/${ATTACKER}`).set({ phone: ATTACKER, role: 'user', bonusBalance: 0 });
      await db.doc(`users/${VICTIM}`).set({ phone: VICTIM, role: 'user', bonusBalance: 5000 });
      await db.doc(`users/${DRIVER}`).set({ phone: DRIVER, role: 'driver' });
    });
  }
  const phoneCtx = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const anonCtx = () => testEnv.authenticatedContext('anon_1', {
    firebase: { sign_in_provider: 'anonymous' },
  }).firestore();
  const now = new Date();

  // ─── Тешик ──────────────────────────────────────────────────────────
  await seed();
  await check('R1 o\'z hujjatiga role:\'driver\' yozish — RAD', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${ATTACKER}`)
        .update({ role: 'driver', updatedAt: now }));
  });
  await seed();
  await check('R2 anonim sessiya begona hujjatga role:\'driver\' — RAD', async () => {
    await assertFails(anonCtx().doc(`users/${VICTIM}`)
        .update({ role: 'driver', updatedAt: now }));
  });
  await seed();
  await check('R3 telefonli foydalanuvchi begona hujjatga role:\'driver\' — RAD', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${VICTIM}`)
        .update({ role: 'driver' }));
  });

  // ─── Қонуний оқимлар (regression) ───────────────────────────────────
  await seed();
  await check('R4 egasi o\'z ismini o\'zgartiradi — ruxsat', async () => {
    await assertSucceeds(phoneCtx(ATTACKER).doc(`users/${ATTACKER}`)
        .update({ name: 'Ali', updatedAt: now }));
  });
  await seed();
  await check('R5 haydovchi o\'zi yo\'lovchiga qaytadi (driver → user) — ruxsat', async () => {
    await assertSucceeds(phoneCtx(DRIVER).doc(`users/${DRIVER}`)
        .update({ role: 'user', updatedAt: now }));
  });
  await seed();
  await check('R6 admin ham rules orqali role yoza olmaydi — faqat CF (52115b3)', async () => {
    await assertFails(phoneCtx(ADMIN).doc(`users/${VICTIM}`)
        .update({ role: 'driver', updatedAt: now }));
  });
  await seed();
  await check('R6b admin profil maydonini o\'zgartiradi (role\'siz) — ruxsat', async () => {
    await assertSucceeds(phoneCtx(ADMIN).doc(`users/${VICTIM}`)
        .update({ name: 'Tuzatildi', updatedAt: now }));
  });
  await seed();
  await check('R7 egasi bonusBalance\'ga tega olmaydi (o\'zgarmagan himoya)', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${ATTACKER}`)
        .update({ bonusBalance: 1000000 }));
  });

  // ─── Бошқанинг профили (usersGuestProfilePatchOnly олиб ташланди) ───
  await seed();
  await check('G1 anonim sessiya begona profilda name/birthDate — RAD', async () => {
    await assertFails(anonCtx().doc(`users/${VICTIM}`)
        .update({ name: 'X', birthDate: '2000-01-01', updatedAt: now }));
  });
  await seed();
  await check('G2 begona foydalanuvchi fcmToken\'ni o\'ziga burolmaydi — RAD', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${VICTIM}`)
        .update({ fcmToken: 'attacker_token', updatedAt: now }));
  });
  await seed();
  await check('G3 begona foydalanuvchi blockedUntil yoza olmaydi — RAD', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${VICTIM}`)
        .update({ blockedUntil: now, cancelCount: 9 }));
  });
  await seed();
  await check('G4 egasi: ilovaning haqiqiy yozuvlari (fcm _saveToken, yangiliklar) — ruxsat', async () => {
    const own = phoneCtx(VICTIM).doc(`users/${VICTIM}`);
    await assertSucceeds(own.set({
      phone: VICTIM, phoneDigits: VICTIM, fcmToken: 't1', updatedAt: now,
    }, { merge: true }));
    await assertSucceeds(own.update({ lastNewsReadAt: now, lastSeenBroadcastSeq: 3 }));
    await assertSucceeds(own.update({ birthDate: '1990-05-05', birthDateSetAt: now }));
  });
  await seed();
  await check('G5 admin blokni tozalaydi (marshrut admin ekrani) — ruxsat', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${VICTIM}`).update({ blockedUntil: now, cancelCount: 3 });
    });
    // rules-unit-testing compat SDK'ни ишлатади (provider_presence_rules каби).
    const firebase = require('firebase/compat/app');
    require('firebase/compat/firestore');
    await assertSucceeds(phoneCtx(ADMIN).doc(`users/${VICTIM}`)
        .update({ blockedUntil: firebase.firestore.FieldValue.delete(), cancelCount: 0 }));
  });

  // ─── users CREATE (O-16): фақат эгаси, фақат каноник id ────────────
  const NEWU = '998907770001';
  await seed();
  await check('C1 anonim sessiya yangi users hujjatini yarata olmaydi — RAD', async () => {
    await assertFails(anonCtx().doc(`users/${NEWU}`)
        .set({ phone: NEWU, name: 'X', fcmToken: 'attacker' }));
  });
  await seed();
  await check('C2 telefonli foydalanuvchi BEGONA raqamga hujjat yarata olmaydi — RAD', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${NEWU}`)
        .set({ phone: NEWU, name: 'X' }));
  });
  await seed();
  await check('C3 ro\'yxatdagi foydalanuvchining 9 xonali dublikati (fcmToken bilan) — RAD', async () => {
    await assertFails(phoneCtx(ATTACKER).doc(`users/${VICTIM.slice(3)}`)
        .set({ phone: VICTIM, fcmToken: 'attacker_token' }));
    await assertFails(anonCtx().doc(`users/${VICTIM.slice(3)}`)
        .set({ phone: VICTIM, fcmToken: 'attacker_token' }));
  });
  await seed();
  await check('C4 egasi o\'z 9 xonali dublikatini ham yarata olmaydi (split hamyon/push) — RAD', async () => {
    await assertFails(phoneCtx(NEWU).doc(`users/${NEWU.slice(3)}`)
        .set({ phone: NEWU, name: 'Ali' }));
  });
  await seed();
  await check('C5 onbording: egasi o\'z kanonik hujjatini yaratadi (ilova payload) — ruxsat', async () => {
    await assertSucceeds(phoneCtx(NEWU).doc(`users/${NEWU}`).set({
      phone: NEWU, name: 'Ali', gender: 'male', birthDate: '1990-01-01',
      birthDateSetAt: now, updatedAt: now,
    }, { merge: true }));
  });
  await seed();
  await check('C6 FcmService._saveToken: hujjat yo\'q bo\'lsa egasi yaratadi — ruxsat', async () => {
    await assertSucceeds(phoneCtx(NEWU).doc(`users/${NEWU}`).set({
      phone: NEWU, phoneDigits: NEWU, fcmToken: 't1', updatedAt: now,
    }, { merge: true }));
  });
  await seed();
  await check('C7 egasi ham yaratishda bonusBalance / role:admin yoza olmaydi — RAD', async () => {
    await assertFails(phoneCtx(NEWU).doc(`users/${NEWU}`).set({ phone: NEWU, bonusBalance: 1000000 }));
    await assertFails(phoneCtx(NEWU).doc(`users/${NEWU}`).set({ phone: NEWU, role: 'admin' }));
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
