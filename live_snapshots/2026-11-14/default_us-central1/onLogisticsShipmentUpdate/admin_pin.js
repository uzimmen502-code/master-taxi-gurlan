/**
 * Admin panel — shaxsiy PIN (ega qarori 2026-10-08, admin audit D-1).
 *
 * Avval `adminWebSignIn` faqat telefon raqami bilan admin token berardi:
 * admin raqamini bilgan har kim panelga kira olardi. Endi kirish =
 * telefon + shaxsiy PIN.
 *
 * Saqlash: `admin_credentials/{usersDocId}` — FAQAT Admin SDK (rules'da
 * klient uchun to'liq yopiq). PIN ochiq saqlanmaydi: scrypt (N=16384,
 * r=8, p=1) + har hujjatga alohida 16 baytli salt.
 *
 * Brute-force: ketma-ket `MAX_FAILED` noto'g'ri urinishdan keyin hujjat
 * `LOCK_MS` ga qulflanadi (tranzaksiyada sanaladi — parallel urinishlar
 * hisobni chetlab o'ta olmaydi). Superadmin yangi PIN bersa qulf ochiladi.
 *
 * PIN beriladigan yo'llar:
 *   - superadmin → `adminSetAdminPin` (tasodifiy 6 xonali, bir marta
 *     ko'rsatiladi; admin keyin o'zi o'zgartiradi);
 *   - admin o'zi → `adminChangeOwnPin` (joriy PIN bilan);
 *   - birinchi superadmin → `functions/tools/set_admin_pin.js` (ega lokal
 *     ishga tushiradi).
 */
'use strict';
const crypto = require('crypto');

const COL = 'admin_credentials';
const PANEL_ROLES = ['admin', 'superadmin', 'dispatcher', 'finance', 'auditor'];
const MAX_FAILED = 5;
const LOCK_MS = 15 * 60 * 1000;
const ALGO = 'scrypt-n16384-r8-p1';

function scryptHash(pin, salt) {
  return crypto.scryptSync(String(pin), salt, 32, { N: 16384, r: 8, p: 1 });
}

/** 6 xonali tasodifiy PIN (kriptografik). */
function generatePin() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

/**
 * Yangi PIN qoidasi: 6–12 raqam, hammasi bir xil emas, ketma-ket
 * (123456 / 987654) emas.
 * @returns {string|null} xato kodi yoki null
 */
function validateNewPin(pin) {
  const p = String(pin == null ? '' : pin);
  if (!/^\d{6,12}$/.test(p)) return 'ADMIN_PIN_FORMAT';
  if (/^(\d)\1+$/.test(p)) return 'ADMIN_PIN_WEAK';
  const asc = '01234567890123456789';
  const desc = '98765432109876543210';
  if (asc.includes(p) || desc.includes(p)) return 'ADMIN_PIN_WEAK';
  return null;
}

function hashPin(pin) {
  const salt = crypto.randomBytes(16);
  return {
    algo: ALGO,
    salt: salt.toString('base64'),
    hash: scryptHash(pin, salt).toString('base64'),
  };
}

function verifyPinHash(pin, rec) {
  if (!rec || rec.algo !== ALGO || !rec.salt || !rec.hash) return false;
  const expected = Buffer.from(String(rec.hash), 'base64');
  const actual = scryptHash(pin, Buffer.from(String(rec.salt), 'base64'));
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

function toMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return Number(v) || 0;
}

/**
 * PIN tekshiruvi (tranzaksiyada). Muvaffaqiyatsiz urinishlar sanaladi.
 * @returns {Promise<{ok: true, mustChange: boolean} | {ok: false, code: string, lockedUntil?: number}>}
 */
async function checkAdminPin(db, { docId, pin, now = new Date() }) {
  const ref = db.collection(COL).doc(docId);
  const nowMs = now.getTime();
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) return { ok: false, code: 'ADMIN_PIN_NOT_SET' };
    const d = snap.data() || {};
    const lockedUntil = toMillis(d.lockedUntil);
    if (lockedUntil > nowMs) {
      return { ok: false, code: 'ADMIN_PIN_LOCKED', lockedUntil };
    }
    if (!verifyPinHash(pin, d.pin)) {
      const failed = (Number(d.failedAttempts) || 0) + 1;
      const patch = { failedAttempts: failed, lastFailedAt: now };
      if (failed >= MAX_FAILED) {
        patch.failedAttempts = 0;
        patch.lockedUntil = new Date(nowMs + LOCK_MS);
      }
      t.update(ref, patch);
      return failed >= MAX_FAILED
        ? { ok: false, code: 'ADMIN_PIN_LOCKED', lockedUntil: nowMs + LOCK_MS }
        : { ok: false, code: 'ADMIN_PIN_WRONG' };
    }
    t.update(ref, { failedAttempts: 0, lockedUntil: null, lastLoginAt: now });
    return { ok: true, mustChange: d.mustChange === true };
  });
}

/** PIN o'rnatish/almashtirish — qulf va urinishlar nolga tushadi. */
async function storeAdminPin(db, { docId, pin, setBy, now = new Date() }) {
  await db.collection(COL).doc(docId).set({
    pin: hashPin(pin),
    setBy,
    setAt: now,
    // Superadmin bergan PIN — admin o'zi almashtirishi tavsiya etiladi.
    mustChange: setBy !== docId,
    failedAttempts: 0,
    lockedUntil: null,
  });
}

module.exports = {
  COL,
  PANEL_ROLES,
  MAX_FAILED,
  LOCK_MS,
  generatePin,
  validateNewPin,
  hashPin,
  verifyPinHash,
  checkAdminPin,
  storeAdminPin,
};
