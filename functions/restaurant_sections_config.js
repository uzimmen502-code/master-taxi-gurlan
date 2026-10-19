/**
 * KAFE-RESTORAN — bo'limlar sozlamasi `settings/restaurant_sections` (S3, D-REST-16, D-REST-33).
 *
 * Bu yerda FAQAT boshqariladigan qiymatlar (ega qarorlari, kodga qotirilmaydi — 9, 7-qoida):
 *   - har bo'lim bosqichi: `off` → `internal` (testerIds) → `public` (42-qoida; modul darvozasi bilan bir xil nomlar);
 *   - «Arzon» reyting chegarasi (ega, 2026-10-19: 5.0 — qat'iy: faqat o'rtachasi 5.0 bo'lganlar yuqori qatorda);
 *   - «Yangi»: eng ko'pi bilan 5 ta baho, 30 kun, bitta restorandan bo'lim boshiga 3 ta (ega, 2026-10-19).
 * Bo'limga KIRISH qoidasi bu yerda emas — `restaurant_dish_index.js` (yagona manba).
 *
 * Har saqlash yangi `version` va o'zgarmas tarix `restaurant_sections_history/v{n}` + `admin_audit`
 * (9, 41-qoida); to'g'ridan-to'g'ri yozish `firestore.rules` da yopiq. Hujjat bo'lmasa klient bo'limlarni
 * KO'RSATMAYDI (default — OFF): server hech qachon o'zi bosqichni yoqmaydi.
 *
 * Diagnostika kodlari: STAGE_INVALID, SECTION_UNKNOWN, THRESHOLD_INVALID, NEW_RULE_INVALID, TESTERS_INVALID.
 */
'use strict';

const { SECTION_KEYS } = require('./restaurant_dish_index');

const CONFIG_DOC = ['settings', 'restaurant_sections'];
const HISTORY = 'restaurant_sections_history';
const ADMIN_AUDIT = 'admin_audit';
const STAGES = Object.freeze(['off', 'internal', 'public']);

/** Ega tasdiqlagan boshlang'ich qiymatlar (klientdagi `RestaurantSectionsConfig` shularni takrorlaydi — parity testi). */
const DEFAULTS = Object.freeze({
  cheapRatingThreshold: 5.0,
  newMaxRatings: 5,
  newMaxDays: 30,
  newPerRestaurantPerSection: 3,
});

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** `current` (mavjud hujjat yoki `{}`) ustiga `input` ni qo'yib, TO'LIQ yangi sozlamani qaytaradi (yoki HttpsError). */
function mergeConfig(input, current, { fail, canonicalUid }) {
  const d = input || {};
  const cur = current || {};
  const sections = {};
  const curSections = cur.sections && typeof cur.sections === 'object' ? cur.sections : {};
  for (const k of SECTION_KEYS) sections[k] = STAGES.includes(curSections[k]) ? curSections[k] : 'off';
  if (d.sections != null) {
    if (typeof d.sections !== 'object' || Array.isArray(d.sections)) throw fail('invalid-argument', 'STAGE_INVALID');
    for (const [k, v] of Object.entries(d.sections)) {
      if (!SECTION_KEYS.includes(k)) throw fail('invalid-argument', 'SECTION_UNKNOWN', { section: k });
      if (!STAGES.includes(v)) throw fail('invalid-argument', 'STAGE_INVALID', { section: k });
      sections[k] = v;
    }
  }

  const pick = (key) => (d[key] != null && d[key] !== '' ? d[key] : (cur[key] != null ? cur[key] : DEFAULTS[key]));
  const threshold = Number(pick('cheapRatingThreshold'));
  // 1.0…5.0, ko'pi bilan 2 xona (5.0 — ega qarori; 5 dan yuqori bo'lsa hech kim yuqori qatorga chiqmaydi).
  if (!Number.isFinite(threshold) || threshold < 1 || threshold > 5
      || Math.abs(threshold * 100 - Math.round(threshold * 100)) > 1e-6) {
    throw fail('invalid-argument', 'THRESHOLD_INVALID');
  }
  const intRule = (key, lo, hi) => {
    const n = Number(pick(key));
    if (!Number.isInteger(n) || n < lo || n > hi) throw fail('invalid-argument', 'NEW_RULE_INVALID', { field: key });
    return n;
  };

  let testerIds = Array.isArray(cur.testerIds) ? cur.testerIds : [];
  if (d.testerIds != null) {
    if (!Array.isArray(d.testerIds) || d.testerIds.length > 200) throw fail('invalid-argument', 'TESTERS_INVALID');
    testerIds = [...new Set(d.testerIds.map((x) => canonicalUid(String(x || ''))))];
    if (testerIds.some((x) => !/^\d{12}$/.test(x))) throw fail('invalid-argument', 'TESTERS_INVALID');
  }

  return {
    sections,
    testerIds,
    cheapRatingThreshold: Math.round(threshold * 100) / 100,
    newMaxRatings: intRule('newMaxRatings', 1, 100),
    newMaxDays: intRule('newMaxDays', 1, 365),
    newPerRestaurantPerSection: intRule('newPerRestaurantPerSection', 1, 20),
  };
}

function attachRestaurantSectionsConfig(exportsObj, deps) {
  const { functions, db, admin, canonicalUid, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });

  /**
   * Admin — bo'limlar sozlamasini o'zgartiradi (qisman: berilmagan qiymat saqlanadi).
   * data: { sections?: { cheap: 'public', ... }, testerIds?: [uid], cheapRatingThreshold?, newMaxRatings?,
   *         newMaxDays?, newPerRestaurantPerSection?, reason }
   * → { ok, version, changed }. O'zgarish bo'lmasa versiya OSHMAYDI (takroriy chaqiruv idempotent).
   */
  exportsObj.adminSetRestaurantSections = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const reason = str(data && data.reason, 300);
    const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const next = mergeConfig(data, cur, { fail, canonicalUid });
      const same = snap.exists
        && JSON.stringify(next) === JSON.stringify({
          sections: cur.sections, testerIds: cur.testerIds, cheapRatingThreshold: cur.cheapRatingThreshold,
          newMaxRatings: cur.newMaxRatings, newMaxDays: cur.newMaxDays, newPerRestaurantPerSection: cur.newPerRestaurantPerSection,
        });
      if (same) return { version: Number.isInteger(cur.version) ? cur.version : 0, changed: false };
      const version = (Number.isInteger(cur.version) ? cur.version : 0) + 1;
      const doc = { ...next, version, reason, updatedAt: ts(), updatedBy: actor };
      t.set(ref, doc);
      t.create(db.collection(HISTORY).doc(`v${version}`), {
        ...doc,
        previous: snap.exists
          ? { version: cur.version || 0, sections: cur.sections || {}, cheapRatingThreshold: cur.cheapRatingThreshold ?? null }
          : null,
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'restaurant_sections_set', actor, target: `v${version}`, reason, at: ts(),
      });
      return { version, changed: true };
    });
    console.log(JSON.stringify({ module: 'restaurants', action: 'sections_config', userId: actor, version: out.version, changed: out.changed, result: 'ok' }));
    return { ok: true, ...out };
  });
}

module.exports = { attachRestaurantSectionsConfig, mergeConfig, DEFAULTS, STAGES, CONFIG_DOC };
