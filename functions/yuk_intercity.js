'use strict';

/**
 * Шаҳарлараро юк биржаси (`yuk_listings`) — Cloud Functions қисми.
 *
 * - runExpiry(now): 48 соат муддати ўтган active → closed + FCM;
 *   T−6 соат огоҳлантириш (бир марта, `expireSoonNotified`).
 *   `expirePendingTrips` (index.js) ҳар 1 дақиқада чақиради.
 * - attachSearchIndex: `yuk_listings/{id}` → `search_index` trigger.
 * - listingToSearchEntry: search rebuild учун mapping.
 *
 * Deploy бирлиги ўзгармаган — index.js require қилади.
 */
const { onDocumentWritten } = require('firebase-functions/v2/firestore');

const BATCH_LIMIT = 450;
const WARN_BEFORE_MS = 6 * 60 * 60 * 1000;
const WARN_WINDOW_MS = 90 * 1000; // cron ҳар 1 дақиқа → ойна ±90с

function createYukIntercity(deps) {
  const { db, admin, digits } = deps;
  const FieldValue = admin.firestore.FieldValue;

  function expiresMs(d) {
    const e = d.expiresAt;
    if (!e) return 0;
    if (typeof e.toMillis === 'function') return e.toMillis();
    if (e._seconds != null) return Number(e._seconds) * 1000;
    const parsed = Date.parse(String(e));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function listingToSearchEntry(id, d) {
    const from = String(d.from || '').trim();
    const to = String(d.to || '').trim();
    const status = String(d.status || '').trim();
    const cargo = String(d.cargo || '').trim();
    const vehicle = String(d.vehicleType || '').trim();
    const listingType = String(d.type || '').trim();
    const ms = expiresMs(d);
    const notExpired = !ms || ms > Date.now();
    const title = from && to
      ? `${from} → ${to}`
      : (cargo || vehicle || 'Юк эълони');
    const subtitle = listingType === 'truck'
      ? (vehicle || 'Юк машина')
      : (cargo || 'Юк');
    const stops = Array.isArray(d.stops) ? d.stops.map((s) => String(s || '')) : [];
    return {
      type: 'yuk_listing',
      moduleId: 'yuk_intercity',
      sourceCollection: 'yuk_listings',
      sourceId: id,
      title,
      subtitle,
      price: Math.trunc(Number(d.price) || 0),
      imageUrl: '',
      iconKey: 'yuk',
      keywords: [
        'юк', 'yuk', 'биржа', listingType, vehicle, cargo, from, to, ...stops,
      ],
      geo: { from, to },
      priorityBoost: 6,
      active: status === 'active' && notExpired && title.length > 0,
    };
  }

  function routeLabel(yuk) {
    return `${yuk.from || ''} → ${yuk.to || ''}`.trim();
  }

  /**
   * Муддати ўтганларни ёпиш + T−6h огоҳлантириш. Ўз batch'и (450 та ёзувда
   * commit). Қайтаради: { closed, warn } — log учун.
   */
  async function runExpiry(now) {
    const [expiredSnap, warnSnap] = await Promise.all([
      db.collection('yuk_listings')
        .where('status', '==', 'active')
        .where('expiresAt', '<', now)
        .get(),
      (() => {
        const nowMs = now.toMillis();
        const warnStart = admin.firestore.Timestamp.fromMillis(
          nowMs + WARN_BEFORE_MS - WARN_WINDOW_MS,
        );
        const warnEnd = admin.firestore.Timestamp.fromMillis(
          nowMs + WARN_BEFORE_MS + WARN_WINDOW_MS,
        );
        return db.collection('yuk_listings')
          .where('status', '==', 'active')
          .where('expiresAt', '>=', warnStart)
          .where('expiresAt', '<=', warnEnd)
          .get();
      })(),
    ]);

    let batch = db.batch();
    let writes = 0;
    async function flushIfFull() {
      if (writes >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    for (const doc of expiredSnap.docs) {
      const yuk = doc.data() || {};
      batch.update(doc.ref, {
        status: 'closed',
        closedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        autoExpired: true,
      });
      writes++;

      const ownerKey = digits(yuk.ownerId || yuk.phone || '');
      if (ownerKey.length >= 9) {
        const route = routeLabel(yuk);
        batch.set(db.collection('notifications').doc(), {
          targetPhone: ownerKey,
          title: 'Эълонингиз ёпилди',
          body: route
            ? `${route} — 48 соат муддати тугади`
            : 'Юк биржаси эълони 48 соатдан кейин ёпилди',
          sent: false,
          type: 'yuk_listing_closed',
          screen: 'yuk_intercity',
          listingId: doc.id,
          createdAt: FieldValue.serverTimestamp(),
        });
        writes++;
      }
      await flushIfFull();
    }

    for (const doc of warnSnap.docs) {
      const yuk = doc.data() || {};
      if (yuk.expireSoonNotified === true) continue;
      const ownerKey = digits(yuk.ownerId || yuk.phone || '');
      if (ownerKey.length < 9) continue;

      batch.update(doc.ref, {
        expireSoonNotified: true,
        updatedAt: FieldValue.serverTimestamp(),
      });
      writes++;

      const route = routeLabel(yuk);
      batch.set(db.collection('notifications').doc(), {
        targetPhone: ownerKey,
        title: 'Эълон муддати тугамоқда',
        body: route
          ? `${route} — 6 соат қолди`
          : 'Юк биржаси эълонига 6 соат қолди',
        sent: false,
        type: 'yuk_listing_expire_soon',
        screen: 'yuk_intercity',
        listingId: doc.id,
        createdAt: FieldValue.serverTimestamp(),
      });
      writes++;
      await flushIfFull();
    }

    if (writes > 0) await batch.commit();
    // Log учун (аввалгидек snapshot ўлчамлари).
    return { closed: expiredSnap.size, warn: warnSnap.size };
  }

  /** `yuk_listings/{id}` → search_index. */
  function attachSearchIndex(exportsObj, searchDeps) {
    const { upsertSearchIndexEntry, deleteSearchIndexEntry } = searchDeps;
    exportsObj.onSearchIndexYukListingWrite = onDocumentWritten(
      {
        document: 'yuk_listings/{id}',
        region: 'europe-west1',
      },
      async (event) => {
        const id = event.params.id;
        const after = event.data && event.data.after;
        if (!after || !after.exists) {
          await deleteSearchIndexEntry('yuk_listing', id);
          return;
        }
        await upsertSearchIndexEntry(
          listingToSearchEntry(id, after.data() || {}),
        );
      },
    );
  }

  return { runExpiry, attachSearchIndex, listingToSearchEntry };
}

module.exports = { createYukIntercity };
