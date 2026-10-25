/**
 * БИЗНЕС ХАРИТАСИ — тадбиркорлик объектлари реестри (ega qarori 2026-10-23, docs/biznes_xaritasi_2026-10-23_uz.md).
 *
 * Қоида (B-1): объектни ЭГАСИ ўзи қўшади ва таҳрирлайди. 2026-10-23 эга қарори билан админ ҲАМ қўша олади
 * (`adminCreateBusiness`), таҳрирлайди ва ўчиради — ҳар бири `admin_audit`га сабаб билан тушади (41-банд).
 * Тасдиқлаш навбати йўқ: ёзув дарҳол харитада.
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
 * BUSINESS_NOT_OWNER, BUSINESS_OWNER_INVALID, REQUEST_ID_INVALID, GEO_DISTRICT_INVALID, REASON_REQUIRED,
 * BUSINESS_STATUS_INVALID, BUSINESS_BLOCKED, SHOP_BLOCKED, SHOP_OWNER_INVALID, SHOP_NOT_FOUND, PARENT_BLOCKED,
 * COMPLAINT_TARGET_INVALID, COMPLAINT_OWN, COMPLAINT_LIMIT, BRANCH_INVALID, BRANCH_NESTED.
 *
 * БЛОКЛАШ (эга қарори 2026-10-25: «админ назорати барча кириш йўлларида»):
 *   • онлайн дўкон `tv_shops/{phone}` ва йўналиш дўкони `businesses/{id}` — `status: active | blocked`;
 *   • блокланганда фарзанд ёзувлар ҳам блокланади ва `blockedByParent` белгиси олади (`shop` ёки
 *     `business:<id>`) — блок олинганда ФАҚАТ шу белгили ёзувлар қайтади; админ алоҳида блоклагани қолади;
 *   • блокланган объект харитадан йўқолади: `lat`/`lng`/`geohash`лар `blockedGeo`га олинади — харита катак
 *     сўрови ҳам, умумий кўриниш ҳам (эски APK'ларда ҳам) координатасиз ҳужжатни чизмайди; блок олинганда тикланади.
 */
'use strict';

const { encode: geohashEncode } = require('./geo_hash');

const COLLECTION = 'businesses';
const GEO_DISTRICTS = 'geo_districts';
const ADMIN_AUDIT = 'admin_audit';
const ITEMS = 'tv_shop_items';
const SHOPS = 'tv_shops';
/** Онлайн дўкон ва йўналиш дўкони ҳолатлари (админ ўрнатади). */
const BLOCK_STATUSES = Object.freeze(['active', 'blocked']);
/** `blockedByParent` белгиси: дўкон блоки ёки муайян йўналиш блоки. */
const PARENT_SHOP = 'shop';
const parentOfBusiness = (businessId) => `business:${businessId}`;
/** Харидор шикояти (`reports`): маҳсулот ёки бутун дўкон. Кунлик чеклов — бозор шикояти билан бир хил (20). */
const COMPLAINT_TYPE = 'shop_content';
const COMPLAINT_TARGETS = Object.freeze(['shop_item', 'shop']);
const COMPLAINT_DAILY_LIMIT = 20;
const PRODUCT_KINDS = Object.freeze(['product', 'service']);
/** Админ маҳсулотни фақат фаол ёки блокланган қила олади (кутилаётган/ўчирилган ҳолатларни ўрнатмайди). */
const PRODUCT_ADMIN_STATUSES = Object.freeze(['active', 'blocked']);
const PRODUCT_LIMITS = Object.freeze({ titleMin: 2, titleMax: 120, descriptionMax: 1000, priceMax: 999999999 });
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
  // Фақат онлайн йўналиш (2026-10-25, 3-босқич): жисмоний жойи йўқ — координата олинмайди ва сақланмайди, харитага
  // тушмайди (уй манзили мажбуран нуқта бўлмасин, 40-банд). Юборилган координата ҳам эътиборсиз.
  const online = d.online === true;
  const lat = d.lat;
  const lng = d.lng;
  if (!online && (typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng)
    || lat < BOUNDS.latMin || lat > BOUNDS.latMax || lng < BOUNDS.lngMin || lng > BOUNDS.lngMax)) {
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
  // Филиал (2026-10-25, 3-босқич): шу эганинг бошқа йўналишининг яна бир жисмоний нуқтаси. Ота мавжудлиги, эгаси
  // ва ичма-ич эмаслиги callable'да (`assertBranch`) текширилади; онлайн филиал бўлмайди.
  const branchOf = str(d.branchOf, 129);
  if (branchOf && (!DOC_ID_RE.test(branchOf) || online)) {
    throw fail('invalid-argument', 'BRANCH_INVALID', 'Филиални қайта танланг.');
  }
  return {
    name,
    category: d.category,
    subtype: str(d.subtype, LIMITS.subtypeMax),
    description: str(d.description, LIMITS.descriptionMax),
    phone,
    address: str(d.address, LIMITS.addressMax),
    ...(online ? { online: true } : { lat, lng, ...geohashPair(lat, lng) }),
    ...(branchOf ? { branchOf } : {}),
    regionId,
    districtId,
    openingHours: str(d.openingHours, LIMITS.hoursMax),
    website: str(d.website, LIMITS.websiteMax),
  };
}

/** Ўзгарадиган (эга таҳрир қила оладиган) майдонлар — ўзгариш аниқлаш ва audit учун. */
const EDITABLE = Object.freeze([
  'name', 'category', 'subtype', 'description', 'phone', 'address', 'lat', 'lng', 'online', 'branchOf',
  'regionId', 'districtId', 'openingHours', 'website',
]);

/**
 * Таҳрирда янги шаклда йўқ бўлса эски ҳужжатдан ўчириладиган майдонлар: онлайн ↔ жисмоний ўтишдаги жой
 * майдонлари ва филиаллиги олинган `branchOf`.
 */
const PLACE_KEYS = Object.freeze(['lat', 'lng', 'geohash', 'geohash4', 'online', 'branchOf']);

function changedKeys(cur, next) {
  return EDITABLE.filter((k) => cur[k] !== next[k]);
}

const isBlocked = (snap) => !!snap && snap.exists && (snap.data() || {}).status === 'blocked';

/**
 * Блокланган объект таҳрирланса ҳам харитага қайтмайди: координата `blockedGeo`га ёзилади, `lat`/`lng`/`geohash`лар
 * ёзилмайди (блок олинганда тикланади).
 */
function visibleFields(cur, fields) {
  if (!cur || cur.status !== 'blocked') return fields;
  const {
    geohash, geohash4, lat, lng, ...rest // eslint-disable-line no-unused-vars
  } = fields;
  return typeof lat === 'number' && typeof lng === 'number' ? { ...rest, blockedGeo: { lat, lng } } : rest;
}

/**
 * Таҳрир патчи: [fields] + жорий ҳужжатда бор-у, янги шаклда йўқ жой майдонларини ўчириш (онлайн ↔ жисмоний).
 * Блокланган объектнинг онлайн/жисмоний тури ўзгармайди (`BUSINESS_BLOCKED`) — `blockedGeo` адашмасин.
 */
function editPatch(FieldValue, cur, fields, fail) {
  const wasOnline = cur.online === true;
  const nowOnline = fields.online === true;
  if (cur.status === 'blocked' && (wasOnline !== nowOnline || (cur.branchOf || '') !== (fields.branchOf || ''))) {
    throw fail('failed-precondition', 'BUSINESS_BLOCKED', 'Объект вақтинча блокланган.');
  }
  const next = visibleFields(cur, fields);
  const out = { ...next };
  if (cur.status !== 'blocked') {
    PLACE_KEYS.forEach((k) => {
      if (cur[k] !== undefined && next[k] === undefined) out[k] = FieldValue.delete();
    });
  }
  return out;
}

const CASCADE_BATCH = 400;
const digitsOf = (v) => String(v == null ? '' : v).replace(/\D/g, '');

/**
 * Объект ўчирилганда унинг маҳсулотларини юмшоқ ўчиради (`status: 'deleted'`) — Аҳоли бозорида «эгасиз» қолмасин
 * (эга қарори, 2026-10-24). Фақат ЭГАСИНИНГ ўз ҳужжатлари: бошқа эга `businessId` ёзиб қўйган «ёт» ҳужжатга ва
 * аллақачон ўчирилганга тегилмайди. Идемпотент (қайта чақириш зарарсиз), саҳифалаб (400 тадан) — сони чекланмаган.
 * Эгаси фойдаланувчи телефони бўлмаган объект (`ownerId: 'admin'`) учун ҳеч нарса қилмайди.
 */
async function cascadeBusinessProducts(db, admin, businessId, ownerId) {
  const owner = digitsOf(ownerId);
  if (owner.length < 12 || !businessId) return { scanned: 0, updated: 0 };
  const { FieldValue, FieldPath } = admin.firestore;
  let last = null;
  let scanned = 0;
  let updated = 0;
  for (;;) {
    let q = db.collection(ITEMS).where('businessId', '==', businessId).orderBy(FieldPath.documentId()).limit(CASCADE_BATCH);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    let n = 0;
    snap.docs.forEach((d) => {
      scanned += 1;
      const x = d.data() || {};
      if (x.status === 'deleted' || digitsOf(x.ownerPhone) !== owner) return;
      batch.update(d.ref, {
        status: 'deleted', deletedAt: FieldValue.serverTimestamp(), deletedBy: 'system:business_deleted', updatedAt: FieldValue.serverTimestamp(),
      });
      n += 1;
    });
    if (n > 0) {
      await batch.commit();
      updated += n;
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < CASCADE_BATCH) break;
  }
  return { scanned, updated };
}

/**
 * Сўров натижасини ҳужжат ID тартибида саҳифалаб юради; `patchOf(data)` патч қайтарса — ёзади, `null` бўлса ўтказади.
 * Идемпотент: патч фақат ҳолат мос келганда қайтарилади, қайта чақирув ярим қолган ишни тугатади (21-банд).
 */
async function patchPaged(db, admin, query, patchOf) {
  const { FieldPath } = admin.firestore;
  let last = null;
  let scanned = 0;
  let updated = 0;
  for (;;) {
    let q = query.orderBy(FieldPath.documentId()).limit(CASCADE_BATCH);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    let n = 0;
    snap.docs.forEach((d) => {
      scanned += 1;
      const patch = patchOf(d.data() || {}, d.id);
      if (!patch) return;
      batch.update(d.ref, patch);
      n += 1;
    });
    if (n > 0) {
      await batch.commit();
      updated += n;
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < CASCADE_BATCH) break;
  }
  return { scanned, updated };
}

/** Эга телефонининг Firestore'да учрайдиган ёзувлари (`998…`, 9 рақам, `+998…`) — `in` сўрови учун. */
function phoneVariants(phone12) {
  return [phone12, phone12.slice(3), `+${phone12}`];
}

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

/** Блокланган объектнинг координатаси `blockedGeo`да сақланади; ҳақиқий жойи (таҳрир ва audit учун). */
function geoOf(cur) {
  const g = cur && cur.blockedGeo;
  if (g && isNum(g.lat) && isNum(g.lng)) return { lat: g.lat, lng: g.lng };
  return cur && isNum(cur.lat) && isNum(cur.lng) ? { lat: cur.lat, lng: cur.lng } : null;
}

/** Ўзгариш аниқлаш учун: блокланган объект координатаси `blockedGeo`дан олинади. */
function effective(cur) {
  const g = geoOf(cur);
  return g ? { ...cur, ...g } : cur;
}

/**
 * Объект харитадан ВА эски APK'лардан йўқолиши учун: `lat`/`lng`/`geohash`лар `blockedGeo`га олинади. Харита катак
 * сўрови (`geohash4 in`) ҳам, умумий кўриниш (`createdAt` бўйича) ҳам координатасиз ҳужжатни чизмайди
 * (`Business.tryFromMap` эски иловада `null` қайтаради). Блок олинганда ҳаммаси тикланади.
 */
function businessBlockPatch(FieldValue, cur, extra) {
  const g = geoOf(cur);
  return {
    status: 'blocked',
    ...(g ? { blockedGeo: g } : {}),
    lat: FieldValue.delete(),
    lng: FieldValue.delete(),
    geohash: FieldValue.delete(),
    geohash4: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

/** Блок олинганда: координата `blockedGeo`дан қайтади, `geohash`лар қайта ҳисобланади, блок майдонлари тозаланади. */
function businessUnblockPatch(FieldValue, cur, extra) {
  const g = geoOf(cur);
  const geo = g ? { lat: g.lat, lng: g.lng, ...geohashPair(g.lat, g.lng) } : {};
  return {
    status: 'active',
    ...geo,
    blockedGeo: FieldValue.delete(),
    blockedByParent: FieldValue.delete(),
    blockedAt: FieldValue.delete(),
    blockedBy: FieldValue.delete(),
    blockReason: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

/**
 * Йўналиш дўкони блокланса/очилса — унинг маҳсулотлари. Блок: эганинг ФАОЛ маҳсулотлари → `blocked` +
 * `blockedByParent: business:<id>`. Очиш: фақат шу белгили `blocked` маҳсулотлар → `active` (админ алоҳида
 * блоклагани ёки дўкон блоки белгисидагилари қолади). Бегона эга ёзиб қўйган «ёт» ҳужжатга тегилмайди.
 */
async function cascadeBusinessBlock(db, admin, businessId, ownerId, block) {
  const owner = digitsOf(ownerId);
  if (owner.length < 12 || !businessId) return { scanned: 0, updated: 0 };
  const { FieldValue } = admin.firestore;
  const marker = parentOfBusiness(businessId);
  return patchPaged(db, admin, db.collection(ITEMS).where('businessId', '==', businessId), (x) => {
    if (digitsOf(x.ownerPhone).slice(-9) !== owner.slice(-9)) return null;
    if (block) {
      return x.status === 'active' ? { status: 'blocked', blockedByParent: marker, updatedAt: FieldValue.serverTimestamp() } : null;
    }
    return x.status === 'blocked' && x.blockedByParent === marker
      ? { status: 'active', blockedByParent: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() }
      : null;
  });
}

/**
 * Йўналиш блокланса/очилса — унинг филиаллари (`branchOf`): блокда фаол филиал → `blocked` + `business:<ота>`,
 * очишда фақат шу белгилилари қайтади (админ филиални алоҳида блоклагани қолади).
 */
async function cascadeBranchBlock(db, admin, parentId, block) {
  if (!parentId) return { scanned: 0, updated: 0 };
  const { FieldValue } = admin.firestore;
  const marker = parentOfBusiness(parentId);
  return patchPaged(db, admin, db.collection(COLLECTION).where('branchOf', '==', parentId), (x) => {
    if (block) return x.status === 'blocked' ? null : businessBlockPatch(FieldValue, x, { blockedByParent: marker });
    return x.status === 'blocked' && x.blockedByParent === marker ? businessUnblockPatch(FieldValue, x) : null;
  });
}

/**
 * Онлайн дўкон блокланса/очилса — эганинг БАРЧА йўналишлари ва маҳсулотлари (`blockedByParent: shop`).
 * Очишда: йўналиши ҳалиям алоҳида блокланган маҳсулот очилмайди — белгиси `business:<id>` га ўтади ва
 * шу йўналиш очилганда қайтади.
 */
async function cascadeShopBlock(db, admin, phone12, block) {
  const { FieldValue } = admin.firestore;
  const ts = FieldValue.serverTimestamp();
  // Очишда: дўкон блоки остидаги филиалнинг отаси АЛОҲИДА блокланган бўлса — филиал очилмайди, белгиси отага ўтади.
  let explicit = new Set();
  if (!block) {
    const all = await db.collection(COLLECTION).where('ownerId', '==', phone12).get();
    explicit = new Set(all.docs.filter((d) => {
      const x = d.data() || {};
      return x.status === 'blocked' && x.blockedByParent !== PARENT_SHOP;
    }).map((d) => d.id));
  }
  const businesses = await patchPaged(db, admin, db.collection(COLLECTION).where('ownerId', '==', phone12), (x) => {
    if (block) return x.status === 'blocked' ? null : businessBlockPatch(FieldValue, x, { blockedByParent: PARENT_SHOP });
    if (x.status !== 'blocked' || x.blockedByParent !== PARENT_SHOP) return null;
    if (x.branchOf && explicit.has(x.branchOf)) return { blockedByParent: parentOfBusiness(x.branchOf), updatedAt: ts };
    return businessUnblockPatch(FieldValue, x);
  });
  let stillBlocked = new Set();
  if (!block) {
    const snap = await db.collection(COLLECTION).where('ownerId', '==', phone12).get();
    stillBlocked = new Set(snap.docs.filter((d) => (d.data() || {}).status === 'blocked').map((d) => d.id));
  }
  const items = await patchPaged(db, admin, db.collection(ITEMS).where('ownerPhone', 'in', phoneVariants(phone12)), (x) => {
    if (block) return x.status === 'active' ? { status: 'blocked', blockedByParent: PARENT_SHOP, updatedAt: ts } : null;
    if (x.status !== 'blocked' || x.blockedByParent !== PARENT_SHOP) return null;
    const biz = str(x.businessId, 128);
    if (biz && stillBlocked.has(biz)) return { blockedByParent: parentOfBusiness(biz), updatedAt: ts };
    return { status: 'active', blockedByParent: FieldValue.delete(), updatedAt: ts };
  });
  return { businesses: businesses.updated, products: items.updated };
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

  /**
   * Филиал отаси (транзакция ичида, ёзишдан олдин): мавжуд, ШУ эганики, ўзи филиал эмас (ичма-ич йўқ), ўзи эмас;
   * ўзининг филиаллари бор объект филиал бўлолмайди (`BRANCH_NESTED`). Клиентга ишонилмайди (18-банд).
   */
  async function assertBranch(t, ownerId, fields, selfId) {
    const parentId = fields.branchOf;
    if (!parentId) return;
    if (parentId === selfId) throw fail('invalid-argument', 'BRANCH_INVALID', 'Филиални қайта танланг.');
    const p = await t.get(db.collection(COLLECTION).doc(parentId));
    const x = p.exists ? (p.data() || {}) : null;
    if (!x || x.ownerId !== ownerId || x.branchOf) throw fail('invalid-argument', 'BRANCH_INVALID', 'Филиални қайта танланг.');
    if (selfId) {
      const kids = await t.get(db.collection(COLLECTION).where('branchOf', '==', selfId).limit(1));
      if (!kids.empty) throw fail('failed-precondition', 'BRANCH_NESTED', 'Бу дўконнинг ўз филиаллари бор.');
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
        if (changedKeys(effective(cur), fields).length === 0) return { changed: false };
        if ((fields.branchOf || '') !== (cur.branchOf || '')) await assertBranch(t, uid, fields, ref.id);
        t.update(ref, { ...editPatch(admin.firestore.FieldValue, cur, fields, fail), updatedAt: ts() });
        return { changed: true };
      });
      log({ action: 'upsertMyBusiness', userId: uid, businessId: ref.id, result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
      return { ok: true, businessId: ref.id, ...out };
    }

    const clientRequestId = str(d.clientRequestId, 64);
    if (!ID_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID', 'Қайта уриниб кўринг.');
    const ref = db.collection(COLLECTION).doc(`${uid}_${clientRequestId}`);
    const out = await db.runTransaction(async (t) => {
      const [snap, ownSnap, shopSnap] = await Promise.all([
        t.get(ref),
        t.get(db.collection(COLLECTION).where('ownerId', '==', uid).limit(LIMITS.maxPerOwner)),
        t.get(db.collection(SHOPS).doc(uid)),
      ]);
      if (snap.exists) return { duplicate: true };
      if (isBlocked(shopSnap)) throw fail('permission-denied', 'SHOP_BLOCKED', 'Дўконингиз вақтинча блокланган.');
      if (ownSnap.size >= LIMITS.maxPerOwner) {
        throw fail('resource-exhausted', 'BUSINESS_LIMIT_REACHED',
          `Бир эгада ${LIMITS.maxPerOwner} тадан ортиқ объект бўлмайди.`);
      }
      await assertBranch(t, uid, fields, '');
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
      // Блокдан қочиш йўли ёпилади: ўчириб, қайта очиб бўлмайди (админ ўзи ўчиради).
      if (isBlocked(snap)) throw fail('failed-precondition', 'BUSINESS_BLOCKED', 'Объект вақтинча блокланган.');
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
      const keys = changedKeys(effective(snap.data()), fields);
      if (keys.length === 0) return { changed: false };
      const cur = snap.data() || {};
      if ((fields.branchOf || '') !== (cur.branchOf || '')) await assertBranch(t, cur.ownerId, fields, ref.id);
      t.update(ref, { ...editPatch(admin.firestore.FieldValue, cur, fields, fail), updatedAt: ts(), updatedBy: actor });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_update', actor, target: ref.id, reason, changedKeys: keys, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminUpdateBusiness', userId: actor, businessId: ref.id, result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
    return { ok: true, businessId: ref.id, ...out };
  });

  /**
   * data: { clientRequestId, reason, ownerPhone?, ...майдонлар (upsert билан бир хил) } → { ok, businessId, duplicate }.
   * Эга қарори (2026-10-23): админ ҲАМ объект ҚЎША олади (аввал B-1: фақат таҳрир/ўчириш эди).
   * `ownerPhone` берилса — ёзув шу фойдаланувчиники бўлади (у кейин ўзи таҳрирлайди); берилмаса — `ownerId: 'admin'`
   * (ҳеч бир фойдаланувчи эга эмас, фақат админ таҳрирлайди). Лимит (`maxPerOwner`) админга қўлланмайди.
   * ID `admin_<clientRequestId>` — қайта чақирув такрор яратмайди (21-банд). `admin_audit` (`business_create`).
   */
  exportsObj.adminCreateBusiness = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const d = data || {};
    const reason = reasonOf(d);
    const clientRequestId = str(d.clientRequestId, 64);
    if (!ID_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID', 'Қайта уриниб кўринг.');
    const fields = normalizeInput(d, fail);
    await assertGeo(fields);
    let ownerId = 'admin';
    if (d.ownerPhone != null && String(d.ownerPhone).trim() !== '') {
      ownerId = canonicalUid(String(d.ownerPhone));
      if (!/^\d{12}$/.test(ownerId)) {
        throw fail('invalid-argument', 'BUSINESS_OWNER_INVALID', 'Эга телефони нотўғри.');
      }
    }
    const ref = db.collection(COLLECTION).doc(`admin_${clientRequestId}`);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (snap.exists) return { duplicate: true };
      await assertBranch(t, ownerId, fields, '');
      t.create(ref, {
        ownerId, ...fields, status: 'active', source: 'admin', createdBy: actor, createdAt: ts(), updatedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_create', actor, target: ref.id, reason, ownerId, at: ts(),
      });
      return { duplicate: false };
    });
    log({ action: 'adminCreateBusiness', userId: actor, businessId: ref.id, result: out.duplicate ? 'duplicate' : 'created', durationMs: Date.now() - started });
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

  function statusOf(data) {
    const s = data && data.status;
    if (!BLOCK_STATUSES.includes(s)) throw fail('invalid-argument', 'BUSINESS_STATUS_INVALID', 'Ҳолат нотўғри.');
    return s;
  }

  /**
   * data: { businessId, status: 'active' | 'blocked', reason } → { ok, changed, products }.
   * Йўналиш дўконини блоклайди/очади: харитадан йўқолади (`geohash`лар олинади), маҳсулотлари блокланади.
   * Эгасининг онлайн дўкони блокланган бўлса, йўналишни очиб бўлмайди (`SHOP_BLOCKED`). Каскад ҳар чақирувда
   * юради — тармоқ узилиб қайта чақирилса ярим қолган иш тугайди; audit фақат ҳолат ўзгарганда (21-банд).
   */
  exportsObj.adminSetBusinessStatus = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const status = statusOf(data);
    const ref = db.collection(COLLECTION).doc(docId(data && data.businessId, 'BUSINESS_NOT_FOUND'));
    const { FieldValue } = admin.firestore;
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'BUSINESS_NOT_FOUND', 'Объект топилмади.');
      const cur = snap.data() || {};
      const owner = digitsOf(cur.ownerId);
      if (status === 'active' && owner.length === 12 && isBlocked(await t.get(db.collection(SHOPS).doc(owner)))) {
        throw fail('failed-precondition', 'SHOP_BLOCKED', 'Аввал онлайн дўконнинг блокини олинг.');
      }
      // Филиални отаси блокда турганда алоҳида очиб бўлмайди.
      if (status === 'active' && cur.branchOf && DOC_ID_RE.test(cur.branchOf)
        && isBlocked(await t.get(db.collection(COLLECTION).doc(cur.branchOf)))) {
        throw fail('failed-precondition', 'PARENT_BLOCKED', 'Аввал асосий йўналишнинг блокини олинг.');
      }
      const was = cur.status === 'blocked' ? 'blocked' : 'active';
      // Дўкон блоки остидаги йўналишни админ алоҳида блокласа — белги олинади: дўкон очилганда ҳам блокланган қолади.
      const explicitOverParent = status === 'blocked' && was === 'blocked' && !!cur.blockedByParent;
      if (was === status && !explicitOverParent) return { changed: false, ownerId: cur.ownerId };
      const meta = { blockedAt: ts(), blockedBy: actor, blockReason: reason, blockedByParent: FieldValue.delete() };
      t.update(ref, status === 'blocked'
        ? businessBlockPatch(FieldValue, cur, { ...meta, updatedBy: actor })
        : businessUnblockPatch(FieldValue, cur, { updatedBy: actor }));
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: status === 'blocked' ? 'business_block' : 'business_unblock', actor, target: ref.id, ownerId: cur.ownerId || '', reason, at: ts(),
      });
      return { changed: true, ownerId: cur.ownerId };
    });
    const cascade = await cascadeBusinessBlock(db, admin, ref.id, out.ownerId, status === 'blocked');
    const branches = await cascadeBranchBlock(db, admin, ref.id, status === 'blocked');
    log({
      action: 'adminSetBusinessStatus', userId: actor, businessId: ref.id, result: out.changed ? status : 'noop',
      products: cascade.updated, branches: branches.updated, durationMs: Date.now() - started,
    });
    return { ok: true, changed: out.changed, products: cascade.updated, branches: branches.updated };
  });

  /**
   * data: { ownerPhone, status: 'active' | 'blocked', reason } → { ok, changed, businesses, products }.
   * Бутун онлайн дўкон (`tv_shops/{phone}`): эганинг барча йўналишлари ва маҳсулотлари блокланади/очилади.
   * `tv_shops` ҳужжати бўлмаса блоклашда яратилади (фақат йўналишлари бор эгага ҳам ишлайди). Каскад идемпотент.
   */
  exportsObj.adminSetShopStatus = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const status = statusOf(data);
    const phone = canonicalUid(String((data && data.ownerPhone) || ''));
    if (!/^\d{12}$/.test(phone)) throw fail('invalid-argument', 'SHOP_OWNER_INVALID', 'Эга телефони нотўғри.');
    const ref = db.collection(SHOPS).doc(phone);
    const { FieldValue } = admin.firestore;
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const was = isBlocked(snap) ? 'blocked' : 'active';
      if (status === 'active' && !snap.exists) throw fail('not-found', 'SHOP_NOT_FOUND', 'Дўкон топилмади.');
      if (was === status) return { changed: false };
      if (status === 'blocked') {
        t.set(ref, {
          ownerPhone: phone, status: 'blocked', blockedAt: ts(), blockedBy: actor, blockReason: reason, updatedAt: ts(),
        }, { merge: true });
      } else {
        t.update(ref, {
          status: 'active', blockedAt: FieldValue.delete(), blockedBy: FieldValue.delete(), blockReason: FieldValue.delete(), updatedAt: ts(),
        });
      }
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: status === 'blocked' ? 'shop_block' : 'shop_unblock', actor, target: phone, reason, at: ts(),
      });
      return { changed: true };
    });
    const cascade = await cascadeShopBlock(db, admin, phone, status === 'blocked');
    log({
      action: 'adminSetShopStatus', userId: actor, ownerPhoneTail: phone.slice(-4), result: out.changed ? status : 'noop',
      ...cascade, durationMs: Date.now() - started,
    });
    return { ok: true, changed: out.changed, ...cascade };
  });

  /**
   * Объект ҳужжати ўчирилганда (эга ёки админ) — унинг маҳсулотлари юмшоқ ўчади. Триггер: ўчириш қайси йўл билан
   * бўлмасин бир хил ишлайди ва чақирув ичидаги ярим ишдан ҳимояланган. Хато — `BUSINESS_CASCADE_FAILED` логда.
   */
  exportsObj.businessProductsCascade = functions.firestore
    .document(`${COLLECTION}/{businessId}`)
    .onDelete(async (snap, context) => {
      const t0 = Date.now();
      const businessId = context.params.businessId;
      try {
        const out = await cascadeBusinessProducts(db, admin, businessId, (snap.data() || {}).ownerId);
        // Отаси ўчирилган филиаллар — мустақил йўналиш бўлади (етим `branchOf` қолмасин).
        const FV = admin.firestore.FieldValue;
        const orphans = await patchPaged(db, admin, db.collection(COLLECTION).where('branchOf', '==', businessId),
          () => ({ branchOf: FV.delete(), updatedAt: FV.serverTimestamp() }));
        out.branchesDetached = orphans.updated;
        log({ action: 'businessProductsCascade', businessId, result: out.updated ? 'deleted_products' : 'noop', ...out, durationMs: Date.now() - t0 });
      } catch (e) {
        console.error(JSON.stringify({
          module: 'business_directory', action: 'businessProductsCascade', businessId, result: 'error',
          errorCode: 'BUSINESS_CASCADE_FAILED', message: String((e && e.message) || e).slice(0, 200), durationMs: Date.now() - t0,
        }));
      }
      return null;
    });

  // ───────────────── Маҳсулотлар (эга қарори, 2026-10-24 / 2026-10-25) ─────────────────
  // Маҳсулот — ягона омбор `tv_shop_items/{id}`: эганинг ўз дўкони (`businessId` йўқ) ёки йўналиш дўкони
  // (`businessId`). Эга уни ўзи жойлайди (модерациясиз); админ ИСТАЛГАН маҳсулотни таҳрирлайди/блоклайди/ўчиради
  // (2026-10-25: аввал фақат `businessId`лилари эди — Аҳоли бозорининг янги маҳсулотлари назоратсиз қоларди).
  // Ҳар бир ҳаракат `admin_audit`га сабаби билан тушади (41-банд).

  function itemRefOf(data) {
    return db.collection(ITEMS).doc(docId(data && data.itemId, 'PRODUCT_NOT_FOUND'));
  }

  function assertProduct(snap) {
    if (!snap.exists) throw fail('not-found', 'PRODUCT_NOT_FOUND', 'Маҳсулот топилмади.');
  }

  /** Маҳсулотни очиш мумкинми: унинг йўналиши ва онлайн дўкони блокланмаган бўлиши шарт (транзакция ичида). */
  async function assertParentsOpen(t, cur) {
    const biz = str(cur.businessId, 128);
    const reads = [];
    if (biz && DOC_ID_RE.test(biz)) reads.push(t.get(db.collection(COLLECTION).doc(biz)));
    const owner = digitsOf(cur.ownerPhone);
    const phone = owner.length === 9 ? `998${owner}` : owner;
    if (phone.length === 12) reads.push(t.get(db.collection(SHOPS).doc(phone)));
    const snaps = await Promise.all(reads);
    if (snaps.some(isBlocked)) {
      throw fail('failed-precondition', 'PARENT_BLOCKED', 'Аввал дўкон ёки йўналишнинг блокини олинг.');
    }
  }

  /**
   * data: { itemId, reason, title?, price?, description?, kind?, status? ('active' | 'blocked') } → { ok, changed, changedKeys }.
   * Фақат берилган майдонлар ўзгаради; ўзгариш бўлмаса audit ёзилмайди (идемпотент). Ўчирилган (`deleted`) тикланмайди.
   */
  exportsObj.adminUpdateBusinessProduct = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const d = data || {};
    const reason = reasonOf(d);
    const patch = {};
    if (d.title !== undefined) {
      const v = str(d.title, PRODUCT_LIMITS.titleMax + 1);
      if (v.length < PRODUCT_LIMITS.titleMin || v.length > PRODUCT_LIMITS.titleMax) {
        throw fail('invalid-argument', 'PRODUCT_TITLE_INVALID', 'Ном нотўғри.');
      }
      patch.title = v;
    }
    if (d.description !== undefined) {
      const v = str(d.description, PRODUCT_LIMITS.descriptionMax + 1);
      if (v.length > PRODUCT_LIMITS.descriptionMax) throw fail('invalid-argument', 'PRODUCT_FIELD_INVALID', 'Тавсиф жуда узун.');
      patch.description = v;
    }
    if (d.price !== undefined) {
      const v = d.price;
      if (!Number.isInteger(v) || v < 0 || v > PRODUCT_LIMITS.priceMax) {
        throw fail('invalid-argument', 'PRODUCT_PRICE_INVALID', 'Нарх нотўғри.');
      }
      patch.price = v;
    }
    if (d.kind !== undefined) {
      if (!PRODUCT_KINDS.includes(d.kind)) throw fail('invalid-argument', 'PRODUCT_KIND_INVALID', 'Тур нотўғри.');
      patch.kind = d.kind;
    }
    if (d.status !== undefined) {
      if (!PRODUCT_ADMIN_STATUSES.includes(d.status)) {
        throw fail('invalid-argument', 'PRODUCT_STATUS_INVALID', 'Ҳолат нотўғри.');
      }
      patch.status = d.status;
    }
    if (Object.keys(patch).length === 0) throw fail('invalid-argument', 'PRODUCT_NOTHING_TO_UPDATE', 'Ўзгариш йўқ.');

    const ref = itemRefOf(d);
    const { FieldValue } = admin.firestore;
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      assertProduct(snap);
      const cur = snap.data();
      if (cur.status === 'deleted') throw fail('failed-precondition', 'PRODUCT_DELETED', 'Маҳсулот ўчирилган.');
      if (patch.status === 'active' && cur.status !== 'active') await assertParentsOpen(t, cur);
      const keys = Object.keys(patch).filter((k) => cur[k] !== patch[k]);
      // Ота блоки остидаги маҳсулотни админ алоҳида блокласа — белги олинади (ота очилганда ҳам блокланган қолади).
      const dropMarker = !!cur.blockedByParent && patch.status !== undefined;
      if (keys.length === 0 && !dropMarker) return { changed: false, changedKeys: [] };
      const next = {};
      keys.forEach((k) => { next[k] = patch[k]; });
      if (dropMarker) next.blockedByParent = FieldValue.delete();
      t.update(ref, { ...next, updatedAt: ts(), updatedBy: actor });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_product_update', actor, target: ref.id, businessId: cur.businessId || '', reason,
        changedKeys: dropMarker && !keys.includes('status') ? [...keys, 'status'] : keys, at: ts(),
      });
      return { changed: true, changedKeys: keys };
    });
    log({ action: 'adminUpdateBusinessProduct', userId: actor, itemId: ref.id, result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  /** data: { itemId, reason } → { ok, deleted }. Юмшоқ ўчириш (`status: 'deleted'`); audit'да олдинги ҳолат сақланади. */
  exportsObj.adminDeleteBusinessProduct = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const ref = itemRefOf(data);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      assertProduct(snap);
      const cur = snap.data();
      if (cur.status === 'deleted') return { deleted: false };
      t.update(ref, { status: 'deleted', deletedAt: ts(), deletedBy: actor, updatedAt: ts() });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_product_delete', actor, target: ref.id, businessId: cur.businessId || '', reason,
        snapshot: { title: cur.title || '', ownerPhone: cur.ownerPhone || '', price: cur.price || 0, status: cur.status || '' },
        at: ts(),
      });
      return { deleted: true };
    });
    log({ action: 'adminDeleteBusinessProduct', userId: actor, itemId: ref.id, result: out.deleted ? 'deleted' : 'noop', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  // ───────────────── Харидор шикояти: маҳсулот ёки дўкон (эга қарори 2026-10-25) ─────────────────
  // `reports/{id}` (`type: shop_content`) — фақат шу callable ёзади (rules мижоз ёзишини ёпади); админ
  // «Онлайн дўконлар» бўлимида кўради ва мавжуд `adminResolveDatingReport` билан ёпади. Кунлик чеклов ва
  // очиқ такрорга қарши ҳимоя — мавжуд `submitMarketComplaint` каби (21-банд).

  /**
   * data: { targetType: 'shop_item' | 'shop', targetId, reason (3..300) } → { ok, reportId, duplicate? }.
   * `shop` учун `targetId` — сотувчи телефони (дўкон ҳужжати ID'си). Ўзининг маҳсулоти/дўконига — COMPLAINT_OWN.
   */
  exportsObj.submitShopComplaint = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const d = data || {};
    const targetType = d.targetType;
    if (!COMPLAINT_TARGETS.includes(targetType)) throw fail('invalid-argument', 'COMPLAINT_TARGET_INVALID', 'Шикоят юбориб бўлмади.');
    const reason = str(d.reason, 301);
    if (reason.length < 3 || reason.length > 300) throw fail('invalid-argument', 'REASON_REQUIRED', 'Сабабни ёзинг.');

    let targetId;
    let ownerPhone;
    let businessId = '';
    let title = '';
    if (targetType === 'shop_item') {
      targetId = docId(d.targetId, 'PRODUCT_NOT_FOUND');
      const snap = await db.collection(ITEMS).doc(targetId).get();
      const x = snap.exists ? (snap.data() || {}) : null;
      if (!x || x.status === 'deleted') throw fail('not-found', 'PRODUCT_NOT_FOUND', 'Маҳсулот топилмади.');
      ownerPhone = canonicalUid(String(x.ownerPhone || ''));
      businessId = str(x.businessId, 128);
      title = str(x.title, 120);
    } else {
      targetId = canonicalUid(String(d.targetId || ''));
      if (!/^\d{12}$/.test(targetId)) throw fail('invalid-argument', 'SHOP_OWNER_INVALID', 'Дўкон топилмади.');
      ownerPhone = targetId;
    }
    if (ownerPhone && ownerPhone === uid) throw fail('failed-precondition', 'COMPLAINT_OWN', 'Ўзингизга шикоят қилиб бўлмайди.');

    const reports = db.collection('reports');
    const dayStart = new Date();
    dayStart.setHours(0, 0, 0, 0);
    const today = await reports.where('type', '==', COMPLAINT_TYPE).where('reporterId', '==', uid)
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart)).limit(COMPLAINT_DAILY_LIMIT + 1).get();
    if (today.size >= COMPLAINT_DAILY_LIMIT) throw fail('resource-exhausted', 'COMPLAINT_LIMIT', 'Бугунги шикоятлар чегараси тугади.');
    const open = await reports.where('type', '==', COMPLAINT_TYPE).where('reporterId', '==', uid)
      .where('targetId', '==', targetId).where('status', '==', 'open').limit(1).get();
    if (!open.empty) return { ok: true, reportId: open.docs[0].id, duplicate: true };

    const ref = reports.doc();
    await ref.set({
      type: COMPLAINT_TYPE, targetType, targetId, ownerPhone: ownerPhone || '', businessId, title,
      reporterId: uid, reason, status: 'open', createdAt: ts(),
    });
    log({ action: 'submitShopComplaint', userId: uid, targetType, result: 'created', durationMs: Date.now() - started });
    return { ok: true, reportId: ref.id };
  });
}

module.exports = {
  attachBusinessDirectory, normalizeInput, changedKeys, CATEGORIES, LIMITS, BOUNDS, EDITABLE, PRODUCT_LIMITS,
  cascadeBusinessProducts, cascadeBusinessBlock, cascadeShopBlock, visibleFields, PARENT_SHOP, parentOfBusiness,
  COMPLAINT_TYPE, COMPLAINT_DAILY_LIMIT,
};
