/**
 * БИЗНЕС ХАРИТАСИ — тадбиркорлик объектлари реестри (ega qarori 2026-10-23, docs/biznes_xaritasi_2026-10-23_uz.md).
 *
 * Қоида (B-1): объектни ЭГАСИ ўзи қўшади ва таҳрирлайди; админ қўшмайди — фақат таҳрирлайди ва ўчиради
 * (ҳар бири `admin_audit`га сабаб билан тушади, 41-банд). Тасдиқлаш навбати йўқ: ёзув дарҳол харитада.
 *
 * Коллекция (client-write ЁПИҚ, фақат шу callable'лар ёзади; ўқиш — оммавий):
 *   businesses/{ownerId}_{clientRequestId}
 *
 * Мавжуд модуллар (кафе, улгуржи сотувчи, EV станция) бу ерга КЎЧИРИЛМАЙДИ — харита уларни ўз манбасидан
 * ўқийди (7-банд: бир қоида — бир манба).
 *
 * Чегаралар (LIMITS, CATEGORIES, BOUNDS) — PROPOSED, эга тасдиқлагунча (47-банд); ўзгартириш = шу константалар.
 * Dart томон паритети: lib/features/business_map/domain/business_category.dart (тест қулфлайди).
 *
 * Диагностика кодлари: BUSINESS_NAME_INVALID, BUSINESS_CATEGORY_INVALID, BUSINESS_LOCATION_INVALID,
 * BUSINESS_PHONE_INVALID, BUSINESS_FIELD_INVALID, BUSINESS_LIMIT_REACHED, BUSINESS_NOT_FOUND,
 * BUSINESS_NOT_OWNER, REQUEST_ID_INVALID, GEO_DISTRICT_INVALID, REASON_REQUIRED.
 */
'use strict';

const { encode: geohashEncode } = require('./geo_hash');

const COLLECTION = 'businesses';
const GEO_DISTRICTS = 'geo_districts';
const ADMIN_AUDIT = 'admin_audit';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);

/** Тур гуруҳлари (B-10). Рўйхат Dart томонида `BusinessCategory` билан бир хил бўлиши шарт. */
const CATEGORIES = Object.freeze([
  'retail', 'wholesale', 'food', 'auto', 'manufacturing', 'personal', 'home_services',
  'health', 'education', 'leisure', 'logistics', 'professional', 'it_media', 'other',
]);

const LIMITS = Object.freeze({
  nameMin: 2,
  nameMax: 80,
  subtypeMax: 60,
  descriptionMax: 500,
  addressMax: 200,
  hoursMax: 120,
  websiteMax: 120,
  phoneMin: 9,
  phoneMax: 15,
  maxPerOwner: 20, // B-9
});

/** Ўзбекистон атрофи (B-11): ғалат/бекорчи координаталарга қарши дағал тўсиқ. */
const BOUNDS = Object.freeze({ latMin: 36, latMax: 46, lngMin: 55, lngMax: 74 });

const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const DOC_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const GEO_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

function geohashPair(lat, lng) {
  return { geohash: geohashEncode(lat, lng, 9), geohash4: geohashEncode(lat, lng, 4) };
}

/**
 * Киритилган майдонларни текширади ва тозалайди. Соф функция (тест учун экспорт).
 * `fail(status, code, message)` — HttpsError ясовчи. Ҳудудни (regionId/districtId) бу ерда ТЕКШИРМАЙДИ —
 * у Firestore ўқишни талаб қилади (callable ичида).
 */
function normalizeInput(input, fail) {
  const d = input || {};
  const name = str(d.name, LIMITS.nameMax + 1);
  if (name.length < LIMITS.nameMin || name.length > LIMITS.nameMax) {
    throw fail('invalid-argument', 'BUSINESS_NAME_INVALID',
      `Номи ${LIMITS.nameMin}–${LIMITS.nameMax} белги бўлсин.`);
  }
  if (!CATEGORIES.includes(d.category)) {
    throw fail('invalid-argument', 'BUSINESS_CATEGORY_INVALID', 'Фаолият турини танланг.');
  }
  const lat = d.lat;
  const lng = d.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng)
    || lat < BOUNDS.latMin || lat > BOUNDS.latMax || lng < BOUNDS.lngMin || lng > BOUNDS.lngMax) {
    throw fail('invalid-argument', 'BUSINESS_LOCATION_INVALID', 'Жойлашувни харитада белгиланг.');
  }
  const phone = String(d.phone == null ? '' : d.phone).replace(/\D/g, '');
  if (phone.length < LIMITS.phoneMin || phone.length > LIMITS.phoneMax) {
    throw fail('invalid-argument', 'BUSINESS_PHONE_INVALID', 'Телефон рақамини тўғри киритинг.');
  }
  const tooLong = (v, max) => String(v == null ? '' : v).trim().length > max;
  if (tooLong(d.subtype, LIMITS.subtypeMax) || tooLong(d.description, LIMITS.descriptionMax)
    || tooLong(d.address, LIMITS.addressMax) || tooLong(d.openingHours, LIMITS.hoursMax)
    || tooLong(d.website, LIMITS.websiteMax)) {
    throw fail('invalid-argument', 'BUSINESS_FIELD_INVALID', 'Матн жуда узун.');
  }
  const regionId = str(d.regionId, 64);
  const districtId = str(d.districtId, 64);
  if ((regionId && !GEO_ID_RE.test(regionId)) || (districtId && !GEO_ID_RE.test(districtId))
    || (!!regionId !== !!districtId)) {
    throw fail('invalid-argument', 'GEO_DISTRICT_INVALID', 'Ҳудудни қайта танланг.');
  }
  return {
    name,
    category: d.category,
    subtype: str(d.subtype, LIMITS.subtypeMax),
    description: str(d.description, LIMITS.descriptionMax),
    phone,
    address: str(d.address, LIMITS.addressMax),
    lat,
    lng,
    ...geohashPair(lat, lng),
    regionId,
    districtId,
    openingHours: str(d.openingHours, LIMITS.hoursMax),
    website: str(d.website, LIMITS.websiteMax),
  };
}

/** Ўзгарадиган (эга таҳрир қила оладиган) майдонлар — ўзгариш аниқлаш ва audit учун. */
const EDITABLE = Object.freeze([
  'name', 'category', 'subtype', 'description', 'phone', 'address', 'lat', 'lng',
  'regionId', 'districtId', 'openingHours', 'website',
]);

function changedKeys(cur, next) {
  return EDITABLE.filter((k) => cur[k] !== next[k]);
}

function attachBusinessDirectory(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles,
  } = deps;
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, message) => new HttpsError(status, message || code, { code });
  const log = (o) => console.log(JSON.stringify({ module: 'business_directory', ...o }));

  function requireUser(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    return uid;
  }
  const requireAdmin = (context) => requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');

  function docId(v, code) {
    const s = str(v, 128);
    if (!DOC_ID_RE.test(s)) throw fail('invalid-argument', code, 'Объект топилмади.');
    return s;
  }

  function reasonOf(data) {
    const r = str(data && data.reason, 300);
    if (r.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED', 'Сабабни ёзинг.');
    return r;
  }

  /** Ҳудуд берилган бўлса — туман мавжуд ва шу вилоятники бўлиши шарт (клиентга ишонилмайди, 18-банд). */
  async function assertGeo(fields) {
    if (!fields.districtId) return;
    const snap = await db.collection(GEO_DISTRICTS).doc(fields.districtId).get();
    const d = snap.exists ? (snap.data() || {}) : null;
    if (!d || String(d.regionId || '') !== fields.regionId) {
      throw fail('invalid-argument', 'GEO_DISTRICT_INVALID', 'Ҳудудни қайта танланг.');
    }
  }

  // ───────────────────────── Эга ─────────────────────────

  /**
   * data: { businessId?, clientRequestId (яратишда шарт), name, category, subtype?, description?, phone,
   *         address?, lat, lng, regionId?, districtId?, openingHours?, website? }
   * → { ok, businessId, duplicate?, changed? }. Яратиш `clientRequestId` бўйича идемпотент (21-банд).
   */
  exportsObj.upsertMyBusiness = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const d = data || {};
    const fields = normalizeInput(d, fail);
    await assertGeo(fields);

    if (d.businessId != null && d.businessId !== '') {
      const ref = db.collection(COLLECTION).doc(docId(d.businessId, 'BUSINESS_NOT_FOUND'));
      const out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) throw fail('not-found', 'BUSINESS_NOT_FOUND', 'Объект топилмади.');
        const cur = snap.data();
        if (cur.ownerId !== uid) throw fail('permission-denied', 'BUSINESS_NOT_OWNER', 'Объект топилмади.');
        if (changedKeys(cur, fields).length === 0) return { changed: false };
        t.update(ref, { ...fields, updatedAt: ts() });
        return { changed: true };
      });
      log({ action: 'upsertMyBusiness', userId: uid, businessId: ref.id, result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
      return { ok: true, businessId: ref.id, ...out };
    }

    const clientRequestId = str(d.clientRequestId, 64);
    if (!ID_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID', 'Қайта уриниб кўринг.');
    const ref = db.collection(COLLECTION).doc(`${uid}_${clientRequestId}`);
    const out = await db.runTransaction(async (t) => {
      const [snap, ownSnap] = await Promise.all([
        t.get(ref),
        t.get(db.collection(COLLECTION).where('ownerId', '==', uid).limit(LIMITS.maxPerOwner)),
      ]);
      if (snap.exists) return { duplicate: true };
      if (ownSnap.size >= LIMITS.maxPerOwner) {
        throw fail('resource-exhausted', 'BUSINESS_LIMIT_REACHED',
          `Бир эгада ${LIMITS.maxPerOwner} тадан ортиқ объект бўлмайди.`);
      }
      t.create(ref, {
        ownerId: uid, ...fields, status: 'active', createdAt: ts(), updatedAt: ts(),
      });
      return { duplicate: false };
    });
    log({ action: 'upsertMyBusiness', userId: uid, businessId: ref.id, result: out.duplicate ? 'duplicate' : 'created', durationMs: Date.now() - started });
    return { ok: true, businessId: ref.id, ...out };
  });

  /** data: { businessId } → { ok, deleted }. Бегона ёзув — BUSINESS_NOT_FOUND (мавжудлигини ошкор қилмайди). */
  exportsObj.deleteMyBusiness = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const ref = db.collection(COLLECTION).doc(docId(data && data.businessId, 'BUSINESS_NOT_FOUND'));
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { deleted: false };
      if (snap.data().ownerId !== uid) throw fail('permission-denied', 'BUSINESS_NOT_OWNER', 'Объект топилмади.');
      t.delete(ref);
      return { deleted: true };
    });
    log({ action: 'deleteMyBusiness', userId: uid, businessId: ref.id, result: out.deleted ? 'deleted' : 'noop', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  // ───────────────────────── Админ ─────────────────────────

  /**
   * data: { businessId, reason, ...майдонлар (upsert билан бир хил) } — админ ТАҲРИРЛАЙДИ, яратмайди (B-1).
   * `ownerId` ўзгармайди. Ўзгариш бўлмаса audit ёзилмайди (идемпотент).
   */
  exportsObj.adminUpdateBusiness = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const d = data || {};
    const reason = reasonOf(d);
    const fields = normalizeInput(d, fail);
    await assertGeo(fields);
    const ref = db.collection(COLLECTION).doc(docId(d.businessId, 'BUSINESS_NOT_FOUND'));
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'BUSINESS_NOT_FOUND', 'Объект топилмади.');
      const keys = changedKeys(snap.data(), fields);
      if (keys.length === 0) return { changed: false };
      t.update(ref, { ...fields, updatedAt: ts(), updatedBy: actor });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_update', actor, target: ref.id, reason, changedKeys: keys, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminUpdateBusiness', userId: actor, businessId: ref.id, result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
    return { ok: true, businessId: ref.id, ...out };
  });

  /** data: { businessId, reason } → { ok, deleted }. Audit ҳужжатида ўчирилган ёзув нусхаси сақланади. */
  exportsObj.adminDeleteBusiness = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const ref = db.collection(COLLECTION).doc(docId(data && data.businessId, 'BUSINESS_NOT_FOUND'));
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { deleted: false };
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_delete', actor, target: ref.id, reason, snapshot: snap.data(), at: ts(),
      });
      t.delete(ref);
      return { deleted: true };
    });
    log({ action: 'adminDeleteBusiness', userId: actor, businessId: ref.id, result: out.deleted ? 'deleted' : 'noop', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });
}

module.exports = {
  attachBusinessDirectory, normalizeInput, changedKeys, CATEGORIES, LIMITS, BOUNDS, EDITABLE,
};
