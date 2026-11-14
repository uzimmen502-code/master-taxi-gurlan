/**
 * Шаҳарлараро рейс — автоматик суриш (жўнашга ≤ 10 дақ, салон тўлмаган → +2 соат,
 * кунига ≤ 4). Эга қарори 2026-10-15.
 *
 *   firebase emulators:exec --only firestore --project demo-auto-shift \
 *     "node functions/test/intercity_auto_shift.test.js"
 *
 * Қулфланади: соф қарор (чегаралар) + ҲАҚИҚИЙ Firestore'да: рейс/броннинг
 * янги вақти, комиссия ЎЗГАРМАЙДИ, аудит, хабарлар, идемпотентлик, лимит.
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-auto-shift';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const { planShift, runAutoShift, deriveDepartureMs, AUTO_SHIFT } = require('../intercity_auto_shift');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

// Тошкент 2026-10-15 14:20 = 09:20Z
const DEP = Date.UTC(2026, 9, 15, 9, 20);
const MIN = 60000;
const listing = (o = {}) => ({ isActive: true, seats: 2, seatCapacity: 4, scheduleDate: '2026-10-15', hour: 14, ...o });

(async () => {
  // ── Соф қарор ──────────────────────────────────────────────────────
  await check('конфигурация: 10 дақ, 2 соат, кунига 4', () => {
    assert.deepStrictEqual({ ...AUTO_SHIFT }, { triggerMinutes: 10, shiftHours: 2, maxPerDay: 4 });
  });
  await check('чегара: 11 дақ — ҳали эмас, 10 дақ ва 1 дақ — суради', () => {
    const p = (m) => planShift({ listing: listing(), tripDepMs: DEP, count: 0, nowMs: DEP - m * MIN });
    assert.strictEqual(p(11).reason, 'not_yet');
    assert.strictEqual(p(10).action, 'shift');
    assert.strictEqual(p(1).action, 'shift');
    assert.strictEqual(p(0).reason, 'departed');
    assert.strictEqual(p(-5).reason, 'departed');
  });
  await check('сурилган вақт: +2 соат, соат/вақт матни, ҳисоб +1', () => {
    const p = planShift({ listing: listing(), tripDepMs: DEP, count: 1, nowMs: DEP - 10 * MIN });
    assert.strictEqual(p.newMs - DEP, 2 * 3600000);
    assert.strictEqual(p.newHour, 16);
    assert.strictEqual(p.newStartTime, '16:20');
    assert.strictEqual(p.count, 2);
  });
  await check('салон тўлган (seats 0) — сурилмайди; номаълум — тахмин қилинмайди', () => {
    const now = DEP - 5 * MIN;
    assert.strictEqual(planShift({ listing: listing({ seats: 0 }), tripDepMs: DEP, nowMs: now }).reason, 'full');
    assert.strictEqual(planShift({ listing: listing({ seats: undefined }), tripDepMs: DEP, nowMs: now }).reason, 'seats_unknown');
    assert.strictEqual(planShift({ listing: listing({ seats: 1 }), tripDepMs: DEP, nowMs: now }).action, 'shift');
  });
  await check('кунлик лимит: 3-марта суради (4-чи), 4 та бўлгач — тўхтайди ва хабар белгиси', () => {
    const now = DEP - 5 * MIN;
    assert.strictEqual(planShift({ listing: listing(), tripDepMs: DEP, count: 3, nowMs: now }).action, 'shift');
    const p = planShift({ listing: listing(), tripDepMs: DEP, count: 4, nowMs: now });
    assert.strictEqual(p.reason, 'cap');
    assert.strictEqual(p.notify, 'cap');
  });
  await check('ярим кечадан ўтса — сурилмайди', () => {
    const late = Date.UTC(2026, 9, 15, 18, 30); // Тошкент 23:30
    const p = planShift({ listing: listing({ hour: 23 }), tripDepMs: late, nowMs: late - 5 * MIN });
    assert.strictEqual(p.reason, 'midnight');
    const ok = Date.UTC(2026, 9, 15, 16, 50); // 21:50 → 23:50 шу кун
    assert.strictEqual(planShift({ listing: listing({ hour: 21 }), tripDepMs: ok, nowMs: ok - 5 * MIN }).action, 'shift');
  });
  await check('10 дақ ичида эълон/ўзгартирилган рейс — сурилмайди', () => {
    const now = DEP - 5 * MIN;
    assert.strictEqual(planShift({ listing: listing(), tripDepMs: DEP, tripTouchedMs: DEP - 7 * MIN, nowMs: now }).reason, 'fresh_in_window');
    assert.strictEqual(planShift({ listing: listing(), tripDepMs: DEP, tripTouchedMs: DEP - 3 * 3600000, nowMs: now }).action, 'shift');
  });
  await check('тўловсиз (эски) эълон: вақт scheduleDate+hour дан, дақиқа 0', () => {
    assert.strictEqual(deriveDepartureMs('2026-10-15', 14), Date.UTC(2026, 9, 15, 9, 0));
    assert.strictEqual(deriveDepartureMs('bad', 14), null);
    const p = planShift({ listing: listing(), nowMs: Date.UTC(2026, 9, 15, 8, 55) });
    assert.strictEqual(p.action, 'shift');
    assert.strictEqual(p.newStartTime, '16:00');
  });
  await check('эълонда minute бор — жўнаш шу дақиқадан ҳисобланади', () => {
    assert.strictEqual(deriveDepartureMs('2026-10-15', 14, 20), DEP);
    assert.strictEqual(deriveDepartureMs('2026-10-15', 14, 61), null);
    const p = planShift({ listing: listing({ minute: 20 }), nowMs: DEP - 10 * MIN });
    assert.strictEqual(p.action, 'shift');
    assert.strictEqual(p.newMinute, 20);
  });
  await check('хабарлар: уч тилда калитлар ва ўринбосарлар бир хил', () => {
    const { MESSAGES, LANGS, render } = require('../notif_i18n');
    const ph = (s) => (s.match(/\{\w+\}/g) || []).sort().join(',');
    for (const [key, byLang] of Object.entries(MESSAGES)) {
      assert.deepStrictEqual(Object.keys(byLang).sort(), [...LANGS].sort(), key);
      for (const part of ['title', 'body']) {
        const set = new Set(LANGS.map((l) => ph(byLang[l][part])));
        assert.strictEqual(set.size, 1, `${key}.${part} ўринбосарлар тилларда фарқ қилади`);
      }
    }
    assert.strictEqual(render('auto_shift_passenger', 'zz', { time: '09:05' }).body.includes('09:05'), true);
  });
  await check('фаол эмас эълон — тегилмайди', () => {
    assert.strictEqual(planShift({ listing: listing({ isActive: false }), tripDepMs: DEP, nowMs: DEP - 5 * MIN }).reason, 'inactive');
  });

  // ── Ҳақиқий Firestore ───────────────────────────────────────────────
  const D = '998901110001';
  const wipe = async (col) => { const s = await db.collection(col).get(); await Promise.all(s.docs.map((d) => d.ref.delete())); };
  const reset = async (o = {}) => {
    await Promise.all(['intercity_drivers', 'taxi_trips', 'taxi_reschedules', 'intercity_bookings',
      'schedules', 'intercity_auto_shifts', 'notifications', 'users'].map(wipe));
    // Тил — иловада сақланган `users.appLang`; B2 да майдон йўқ (эски илова).
    await db.collection('users').doc(D).set({ appLang: 'uz_Latn' });
    await db.collection('users').doc('998901110002').set({ appLang: 'ru' });
    await db.collection('users').doc('998901110003').set({ phone: 'x' });
    await db.collection('intercity_drivers').doc(D).set({
      isActive: true, seats: 2, seatCapacity: 4, scheduleDate: '2026-10-15', hour: 14,
      phoneDigits: D, price: 100000, ...(o.legacy ? {} : { billingTripId: 'T1' }),
    });
    if (!o.legacy) {
      await db.collection('taxi_trips').doc('T1').set({
        status: 'published', driverUid: D, accountId: 'ACC1', feeAmount: 8000, farePerSeat: 100000,
        departureAt: Timestamp.fromMillis(DEP), scheduleDate: '2026-10-15', startTime: '14:20',
        createdAt: Timestamp.fromMillis(DEP - 5 * 3600000), updatedAt: Timestamp.fromMillis(DEP - 5 * 3600000),
        rescheduleCount: 0,
      });
    }
    for (const [id, st, ph] of [['B1', 'confirmed', '998901110002'], ['B2', 'pending', '998901110003'], ['B3', 'cancelled', '998901110004']]) {
      await db.collection('intercity_bookings').doc(id).set({
        driverId: D, status: st, userPhone: ph, passengers: 1, departureTime: Timestamp.fromMillis(DEP),
        departureReminderSent: true,
      });
    }
    await db.collection('schedules').doc('S1').set({ driverId: D, taxiType: 'intercity', date: '2026-10-15', isActive: true, startTime: '14:20' });
  };
  const run = (nowMs) => runAutoShift({ db, admin, nowMs });
  const notifs = async () => (await db.collection('notifications').get()).docs.map((d) => ({ id: d.id, ...d.data() }));

  await reset();
  await check('10 дақ қолганда: эълон, рейс, бронлар, жадвал +2 соат; комиссия ўзгармайди', async () => {
    const st = await run(DEP - 10 * MIN);
    assert.strictEqual(st.shifted, 1);
    const l = (await db.collection('intercity_drivers').doc(D).get()).data();
    assert.strictEqual(l.hour, 16);
    assert.strictEqual(l.scheduleDate, '2026-10-15');
    const t = (await db.collection('taxi_trips').doc('T1').get()).data();
    assert.strictEqual(t.departureAt.toMillis(), DEP + 2 * 3600000);
    assert.strictEqual(t.startTime, '16:20');
    assert.strictEqual(t.rescheduleCount, 1);
    assert.strictEqual(t.feeAmount, 8000, 'комиссия ўзгармайди');
    assert.strictEqual(t.status, 'published');
    const rs = (await db.collection('taxi_reschedules').get()).docs.map((d) => d.data());
    assert.strictEqual(rs.length, 1);
    assert.strictEqual(rs[0].source, 'auto_shift');
    const b1 = (await db.collection('intercity_bookings').doc('B1').get()).data();
    const b2 = (await db.collection('intercity_bookings').doc('B2').get()).data();
    const b3 = (await db.collection('intercity_bookings').doc('B3').get()).data();
    assert.strictEqual(b1.departureTime.toMillis(), DEP + 2 * 3600000);
    assert.strictEqual(b2.departureTime.toMillis(), DEP + 2 * 3600000);
    assert.strictEqual(b1.departureReminderSent, false);
    assert.strictEqual(b3.departureTime.toMillis(), DEP, 'бекор қилинган брон тегилмайди');
    assert.strictEqual(b3.departureReminderSent, true);
    assert.strictEqual((await db.collection('schedules').doc('S1').get()).data().startTime, '16:20');
    const c = (await db.collection('intercity_auto_shifts').doc(`${D}_2026-10-15`).get()).data();
    assert.strictEqual(c.count, 1);
  });
  await check('хабарлар: ҳайдовчига 1, 2 та фаол йўловчига 1 тадан, бекор қилинганга йўқ', async () => {
    const n = await notifs();
    assert.strictEqual(n.length, 3);
    assert.strictEqual(n.filter((x) => x.type === 'intercity_auto_shift' && x.targetPhone === D).length, 1);
    const pax = n.filter((x) => x.type === 'intercity_trip_rescheduled').map((x) => x.targetPhone).sort();
    assert.deepStrictEqual(pax, ['998901110002', '998901110003']);
    assert.ok(n.every((x) => x.sent === false));
  });
  await check('хабар тили фойдаланувчи тилида: uz_Latn / ru / (майдон йўқ → uz_Cyrl)', async () => {
    const n = await notifs();
    const drv = n.find((x) => x.type === 'intercity_auto_shift');
    assert.ok(drv.title.startsWith('⏱ Reys 2 soatga surildi'), drv.title);
    assert.ok(drv.body.includes('16:20') && drv.body.includes('(1/4)'), drv.body);
    const ru = n.find((x) => x.targetPhone === '998901110002');
    assert.ok(ru.body.includes('Отправление перенесено на 16:20'), ru.body);
    const cy = n.find((x) => x.targetPhone === '998901110003');
    assert.ok(cy.body.includes('Жўнаш 16:20 га сурилди'), cy.body);
    assert.ok(n.every((x) => !/[{}]/.test(x.title + x.body)), 'ўринбосар қолмаган');
  });
  await check('эълонга минут ёзилади (йўловчи экрани дақиқани кўрсатади)', async () => {
    const l = (await db.collection('intercity_drivers').doc(D).get()).data();
    assert.strictEqual(l.minute, 20);
    assert.strictEqual(l.hour, 16);
  });
  await check('қайта ишга туширилса (retry/кейинги дақиқа) — икки марта сурилмайди', async () => {
    const st = await run(DEP - 9 * MIN);
    assert.strictEqual(st.shifted, 0);
    assert.strictEqual((await db.collection('taxi_trips').doc('T1').get()).data().rescheduleCount, 1);
    assert.strictEqual((await notifs()).length, 3);
  });

  await reset();
  await check('салон тўлган — суриш йўқ', async () => {
    await db.collection('intercity_drivers').doc(D).update({ seats: 0 });
    const st = await run(DEP - 5 * MIN);
    assert.strictEqual(st.shifted, 0);
    assert.strictEqual((await db.collection('taxi_trips').doc('T1').get()).data().rescheduleCount, 0);
  });

  await reset();
  await check('лимит: 4 марта сурилгач 5-чида сурилмайди, ҳайдовчига хабар БИР марта', async () => {
    await db.collection('intercity_auto_shifts').doc(`${D}_2026-10-15`).set({ count: 4 });
    let st = await run(DEP - 5 * MIN);
    assert.strictEqual(st.shifted, 0);
    st = await run(DEP - 4 * MIN);
    assert.strictEqual(st.shifted, 0);
    const stops = (await notifs()).filter((x) => x.type === 'intercity_auto_shift_stop');
    assert.strictEqual(stops.length, 1);
    assert.strictEqual((await db.collection('taxi_trips').doc('T1').get()).data().rescheduleCount, 0);
  });

  await reset();
  await check('соат филтри: 14:00 жорий соатдан бошқа эълонлар ўқилмайди', async () => {
    await db.collection('intercity_drivers').doc(D).update({ hour: 18 });
    const st = await run(DEP - 5 * MIN);
    assert.strictEqual(st.checked, 0);
  });

  await reset({ legacy: true });
  await check('тўловсиз (эски) эълон: соат бўйича сурилади, брон ҳам', async () => {
    const st = await run(Date.UTC(2026, 9, 15, 8, 55)); // Тошкент 13:55, жўнаш 14:00
    assert.strictEqual(st.shifted, 1);
    assert.strictEqual((await db.collection('intercity_drivers').doc(D).get()).data().hour, 16);
    assert.strictEqual((await db.collection('schedules').doc('S1').get()).data().startTime, '16:00');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
