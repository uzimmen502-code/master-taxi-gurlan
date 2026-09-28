'use strict';

const { encode: geohashEncode } = require('./geo_hash');

/**
 * «Кўчмас мулк Кластери» — сервер томони (1-босқич).
 *
 * Нега callable: эълон матнини клиент ёзиши мумкин эди, лекин учта нарса
 * серверда ҳал бўлиши шарт —
 *   1) бепул ОДДИЙ лимити (эгасига 2 тагача объект) — клиент саноғига
 *      ишониб бўлмайди;
 *   2) ҳудуд тамғаси (`ownerGeoStamp`) — акс ҳолда фойдаланувчи ўз
 *      объектини истаган туманга «кўчириб» қўя оларди;
 *   3) муддат (`expiresAt`) ва статус — тўлов босқичи қўшилганда айнан
 *      шу ерда ҳисобланади.
 *
 * Шунинг учун `firestore.rules`'да `realty_listings` клиент томонидан
 * `create` қилинмайди (`ev_charging_stations` билан бир хил қоида).
 */
function attachRealty(exports, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
    assertAdmin, notifyUserInApp,
  } = deps;

  /** Бепул ОДДИЙ объект лимити — концепциянинг 2-бўлими. */
  const FREE_PLAIN_LIMIT = 2;

  /** Бепул ОДДИЙ эълон қанча кун кўринади. */
  const PLAIN_EXPIRY_DAYS = 30;

  /**
   * Янги эълон яратишда фақат бепул ОДДИЙ бўлади. РЕКЛАМА ва СРОЧНО —
   * мавжуд объектга `purchaseRealtyTier` орқали сотиб олинади, чунки
   * концепцияда бир уй учта эълон эмас, битта ёзув (6-бўлим).
   */
  const PURCHASABLE_TIERS = ['plain'];

  /** Пуллик даражалар ва уларнинг муддат вариантлари (концепция, 2-бўлим). */
  const PAID_DURATIONS = {
    promo: [7, 15, 30],
    urgent: [3, 7, 15],
  };

  /**
   * `settings/app.realtyPricing` топилмаса ишлатиладиган бошланғич
   * нархлар. СРОЧНО РЕКЛАМАдан қиммат — концепциянинг талаби.
   * Ҳақиқий нархларни эга админ панелдан белгилайди.
   */
  const REALTY_PRICING_DEFAULT = {
    promo: { 7: 20000, 15: 35000, 30: 60000 },
    urgent: { 3: 25000, 7: 45000, 15: 80000 },
  };

  const ts = () => admin.firestore.FieldValue.serverTimestamp();

  function fail(code, reason, details) {
    return new functions.https.HttpsError(code, reason, {
      reason, ...(details || {}),
    });
  }

  function requireUid(context) {
    if (!context || !context.auth) {
      throw fail('unauthenticated', 'auth_required');
    }
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 9) {
      throw fail('permission-denied', 'phone_required');
    }
    return uid;
  }

  /** `settings/app` дан битта майдон — ҳужжат бўлмаса `fallback`. */
  async function appSetting(field, fallback) {
    try {
      const snap = await db.collection('settings').doc('app').get();
      const v = (snap.data() || {})[field];
      return v === undefined || v === null ? fallback : v;
    } catch (e) {
      console.error('realty.appSetting', field, e.message || e);
      return fallback;
    }
  }

  /** Қидирув учун оддий токенлар — `ad_search_text.dart` билан бир хил ғоя. */
  function buildSearchTokens(title, text) {
    const words = `${title} ${text}`
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, ' ')
      .split(' ')
      .filter((w) => w.length >= 3);
    return [...new Set(words)].slice(0, 40);
  }

  function optionalInt(v, min, max) {
    if (v === undefined || v === null || v === '') return null;
    const n = Math.round(Number(v));
    if (!Number.isFinite(n) || n < min || n > max) return null;
    return n;
  }

  function optionalNum(v, min, max) {
    if (v === undefined || v === null || v === '') return null;
    const n = Number(v);
    if (!Number.isFinite(n) || n < min || n > max) return null;
    return n;
  }

  /** Эганинг ҳозир кўриниб турган ОДДИЙ объектлари сони. */
  async function countActivePlain(uid) {
    const snap = await db.collection('realty_listings')
      .where('ownerId', '==', uid)
      .where('tier', '==', 'plain')
      .limit(50)
      .get();
    const now = Date.now();
    let count = 0;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      if (d.status === 'blocked') continue;
      const exp = d.expiresAt && d.expiresAt.toMillis
        ? d.expiresAt.toMillis() : 0;
      if (exp && exp < now) continue;
      count += 1;
    }
    return count;
  }

  /** Mijoz: янги объект (координата МАЖБУРИЙ). */
  exports.submitRealtyListing = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const d = data || {};

    const tier = String(d.tier || 'plain');
    if (!PURCHASABLE_TIERS.includes(tier)) {
      // РЕКЛАМА/СРОЧНО — 2-босқич (ҳамёндан тўлов билан).
      throw fail('failed-precondition', 'tier_not_available');
    }

    const deal = d.deal === 'rent' ? 'rent' : 'sale';

    const title = String(d.title || '').trim().slice(0, 120);
    if (title.length < 3) throw fail('invalid-argument', 'title_required');
    const text = String(d.text || '').trim().slice(0, 2000);
    if (text.length < 3) throw fail('invalid-argument', 'text_required');

    // ─── Харитага боғлаш — мажбурий (концепция, 7-бўлим) ───
    const lat = Number(d.lat);
    const lng = Number(d.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)
        || lat < -90 || lat > 90 || lng < -180 || lng > 180
        || (lat === 0 && lng === 0)) {
      throw fail('invalid-argument', 'location_required');
    }

    const freeUsed = await countActivePlain(uid);
    if (freeUsed >= FREE_PLAIN_LIMIT) {
      throw fail('resource-exhausted', 'free_limit_reached', {
        limit: FREE_PLAIN_LIMIT,
      });
    }

    const contactMode = d.contactMode === 'ava_agent' ? 'ava_agent' : 'owner';
    const agentPhone = contactMode === 'ava_agent'
      ? String(await appSetting('realtyAgentPhone', '')).replace(/\D/g, '')
      : '';

    const imageUrls = Array.isArray(d.imageUrls)
      ? d.imageUrls.filter((u) => typeof u === 'string' && u.startsWith('http'))
        .slice(0, 5)
      : [];

    let ownerName = String(d.ownerName || '').trim().slice(0, 80);
    if (!ownerName) {
      try {
        const u = await db.collection('users').doc(uid).get();
        ownerName = String((u.data() || {}).name || '').trim().slice(0, 80);
      } catch (e) {
        console.error('realty.ownerName', e.message || e);
      }
    }

    const autoApprove = (await appSetting('realtyAutoApprove', true)) !== false;
    const geo = await ownerGeoStamp(uid);
    const expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + PLAIN_EXPIRY_DAYS * 24 * 60 * 60 * 1000),
    );

    const rooms = optionalInt(d.rooms, 1, 99);
    const floor = optionalInt(d.floor, -5, 200);
    const totalFloors = optionalInt(d.totalFloors, 1, 200);
    const areaM2 = optionalNum(d.areaM2, 1, 100000);

    const ref = await db.collection('realty_listings').add({
      ownerId: uid,
      ownerPhone: uid,
      ownerName: ownerName || 'Фойдаланувчи',
      deal,
      tier,
      title,
      text,
      priceText: String(d.priceText || '').trim().slice(0, 80),
      addressText: String(d.addressText || '').trim().slice(0, 300),
      ...(rooms === null ? {} : { rooms }),
      ...(floor === null ? {} : { floor }),
      ...(totalFloors === null ? {} : { totalFloors }),
      ...(areaM2 === null ? {} : { areaM2 }),
      imageUrls,
      lat,
      lng,
      geohash4: geohashEncode(lat, lng, 4),
      contactMode,
      ...(agentPhone ? { agentPhone } : {}),
      avagramClipId: '',
      adClipId: '',
      status: autoApprove ? 'active' : 'pending',
      ...geo,
      views: 0,
      searchTokens: buildSearchTokens(title, text),
      tierUntil: null,
      expiresAt,
      createdAt: ts(),
      updatedAt: ts(),
      ...(autoApprove
        ? { moderatedAt: ts(), moderatedBy: 'auto', autoApproved: true }
        : {}),
    });

    return {
      ok: true,
      listingId: ref.id,
      status: autoApprove ? 'active' : 'pending',
      freeLeft: Math.max(0, FREE_PLAIN_LIMIT - freeUsed - 1),
    };
  });

  /**
   * Mijoz: ўз объектини таҳрирлаш.
   *
   * Кўчмас мулкда нарх тушиши — одатий ҳол, шунинг учун таҳрир мажбурий
   * восита: усиз эга эълонни ўчириб, қайта яратишга мажбур бўлади ва
   * бепул лимитдаги ўрнини йўқотади.
   *
   * Фақат whitelist майдонлар ўзгаради. `tier`, `ownerId`, `expiresAt`
   * ва статус БУ ЕРДАН ўзгармайди — улар тўлов ва модерация ишлари.
   * Координата ўзгарса `geohash4` қайта ҳисобланади.
   */
  exports.updateRealtyListing = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const d = data || {};
    const listingId = String(d.listingId || '').trim();
    if (!listingId) throw fail('invalid-argument', 'listing_required');

    const ref = db.collection('realty_listings').doc(listingId);
    const snap = await ref.get();
    if (!snap.exists) throw fail('not-found', 'listing_not_found');
    const current = snap.data() || {};
    if (String(current.ownerId || '') !== uid) {
      throw fail('permission-denied', 'not_owner');
    }

    const title = String(d.title || '').trim().slice(0, 120);
    if (title.length < 3) throw fail('invalid-argument', 'title_required');
    const text = String(d.text || '').trim().slice(0, 2000);
    if (text.length < 3) throw fail('invalid-argument', 'text_required');

    const lat = Number(d.lat);
    const lng = Number(d.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)
        || lat < -90 || lat > 90 || lng < -180 || lng > 180
        || (lat === 0 && lng === 0)) {
      throw fail('invalid-argument', 'location_required');
    }

    const contactMode = d.contactMode === 'ava_agent' ? 'ava_agent' : 'owner';
    const agentPhone = contactMode === 'ava_agent'
      ? String(await appSetting('realtyAgentPhone', '')).replace(/\D/g, '')
      : '';

    const imageUrls = Array.isArray(d.imageUrls)
      ? d.imageUrls.filter((u) => typeof u === 'string' && u.startsWith('http'))
        .slice(0, 5)
      : [];

    const rooms = optionalInt(d.rooms, 1, 99);
    const floor = optionalInt(d.floor, -5, 200);
    const totalFloors = optionalInt(d.totalFloors, 1, 200);
    const areaM2 = optionalNum(d.areaM2, 1, 100000);

    // Модерация ёқиқ бўлса, таҳрирланган эълон қайта текширувга тушади —
    // акс ҳолда тасдиқдан ўтган матнни кейин алмаштириб юбориш мумкин эди.
    const autoApprove = (await appSetting('realtyAutoApprove', true)) !== false;
    const nextStatus = current.status === 'blocked'
      ? 'blocked'
      : (autoApprove ? 'active' : 'pending');

    await ref.update({
      deal: d.deal === 'rent' ? 'rent' : 'sale',
      title,
      text,
      priceText: String(d.priceText || '').trim().slice(0, 80),
      addressText: String(d.addressText || '').trim().slice(0, 300),
      rooms: rooms === null
        ? admin.firestore.FieldValue.delete() : rooms,
      floor: floor === null
        ? admin.firestore.FieldValue.delete() : floor,
      totalFloors: totalFloors === null
        ? admin.firestore.FieldValue.delete() : totalFloors,
      areaM2: areaM2 === null
        ? admin.firestore.FieldValue.delete() : areaM2,
      imageUrls,
      lat,
      lng,
      geohash4: geohashEncode(lat, lng, 4),
      contactMode,
      agentPhone: agentPhone || admin.firestore.FieldValue.delete(),
      searchTokens: buildSearchTokens(title, text),
      status: nextStatus,
      editedAt: ts(),
      updatedAt: ts(),
    });

    return { ok: true, listingId, status: nextStatus };
  });

  /** Mijoz: ўз объектини ўчириш («сотилди» ёки хато киритилган). */
  exports.deleteRealtyListing = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const listingId = String((data || {}).listingId || '').trim();
    if (!listingId) throw fail('invalid-argument', 'listing_required');

    const ref = db.collection('realty_listings').doc(listingId);
    const snap = await ref.get();
    if (!snap.exists) throw fail('not-found', 'listing_not_found');
    if (String((snap.data() || {}).ownerId || '') !== uid) {
      throw fail('permission-denied', 'not_owner');
    }
    await ref.delete();
    return { ok: true };
  });

  // ─── 2-босқич: пуллик РЕКЛАМА ва СРОЧНО ───────────────────────

  /** Нарх: `settings/app.realtyPricing.{tier}.{days}`, бўлмаса default. */
  async function realtyPriceFor(tier, days) {
    const fallback = (REALTY_PRICING_DEFAULT[tier] || {})[days] || 0;
    try {
      const snap = await db.collection('settings').doc('app').get();
      const map = (snap.data() || {}).realtyPricing;
      const tierMap = map && typeof map === 'object' ? map[tier] : null;
      if (tierMap && typeof tierMap === 'object'
          && tierMap[String(days)] != null) {
        const v = Number(tierMap[String(days)]);
        if (Number.isFinite(v) && v >= 0) return Math.round(v);
      }
    } catch (e) {
      console.error('realtyPriceFor', e.message || e);
    }
    return fallback;
  }

  /**
   * Мавжуд объектга РЕКЛАМА ёки СРОЧНО сотиб олиш (ва узайтириш).
   *
   * Тўлов AVA ҳамёнидан (`users/{uid}.bonusBalance`), `publishTvAd`
   * билан бир хил нақш: идемпотентлик калити, баланс текшируви, дебит
   * ва ёзув янгиланиши — ҳаммаси битта транзакцияда.
   *
   * ⚠️ МУДДАТ ҲИСОБИ — ЭГА ЭЪТИБОРИГА. Концепцияда «муддат тугаса
   * объектнинг ўзи ўчирилади» дейилган. Уни сўзма-сўз олсак, 28 куни
   * қолган ОДДИЙ эълонга 3 кунлик СРОЧНО олган одам 25 кунини
   * йўқотарди — бу шикоят келтирадиган нуқсон. Шунинг учун:
   *   • `tierUntil` — пуллик даража қанча туриши;
   *   • `expiresAt` — объектнинг ўзи қачон ўчиши, ҳозиргисидан
   *     ҚИСҚАРМАЙДИ (`max`).
   * Даража муддати тугаса объект ўчмайди, ОДДИЙга қайтади
   * (`realtyExpirySweep`), объектнинг ўзи эса `expiresAt` да ўчади.
   */
  exports.purchaseRealtyTier = functions.https.onCall(
    async (data, context) => {
      const uid = requireUid(context);
      const d = data || {};

      const idempotencyKey = String(d.idempotencyKey || '').trim();
      if (!idempotencyKey) throw fail('invalid-argument', 'idem_required');
      const idemRef = db.collection('wallet_idempotency')
        .doc('realty_tier_' + idempotencyKey);
      const existingIdem = await idemRef.get();
      if (existingIdem.exists) {
        return (existingIdem.data() || {}).result || { ok: true, duplicate: true };
      }

      const listingId = String(d.listingId || '').trim();
      if (!listingId) throw fail('invalid-argument', 'listing_required');

      const tier = String(d.tier || '');
      if (!Object.keys(PAID_DURATIONS).includes(tier)) {
        throw fail('invalid-argument', 'bad_tier');
      }
      const days = parseInt(String(d.durationDays || 0), 10);
      if (!PAID_DURATIONS[tier].includes(days)) {
        throw fail('invalid-argument', 'bad_duration');
      }

      const price = await realtyPriceFor(tier, days);
      const listingRef = db.collection('realty_listings').doc(listingId);
      const userRef = db.collection('users').doc(uid);
      const durationMs = days * 24 * 60 * 60 * 1000;

      try {
        return await db.runTransaction(async (t) => {
          const idemSnap = await t.get(idemRef);
          if (idemSnap.exists) {
            return (idemSnap.data() || {}).result || { ok: true, duplicate: true };
          }

          const snap = await t.get(listingRef);
          if (!snap.exists) throw fail('not-found', 'listing_not_found');
          const cur = snap.data() || {};
          if (String(cur.ownerId || '') !== uid) {
            throw fail('permission-denied', 'not_owner');
          }
          if (cur.status === 'blocked') {
            throw fail('failed-precondition', 'listing_blocked');
          }

          if (price > 0) {
            const userSnap = await t.get(userRef);
            if (!userSnap.exists) throw fail('not-found', 'user_not_found');
            const balance = (userSnap.data() || {}).bonusBalance || 0;
            if (balance < price) {
              throw fail('failed-precondition', 'insufficient_balance', {
                price, balance,
              });
            }
            t.update(userRef, {
              bonusBalance: admin.firestore.FieldValue.increment(-price),
              balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            t.set(userRef.collection('wallet_ledger').doc(), {
              type: 'realty_tier_purchase',
              amount: price,
              debitCredit: 'debit',
              note: `Кўчмас мулк (${tier}) — ${days} кун`,
              refType: 'realty_listing',
              refId: listingId,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          // Худди шу даража ҳали амал қилаётган бўлса — устига қўшилади,
          // акс ҳолда ҳозирдан бошланади (`renewTvAd` билан бир хил).
          const curUntil = cur.tierUntil && cur.tierUntil.toMillis
            ? cur.tierUntil.toMillis() : 0;
          const base = (cur.tier === tier && curUntil > Date.now())
            ? curUntil : Date.now();
          const tierUntilMs = base + durationMs;

          const curExpires = cur.expiresAt && cur.expiresAt.toMillis
            ? cur.expiresAt.toMillis() : 0;
          const expiresMs = Math.max(curExpires, tierUntilMs);

          t.update(listingRef, {
            tier,
            tierUntil: admin.firestore.Timestamp.fromMillis(tierUntilMs),
            expiresAt: admin.firestore.Timestamp.fromMillis(expiresMs),
            expiryWarnedAt: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          const res = {
            ok: true,
            listingId,
            tier,
            durationDays: days,
            price,
            tierUntil: tierUntilMs,
          };
          t.set(idemRef, {
            type: 'purchaseRealtyTier',
            result: res,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return res;
        });
      } catch (e) {
        if (e instanceof functions.https.HttpsError) throw e;
        console.error('purchaseRealtyTier', e);
        throw fail('internal', 'purchase_failed');
      }
    });

  /** Нархлар жадвали — илова тариф варағида кўрсатиш учун. */
  exports.getRealtyPricing = functions.https.onCall(async () => {
    const out = {};
    for (const tier of Object.keys(PAID_DURATIONS)) {
      out[tier] = {};
      for (const days of PAID_DURATIONS[tier]) {
        out[tier][String(days)] = await realtyPriceFor(tier, days);
      }
    }
    return { pricing: out };
  });

  // ─── Админ панел ───────────────────────────────────────────────
  // `admin_jobs_service.dart` билан бир хил нақш: текширув сервер
  // томонда `assertAdmin()` да, Firestore rules'га таянилмайди.

  /** Admin: эълонни блоклаш / тиклаш / текширувдан ўтказиш. */
  exports.adminSetRealtyStatus = functions.https.onCall(
    async (data, context) => {
      const d = data || {};
      const adminPhone = await assertAdmin(d.adminPhone, context);
      const listingId = String(d.listingId || '').trim();
      const status = String(d.status || '').trim();
      if (!listingId) throw fail('invalid-argument', 'listing_required');
      if (!['active', 'pending', 'blocked'].includes(status)) {
        throw fail('invalid-argument', 'bad_status');
      }
      await db.collection('realty_listings').doc(listingId).update({
        status,
        adminNote: String(d.adminNote || '').trim().slice(0, 300),
        moderatedAt: ts(),
        moderatedBy: String(adminPhone || '').slice(0, 20),
        updatedAt: ts(),
      });
      return { ok: true, status };
    });

  /** Admin: эълонни бутунлай ўчириш. */
  exports.adminDeleteRealtyListing = functions.https.onCall(
    async (data, context) => {
      const d = data || {};
      await assertAdmin(d.adminPhone, context);
      const listingId = String(d.listingId || '').trim();
      if (!listingId) throw fail('invalid-argument', 'listing_required');
      await db.collection('realty_listings').doc(listingId).delete();
      return { ok: true };
    });

  /**
   * Муддати тугаган объектларни ўчириш (концепция, 9-бўлим: СРОЧНО ёки
   * РЕКЛАМА муддати тугаса объектнинг ЎЗИ ўчирилади — лентадан ҳам,
   * харитадан ҳам). Бепул ОДДИЙ ҳам шу қоида бўйича яшайди.
   *
   * Кунига бир марта; клиент лентада ҳам `expiresAt` ни текширади,
   * шунинг учун бу оралиқ фойдаланувчига кўринмайди.
   */
  exports.realtyExpirySweep = functions
    .runWith({ timeoutSeconds: 540 })
    .pubsub.schedule('20 0 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const now = admin.firestore.Timestamp.now();

      // 1) Муддати тугаган объектлар — ўчирилади.
      let deleted = 0;
      // Партия-партия: битта юришда 400 тагача (Firestore batch чегараси).
      for (let round = 0; round < 10; round += 1) {
        const snap = await db.collection('realty_listings')
          .where('expiresAt', '<=', now)
          .limit(400)
          .get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted += snap.size;
        if (snap.size < 400) break;
      }

      // 2) Пуллик даража муддати тугаган, лекин объектнинг ўзи ҳали
      //    яшайдиганлар — ОДДИЙга қайтади (қаранг: `purchaseRealtyTier`
      //    изоҳидаги муддат ҳисоби).
      let downgraded = 0;
      for (let round = 0; round < 10; round += 1) {
        const snap = await db.collection('realty_listings')
          .where('tierUntil', '<=', now)
          .limit(400)
          .get();
        if (snap.empty) break;
        const batch = db.batch();
        let writes = 0;
        snap.docs.forEach((doc) => {
          if ((doc.data() || {}).tier === 'plain') return;
          batch.update(doc.ref, {
            tier: 'plain',
            tierUntil: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writes += 1;
        });
        if (writes > 0) await batch.commit();
        downgraded += writes;
        if (snap.size < 400) break;
      }

      console.log(
        `realtyExpirySweep deleted=${deleted} downgraded=${downgraded}`,
      );
      return null;
    });

  /**
   * Муддат тугашидан 1 кун олдин эгасига огоҳлантириш + «узайтириш»
   * таклифи (концепциянинг 9-бўлимидаги тавсия).
   *
   * Иккита фойдаси бор: объект тасодифан ўчиб кетмайди ва AVA такрорий
   * тўлов олади. `expiryWarnedAt` — бир хил эълон учун такрор хабар
   * юборилмаслиги учун.
   */
  exports.realtyExpiryWarning = functions
    .runWith({ timeoutSeconds: 540 })
    .pubsub.schedule('0 10 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const now = Date.now();
      const horizon = admin.firestore.Timestamp.fromMillis(
        now + 24 * 60 * 60 * 1000,
      );
      const snap = await db.collection('realty_listings')
        .where('expiresAt', '<=', horizon)
        .limit(300)
        .get();

      let sent = 0;
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        if (d.expiryWarnedAt) continue;
        const exp = d.expiresAt && d.expiresAt.toMillis
          ? d.expiresAt.toMillis() : 0;
        if (!exp || exp <= now) continue; // аллақачон тугаган — sweep иши
        try {
          await notifyUserInApp({
            userId: String(d.ownerId || ''),
            title: '🏠 Эълон муддати тугаяпти',
            body: `«${String(d.title || '').slice(0, 60)}» эртага лентадан `
              + 'ўчади. Муддатни узайтиришингиз мумкин.',
            category: 'info',
            source: 'realty',
            dataType: 'realty_expiry',
            screen: 'realty_my',
            extraData: { listingId: doc.id },
          });
          await doc.ref.update({
            expiryWarnedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          sent += 1;
        } catch (e) {
          console.error('realtyExpiryWarning', doc.id, e.message || e);
        }
      }
      console.log('realtyExpiryWarning sent', sent);
      return null;
    });
}

module.exports = { attachRealty };
