/**
 * Улгуржи бозор ҳудуди ва эски синов товарлари (docs/hudud_geo_tizimi_uz.md,
 * эга қарорлари D-GEO-10/14, 2026-10-11).
 *
 * 1. Товар ҳудуди = сотувчининг жўнатиш манзили (`wholesale_sellers`
 *    regionId/districtId). Товарни клиент ёзади, лекин rules товарга ҳудуд
 *    ёзишни ТАЪҚИҚЛАЙДИ — ҳудудни фақат шу триггерлар қўяди (18-банд:
 *    клиентга ишонма). Сотувчи манзилни ўзгартирса — барча товарлари.
 * 2. Эски синов товарлари (эга: «янги товарлар 10 тага етганда эскилардан
 *    ўчириш бошлансин, янги 20 та — эски 20 та…»): соатига бир марта,
 *    БОЗОР бўйича алоҳида. ЎЧИРМАЙДИ — `status: inactive` +
 *    `legacyArchived: true` (қайтариб бўлади, 27-банд); audit — admin_audit.
 *    Чегара сана: `settings/app.wholesaleLegacyCutoff` (биринчи ишга
 *    тушганда ҳозирги вақт ёзилади).
 *    ФАҚАТ Улгуржи бозори (эга, 2026-10-11: «Хитойдаги ҳақиқий, тозалаш
 *    фақат Улгуржида»). Аввалги `adminNote`/`status` `legacyPrev*` га
 *    сақланади; бир марта ишланган (`legacyArchived`) товар қайта
 *    танланмайди — админ қайта ёқса, унинг қарори бузилмайди.
 */
'use strict';

/** Тозалаш ишлайдиган бозорлар — Хитой атайлаб йўқ (ҳақиқий товарлар). */
const LEGACY_MARKETS = ['wholesale'];
const LEGACY_NOTE = 'legacy_test_cleanup';
const START_AFTER = 10;
const BATCH = 400;

/** Эски ҳужжатда `market` йўқ — бу Улгуржи (модел `belongsToMarket`). */
function marketOf(d) {
  const m = String((d && d.market) || '').trim();
  return m === 'china' ? 'china' : 'wholesale';
}

function sellerGeo(seller) {
  const s = seller || {};
  const regionId = String(s.regionId || '').trim();
  const districtId = String(s.districtId || '').trim();
  return regionId && districtId ? { regionId, districtId } : { regionId: '', districtId: '' };
}

/** Товарга сотувчи ҳудудини ёзади (фарқ бўлса). `true` — ёзилди. */
async function syncProductGeo(db, admin, productRef, product) {
  const sellerId = String((product && product.sellerId) || '').trim();
  if (!sellerId) return false;
  const seller = await db.collection('wholesale_sellers').doc(sellerId).get();
  const geo = sellerGeo(seller.exists ? seller.data() : null);
  const cur = { regionId: String(product.regionId || ''), districtId: String(product.districtId || '') };
  if (cur.regionId === geo.regionId && cur.districtId === geo.districtId) return false;
  const del = admin.firestore.FieldValue.delete();
  await productRef.update({
    regionId: geo.regionId || del,
    districtId: geo.districtId || del,
  });
  return true;
}

/** Сотувчи манзили ўзгарди — унинг ҳамма товарларига. */
async function syncSellerProducts(db, admin, sellerId, seller) {
  const geo = sellerGeo(seller);
  const snap = await db.collection('wholesale_products').where('sellerId', '==', sellerId).get();
  const del = admin.firestore.FieldValue.delete();
  let updated = 0;
  for (let i = 0; i < snap.docs.length; i += BATCH) {
    const batch = db.batch();
    let n = 0;
    for (const d of snap.docs.slice(i, i + BATCH)) {
      const x = d.data() || {};
      if (String(x.regionId || '') === geo.regionId && String(x.districtId || '') === geo.districtId) continue;
      batch.update(d.ref, { regionId: geo.regionId || del, districtId: geo.districtId || del });
      n += 1;
    }
    if (n > 0) await batch.commit();
    updated += n;
  }
  return updated;
}

function ms(v) {
  if (!v) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

/**
 * Эски синов товарларини яшириш. [LEGACY_MARKETS] бозорида: янги
 * (cutoff'дан кейин яратилган, фаол) товарлар сони N ≥ 10 бўлса — ишланган
 * (`legacyArchived`) эскилар сони N га етгунча энг эски фаол, ҳали
 * ишланмаган эскилар яширилади. Қайта ишга туширилса — ортиқча яширмайди
 * (idempotent: ҳар сафар сонлардан ҳисобланади). Админ қайта ёққан товар
 * ишланган ҳисобланади ва қайта яширилмайди.
 */
async function runLegacyCleanup(db, admin, { now = Date.now(), log = console.log } = {}) {
  const appRef = db.collection('settings').doc('app');
  const app = (await appRef.get()).data() || {};
  let cutoffMs = ms(app.wholesaleLegacyCutoff);
  if (cutoffMs === null) {
    await appRef.set({ wholesaleLegacyCutoff: admin.firestore.Timestamp.fromMillis(now) }, { merge: true });
    log(JSON.stringify({ action: 'wholesaleLegacyCleanup', result: 'cutoff_initialized', cutoffMs: now }));
    return { initialized: true, archived: { wholesale: 0 } };
  }
  const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMs);
  const archived = {};
  for (const market of LEGACY_MARKETS) {
    const newSnap = await db.collection('wholesale_products')
        .where('status', '==', 'active')
        .where('createdAt', '>', cutoff)
        .get();
    const newCount = newSnap.docs.filter((d) => marketOf(d.data()) === market).length;

    const doneSnap = await db.collection('wholesale_products')
        .where('legacyArchived', '==', true)
        .get();
    const alreadyArchived = doneSnap.docs.filter((d) => marketOf(d.data()) === market).length;

    const target = newCount >= START_AFTER ? newCount : 0;
    const need = target - alreadyArchived;
    archived[market] = 0;
    if (need <= 0) continue;

    const oldSnap = await db.collection('wholesale_products')
        .where('status', '==', 'active')
        .where('createdAt', '<=', cutoff)
        .orderBy('createdAt', 'asc')
        .get();
    const pick = oldSnap.docs
        .filter((d) => {
          const x = d.data() || {};
          return marketOf(x) === market && x.legacyArchived !== true;
        })
        .slice(0, need);
    if (pick.length === 0) continue;
    const batch = db.batch();
    for (const d of pick) {
      const x = d.data() || {};
      batch.update(d.ref, {
        status: 'inactive',
        legacyArchived: true,
        legacyArchivedAt: admin.firestore.FieldValue.serverTimestamp(),
        // Қайтариш учун аввалги қийматлар (27-банд).
        legacyPrevStatus: String(x.status || 'active'),
        legacyPrevAdminNote: typeof x.adminNote === 'string' ? x.adminNote : null,
        adminNote: LEGACY_NOTE,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    batch.set(db.collection('admin_audit').doc(), {
      kind: 'wholesale_legacy_archive',
      actor: 'system:wholesaleLegacyCleanup',
      market,
      newCount,
      archivedNow: pick.length,
      archivedTotal: alreadyArchived + pick.length,
      productIds: pick.map((d) => d.id),
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    archived[market] = pick.length;
    log(JSON.stringify({
      action: 'wholesaleLegacyCleanup', market, newCount,
      archivedNow: pick.length, archivedTotal: alreadyArchived + pick.length,
    }));
  }
  return { initialized: false, archived };
}

/**
 * Қайтариш (rollback, 27-банд): тозалаш яширган ва ҳали шу ҳолатда турган
 * товарларга аввалги `status`/`adminNote` қайтарилади. Стандарт — DRY-RUN
 * (ҳеч нарса ёзмайди, номзодлар рўйхати). `legacyArchived` белгиси қолади —
 * товар «ишланган» ҳисобланади ва тозалаш уни қайта яширмайди.
 */
async function restoreLegacyArchived(db, admin, { apply = false, ids = null, actor = 'tool' } = {}) {
  const snap = await db.collection('wholesale_products').where('legacyArchived', '==', true).get();
  const only = ids ? new Set(ids) : null;
  const candidates = snap.docs.filter((d) => {
    const x = d.data() || {};
    return (!only || only.has(d.id)) && x.status === 'inactive' && x.adminNote === LEGACY_NOTE;
  });
  const result = { candidates: candidates.map((d) => d.id), restored: 0, applied: apply };
  if (!apply || candidates.length === 0) return result;
  const FV = admin.firestore.FieldValue;
  for (let i = 0; i < candidates.length; i += BATCH) {
    const part = candidates.slice(i, i + BATCH);
    const batch = db.batch();
    for (const d of part) {
      const x = d.data() || {};
      batch.update(d.ref, {
        status: x.legacyPrevStatus || 'active',
        adminNote: typeof x.legacyPrevAdminNote === 'string' ? x.legacyPrevAdminNote : FV.delete(),
        legacyRestoredAt: FV.serverTimestamp(),
        updatedAt: FV.serverTimestamp(),
      });
    }
    batch.set(db.collection('admin_audit').doc(), {
      kind: 'wholesale_legacy_restore',
      actor: String(actor),
      productIds: part.map((d) => d.id),
      at: FV.serverTimestamp(),
    });
    await batch.commit();
    result.restored += part.length;
  }
  return result;
}

function attachWholesaleGeo(exports, { functions, db, admin }) {
  exports.wholesaleProductGeoSync = functions.firestore
    .document('wholesale_products/{id}')
    .onWrite(async (change) => {
      if (!change.after.exists) return;
      try {
        await syncProductGeo(db, admin, change.after.ref, change.after.data() || {});
      } catch (e) {
        console.error(JSON.stringify({
          action: 'wholesaleProductGeoSync', productId: change.after.id,
          result: 'failed', errorCode: 'WHOLESALE_GEO_SYNC_FAILED', error: String(e.message || e),
        }));
        throw e;
      }
    });

  exports.wholesaleSellerGeoSync = functions.firestore
    .document('wholesale_sellers/{sellerId}')
    .onWrite(async (change, context) => {
      if (!change.after.exists) return;
      const before = sellerGeo(change.before.exists ? change.before.data() : null);
      const after = sellerGeo(change.after.data());
      if (before.regionId === after.regionId && before.districtId === after.districtId) return;
      const n = await syncSellerProducts(db, admin, context.params.sellerId, change.after.data());
      console.log(JSON.stringify({ action: 'wholesaleSellerGeoSync', sellerTail: String(context.params.sellerId).slice(-4), updated: n }));
    });

  exports.wholesaleLegacyCleanup = functions.pubsub
    .schedule('every 60 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      await runLegacyCleanup(db, admin);
      return null;
    });
}

module.exports = {
  attachWholesaleGeo, syncProductGeo, syncSellerProducts, runLegacyCleanup, restoreLegacyArchived,
  marketOf, START_AFTER, LEGACY_MARKETS, LEGACY_NOTE,
};
