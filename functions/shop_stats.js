'use strict';

/**
 * СОТУВЧИ СТАТИСТИКАСИ (эга қарори 2026-10-25, 6-босқич). Фақат ЎЛЧАНАДИГАН кўрсаткичлар:
 *
 *   • `shop_view`    — харидор онлайн дўкон саҳифасини очди (йўналиш билан);
 *   • `product_view` — харидор маҳсулот экранини очди;
 *   • манба: market | video | map | link | qr | search | shop | product | other
 *     (`product` = маҳсулотдан дўконга ўтиш; `link`/`qr` = доимий ҳавола/QR орқали келиб, иловада очилган).
 *
 * Санаш қоидаси (сервер, 18-банд): бир харидор × бир объект × бир кун (Тошкент вақти) = 1. Эганинг ўз кўриши
 * саналмайди. Мавжуд бўлмаган/бегона дўкон ёки маҳсулот учун ёзилмайди (бировнинг статистикасини «ифлос» қилиб
 * бўлмайди). Харидор ID'си САҚЛАНМАЙДИ: `shop_stats_seen/{day}_{sha256(uid,day,kind,target)}` — фақат такрорни
 * аниқлаш учун, 3 кундан кейин ўчирилади (`shopStatsSeenCleanup`).
 *
 *   shop_stats/{ownerPhone}_{yyyymmdd} = { ownerPhone, day, shopViews, productViews,
 *     src: {<manba>: n}, shopSrc: {...}, productSrc: {...}, dirs: {<businessId|own>: n}, items: {<itemId>: n} }
 *
 * Ташқи платформалардаги кўришлар (Telegram превьюси, CDN кэшидаги `/s/` саҳифаси) ИШОНЧЛИ ЎЛЧАНМАЙДИ — саналмайди;
 * фақат шу ҳаволадан иловага келган (link/qr) ташриф саналади.
 *
 * КАФЕ-РЕСТОРАН (2026-10-25, Agent C) — ўша callable, ўша санаш ва такрор қоидаси:
 *   • `restaurant_view` — ресторан (меню) экрани очилди; `dish_view` — таом варағи очилди;
 *   • қўшимча манбалар: list (рўйхат) | home (бош саҳифа бўлими) | section (таомлар лентаси/бўлими) |
 *     restaurant (меню ичида);
 *   • ресторан а'золари (эга ва ходимлар — `members/{uid}`) саналмайди; фақат `approved` ресторан ва унинг мавжуд,
 *     сотувдаги таоми саналади;
 *   • сақланиши — ресторан ИЧИДА (ўқиш ҳуқуқи телефонга эмас, а'золикка боғлиқ):
 *     restaurants/{rid}/view_stats/{yyyymmdd} = { restaurantId, day, restaurantViews, dishViews,
 *       src: {<manba>: n}, restaurantSrc: {...}, dishSrc: {...}, items: {<itemId>: n} }
 */

const crypto = require('crypto');

const STATS = 'shop_stats';
const SEEN = 'shop_stats_seen';
const RESTAURANTS = 'restaurants';
const RESTAURANT_STATS = 'view_stats';
const SHOP_KINDS = Object.freeze(['shop_view', 'product_view']);
const RESTAURANT_KINDS = Object.freeze(['restaurant_view', 'dish_view']);
const KINDS = Object.freeze([...SHOP_KINDS, ...RESTAURANT_KINDS]);
const SOURCES = Object.freeze([
  'market', 'video', 'map', 'link', 'qr', 'search', 'shop', 'product', 'other',
  'list', 'home', 'section', 'restaurant',
]);
const SEEN_KEEP_DAYS = 3;
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

const digits = (v) => String(v == null ? '' : v).replace(/\D/g, '');
const canonical = (v) => {
  const d = digits(v);
  return d.length === 9 ? `998${d}` : d;
};

/** Тошкент (UTC+5) куни: `yyyymmdd`. */
function dayKey(ms = Date.now()) {
  return new Date(ms + 5 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, '');
}

function seenId(day, uid, kind, target) {
  const h = crypto.createHash('sha256').update(`${uid}|${day}|${kind}|${target}`).digest('hex').slice(0, 32);
  return `${day}_${h}`;
}

const sourceOf = (v) => (SOURCES.includes(v) ? v : 'other');

function attachShopStats(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid } = deps;
  const log = (o) => console.log(JSON.stringify({ module: 'shop_stats', ...o }));
  const FV = admin.firestore.FieldValue;

  /**
   * Ресторан/таом кўриши (дўкон билан бир хил қоида): бир харидор × бир объект × бир кун = 1; а'зо саналмайди;
   * фақат тасдиқланган ресторан ва унинг мавжуд, сотувдаги таоми.
   */
  async function recordRestaurantEvent(d, context, uid) {
    const kind = d.kind;
    const restaurantId = String(d.restaurantId || '').trim();
    const itemId = String(d.itemId || '').trim();
    if (!ID_RE.test(restaurantId) || (itemId && !ID_RE.test(itemId))) return { ok: false, counted: false, reason: 'id' };
    if (kind === 'dish_view' && !itemId) return { ok: false, counted: false, reason: 'item' };
    let viewer = '';
    try { viewer = canonicalUid(callerPhone(context)) || ''; } catch (_) { viewer = ''; }
    const source = sourceOf(d.source);
    const day = dayKey();
    const target = kind === 'dish_view' ? `r:${restaurantId}:${itemId}` : `r:${restaurantId}`;
    const rRef = db.collection(RESTAURANTS).doc(restaurantId);
    const seenRef = db.collection(SEEN).doc(seenId(day, uid, kind, target));
    const statsRef = rRef.collection(RESTAURANT_STATS).doc(day);

    const result = await db.runTransaction(async (t) => {
      const reads = [t.get(seenRef), t.get(rRef)];
      if (viewer.length === 12) reads.push(t.get(rRef.collection('members').doc(viewer)));
      if (kind === 'dish_view') reads.push(t.get(rRef.collection('menu_items').doc(itemId)));
      const [seen, r, ...rest] = await Promise.all(reads);
      const member = viewer.length === 12 ? rest.shift() : null;
      const item = kind === 'dish_view' ? rest.shift() : null;
      if (member && member.exists) return 'own';
      const rx = r.exists ? (r.data() || {}) : null;
      if (!rx || rx.status !== 'approved') return 'unavailable';
      if (viewer && canonical(rx.ownerUid) === canonical(viewer)) return 'own';
      if (item && (!item.exists || (item.data() || {}).available === false)) return 'unavailable';
      if (seen.exists) return 'seen';
      t.create(seenRef, { day });
      const inc = FV.increment(1);
      // Ичма-ич объект (нуқтали калит эмас) — `set(merge)` уни чуқур бирлаштиради.
      const patch = { restaurantId, day, updatedAt: FV.serverTimestamp(), src: { [source]: inc } };
      if (kind === 'restaurant_view') {
        patch.restaurantViews = inc;
        patch.restaurantSrc = { [source]: inc };
      } else {
        patch.dishViews = inc;
        patch.dishSrc = { [source]: inc };
        patch.items = { [itemId]: inc };
      }
      t.set(statsRef, patch, { merge: true });
      return 'counted';
    });
    const counted = result === 'counted';
    if (counted) log({ action: 'recordShopEvent', kind, restaurantId, source, result: 'counted' });
    return counted ? { ok: true, counted } : { ok: true, counted, reason: result };
  }

  /**
   * data: { kind, ownerPhone, businessId?, itemId?, source? } → { ok, counted }. Логинсиз — ҳисобга олинмайди
   * (такрорни аниқлаб бўлмайди). Хато ҳеч қачон харидорга кўрсатилмайди (клиент жим чақиради).
   */
  exportsObj.recordShopEvent = functions.https.onCall(async (data, context) => {
    const d = data || {};
    const uid = context && context.auth && context.auth.uid;
    if (!uid) return { ok: true, counted: false, reason: 'no_auth' };
    const kind = d.kind;
    if (!KINDS.includes(kind)) return { ok: false, counted: false, reason: 'kind' };
    if (RESTAURANT_KINDS.includes(kind)) return recordRestaurantEvent(d, context, uid);
    const owner = canonical(d.ownerPhone);
    if (owner.length !== 12) return { ok: false, counted: false, reason: 'owner' };
    let viewer = '';
    try { viewer = canonicalUid(callerPhone(context)) || ''; } catch (_) { viewer = ''; }
    if (viewer && canonical(viewer) === owner) return { ok: true, counted: false, reason: 'own' };
    const businessId = String(d.businessId || '').trim();
    const itemId = String(d.itemId || '').trim();
    if ((businessId && !ID_RE.test(businessId)) || (itemId && !ID_RE.test(itemId))) {
      return { ok: false, counted: false, reason: 'id' };
    }
    if (kind === 'product_view' && !itemId) return { ok: false, counted: false, reason: 'item' };
    const source = sourceOf(d.source);
    const day = dayKey();
    const target = kind === 'product_view' ? itemId : (businessId || 'own');
    const seenRef = db.collection(SEEN).doc(seenId(day, uid, kind, `${owner}:${target}`));
    const statsRef = db.collection(STATS).doc(`${owner}_${day}`);

    const counted = await db.runTransaction(async (t) => {
      const seen = await t.get(seenRef);
      if (seen.exists) return false;
      // Объект ҳақиқатан шу эганики ва очиқ бўлсин.
      if (kind === 'product_view') {
        const it = await t.get(db.collection('tv_shop_items').doc(itemId));
        const x = it.exists ? (it.data() || {}) : null;
        if (!x || x.status !== 'active' || canonical(x.ownerPhone) !== owner) return false;
      } else if (businessId) {
        const b = await t.get(db.collection('businesses').doc(businessId));
        const x = b.exists ? (b.data() || {}) : null;
        if (!x || x.status === 'blocked' || canonical(x.ownerId) !== owner) return false;
      } else {
        const s = await t.get(db.collection('tv_shops').doc(owner));
        const x = s.exists ? (s.data() || {}) : null;
        if (x && x.status === 'blocked') return false;
        if (!x) {
          // Онлайн дўкон ҳужжати йўқ бўлиши мумкин (фақат маҳсулот ёки йўналиши бор эга) — бирорта фаол маҳсулоти
          // бўлмаса ёзилмайди (бегона телефонга статистика очилмасин).
          const any = await t.get(db.collection('tv_shop_items').where('ownerPhone', '==', owner).where('status', '==', 'active').limit(1));
          if (any.empty) return false;
        }
      }
      t.create(seenRef, { day });
      const inc = FV.increment(1);
      // `set(..., {merge})` да нуқтали калит йўл ЭМАС (майдон номи бўлиб қолади) — ичма-ич объект, merge уни
      // чуқур бирлаштиради ва `increment` ҳар баргда ишлайди.
      const patch = {
        ownerPhone: owner, day, updatedAt: FV.serverTimestamp(),
        src: { [source]: inc },
      };
      if (kind === 'shop_view') {
        patch.shopViews = inc;
        patch.shopSrc = { [source]: inc };
        patch.dirs = { [businessId || 'own']: inc };
      } else {
        patch.productViews = inc;
        patch.productSrc = { [source]: inc };
        patch.items = { [itemId]: inc };
      }
      t.set(statsRef, patch, { merge: true });
      return true;
    });
    if (counted) log({ action: 'recordShopEvent', kind, source, result: 'counted' });
    return { ok: true, counted };
  });

  /** Такрор белгилари 3 кундан кейин ўчирилади (харидор изи сақланмасин). */
  exportsObj.shopStatsSeenCleanup = functions
    .runWith({ timeoutSeconds: 300, memory: '256MB' })
    .pubsub.schedule('40 3 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const removed = await cleanupSeen(db, dayKey(Date.now() - SEEN_KEEP_DAYS * 86400000));
      log({ action: 'shopStatsSeenCleanup', removed });
      return null;
    });
}

/** [beforeDay]дан олдинги такрор белгиларини ўчириш (сони чекланмаган, 400 тадан). */
async function cleanupSeen(db, beforeDay) {
  let removed = 0;
  for (;;) {
    const snap = await db.collection(SEEN).where('day', '<', beforeDay).limit(400).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    removed += snap.size;
    if (snap.size < 400) break;
  }
  return removed;
}

module.exports = { attachShopStats, dayKey, seenId, cleanupSeen, SOURCES, KINDS, RESTAURANT_KINDS };
