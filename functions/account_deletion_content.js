/**
 * ҲИСОБНИ ЎЧИРИШ — якуний ўчириш қадамлари: очиқ контент, провайдер/чат ҳужжатлари, шахсий майдонларни тозалаш
 * (docs/hisobni_ochirish_2026-10-24_uz.md §5). Ҳар қадам идемпотент: қайта юритса зарарсиз.
 *
 * Майдон номлари — коддан/rules'дан тасдиқланган (A1 + инвентаризация, 2026-10-24):
 *  ads.ownerId (market) / ads.authorPhone (ish), tv_clips/tv_shop_items.ownerPhone, businesses/yuk_listings/
 *  yuk_local_drivers.ownerId, realty_listings.ownerKey (= users.realtyOwnerKey), wholesale_products.sellerId,
 *  ev_charging_stations.createdBy, schedules.driverId; ҳужжат ID = телефон: tv_shops, tv_public_profiles,
 *  wholesale_sellers, drivers, queue, driver_requests, couriers, intercity_drivers, provider_presence,
 *  support_chats, relatives.
 * Тозаланадиган шахсий майдонлар: orders.userName/address/note; trips.userName/fromAddr/toAddr (йўловчи) ва
 * trips.acceptedDriver{Name,Phone,Car,Plate} (ҳайдовчи); restaurant_bookings.userName;
 * wallet_topup/withdraw_requests.telegram*; wallet_withdraw_requests.payoutCard*.
 * Молиявий калитлар (userPhone/uid) ЎЗГАРМАЙДИ — 3 йил сақланади (web/delete-account.html).
 *
 * ЎЧИРИЛМАЙДИ (UNKNOWN/кейинга): comments/likes/ratings (муаллиф бўйича индекс йўқ), relative_phone_watchers,
 * notifications, admin_news (шахсий хабарлар), давралар ва шажара (эга: кейинга), topup_receipts (молиявий далил),
 * logistics/* (escrow далили), restaurants/* (эга блокланади).
 */
'use strict';

const { MARK } = require('./account_deletion_hide');

const PAGE = 400;
const uniq = (arr) => [...new Set(arr.filter((x) => typeof x === 'string' && x !== ''))];

function createContentSteps({ db, admin, deleteStoragePrefix }) {
  const FV = admin.firestore.FieldValue;
  const storagePrefix = deleteStoragePrefix || (async () => {});

  /** `field == value` бўйича саҳифалаб (ҳужжат ID тартибида, startAfter курсор) `fn(docSnap)` чақиради. */
  async function eachDoc(col, field, value, fn) {
    let last = null;
    // eslint-disable-next-line no-constant-condition
    while (true) {
      let q = db.collection(col).where(field, '==', value).limit(PAGE);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) return;
      for (const d of snap.docs) await fn(d);
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < PAGE) return;
    }
  }

  async function deleteWhere(col, field, values) {
    let n = 0;
    for (const v of uniq(values)) {
      await eachDoc(col, field, v, async (d) => { await db.recursiveDelete(d.ref); n += 1; });
    }
    return n;
  }

  /** Ота ҳужжат йўқ бўлса ҳам ости-коллекциялар қолиши мумкин (виртуал ота: relatives/{uid}) — доим recursiveDelete. */
  async function deleteDocIds(col, ids) {
    let n = 0;
    for (const id of uniq(ids)) {
      const ref = db.collection(col).doc(id);
      const s = await ref.get();
      await db.recursiveDelete(ref);
      if (s.exists) n += 1;
    }
    return n;
  }

  /** `fields` ни `update`+delete билан олиб ташлайди (ҳужжат ўзи қолади). */
  async function stripFields(col, field, values, fields) {
    let n = 0;
    const patch = {};
    for (const f of fields) patch[f] = FV.delete();
    for (const v of uniq(values)) {
      await eachDoc(col, field, v, async (d) => {
        const data = d.data() || {};
        if (!fields.some((f) => f in data)) return;
        await d.ref.update(patch);
        n += 1;
      });
    }
    return n;
  }

  const STEPS = [
    {
      name: 'delete_public_content',
      async run({ identity }) {
        const c = {};
        c.ads = await deleteWhere('ads', 'ownerId', identity.ids) + await deleteWhere('ads', 'authorPhone', identity.forms);
        c.tvClips = await deleteWhere('tv_clips', 'ownerPhone', identity.forms);
        c.tvShopItems = await deleteWhere('tv_shop_items', 'ownerPhone', identity.forms);
        c.businesses = await deleteWhere('businesses', 'ownerId', identity.ids);
        c.yuk = await deleteWhere('yuk_listings', 'ownerId', identity.ids)
          + await deleteWhere('yuk_local_drivers', 'ownerId', identity.ids);
        c.realty = await deleteWhere('realty_listings', 'ownerKey', identity.realtyOwnerKeys);
        c.wholesaleProducts = await deleteWhere('wholesale_products', 'sellerId', identity.ids);
        const phoneIds = [identity.d12, identity.d9];
        c.byId = await deleteDocIds('tv_shops', phoneIds)
          + await deleteDocIds('tv_public_profiles', phoneIds)
          + await deleteDocIds('wholesale_sellers', phoneIds);
        for (const p of phoneIds) {
          for (const root of ['ads', 'wholesale_products', 'profiles', 'relatives', 'tv_clips', 'tv_profile', 'tv_shop']) {
            await storagePrefix(`${root}/${p}/`);
          }
        }
        return c;
      },
    },
    {
      name: 'release_ev_stations',
      /** Станция жамоат инфратузилмаси: қолади, фақат эга боғланиши олинади; яширилган бўлса қайта фаоллаштирилади. */
      async run({ identity, uid }) {
        let n = 0;
        for (const v of uniq(identity.ids)) {
          await eachDoc('ev_charging_stations', 'createdBy', v, async (d) => {
            const data = d.data() || {};
            const patch = { createdBy: '' };
            if (data[MARK] === true) {
              patch.isActive = true;
              patch[MARK] = FV.delete();
              await db.collection('account_deletions').doc(uid).collection('hidden').doc(`ev_stations__${d.id}`)
                .set({ restored: true, restoredAt: FV.serverTimestamp() }, { merge: true });
            }
            await d.ref.update(patch);
            n += 1;
          });
        }
        return { stations: n };
      },
    },
    {
      name: 'delete_provider_and_support',
      async run({ identity }) {
        const ids = [identity.d12, identity.d9];
        const c = {};
        for (const col of ['drivers', 'queue', 'driver_requests', 'couriers', 'intercity_drivers', 'provider_presence',
          'support_chats', 'relatives']) {
          c[col] = await deleteDocIds(col, ids);
        }
        c.schedules = await deleteWhere('schedules', 'driverId', identity.ids);
        return c;
      },
    },
    {
      name: 'anonymize_records',
      async run({ identity }) {
        const c = {};
        c.orders = await stripFields('orders', 'userPhone', identity.forms, ['userName', 'address', 'note']);
        c.tripsPassenger = await stripFields('trips', 'userPhone', identity.forms, ['userName', 'fromAddr', 'toAddr']);
        const driverFields = ['acceptedDriverName', 'acceptedDriverPhone', 'acceptedDriverCar', 'acceptedDriverPlate'];
        c.tripsDriver = await stripFields('trips', 'driverId', identity.ids, driverFields)
          + await stripFields('trips', 'acceptedDriverId', identity.ids, driverFields);
        c.bookings = await stripFields('restaurant_bookings', 'userPhone', identity.forms, ['userName']);
        const tg = ['telegramUserId', 'telegramChatId', 'telegramUsername'];
        c.topups = await stripFields('wallet_topup_requests', 'uid', identity.ids, tg);
        c.withdraws = await stripFields('wallet_withdraw_requests', 'uid', identity.ids,
          [...tg, 'payoutCardNumber', 'payoutCardHolder']);
        return c;
      },
    },
  ];

  return { STEPS };
}

module.exports = { createContentSteps };
