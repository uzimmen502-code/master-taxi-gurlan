#!/usr/bin/env node
/**
 * Admin panel shaxsiy PIN — bootstrap (admin audit D-1, 2026-10-08).
 *
 * `adminWebSignIn` endi telefon + PIN talab qiladi. Panelda PIN'ni
 * superadmin beradi (`adminSetAdminPin`), lekin BIRINCHI superadmin'ga
 * PIN berish uchun panelga kirib bo'lmaydi — shu tool kerak. Ega lokal
 * ishga tushiradi (`functions/service-account.json`).
 *
 *   node functions/tools/set_admin_pin.js --list
 *       panel roli bor foydalanuvchilar va PIN berilganmi (faqat o'qish)
 *   node functions/tools/set_admin_pin.js --phone 998XXXXXXXXX
 *       DRY-RUN: kimga berilishini ko'rsatadi, hech narsa yozmaydi
 *   node functions/tools/set_admin_pin.js --phone 998XXXXXXXXX --write
 *       tasodifiy 6 xonali PIN — xeshi `admin_credentials`ga, audit
 *       `admin_audit`ga; PIN ekranga BIR MARTA chiqadi (hech qayerda
 *       saqlanmaydi). Admin keyin panelda o'zi almashtiradi.
 *
 * Rollback: `admin_credentials/{docId}` hujjatini o'chirish (Console) —
 * o'sha admin yana PIN'siz qoladi (kira olmaydi, superadmin qayta beradi).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const adminPin = require('../admin_pin');

const args = process.argv.slice(2);
const LIST = args.includes('--list');
const WRITE = args.includes('--write');
const phoneArg = (() => {
  const i = args.indexOf('--phone');
  return i >= 0 ? String(args[i + 1] || '') : '';
})();

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();
db.settings({ preferRest: true });

const digits = (v) => String(v || '').replace(/\D/g, '');

async function findUser(raw) {
  const d = digits(raw);
  const ids = [...new Set([
    d.length === 9 ? `998${d}` : d,
    d.length === 12 && d.startsWith('998') ? d.slice(3) : d,
  ])].filter((x) => x.length >= 9);
  for (const id of ids) {
    const s = await db.collection('users').doc(id).get();
    if (s.exists) return s;
  }
  return null;
}

async function list() {
  const snap = await db.collection('users').where('role', 'in', adminPin.PANEL_ROLES).get();
  const rows = [];
  for (const u of snap.docs) {
    const c = await db.collection(adminPin.COL).doc(u.id).get();
    rows.push({ docId: u.id, role: u.data().role, pinSet: c.exists, mustChange: c.exists ? c.data().mustChange === true : '' });
  }
  console.table(rows);
}

async function main() {
  if (LIST) return list();
  if (!phoneArg) {
    console.error('Foydalanish: --list | --phone 998XXXXXXXXX [--write]');
    process.exit(2);
  }
  const u = await findUser(phoneArg);
  if (!u) {
    console.error('Foydalanuvchi topilmadi:', phoneArg);
    process.exit(1);
  }
  const role = String(u.data().role || 'user');
  if (!adminPin.PANEL_ROLES.includes(role)) {
    console.error(`Panel roli yo'q (role=${role}) — PIN berilmaydi.`);
    process.exit(1);
  }
  const existing = await db.collection(adminPin.COL).doc(u.id).get();
  console.log(`users/${u.id} role=${role} · PIN ${existing.exists ? 'BOR (almashtiriladi)' : 'yo\'q'}`);
  if (!WRITE) {
    console.log('DRY-RUN: hech narsa yozilmadi. Yozish uchun --write qo\'shing.');
    return;
  }
  const pin = adminPin.generatePin();
  await adminPin.storeAdminPin(db, { docId: u.id, pin, setBy: 'tool:set_admin_pin' });
  await db.collection('admin_audit').add({
    kind: 'admin_pin_set', actor: 'tool:set_admin_pin', target: u.id, role,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
  const check = await db.collection(adminPin.COL).doc(u.id).get();
  if (!check.exists || !adminPin.verifyPinHash(pin, check.data().pin)) {
    console.error('TEKSHIRUV: yozilgan xesh PIN bilan mos emas — qayta urinib ko\'ring.');
    process.exit(1);
  }
  console.log(`\nPIN (faqat hozir ko'rinadi): ${pin}\n` +
    'Panelga kirgach «PIN\'ni o\'zgartirish» bilan almashtiring.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
