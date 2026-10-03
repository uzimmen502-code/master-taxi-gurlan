'use strict';

/**
 * 13.2.4 — `dispatchNotifications`.
 *
 * Matcher kimlar mosligini topdi (`demand_matches` yozilgan). Bu modul
 * FAQAT bitta savolga javob beradi: kimning telefoni jiringlaydi.
 *
 * Konsepsiyaning eng muhim ajratmasi ayni shu: KO'RINISH allaqachon
 * ta'minlangan (barcha mos taklifchi `demand_matches`da talabni ko'radi),
 * bu yerda esa faqat PUSH hal qilinadi.
 */

const policy = require('./policy');
const fcm = require('./fcm');

const PUSH_LOG = 'demand_push_log';

/**
 * Taklifchining push tarixini sanaydi (soatlik/kunlik limit uchun).
 *
 * `demand_push_log` dan o'qiladi: u idempotentlik uchun ham, limit uchun
 * ham bitta haqiqat manbai.
 */
async function pushCounters(db, providerId, now) {
  const hourAgo = new Date(now.getTime() - 3600 * 1000);
  const dayAgo = new Date(now.getTime() - 24 * 3600 * 1000);

  const snap = await db.collection(PUSH_LOG)
    .where('providerId', '==', providerId)
    .where('at', '>=', dayAgo)
    .get();

  let sentToday = 0;
  let sentLastHour = 0;
  for (const d of snap.docs) {
    const x = d.data() || {};
    if (x.sent !== true) continue;
    sentToday += 1;
    const at = x.at && typeof x.at.toDate === 'function' ? x.at.toDate() : x.at;
    if (at && at.getTime() >= hourAgo.getTime()) sentLastHour += 1;
  }
  return { sentToday, sentLastHour };
}

/**
 * Push yuborish — bitta talab bo'yicha barcha mos taklifchilarga.
 *
 * @param {object} deps
 * @param {object} deps.db
 * @param {object} deps.messaging admin.messaging()
 * @param {object} deps.keywordIndex
 */
function makeDispatchNotifications(deps) {
  const { db, messaging, keywordIndex } = deps;

  return async function dispatchNotifications(_db, demand, matchResult, extra = {}) {
    const { flags, config } = extra;
    const now = new Date();
    const pushEnabled = Boolean(flags && flags.pushEnabled);

    const districtName = (demand.location || {}).districtId || '';
    const cat = demand.categoryId
      ? keywordIndex.categoryById.get(demand.categoryId)
      : null;
    const categoryName = cat ? (cat.names.uz_Latn || cat.names.uz_Cyrl) : '';

    const summary = {
      demandId: demand.id,
      total: matchResult.ranked.length,
      sent: 0,
      digest: 0,
      skipped: 0,
      reasons: {},
    };

    for (const s of matchResult.ranked) {
      const c = s.candidate || {};
      const providerId = s.providerId;

      // Rozilik bermagan nomzod (cold start, `active_listings`) —
      // talabni inbox'da ko'radi, lekin PUSH OLMAYDI.
      if (c.consentGiven === false) {
        bump(summary.reasons, 'no_consent');
        summary.skipped += 1;
        continue;
      }

      const counters = pushEnabled
        ? await pushCounters(db, providerId, now)
        : { sentToday: 0, sentLastHour: 0 };

      const logSnap = await db.collection(PUSH_LOG)
        .doc(`${demand.id}_${providerId}`).get();

      const decision = policy.decidePush({
        mode: demand.mode,
        config,
        pushEnabled,
        provider: {
          moduleOptOut: c.pushOptOut === true,
          digestOnly: c.digestOnly === true,
          hasToken: true, // haqiqiy tekshiruv `sendToProvider` ichida
          sentLastHour: counters.sentLastHour,
          sentToday: counters.sentToday,
        },
        alreadyLogged: logSnap.exists && (logSnap.data() || {}).sent === true,
        alreadySeen: false,
        now,
      });

      bump(summary.reasons, decision.reason);

      if (decision.digest) {
        summary.digest += 1;
        await queueDigest(db, providerId, demand, decision, now);
        continue;
      }
      if (!decision.send) {
        summary.skipped += 1;
        continue;
      }

      const text = policy.buildPushText({
        mode: demand.mode,
        categoryName,
        districtName,
        distanceKm: (s.metrics || {}).distanceKm,
        detourKm: (s.metrics || {}).detourKm,
      });

      const images = ((demand.media || {}).images || []);
      const message = fcm.buildMessage({
        demandId: demand.id,
        module: demand.module,
        mode: demand.mode,
        text,
        imageUrl: images.length ? images[0] : null,
      });

      const res = await fcm.sendToProvider(
        { db, messaging },
        {
          demandId: demand.id,
          providerId,
          message,
          reason: decision.reason,
          dryRun: !pushEnabled,
        },
      );
      if (res.sent) summary.sent += 1; else summary.skipped += 1;
    }

    console.log(`dispatchNotifications ${demand.id}: ${JSON.stringify(summary)}`);
    return summary;
  };
}

/**
 * Dayjest navbati.
 *
 * Limitdan oshgan yoki tinch soatga tushgan talab shu yerda to'planadi.
 * Yuborish `sendDigests` (scheduled) ishi — bu yerda faqat navbatga
 * qo'yiladi, chunki dayjestning ma'nosi bir nechta talabni BIRGA
 * yuborishda.
 */
async function queueDigest(db, providerId, demand, decision, now) {
  const ref = db.collection('demand_digest_queue').doc(providerId);
  const snap = await ref.get();
  const prev = snap.exists ? (snap.data() || {}) : {};
  const pending = Array.isArray(prev.pending) ? prev.pending : [];

  if (pending.some((p) => p.demandId === demand.id)) return;
  pending.push({
    demandId: demand.id,
    module: demand.module,
    categoryId: demand.categoryId || null,
    at: now,
  });

  await ref.set({
    providerId,
    pending: pending.slice(-50),
    notBefore: decision.retryAt || null,
    lastDigestAt: prev.lastDigestAt || null,
    updatedAt: now,
  }, { merge: true });
}

function bump(obj, key) {
  obj[key] = (obj[key] || 0) + 1;
}

module.exports = { makeDispatchNotifications, pushCounters, queueDigest };
