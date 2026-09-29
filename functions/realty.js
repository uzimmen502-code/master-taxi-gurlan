'use strict';

const crypto = require('crypto');

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

  /**
   * ОЧИҚ ҳужжатдаги тахминий нуқта.
   *
   * Аввал бу geohash4 катакчасининг маркази эди (≈20 км). Лекин
   * битта тумандаги ҳамма объект БИТТА нуқтага тушиб қолар, харитада
   * бир дона пин кўринарди. Энди ҳар бир объект ўз нуқтасини олади:
   * аниқ координата [JITTER_METERS] радиусида тасодифий силкитилади.
   *
   * НЕГА ХАВФСИЗ: силкитиш БИР МАРТА, объект яратилганда ҳисобланади
   * ва ўзгармайди. Агар у ҳар ўқишда қайта ҳисобланса, бир нечта
   * қийматнинг ўртачаси аниқ нуқтани очиб қўйган бўларди.
   * Координата 3 хонагача яхлитланади (≈110 м тўр).
   */
  const JITTER_METERS = 1200;

  function jitteredPoint(lat, lng) {
    const angle = Math.random() * 2 * Math.PI;
    // `sqrt` — доира бўйлаб текис тақсимот (акс ҳолда марказга зичланади).
    const dist = Math.sqrt(Math.random()) * JITTER_METERS;
    const dLat = (dist * Math.cos(angle)) / 111320;
    const dLng = (dist * Math.sin(angle))
      / (111320 * Math.cos((lat * Math.PI) / 180) || 1);
    const round3 = (v) => Number(v.toFixed(3));
    return { lat: round3(lat + dLat), lng: round3(lng + dLng) };
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

  /**
   * Эганинг очиқ ҳужжатдаги калити.
   *
   * НЕГА телефон эмас: очиқ ҳужжатда `ownerId` (телефон рақами) турса,
   * харидор пакет сотиб олмасдан ҳам базадан эганинг рақамини ўқиб
   * олган бўларди — ахборот пакетининг маъноси қолмасди. Шунинг учун
   * очиқ ҳужжатда фақат тасодифий калит, телефон эса ёпиқ
   * `private/detail` ҳужжатида.
   *
   * Калит бир марта яратилади ва `users/{uid}.realtyOwnerKey` да
   * сақланади — эга ўз объектларини шу калит бўйича топади.
   */
  async function ensureOwnerKey(uid) {
    const userRef = db.collection('users').doc(uid);
    const snap = await userRef.get();
    const existing = String((snap.data() || {}).realtyOwnerKey || '').trim();
    if (existing) return existing;
    const key = crypto.randomBytes(12).toString('hex');
    await userRef.set({ realtyOwnerKey: key }, { merge: true });
    return key;
  }

  /**
   * Эгалик текшируви — `ownerKey` бўйича, телефон бўйича эмас.
   *
   * Шу туфайли ЖАМОА АККАУНТИ ўз-ўзидан ишлайди (концепция, 5-бўлим):
   * компаниянинг бир неча ходими битта `realtyOwnerKey` ни улашади,
   * шунинг учун ҳар бири компания объектларини таҳрирлай олади.
   */
  async function assertOwner(listingId, uid) {
    const [listing, myKey] = await Promise.all([
      db.collection('realty_listings').doc(listingId).get(),
      ensureOwnerKey(uid),
    ]);
    const key = String((listing.data() || {}).ownerKey || '');
    if (!listing.exists || !key || key !== myKey) {
      throw fail('permission-denied', 'not_owner');
    }
    return listing.data() || {};
  }

  /** Эганинг ҳозир кўриниб турган ОДДИЙ объектлари сони. */
  async function countActivePlain(ownerKey) {
    const snap = await db.collection('realty_listings')
      .where('ownerKey', '==', ownerKey)
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

    // ─── Матнли манзил — мажбурий (эга қарори, 2026-09-29) ───
    // Харитадаги нуқта очиқ ҳужжатда ТАХМИНИЙ (≈1.2 км силкитилган),
    // шунинг учун у матнли манзилнинг ўрнини боса олмайди: харидор
    // пакетни очгач кўча ва уй рақамини кўриши керак.
    if (String(d.addressText || '').trim().length < 5) {
      throw fail('invalid-argument', 'address_required');
    }

    const ownerKey = await ensureOwnerKey(uid);
    const pro = await activeProPlan(uid);
    const used = await countActivePlain(ownerKey);
    // Профессионал пакет бор бўлса лимит ўша пакетники, бепул 2 та эмас
    // (концепция, 5-бўлим: риэлтор кўп объект жойлайди).
    const limit = pro ? pro.objects : FREE_PLAIN_LIMIT;
    if (used >= limit) {
      throw fail('resource-exhausted', 'free_limit_reached', {
        limit, pro: pro !== null,
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

    // Аниқ нуқта ўрнига силкитилган нуқта — бу ОЧИҚ ҳужжатга тушади.
    const cell = jitteredPoint(lat, lng);

    const ref = db.collection('realty_listings').doc();
    const batch = db.batch();

    // ─── ОЧИҚ ҳужжат: тавсиф, тахминий ҳудуд ───
    batch.set(ref, {
      ownerKey,
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
      areaLat: cell.lat,
      areaLng: cell.lng,
      geohash4: geohashEncode(lat, lng, 4),
      contactMode,
      hasAgent: agentPhone !== '',
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

    // ─── ЁПИҚ ҳужжат: айнан шу иккови пуллик ахборот ───
    batch.set(ref.collection('private').doc('detail'), {
      ownerId: uid,
      lat,
      lng,
      ownerPhone: uid,
      ...(agentPhone ? { agentPhone } : {}),
      updatedAt: ts(),
    });

    await batch.commit();

    return {
      ok: true,
      listingId: ref.id,
      status: autoApprove ? 'active' : 'pending',
      freeLeft: Math.max(0, limit - used - 1),
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
    await assertOwner(listingId, uid);

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

    // Таҳрирда ҳам манзил мажбурий — акс ҳолда эга эълонни жойлагач
    // манзилни ўчириб, текин «тизер» қилиб қўя оларди.
    if (String(d.addressText || '').trim().length < 5) {
      throw fail('invalid-argument', 'address_required');
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

    // Нуқта ўзгармаган бўлса ЭСКИ силкитиш сақланади. Ҳар таҳрирда
    // қайта силкитилса, бир неча қийматнинг ўртачаси аниқ жойни очиб
    // қўйган бўларди.
    const prevDetail = await ref.collection('private').doc('detail').get();
    const prev = prevDetail.data() || {};
    const samePoint = Number(prev.lat) === lat && Number(prev.lng) === lng;
    const cell = (samePoint
        && Number.isFinite(Number(current.areaLat))
        && Number.isFinite(Number(current.areaLng)))
      ? { lat: Number(current.areaLat), lng: Number(current.areaLng) }
      : jitteredPoint(lat, lng);

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
      // Очиқ ҳужжатда фақат тахминий марказ (қаранг: `ensureOwnerKey`).
      areaLat: cell.lat,
      areaLng: cell.lng,
      geohash4: geohashEncode(lat, lng, 4),
      contactMode,
      hasAgent: agentPhone !== '',
      searchTokens: buildSearchTokens(title, text),
      status: nextStatus,
      editedAt: ts(),
      updatedAt: ts(),
    });

    await ref.collection('private').doc('detail').set({
      ownerId: uid,
      lat,
      lng,
      ownerPhone: uid,
      ...(agentPhone ? { agentPhone } : {}),
      updatedAt: ts(),
    }, { merge: false });

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
    await assertOwner(listingId, uid);
    await deleteListingDeep(ref);
    return { ok: true };
  });

  /**
   * Ёзувни ёпиқ ҳужжати билан бирга ўчиради.
   *
   * Firestore'да ҳужжат ўчирилса ички коллекцияси ЎЧМАЙДИ — эътибор
   * берилмаса, `private/detail` (телефон ва аниқ координата) базада
   * етим бўлиб қолаверарди.
   */
  async function deleteListingDeep(ref) {
    const subs = await ref.collection('private').listDocuments();
    await Promise.all(subs.map((doc) => doc.delete()));
    await ref.delete();
  }

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

      // Эгалик транзакциядан ТАШҚАРИДА текширилади: телефон ёпиқ
      // ҳужжатда, уни транзакция ичида ўқиш керак эмас.
      await assertOwner(listingId, uid);

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

  // ─── 3-босқич: ахборот пакети ─────────────────────────────────
  // Концепциянинг 4-бўлими: AVA уй сотилгани учун комиссия олмайди,
  // объектлар ҳақидаги АХБОРОТ хизмати учун ҳақ олади. Пакет — шунча
  // объектнинг аниқ маълумотини очиш ҳуқуқи.

  /** Пакет ўлчамлари — концепцияда «масалан, 5 объект ёки 10 объект». */
  const PACKAGE_SIZES = [5, 10];

  const PACKAGE_PRICING_DEFAULT = { 5: 30000, 10: 50000 };

  async function packagePriceFor(size) {
    const fallback = PACKAGE_PRICING_DEFAULT[size] || 0;
    try {
      const snap = await db.collection('settings').doc('app').get();
      const map = (snap.data() || {}).realtyPackagePricing;
      if (map && typeof map === 'object' && map[String(size)] != null) {
        const v = Number(map[String(size)]);
        if (Number.isFinite(v) && v >= 0) return Math.round(v);
      }
    } catch (e) {
      console.error('packagePriceFor', e.message || e);
    }
    return fallback;
  }

  /** Ахборот пакети — ҳамёндан тўлов, `realtyUnlocksLeft` га қўшилади. */
  exports.purchaseRealtyPackage = functions.https.onCall(
    async (data, context) => {
      const uid = requireUid(context);
      const d = data || {};

      const idempotencyKey = String(d.idempotencyKey || '').trim();
      if (!idempotencyKey) throw fail('invalid-argument', 'idem_required');
      const idemRef = db.collection('wallet_idempotency')
        .doc('realty_pkg_' + idempotencyKey);
      const existingIdem = await idemRef.get();
      if (existingIdem.exists) {
        return (existingIdem.data() || {}).result || { ok: true, duplicate: true };
      }

      const size = parseInt(String(d.size || 0), 10);
      if (!PACKAGE_SIZES.includes(size)) {
        throw fail('invalid-argument', 'bad_package_size');
      }
      const price = await packagePriceFor(size);
      const userRef = db.collection('users').doc(uid);

      try {
        return await db.runTransaction(async (t) => {
          const idemSnap = await t.get(idemRef);
          if (idemSnap.exists) {
            return (idemSnap.data() || {}).result || { ok: true, duplicate: true };
          }
          const userSnap = await t.get(userRef);
          if (!userSnap.exists) throw fail('not-found', 'user_not_found');
          const u = userSnap.data() || {};

          if (price > 0) {
            const balance = u.bonusBalance || 0;
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
              type: 'realty_package_purchase',
              amount: price,
              debitCredit: 'debit',
              note: `Кўчмас мулк ахборот пакети — ${size} объект`,
              refType: 'realty_package',
              refId: `${size}`,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          // Қолган ўринлар устига қўшилади — эски пакет куймайди.
          t.set(userRef, {
            realtyUnlocksLeft:
              admin.firestore.FieldValue.increment(size),
            realtyPackageAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          const left = Number(u.realtyUnlocksLeft || 0) + size;
          const res = { ok: true, size, price, unlocksLeft: left };
          t.set(idemRef, {
            type: 'purchaseRealtyPackage',
            result: res,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return res;
        });
      } catch (e) {
        if (e instanceof functions.https.HttpsError) throw e;
        console.error('purchaseRealtyPackage', e);
        throw fail('internal', 'purchase_failed');
      }
    });

  /**
   * Битта объектнинг аниқ маълумотини очиш — пакетдан 1 ўрин ейди.
   *
   * Очилгач `users/{uid}/realty_unlocked/{listingId}` ҳужжати яратилади;
   * `firestore.rules` айнан шу ҳужжат борлигига қараб ёпиқ
   * `private/detail` ни ўқишга рухсат беради. Такрор очишда ўрин
   * ЕЙИЛМАЙДИ — бир марта тўланган объект доим очиқ қолади.
   */
  exports.unlockRealtyListing = functions.https.onCall(
    async (data, context) => {
      const uid = requireUid(context);
      const listingId = String((data || {}).listingId || '').trim();
      if (!listingId) throw fail('invalid-argument', 'listing_required');

      const listingRef = db.collection('realty_listings').doc(listingId);
      const listingSnap = await listingRef.get();
      if (!listingSnap.exists) throw fail('not-found', 'listing_not_found');

      const userRef = db.collection('users').doc(uid);
      const unlockRef = userRef.collection('realty_unlocked').doc(listingId);

      return db.runTransaction(async (t) => {
        const existing = await t.get(unlockRef);
        if (existing.exists) {
          const u = await t.get(userRef);
          return {
            ok: true,
            alreadyUnlocked: true,
            unlocksLeft: Number((u.data() || {}).realtyUnlocksLeft || 0),
          };
        }
        const userSnap = await t.get(userRef);
        const left = Number((userSnap.data() || {}).realtyUnlocksLeft || 0);
        if (left <= 0) throw fail('failed-precondition', 'no_unlocks_left');

        t.update(userRef, {
          realtyUnlocksLeft: admin.firestore.FieldValue.increment(-1),
        });
        t.set(unlockRef, {
          listingId,
          unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { ok: true, alreadyUnlocked: false, unlocksLeft: left - 1 };
      });
    });

  /** Пакет нархлари — илова варағида кўрсатиш учун. */
  exports.getRealtyPackagePricing = functions.https.onCall(async () => {
    const out = {};
    for (const size of PACKAGE_SIZES) {
      out[String(size)] = await packagePriceFor(size);
    }
    return { pricing: out };
  });

  // ─── 4-босқич: риэлторлик компанияси ──────────────────────────
  // Концепциянинг 5-бўлими: объектлар биттадан киритилади ва ҳар бири
  // харитага боғланади — бу қоида ЎЗГАРМАЙДИ. Лекин компанияга шу
  // ишни тезлаштирадиган воситалар берилади.

  /**
   * Профессионал пакет режалари. Админ `settings/app.realtyProPlans`
   * орқали алмаштиради: [{id, objects, days, price}].
   */
  const PRO_PLANS_DEFAULT = [
    { id: 'pro_25', objects: 25, days: 30, price: 250000 },
    { id: 'pro_60', objects: 60, days: 30, price: 500000 },
    { id: 'pro_150', objects: 150, days: 90, price: 1200000 },
  ];

  async function proPlans() {
    try {
      const snap = await db.collection('settings').doc('app').get();
      const raw = (snap.data() || {}).realtyProPlans;
      if (Array.isArray(raw) && raw.length) {
        const parsed = raw
          .map((p) => ({
            id: String((p || {}).id || '').trim(),
            objects: Math.round(Number((p || {}).objects) || 0),
            days: Math.round(Number((p || {}).days) || 0),
            price: Math.round(Number((p || {}).price) || 0),
          }))
          .filter((p) => p.id && p.objects > 0 && p.days > 0 && p.price >= 0);
        if (parsed.length) return parsed;
      }
    } catch (e) {
      console.error('proPlans', e.message || e);
    }
    return PRO_PLANS_DEFAULT;
  }

  /** Фойдаланувчининг амал қилаётган профессионал пакети ёки `null`. */
  async function activeProPlan(uid) {
    try {
      const snap = await db.collection('users').doc(uid).get();
      const pro = (snap.data() || {}).realtyPro;
      if (!pro || typeof pro !== 'object') return null;
      const until = pro.expiresAt && pro.expiresAt.toMillis
        ? pro.expiresAt.toMillis() : 0;
      if (!until || until < Date.now()) return null;
      const objects = Math.round(Number(pro.objects) || 0);
      if (objects <= 0) return null;
      return { objects, expiresAt: until, planId: String(pro.planId || '') };
    } catch (e) {
      console.error('activeProPlan', e.message || e);
      return null;
    }
  }

  exports.getRealtyProPlans = functions.https.onCall(async () => {
    return { plans: await proPlans() };
  });

  /**
   * Профессионал пакет сотиб олиш.
   *
   * Амал қилаётган пакет устига олинса, объект ўрни ва муддат
   * ҚЎШИЛАДИ — эски пакет куймайди (`purchaseRealtyTier` билан бир хил
   * мантиқ).
   */
  exports.purchaseRealtyProPackage = functions.https.onCall(
    async (data, context) => {
      const uid = requireUid(context);
      const d = data || {};

      const idempotencyKey = String(d.idempotencyKey || '').trim();
      if (!idempotencyKey) throw fail('invalid-argument', 'idem_required');
      const idemRef = db.collection('wallet_idempotency')
        .doc('realty_pro_' + idempotencyKey);
      const existingIdem = await idemRef.get();
      if (existingIdem.exists) {
        return (existingIdem.data() || {}).result || { ok: true, duplicate: true };
      }

      const planId = String(d.planId || '').trim();
      const plan = (await proPlans()).find((p) => p.id === planId);
      if (!plan) throw fail('invalid-argument', 'bad_plan');

      const userRef = db.collection('users').doc(uid);
      try {
        return await db.runTransaction(async (t) => {
          const idemSnap = await t.get(idemRef);
          if (idemSnap.exists) {
            return (idemSnap.data() || {}).result || { ok: true, duplicate: true };
          }
          const userSnap = await t.get(userRef);
          if (!userSnap.exists) throw fail('not-found', 'user_not_found');
          const u = userSnap.data() || {};

          if (plan.price > 0) {
            const balance = u.bonusBalance || 0;
            if (balance < plan.price) {
              throw fail('failed-precondition', 'insufficient_balance', {
                price: plan.price, balance,
              });
            }
            t.update(userRef, {
              bonusBalance: admin.firestore.FieldValue.increment(-plan.price),
              balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            t.set(userRef.collection('wallet_ledger').doc(), {
              type: 'realty_pro_purchase',
              amount: plan.price,
              debitCredit: 'debit',
              note: `Риэлтор пакети ${plan.id} — ${plan.objects} объект, `
                + `${plan.days} кун`,
              refType: 'realty_pro',
              refId: plan.id,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          const cur = u.realtyPro || {};
          const curUntil = cur.expiresAt && cur.expiresAt.toMillis
            ? cur.expiresAt.toMillis() : 0;
          const base = curUntil > Date.now() ? curUntil : Date.now();
          const expiresMs = base + plan.days * 24 * 60 * 60 * 1000;
          const objects = (curUntil > Date.now()
            ? Math.round(Number(cur.objects) || 0) : 0) + plan.objects;

          t.set(userRef, {
            realtyPro: {
              planId: plan.id,
              objects,
              expiresAt: admin.firestore.Timestamp.fromMillis(expiresMs),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          }, { merge: true });

          const res = {
            ok: true,
            planId: plan.id,
            objects,
            price: plan.price,
            expiresAt: expiresMs,
          };
          t.set(idemRef, {
            type: 'purchaseRealtyProPackage',
            result: res,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return res;
        });
      } catch (e) {
        if (e instanceof functions.https.HttpsError) throw e;
        console.error('purchaseRealtyProPackage', e);
        throw fail('internal', 'purchase_failed');
      }
    });

  /** Пакет ҳисоблагичи — иловада доим кўриниб туриши учун. */
  exports.getRealtyQuota = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const ownerKey = await ensureOwnerKey(uid);
    const pro = await activeProPlan(uid);
    const used = await countActivePlain(ownerKey);
    return {
      used,
      limit: pro ? pro.objects : FREE_PLAIN_LIMIT,
      isPro: pro !== null,
      proExpiresAt: pro ? pro.expiresAt : 0,
    };
  });

  /**
   * Жамоа аккаунти — ходимни компания пакетига улаш.
   *
   * Иш принципи: ходим компаниянинг `realtyOwnerKey` ини УЛАШАДИ.
   * Шунда ходим киритган объект ҳам компания объекти бўлиб қолади,
   * `assertOwner` эса иккаласига ҳам бирдек рухсат беради — алоҳида
   * «жамоа» жадвали ва унга қарайдиган қўшимча қоида керак эмас.
   *
   * Фақат профессионал пакет эгаси ходим қўша олади.
   */
  exports.addRealtyTeamMember = functions.https.onCall(
    async (data, context) => {
      const uid = requireUid(context);
      const pro = await activeProPlan(uid);
      if (!pro) throw fail('failed-precondition', 'pro_required');

      const memberPhone = canonicalUid(
        String((data || {}).phone || '').replace(/\D/g, ''),
      );
      if (!memberPhone || memberPhone.length < 9) {
        throw fail('invalid-argument', 'bad_phone');
      }
      if (memberPhone === uid) throw fail('invalid-argument', 'self');

      const memberRef = db.collection('users').doc(memberPhone);
      const memberSnap = await memberRef.get();
      if (!memberSnap.exists) throw fail('not-found', 'member_not_found');
      const member = memberSnap.data() || {};

      // Ходимнинг ўз эълонлари бўлса, уларни компанияга кўчириб
      // юбормаймиз — бу унинг шахсий контенти.
      const ownerKey = await ensureOwnerKey(uid);
      const memberKey = String(member.realtyOwnerKey || '');
      if (memberKey && memberKey !== ownerKey) {
        const own = await db.collection('realty_listings')
          .where('ownerKey', '==', memberKey).limit(1).get();
        if (!own.empty) throw fail('failed-precondition', 'member_has_listings');
      }

      await memberRef.set({
        realtyOwnerKey: ownerKey,
        realtyTeamOwner: uid,
      }, { merge: true });

      return { ok: true, memberPhone };
    });

  /** Ходимни жамоадан чиқариш — ўз калитини қайта олади. */
  exports.removeRealtyTeamMember = functions.https.onCall(
    async (data, context) => {
      const uid = requireUid(context);
      const memberPhone = canonicalUid(
        String((data || {}).phone || '').replace(/\D/g, ''),
      );
      if (!memberPhone) throw fail('invalid-argument', 'bad_phone');

      const memberRef = db.collection('users').doc(memberPhone);
      const snap = await memberRef.get();
      if (String((snap.data() || {}).realtyTeamOwner || '') !== uid) {
        throw fail('permission-denied', 'not_team_owner');
      }
      await memberRef.set({
        realtyOwnerKey: crypto.randomBytes(12).toString('hex'),
        realtyTeamOwner: admin.firestore.FieldValue.delete(),
      }, { merge: true });
      return { ok: true };
    });

  // ─── 5-босқич: видеони эълонга боғлаш ─────────────────────────
  // Концепциянинг 3-бўлими: видеони матнли эълонга боғлаш ИХТИЁРИЙ.
  // Боғланса, эълон охирида «Видеони кўриш» тугмаси пайдо бўлади ва
  // айнан шу объект видеосини очади. Боғланмаса — эълон тугмасиз,
  // одатдагидек кўринади.

  /**
   * Видеони объектга боғлаш.
   *
   * Клип КИМНИКИ эканини ва тури (бепул AVAGram ёки пуллик реклама)
   * серверда аниқланади — клиент «бу реклама видеоси» деб айта
   * олмайди. Бепул/пуллик фарқи `tv_clips.category === 'ad'` бўйича.
   */
  exports.linkRealtyVideo = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const d = data || {};
    const listingId = String(d.listingId || '').trim();
    const clipId = String(d.clipId || '').trim();
    if (!listingId || !clipId) throw fail('invalid-argument', 'bad_args');

    await assertOwner(listingId, uid);

    const clipSnap = await db.collection('tv_clips').doc(clipId).get();
    if (!clipSnap.exists) throw fail('not-found', 'clip_not_found');
    const clip = clipSnap.data() || {};
    if (canonicalUid(String(clip.ownerPhone || '')) !== uid) {
      throw fail('permission-denied', 'not_clip_owner');
    }
    if (clip.status !== 'active') {
      throw fail('failed-precondition', 'clip_not_active');
    }

    const isAd = String(clip.category || '') === 'ad';
    await db.collection('realty_listings').doc(listingId).update({
      [isAd ? 'adClipId' : 'avagramClipId']: clipId,
      updatedAt: ts(),
    });
    return { ok: true, clipId, paid: isAd };
  });

  /** Видео боғламасини олиб ташлаш — клипнинг ўзи ўчирилмайди. */
  exports.unlinkRealtyVideo = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const listingId = String((data || {}).listingId || '').trim();
    if (!listingId) throw fail('invalid-argument', 'listing_required');
    await assertOwner(listingId, uid);
    await db.collection('realty_listings').doc(listingId).update({
      avagramClipId: '',
      adClipId: '',
      updatedAt: ts(),
    });
    return { ok: true };
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
      await deleteListingDeep(db.collection('realty_listings').doc(listingId));
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

      // 1) Муддати тугаган объектлар — ёпиқ ҳужжати билан ўчирилади.
      let deleted = 0;
      for (let round = 0; round < 10; round += 1) {
        const snap = await db.collection('realty_listings')
          .where('expiresAt', '<=', now)
          .limit(150)
          .get();
        if (snap.empty) break;
        for (const doc of snap.docs) {
          try {
            await deleteListingDeep(doc.ref);
            deleted += 1;
          } catch (e) {
            console.error('realtyExpirySweep delete', doc.id, e.message || e);
          }
        }
        if (snap.size < 150) break;
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
          // Эганинг рақами ёпиқ ҳужжатда (очиқда фақат `ownerKey`).
          const priv = await doc.ref.collection('private').doc('detail').get();
          const ownerId = String((priv.data() || {}).ownerId || '');
          if (!ownerId) continue;
          await notifyUserInApp({
            userId: ownerId,
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
