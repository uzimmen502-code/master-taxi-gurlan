'use strict';

/**
 * 13.2.11 — `trust_events` JURNALI (yozish tomoni).
 *
 * Hisob `trust/compute.js`da, bu fayl faqat voqea yozadi.
 *
 * Jurnal O'ZGARMAS (append-only): hech qachon tahrirlanmaydi va
 * o'chirilmaydi. Sabab — `compute.js` izohida: trust «joriy qiymat ±
 * delta» tarzida saqlansa, bitta xato hisob abadiy qolib ketadi.
 * Jurnal esa har doim qaytadan hisoblashga imkon beradi.
 */

const { requireCanonicalId } = require('../core/ids');
const compute = require('./compute');

const COLLECTION = 'trust_events';

/** Voqea turlari — `compute.EVENT` ustiga qo'shimchalar bilan. */
const EVENT = {
  ...compute.EVENT,
  /** Qabul qilgandan keyin 2 daqiqa ichida bekor qildi — jarima yo'q. */
  QUICK_CANCEL: 'quickCancel',
};

/**
 * Tez bekor qilish vazni 0: konsepsiya «jarima yo'q, lekin tez-tez
 * bo'lsa trust pasayadi» deydi. «Tez-tez» ni alohida hisoblash kerak,
 * shuning uchun voqea YOZILADI (tarix uchun), lekin ballga ta'sir
 * qilmaydi. Ko'p takrorlansa moderator ko'radi.
 */
const EXTRA_WEIGHTS = {
  [EVENT.QUICK_CANCEL]: 0,
};

/**
 * Voqea yozadi.
 *
 * @param {object} db
 * @param {object} e
 * @param {string} e.subjectId  kimning trust'iga ta'sir qiladi
 * @param {string} e.type
 * @param {string} [e.demandId]
 * @param {'provider'|'buyer'} [e.side]
 * @param {number} [e.weight]  konfigni bekor qiladi (qo'lda tuzatish)
 * @param {Date} [e.at]
 */
async function record(db, e) {
  const subjectId = requireCanonicalId(e.subjectId, 'subjectId');
  const at = e.at || new Date();

  const doc = {
    subjectId,
    type: String(e.type || ''),
    side: e.side || 'provider',
    demandId: e.demandId || null,
    at,
    createdAt: at,
  };
  if (Number.isFinite(e.weight)) doc.weight = e.weight;
  else if (Object.prototype.hasOwnProperty.call(EXTRA_WEIGHTS, doc.type)) {
    doc.weight = EXTRA_WEIGHTS[doc.type];
  }
  if (e.note) doc.note = String(e.note).slice(0, 300);

  try {
    await db.collection(COLLECTION).add(doc);
  } catch (err) {
    // Trust voqeasi yozilmasa ASOSIY AMAL BUZILMAYDI: mijoz ishini
    // qaytadan qilmaydi. Lekin logga tushadi — qayta hisoblash uchun.
    console.error(`trust_events yozilmadi (${subjectId}/${doc.type}): ${err.message}`);
  }
  return doc;
}

/**
 * Subyektning barcha voqealari (qayta hisoblash uchun).
 *
 * Chegara 500: undan ortiq voqeasi bor odamda eski voqealar allaqachon
 * so'nib bo'lgan (180 kundan keyin x0.25) va natijaga sezilarli ta'sir
 * qilmaydi.
 */
async function fetchFor(db, subjectId, limit = 500) {
  const id = requireCanonicalId(subjectId, 'subjectId');
  const snap = await db.collection(COLLECTION)
    .where('subjectId', '==', id)
    .orderBy('at', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((d) => d.data() || {});
}

/**
 * `provider_stats`ni qaytadan hisoblab yozadi.
 *
 * Bu YAGONA joy `provider_stats.trustScore`ga yozadi — konsepsiya
 * talabi: «Natija фақат providerStats'га сервер томонидан ёзилади.»
 */
async function recompute(db, subjectId, config, now = new Date()) {
  const id = requireCanonicalId(subjectId, 'subjectId');
  const events = await fetchFor(db, id);
  const r = compute.computeTrust(events, config, now);

  const excluded = compute.excludedFromMatching(r.score, config);

  await db.collection('provider_stats').doc(id).set({
    providerId: id,
    trustScore: r.score,
    trustRaw: r.raw,
    trustEventCount: r.counted,
    matchingBlocked: excluded,
    trustUpdatedAt: now,
  }, { merge: true });

  if (excluded) {
    // Moderatorga xabar — konsepsiya talabi.
    try {
      await db.collection('complaints').add({
        kind: 'trust_too_low',
        subjectId: id,
        trustScore: r.score,
        status: 'pending',
        createdAt: now,
      });
    } catch (e) {
      console.error(`moderator xabari yozilmadi: ${e.message}`);
    }
  }

  return r;
}

module.exports = { COLLECTION, EVENT, EXTRA_WEIGHTS, record, fetchFor, recompute };
