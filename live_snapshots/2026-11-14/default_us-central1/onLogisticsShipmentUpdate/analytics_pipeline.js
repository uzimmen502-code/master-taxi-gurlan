/**
 * AVA analytics pipeline — business collections → analytics_daily.
 * Does not write into users/orders/tv_clips. Admin-only read of analytics_*.
 *
 * Additive fields (SUM across a Dashboard period):
 *   users.new, content.new*, commerce.ordersCreated/Revenue, tripsCompleted/Revenue
 * Stock fields (last day of period, never SUM):
 *   users.total, content.total*
 * Unique active users are NOT stored as a SUM of DAU — client counts
 * users.lastActiveAt >= periodStart.
 */
'use strict';

const JOB_ID = 'historical_v1';
const PAGE = 400;
const MIN_DATE = '2024-01-01';
const SKIP_ORDER_STATUS = new Set(['rejected', 'cancelled']);

function attachAnalyticsPipeline(exports, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;

  function dateKeyTashkent(raw) {
    if (!raw) return '';
    const d = raw instanceof Date ? raw : raw.toDate ? raw.toDate() : new Date(raw);
    if (Number.isNaN(d.getTime())) return '';
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Tashkent',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(d);
  }

  function todayKeyTashkent() {
    return dateKeyTashkent(new Date());
  }

  function addDays(key, n) {
    const [y, m, d] = key.split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d + n));
    const yyyy = dt.getUTCFullYear();
    const mm = String(dt.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(dt.getUTCDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  function emptyDay(date) {
    return {
      date,
      users: { new: 0, total: 0 },
      content: {
        newClips: 0,
        newShopItems: 0,
        newPlatformProducts: 0,
        newAds: 0,
        totalClips: 0,
        totalShopItems: 0,
        totalPlatformProducts: 0,
        totalAds: 0,
      },
      commerce: {
        ordersCreated: 0,
        ordersRevenue: 0,
        tripsCompleted: 0,
        tripsRevenue: 0,
      },
      source: 'business_backfill',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
  }

  function bump(days, key, path, amount, today) {
    if (!key || key < MIN_DATE || key > today) return;
    const n = Number(amount) || 0;
    if (!n) return;
    if (!days[key]) days[key] = emptyDay(key);
    const parts = path.split('.');
    let cur = days[key];
    for (let i = 0; i < parts.length - 1; i++) {
      cur = cur[parts[i]];
    }
    cur[parts[parts.length - 1]] += n;
  }

  function tsOf(data, field) {
    const v = data[field];
    if (!v) return null;
    if (v.toDate) return v;
    return null;
  }

  async function scanCollection(name, onDoc) {
    let last = null;
    let n = 0;
    for (;;) {
      let q = db
        .collection(name)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(PAGE);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        onDoc(doc);
        n += 1;
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < PAGE) break;
    }
    return n;
  }

  async function buildDailyBuckets() {
    const days = Object.create(null);
    const today = todayKeyTashkent();
    const counts = {
      users: 0,
      tv_clips: 0,
      tv_shop_items: 0,
      platform_products: 0,
      ads: 0,
      orders: 0,
      trips: 0,
    };

    counts.users = await scanCollection('users', (doc) => {
      const d = doc.data() || {};
      bump(days, dateKeyTashkent(tsOf(d, 'createdAt')), 'users.new', 1, today);
    });

    counts.tv_clips = await scanCollection('tv_clips', (doc) => {
      const d = doc.data() || {};
      bump(days, dateKeyTashkent(tsOf(d, 'createdAt')), 'content.newClips', 1, today);
    });

    counts.tv_shop_items = await scanCollection('tv_shop_items', (doc) => {
      const d = doc.data() || {};
      bump(days, dateKeyTashkent(tsOf(d, 'createdAt')), 'content.newShopItems', 1, today);
    });

    counts.platform_products = await scanCollection('platform_products', (doc) => {
      const d = doc.data() || {};
      bump(days, dateKeyTashkent(tsOf(d, 'createdAt')), 'content.newPlatformProducts', 1, today);
    });

    counts.ads = await scanCollection('ads', (doc) => {
      const d = doc.data() || {};
      bump(days, dateKeyTashkent(tsOf(d, 'createdAt')), 'content.newAds', 1, today);
    });

    counts.orders = await scanCollection('orders', (doc) => {
      const d = doc.data() || {};
      const key = dateKeyTashkent(tsOf(d, 'createdAt'));
      if (!key) return;
      bump(days, key, 'commerce.ordersCreated', 1, today);
      const status = String(d.status || '');
      if (SKIP_ORDER_STATUS.has(status)) return;
      bump(days, key, 'commerce.ordersRevenue', Math.trunc(Number(d.total) || 0), today);
    });

    counts.trips = await scanCollection('trips', (doc) => {
      const d = doc.data() || {};
      if (String(d.status || '') !== 'completed') return;
      const key = dateKeyTashkent(tsOf(d, 'createdAt'));
      bump(days, key, 'commerce.tripsCompleted', 1, today);
      bump(days, key, 'commerce.tripsRevenue', Math.trunc(Number(d.fare) || 0), today);
    });

    const keys = Object.keys(days).sort();
    if (keys.length === 0) {
      days[today] = emptyDay(today);
      keys.push(today);
    }

    let cursor = keys[0];
    while (cursor < today) {
      const next = addDays(cursor, 1);
      if (!days[next]) days[next] = emptyDay(next);
      cursor = next;
    }
    if (!days[today]) days[today] = emptyDay(today);

    const allKeys = Object.keys(days).sort();
    let totUsers = 0;
    let totClips = 0;
    let totShop = 0;
    let totPlat = 0;
    let totAds = 0;
    for (const k of allKeys) {
      const row = days[k];
      totUsers += row.users.new;
      totClips += row.content.newClips;
      totShop += row.content.newShopItems;
      totPlat += row.content.newPlatformProducts;
      totAds += row.content.newAds;
      row.users.total = totUsers;
      row.content.totalClips = totClips;
      row.content.totalShopItems = totShop;
      row.content.totalPlatformProducts = totPlat;
      row.content.totalAds = totAds;
      row.source = 'business_backfill';
    }

    return { days, counts, from: allKeys[0], to: allKeys[allKeys.length - 1] };
  }

  async function writeDays(days) {
    const keys = Object.keys(days).sort();
    let written = 0;
    for (let i = 0; i < keys.length; i += 400) {
      const batch = db.batch();
      const slice = keys.slice(i, i + 400);
      for (const k of slice) {
        const row = { ...days[k], date: k };
        batch.set(db.collection('analytics_daily').doc(k), row);
      }
      await batch.commit();
      written += slice.length;
    }
    return written;
  }

  async function runPipeline(reason) {
    const built = await buildDailyBuckets();
    const written = await writeDays(built.days);
    return {
      reason,
      from: built.from,
      to: built.to,
      daysWritten: written,
      processed: built.counts,
    };
  }

  exports.analyticsHistoricalBackfill = functions
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onCall(async (data, context) => {
      const uid = await requireCallerRoles(
        context,
        ['admin', 'superadmin'],
        'Admin only',
      );
      const force = !!(data && data.force);
      const jobRef = db.collection('analytics_backfill_jobs').doc(JOB_ID);
      const prev = await jobRef.get();
      if (prev.exists && prev.data().status === 'completed' && !force) {
        return { ok: true, skipped: true, job: prev.data() };
      }
      await jobRef.set({
        status: 'running',
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        startedBy: uid,
        force,
      }, { merge: true });
      try {
        const result = await runPipeline('backfill');
        await jobRef.set({
          status: 'completed',
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          from: result.from,
          to: result.to,
          processed: result.processed,
          daysWritten: result.daysWritten,
        }, { merge: true });
        return { ok: true, ...result };
      } catch (e) {
        await jobRef.set({
          status: 'failed',
          error: String(e && e.message ? e.message : e),
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw new functions.https.HttpsError(
          'internal',
          String(e && e.message ? e.message : e),
        );
      }
    });

  exports.analyticsDailyRollup = functions
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .pubsub.schedule('10 0 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const result = await runPipeline('daily_rollup');
      await db.collection('analytics_backfill_jobs').doc('daily_rollup').set({
        status: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...result,
      }, { merge: true });
      return null;
    });
}

module.exports = { attachAnalyticsPipeline };
