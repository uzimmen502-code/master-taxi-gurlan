/**
 * Аудитория бўйича FCM tokenlar — «ҳайдовчи» ҲУҚУҚДАН (capability) аниқланади.
 *
 * Аввал `driver` аудиторияси фақат `users.role == 'driver'` эди. Бу белгини
 * эски «ариза → админ тасдиғи» оқими ёзган; янги оқимда (D-CLEAN-1, ҳайдовчи
 * ўзи ёқади, `starter`) белги ЁЗИЛМАЙДИ — яъни янги ҳайдовчилар «ҳайдовчиларга»
 * хабарни олмас, «фойдаланувчиларга» хабарни эса олар эди (`role == 'user'`).
 * Ҳуқуқ манбаи — `provider_capabilities` (`status.taxi` ишлайдиган ҳолат ва
 * `taxi.taxiTypes` бўш эмас). Ўтиш даврида эски белги ҳам қўшилар эди (union);
 * 2026-10-17 да прод'даги охирги 3 та `role: driver` тозаланди
 * (`tools/cleanup_legacy_driver_role.js`, backup + rollback), union ўчирилди.
 */
'use strict';
const admin = require('firebase-admin');
const capabilitiesModel = require('./capabilities_model');

// Ишлайдиган ҳолатлар — capability моделидан (7-қоида: ягона манба).
const TAXI_WORKING = capabilitiesModel.LIFECYCLES.taxi.working;

function digits(v) {
  return String(v || '').replace(/[^\d]/g, '');
}

/** 998 + 9 рақам; 9 хонали эски ID ҳам канонга келтирилади. */
function canonicalUid(v) {
  const d = digits(v);
  return d.length === 9 ? `998${d}` : d;
}

/**
 * Ишлайдиган ҳолатдаги ва камида битта тури эълон қилинган такси
 * ҳайдовчиларининг канон телефон ID'лари.
 */
async function taxiDriverUids(db, { pageSize = 400 } = {}) {
  const out = new Set();
  for (const status of TAXI_WORKING) {
    let last = null;
    for (;;) {
      let q = db.collection('provider_capabilities')
        .where('status.taxi', '==', status)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const types = Array.isArray((d.taxi || {}).taxiTypes) ? d.taxi.taxiTypes : [];
        const uid = canonicalUid(((d.identity || {}).primaryUid) || '');
        if (types.length > 0 && uid.length >= 12) out.add(uid);
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < pageSize) break;
    }
  }
  return out;
}

function validToken(t) {
  return typeof t === 'string' && t.length >= 10;
}

/** Аудитория бўйича FCM tokenlar (битта token — битта user). */
async function collectFcmTokensForAudience(db, audience) {
  const aud = String(audience || 'all');
  const tokens = new Set();
  let query = db.collection('users');
  if (aud === 'driver') {
    // Эски `role == 'driver'` ЭНДИ ҳисобга олинмайди (прод'да тозаланган,
    // 2026-10-17): «ҳайдовчи» фақат ҲУҚУҚДАН. Қуйида tokenlar ҳуқуқли
    // ҳайдовчилар рўйхатидан йиғилади; `users` саҳифалаш керак эмас.
    query = null;
  } else if (aud === 'courier') {
    query = query.where('role', '==', 'courier');
  } else if (aud === 'user') {
    query = query.where('role', '==', 'user');
  }
  // «user» — ҳайдовчи эмаслар; «driver» — ҳуқуқ бўйича ҳайдовчилар ҳам.
  const drivers = (aud === 'driver' || aud === 'user')
    ? await taxiDriverUids(db) : new Set();

  let lastDoc = null;
  const pageSize = 400;
  for (; query;) {
    let q = query.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const t = data.fcmToken;
      if (!validToken(t)) continue;
      if (aud === 'user') {
        const role = String(data.role || 'user');
        if (role !== 'user') continue;
        if (drivers.has(canonicalUid(doc.id))) continue;
      }
      tokens.add(t);
    }
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }

  if (aud === 'driver' && drivers.size > 0) {
    const ids = [...drivers];
    for (let i = 0; i < ids.length; i += 300) {
      const refs = ids.slice(i, i + 300).map((id) => db.collection('users').doc(id));
      const docs = await db.getAll(...refs);
      for (const doc of docs) {
        if (!doc.exists) continue;
        const t = (doc.data() || {}).fcmToken;
        if (validToken(t)) tokens.add(t);
      }
    }
  }
  return [...tokens];
}

module.exports = { taxiDriverUids, collectFcmTokensForAudience, canonicalUid };
