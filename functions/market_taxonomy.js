/**
 * «Бозорлар» — `taxonomy/markets` (1-босқич «маълумот асоси», эга 2026-11-15; docs/bozorlar_0_bosqich_2026-11-15_uz.md §4).
 *
 * 4 та янги бозор (мол / мошина / гўшт / деҳқон) учун ягона манба: номлар, шиорлар, бўлимлар (categories),
 * эълон майдонлари (fields) ва рухсат этилган нарх бирликлари (priceUnits). Уй-жой, Улгуржи, Хитой, Аралаш —
 * ўз моделида қолади.
 *
 *   - Ёзиш ФАҚАТ `adminSetMarketTaxonomy` орқали (rules: `taxonomy` write false): версия +1, `taxonomy_history/v{n}`,
 *     `admin_audit` (kind `market_taxonomy_set`) — бир транзакцияда (41-банд).
 *   - Оптимистик қулф: `expectedVersion` жорий версияга тенг бўлмаса → `TAXONOMY_VERSION_CONFLICT` (эски таб бошқа
 *     админ ўзгаришини жимгина қайтармасин).
 *   - Таркиб ўзгармаса версия ОШМАЙДИ (қайта юбориш — идемпотент; `restaurant_seasons.writeVersioned` услуби).
 *   - Бошланғич мазмун: `tools/data/market_taxonomy_v1.json`, ёзиш — `tools/seed_market_taxonomy.js` (DRY RUN сукут).
 *
 * `PRICE_UNITS` — `firestore.rules` `tvShopItemShapeOk` даги `priceUnit` рўйхати билан БИР ХИЛ (тест текширади).
 */
'use strict';

const TAXONOMY_DOC = ['taxonomy', 'markets'];
const HISTORY_COLLECTION = 'taxonomy_history';
const ADMIN_AUDIT = 'admin_audit';
const AUDIT_KIND = 'market_taxonomy_set';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);

const LANGS = Object.freeze(['uz_Cyrl', 'uz_Latn', 'ru']);
const FIELD_TYPES = Object.freeze(['int', 'text', 'select', 'bool', 'date']);
const PRICE_UNITS = Object.freeze(['', 'from', 'hour', 'day', 'month', 'session', 'person', 'kg', 'ton', 'm2', 'piece', 'negotiable']);

const MARKET_ID_RE = /^[a-z][a-z_]{1,29}$/;
const MODULE_ID_RE = /^[a-z][a-z_]{1,39}$/;
const ITEM_ID_RE = /^[a-z][a-z_]{1,29}$/;

const LIMITS = Object.freeze({
  marketName: 60,
  slogan: 300,
  imageUrl: 500,
  categoryName: 40,
  fieldName: 60,
  optionName: 60,
  maxLenMin: 1,
  maxLenMax: 500,
  maxBytes: 200 * 1024,
  maxErrors: 50,
});

const MARKET_KEYS = Object.freeze(['moduleId', 'order', 'names', 'slogan', 'sloganNoOrder', 'imageUrl', 'categories', 'fields', 'priceUnits']);
const CATEGORY_KEYS = Object.freeze(['id', 'names', 'orderable']);
const FIELD_KEYS = Object.freeze(['key', 'type', 'names', 'required', 'min', 'max', 'maxLen', 'options', 'categories']);
const OPTION_KEYS = Object.freeze(['id', 'names']);

const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

function isPlainObject(v) {
  if (v == null || typeof v !== 'object' || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

/** Сатрларни trim қилади (чуқур нусха). Объект/рўйхат бўлмаган қийматлар ўзгармайди. */
function normalizeTaxonomy(v) {
  if (typeof v === 'string') return v.trim();
  if (Array.isArray(v)) return v.map(normalizeTaxonomy);
  if (isPlainObject(v)) {
    const out = {};
    for (const k of Object.keys(v)) out[k] = normalizeTaxonomy(v[k]);
    return out;
  }
  return v;
}

/** Калит тартибидан мустақил JSON (Firestore map тартибини кафолатламайди). */
function stableStringify(v) {
  if (Array.isArray(v)) return `[${v.map(stableStringify).join(',')}]`;
  if (isPlainObject(v)) {
    return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stableStringify(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v === undefined ? null : v);
}

/**
 * Тоза валидатор: `{ ok, errors[] }`. Хато — `'<CODE> <path>'` (масалан `NAME_MISSING markets.meat.names.ru`).
 * Хатолар сони `LIMITS.maxErrors` билан чекланади (callable details ихчам бўлсин).
 */
function validateMarketTaxonomy(obj) {
  const errors = [];
  const err = (code, p) => { if (errors.length < LIMITS.maxErrors) errors.push(p ? `${code} ${p}` : code); };
  const done = () => ({ ok: errors.length === 0, errors });

  if (!isPlainObject(obj)) { err('TAXONOMY_NOT_OBJECT'); return done(); }
  let bytes;
  try {
    bytes = Buffer.byteLength(JSON.stringify(obj), 'utf8');
  } catch (e) {
    err('TAXONOMY_NOT_SERIALIZABLE');
    return done();
  }
  if (bytes > LIMITS.maxBytes) { err('TAXONOMY_TOO_LARGE', `${bytes}`); return done(); }

  for (const k of Object.keys(obj)) if (k !== 'markets') err('UNKNOWN_KEY', k);
  const markets = obj.markets;
  if (!isPlainObject(markets)) { err('MARKETS_MISSING', 'markets'); return done(); }
  const marketIds = Object.keys(markets);
  if (marketIds.length === 0) { err('MARKETS_EMPTY', 'markets'); return done(); }

  const unknownKeys = (o, allowed, p) => {
    for (const k of Object.keys(o)) if (!allowed.includes(k)) err('UNKNOWN_KEY', `${p}.${k}`);
  };
  const localized = (v, p, kind, max) => {
    if (!isPlainObject(v)) { err(`${kind}_MISSING`, p); return; }
    for (const lang of LANGS) {
      const s = v[lang];
      if (typeof s !== 'string' || s.trim().length === 0) err(`${kind}_MISSING`, `${p}.${lang}`);
      else if (s.length > max) err(`${kind}_TOO_LONG`, `${p}.${lang}`);
    }
    for (const k of Object.keys(v)) if (!LANGS.includes(k)) err('UNKNOWN_KEY', `${p}.${k}`);
  };

  const moduleIds = new Set();
  for (const marketId of marketIds) {
    const mp = `markets.${marketId}`;
    if (!MARKET_ID_RE.test(marketId)) err('MARKET_ID_INVALID', mp);
    const m = markets[marketId];
    if (!isPlainObject(m)) { err('MARKET_NOT_OBJECT', mp); continue; }
    unknownKeys(m, MARKET_KEYS, mp);

    if (typeof m.moduleId !== 'string' || !MODULE_ID_RE.test(m.moduleId)) err('MODULE_ID_INVALID', `${mp}.moduleId`);
    else if (moduleIds.has(m.moduleId)) err('MODULE_ID_DUPLICATE', `${mp}.moduleId`);
    else moduleIds.add(m.moduleId);

    if (!Number.isInteger(m.order)) err('ORDER_INVALID', `${mp}.order`);
    localized(m.names, `${mp}.names`, 'NAME', LIMITS.marketName);
    localized(m.slogan, `${mp}.slogan`, 'SLOGAN', LIMITS.slogan);
    if (has(m, 'sloganNoOrder')) localized(m.sloganNoOrder, `${mp}.sloganNoOrder`, 'SLOGAN', LIMITS.slogan);
    if (typeof m.imageUrl !== 'string' || m.imageUrl.length > LIMITS.imageUrl) err('IMAGE_URL_INVALID', `${mp}.imageUrl`);

    // ── categories ──
    const catIds = new Set();
    if (!Array.isArray(m.categories) || m.categories.length === 0) {
      err('CATEGORIES_EMPTY', `${mp}.categories`);
    } else {
      m.categories.forEach((c, i) => {
        const cp = `${mp}.categories[${i}]`;
        if (!isPlainObject(c)) { err('CATEGORY_NOT_OBJECT', cp); return; }
        unknownKeys(c, CATEGORY_KEYS, cp);
        if (typeof c.id !== 'string' || !ITEM_ID_RE.test(c.id)) err('CATEGORY_ID_INVALID', `${cp}.id`);
        else if (catIds.has(c.id)) err('CATEGORY_ID_DUPLICATE', `${cp}.id`);
        else catIds.add(c.id);
        localized(c.names, `${cp}.names`, 'NAME', LIMITS.categoryName);
        if (typeof c.orderable !== 'boolean') err('ORDERABLE_INVALID', `${cp}.orderable`);
      });
    }

    // ── fields ──
    if (!Array.isArray(m.fields)) {
      err('FIELDS_INVALID', `${mp}.fields`);
    } else {
      const fieldKeys = new Set();
      m.fields.forEach((f, i) => {
        const fp = `${mp}.fields[${i}]`;
        if (!isPlainObject(f)) { err('FIELD_NOT_OBJECT', fp); return; }
        unknownKeys(f, FIELD_KEYS, fp);
        if (typeof f.key !== 'string' || !ITEM_ID_RE.test(f.key)) err('FIELD_KEY_INVALID', `${fp}.key`);
        else if (fieldKeys.has(f.key)) err('FIELD_KEY_DUPLICATE', `${fp}.key`);
        else fieldKeys.add(f.key);
        const typeOk = FIELD_TYPES.includes(f.type);
        if (!typeOk) err('FIELD_TYPE_INVALID', `${fp}.type`);
        localized(f.names, `${fp}.names`, 'NAME', LIMITS.fieldName);
        if (typeof f.required !== 'boolean') err('REQUIRED_INVALID', `${fp}.required`);

        // min/max — фақат int
        const hasMin = has(f, 'min');
        const hasMax = has(f, 'max');
        if (hasMin || hasMax) {
          if (typeOk && f.type !== 'int') {
            err('MIN_MAX_NOT_ALLOWED', fp);
          } else {
            if (hasMin && !Number.isInteger(f.min)) err('MIN_INVALID', `${fp}.min`);
            if (hasMax && !Number.isInteger(f.max)) err('MAX_INVALID', `${fp}.max`);
            if (Number.isInteger(f.min) && Number.isInteger(f.max) && f.min > f.max) err('MIN_GT_MAX', fp);
          }
        }
        // maxLen — фақат text
        if (has(f, 'maxLen')) {
          if (typeOk && f.type !== 'text') err('MAXLEN_NOT_ALLOWED', `${fp}.maxLen`);
          else if (!Number.isInteger(f.maxLen) || f.maxLen < LIMITS.maxLenMin || f.maxLen > LIMITS.maxLenMax) {
            err('MAXLEN_INVALID', `${fp}.maxLen`);
          }
        }
        // options — select учун шарт, бошқасида тақиқ
        if (f.type === 'select') {
          if (!Array.isArray(f.options) || f.options.length === 0) {
            err('OPTIONS_MISSING', `${fp}.options`);
          } else {
            const optIds = new Set();
            f.options.forEach((o, j) => {
              const op = `${fp}.options[${j}]`;
              if (!isPlainObject(o)) { err('OPTION_NOT_OBJECT', op); return; }
              unknownKeys(o, OPTION_KEYS, op);
              if (typeof o.id !== 'string' || !ITEM_ID_RE.test(o.id)) err('OPTION_ID_INVALID', `${op}.id`);
              else if (optIds.has(o.id)) err('OPTION_ID_DUPLICATE', `${op}.id`);
              else optIds.add(o.id);
              localized(o.names, `${op}.names`, 'NAME', LIMITS.optionName);
            });
          }
        } else if (has(f, 'options')) {
          err('OPTIONS_NOT_ALLOWED', `${fp}.options`);
        }
        // categories — шу бозорнинг мавжуд бўлимлари
        if (has(f, 'categories')) {
          if (!Array.isArray(f.categories) || f.categories.length === 0) {
            err('FIELD_CATEGORIES_INVALID', `${fp}.categories`);
          } else {
            const seen = new Set();
            f.categories.forEach((cid, j) => {
              if (typeof cid !== 'string' || !catIds.has(cid)) err('FIELD_CATEGORY_UNKNOWN', `${fp}.categories[${j}]`);
              else if (seen.has(cid)) err('FIELD_CATEGORY_DUPLICATE', `${fp}.categories[${j}]`);
              else seen.add(cid);
            });
          }
        }
      });
    }

    // ── priceUnits ──
    if (!Array.isArray(m.priceUnits) || m.priceUnits.length === 0) {
      err('PRICE_UNITS_EMPTY', `${mp}.priceUnits`);
    } else {
      const seen = new Set();
      m.priceUnits.forEach((u, i) => {
        if (typeof u !== 'string' || !PRICE_UNITS.includes(u)) err('PRICE_UNIT_INVALID', `${mp}.priceUnits[${i}]`);
        else if (seen.has(u)) err('PRICE_UNIT_DUPLICATE', `${mp}.priceUnits[${i}]`);
        else seen.add(u);
      });
    }
  }
  return done();
}

/**
 * Битта версия учун ёзиладиган учта ҳужжат (callable ва seed скрипти бир хил шаклда ёзсин — 7-банд).
 * `ts` — serverTimestamp қиймати.
 */
function buildVersionDocs({ markets, version, previousVersion, actor, ts }) {
  const doc = { markets, version, updatedAt: ts, updatedBy: actor };
  return {
    doc,
    history: { ...doc, previousVersion: previousVersion == null ? null : previousVersion },
    audit: { kind: AUDIT_KIND, actor, target: `v${version}`, version, at: ts },
  };
}

function attachMarketTaxonomy(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: 'market_taxonomy', action: 'adminSetMarketTaxonomy', ...fields }));

  /**
   * Admin — бозорлар таксономиясини ТЎЛИҚ алмаштиради.
   * data: { taxonomy: { markets: {...} }, expectedVersion: int (ҳужжат йўқ бўлса 0) }
   * Жавоб: { ok, version, changed }
   */
  exportsObj.adminSetMarketTaxonomy = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const expectedVersion = data ? data.expectedVersion : undefined;
    if (!Number.isInteger(expectedVersion) || expectedVersion < 0) {
      log({ result: 'error', errorCode: 'EXPECTED_VERSION_INVALID', userId: actor, duration: Date.now() - started });
      throw fail('invalid-argument', 'EXPECTED_VERSION_INVALID');
    }
    const taxonomy = normalizeTaxonomy(data ? data.taxonomy : undefined);
    const v = validateMarketTaxonomy(taxonomy);
    if (!v.ok) {
      log({ result: 'error', errorCode: 'TAXONOMY_INVALID', userId: actor, errorCount: v.errors.length, duration: Date.now() - started });
      throw fail('invalid-argument', 'TAXONOMY_INVALID', { errors: v.errors });
    }
    const markets = taxonomy.markets;
    const ref = db.collection(TAXONOMY_DOC[0]).doc(TAXONOMY_DOC[1]);

    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const cur = snap.exists ? (snap.data() || {}) : {};
        const currentVersion = Number.isInteger(cur.version) ? cur.version : 0;
        const same = snap.exists && stableStringify(cur.markets) === stableStringify(markets);
        // Қайта юбориш (жавоб йўқолган): аввалги чақирув шу таркибни аллақачон ёзган.
        if (same && (expectedVersion === currentVersion || expectedVersion + 1 === currentVersion)) {
          return { version: currentVersion, changed: false };
        }
        if (expectedVersion !== currentVersion) {
          throw fail('failed-precondition', 'TAXONOMY_VERSION_CONFLICT', { currentVersion });
        }
        const version = currentVersion + 1;
        const docs = buildVersionDocs({
          markets, version, previousVersion: snap.exists ? currentVersion : null, actor, ts: ts(),
        });
        t.set(ref, docs.doc);
        t.create(db.collection(HISTORY_COLLECTION).doc(`v${version}`), docs.history);
        t.set(db.collection(ADMIN_AUDIT).doc(), docs.audit);
        return { version, changed: true };
      });
    } catch (e) {
      const code = (e && e.details && e.details.code) || 'INTERNAL';
      log({ result: 'error', errorCode: code, userId: actor, expectedVersion, duration: Date.now() - started });
      if (e instanceof HttpsError) throw e;
      throw fail('internal', 'TAXONOMY_WRITE_FAILED');
    }
    log({
      result: 'ok', userId: actor, version: out.version, changed: out.changed,
      markets: Object.keys(markets).length, duration: Date.now() - started,
    });
    return { ok: true, ...out };
  });
}

module.exports = {
  attachMarketTaxonomy,
  validateMarketTaxonomy,
  normalizeTaxonomy,
  stableStringify,
  buildVersionDocs,
  TAXONOMY_DOC,
  HISTORY_COLLECTION,
  AUDIT_KIND,
  PRICE_UNITS,
  LANGS,
  FIELD_TYPES,
  LIMITS,
};
