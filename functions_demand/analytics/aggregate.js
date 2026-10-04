'use strict';

/**
 * 13.5.2 — КУНЛИК АГРЕГАЦИЯ.
 *
 * Мавжуд ҳужжатларни скан қилиб `analytics_demand_daily` ёзади.
 * Янги коллекция, янги trigger ва BigQuery керак эмас (Т-22) —
 * репода аллақачон шунга ўхшаш қувур бор (`analytics_pipeline.js`).
 *
 * Кесим: **кун × модул × ҳудуд** (эга талаби: «ҳаммаси модул ва ҳудуд
 * бўйича кесимда»).
 *
 * НАРХИ: кунда 200 талаб бўлса — 200 ҳужжат + 200 `private/stats` =
 * 400 ўқиш/кун ≈ $0,0002. Ҳажм 10 000'дан ошса `pageSize` билан
 * бўлиб ўқиш керак бўлади (интерфейс шунга тайёр).
 */

const m = require('./metrics');

const DEMANDS = 'demands';

/**
 * Берилган кун учун агрегация.
 *
 * @param {object} deps
 * @param {object} deps.db
 * @param {string} [deps.dateStr] `YYYY-MM-DD` (Asia/Tashkent). Бўлмаса — кечаги кун.
 * @param {Date} [deps.now]
 * @param {number} [deps.pageSize]
 * @param {boolean} [deps.dryRun] ҳисоблайди, ЁЗМАЙДИ
 */
async function aggregateDay(deps) {
  const {
    db, dateStr: inputDate, now = new Date(), pageSize = 500, dryRun = false,
  } = deps;

  // Стандарт — КЕЧАГИ кун: бугунги кун ҳали тугамаган, унинг ҳисоби
  // чала бўлади ва кун сайин ўзгариб турарди.
  const dateStr = inputDate
    || m.tashkentDateStr(new Date(now.getTime() - 24 * 3600 * 1000));
  const { start, end } = m.tashkentDayRange(dateStr);

  /** @type {Map<string, object>} `module_regionId` -> bucket */
  const buckets = new Map();

  let scanned = 0;
  let lastDoc = null;

  for (;;) {
    let q = db.collection(DEMANDS)
      .where('createdAt', '>=', start)
      .where('createdAt', '<', end)
      .limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const demand = doc.data() || {};
      const module = demand.module || 'unknown';
      const regionId = (demand.location || {}).regionId || 'unknown';
      const key = `${module}__${regionId}`;

      if (!buckets.has(key)) buckets.set(key, m.emptyBucket());

      // `private/stats` — matchedCount, rejectReasons, push хулосаси.
      let stats = {};
      try {
        const s = await doc.ref.collection('private').doc('stats').get();
        if (s.exists) stats = s.data() || {};
      } catch (e) {
        console.error(`stats o'qilmadi (${doc.id}): ${e.message}`);
      }

      m.addDemand(buckets.get(key), demand, stats);
      scanned += 1;
    }

    if (snap.size < pageSize) break;
    lastDoc = snap.docs[snap.docs.length - 1];
    // `startAfter` учун ишлатилмайдиган саҳифалаш ёрдамчиси йўқ бўлса
    // (fake Firestore), бир саҳифадан кейин тўхтаймиз.
    if (typeof q.startAfter !== 'function') break;
  }

  const written = [];
  for (const [key, bucket] of buckets) {
    const [module, regionId] = key.split('__');
    const docData = m.finalize(bucket, { date: dateStr, module, regionId });
    written.push(docData);
    if (!dryRun) {
      await db.collection(m.COLLECTION)
        .doc(m.docKey(dateStr, module, regionId))
        .set(docData, { merge: true });
    }
  }

  console.log(
    `aggregateDay ${dateStr}: ${scanned} talab, ${written.length} kesim`
    + `${dryRun ? ' (dryRun)' : ''}`,
  );
  return { dateStr, scanned, buckets: written };
}

/**
 * `dispatchNotifications` хулосасини `private/stats`га ёзади.
 *
 * 13.5.3 — `pushEligible` АЛОҲИДА ҳисобланади: policy «юборилади»
 * деган, лекин shadow mode'да юборилмаган ҳолатлар кўриниши керак.
 * Акс ҳолда «push спам бўляптими?» саволига shadow mode'да жавоб
 * бериб бўлмасди — ҳамма нол бўлиб кўринарди.
 */
async function recordPushSummary(db, demandId, summary) {
  const reasons = summary.reasons || {};

  // «Юборилиши керак эди» — ҳақиқатан юборилганлар + shadow mode
  // сабабли тўхтатилганлар. Лимит ва тинч соат БУ ЕРГА КИРМАЙДИ:
  // улар policy'нинг атайин қарори, shadow mode'нинг таъсири эмас.
  const shadowBlocked = Number(reasons.send || 0) - Number(summary.sent || 0);
  const eligible = Number(summary.sent || 0) + Math.max(0, shadowBlocked);

  try {
    await db.collection(DEMANDS).doc(demandId)
      .collection('private').doc('stats')
      .set({
        push: {
          eligible,
          sent: Number(summary.sent || 0),
          digest: Number(summary.digest || 0),
          noConsent: Number(reasons.no_consent || 0),
          skipped: Number(summary.skipped || 0),
          reasons,
          at: new Date(),
        },
      }, { merge: true });
  } catch (e) {
    // Аналитика ёзилмаса асосий оқим бузилмайди.
    console.error(`push xulosasi yozilmadi (${demandId}): ${e.message}`);
  }
}

module.exports = { aggregateDay, recordPushSummary };
