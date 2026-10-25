'use strict';

/**
 * ДЎКОННИНГ ДОИМИЙ ҲАВОЛАСИ ВА QR (эга қарори 2026-10-25, 5-босқич).
 *
 *   https://master-taxi-gurlan.web.app/s/<publicId>
 *
 *  • `publicId` — тасодифий 10 белги (телефон йўқ: `tv_shops/{phone}`, `businesses/{phone}_…` ID'лари ҳаволага
 *    қўйилмайди, 40-банд). Фақат сервер беради (`getMyShopLink`), rules эгага ёзишни ёпади — бировнинг ҳаволасини
 *    эгаллаб бўлмайди. Бир марта берилади ва ЎЗГАРМАЙДИ: дўкон номи ўзгарса ҳам ҳавола ишлайди.
 *  • Онлайн дўкон (`tv_shops`) ёки йўналиш (`businesses`, филиал → отаси) ҳаволаси.
 *  • `/s/<id>` — сервер HTML (Telegram/Facebook превьюси учун OG теглари; `clipPage` каби): дўкон номи, йўналиш,
 *    маҳсулотлар (расм, ном, нарх). Телефон ва манзил КЎРСАТИЛМАЙДИ (меҳмонга, rules билан бир хил). «Веб-иловада
 *    очиш» → `/?shop=<id>` (Flutter web шу дўконни очади), Google Play.
 *  • Блокланган ёки номаълум — хавфсиз «топилмади» саҳифаси (бошқа дўкон эмас), `noindex`.
 *
 * Диагностика: SHOP_LINK_NOT_FOUND, SHOP_BLOCKED, BUSINESS_NOT_FOUND, BUSINESS_BLOCKED.
 */

const crypto = require('crypto');
const page = require('./tv_clip_page');

const SHOPS = 'tv_shops';
const BUSINESSES = 'businesses';
const ITEMS = 'tv_shop_items';
const ID_ALPHABET = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // адаштирадиган 0/O, 1/l/I йўқ
const ID_LEN = 10;
const PUBLIC_ID_RE = /^[A-Za-z0-9]{10}$/;
const PAGE_ITEMS = 12;

function newPublicId() {
  const bytes = crypto.randomBytes(ID_LEN);
  let out = '';
  for (let i = 0; i < ID_LEN; i += 1) out += ID_ALPHABET[bytes[i] % ID_ALPHABET.length];
  return out;
}

const isPublicId = (v) => typeof v === 'string' && PUBLIC_ID_RE.test(v);
const digits = (v) => String(v == null ? '' : v).replace(/\D/g, '');
const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

/** Саҳифа матнлари: ўзбек (кирилл) асосий, рус — браузер тили бўйича. */
const TEXTS = Object.freeze({
  uz: {
    open_web: '🌐 Дўконни очиш',
    open_app: '📲 AVA иловасида очиш',
    apk: 'APK орқали юклаб олиш',
    products: 'Маҳсулотлар',
    empty: 'Ҳозирча маҳсулот йўқ.',
    nf_title: 'Дўкон топилмади',
    nf_desc: 'Бу дўкон мавжуд эмас ёки вақтинча ёпилган.',
    shop: 'Онлайн дўкон',
  },
  ru: {
    open_web: '🌐 Открыть магазин',
    open_app: '📲 Открыть в приложении AVA',
    apk: 'Скачать APK',
    products: 'Товары',
    empty: 'Пока нет товаров.',
    nf_title: 'Магазин не найден',
    nf_desc: 'Этот магазин не существует или временно закрыт.',
    shop: 'Онлайн-магазин',
  },
});

function langOf(acceptLanguage) {
  return /^\s*ru\b/i.test(String(acceptLanguage || '')) ? 'ru' : 'uz';
}

/**
 * Дўкон ҳаволаси саҳифаси (соф функция — тест учун). [items] — фаол маҳсулотлар (title, price, photoUrl).
 */
function buildShopPageHtml({ shopName, directionName, items, pageUrl, webUrl, appUrl, altUrl, lang = 'uz' }) {
  const t = TEXTS[lang] || TEXTS.uz;
  const name = page.escapeHtml(str(shopName, 160) || t.shop);
  const dir = page.escapeHtml(str(directionName, 160));
  const list = Array.isArray(items) ? items.slice(0, PAGE_ITEMS) : [];
  const cover = list.map((i) => page.safeUrl(i.photoUrl)).find(Boolean) || '';
  const ogTitle = dir && dir !== name ? `${name} — ${dir}` : name;
  const ogDesc = page.escapeHtml(list.map((i) => str(i.title, 60)).filter(Boolean).slice(0, 6).join(' · ') || t.shop);
  const url = page.safeUrl(pageUrl);
  const head = [
    '<meta property="og:site_name" content="AVA">',
    '<meta property="og:type" content="website">',
    `<meta property="og:title" content="${ogTitle}">`,
    `<meta property="og:description" content="${ogDesc}">`,
    url ? `<meta property="og:url" content="${url}">` : '',
    cover ? `<meta property="og:image" content="${cover}">` : '',
    cover ? '<meta name="twitter:card" content="summary_large_image">' : '<meta name="twitter:card" content="summary">',
    url ? `<link rel="canonical" href="${url}">` : '',
    '<style>.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:8px 0 18px}'
      + '.card{background:#1a1a1a;border-radius:12px;overflow:hidden}'
      + '.card img{width:100%;aspect-ratio:1/1;object-fit:cover;display:block;background:#111}'
      + '.card .t{font-size:13px;padding:6px 8px 0;line-height:1.3;max-height:2.6em;overflow:hidden}'
      + '.card .p{color:#00e676;font-weight:700;font-size:13px;padding:2px 8px 8px}'
      + '.dir{color:#ffa500;font-weight:700;margin:0 0 10px}</style>',
  ].filter(Boolean).join('\n');
  const cards = list.map((i) => {
    const img = page.safeUrl(i.photoUrl);
    const price = page.formatMoneyUz(i.price);
    return `<div class="card">${img ? `<img src="${img}" alt="" loading="lazy">` : ''}`
      + `<div class="t">${page.escapeHtml(str(i.title, 120))}</div>`
      + `${price ? `<div class="p">${price}</div>` : ''}</div>`;
  }).join('');
  const web = page.safeUrl(webUrl);
  const body = [
    `<h1>${name}</h1>`,
    dir && dir !== name ? `<p class="dir">${dir}</p>` : '',
    web ? `<a class="cta" href="${web}">${t.open_web}</a>` : '',
    `<h1 style="font-size:16px">${t.products}</h1>`,
    cards ? `<div class="grid">${cards}</div>` : `<p class="desc">${t.empty}</p>`,
    page.safeUrl(appUrl) ? `<a class="alt" href="${page.safeUrl(appUrl)}">${t.open_app}</a>` : '',
    page.safeUrl(altUrl) ? `<a class="alt" href="${page.safeUrl(altUrl)}">${t.apk}</a>` : '',
  ].filter(Boolean).join('\n');
  return page.pageShell({ title: ogTitle, description: ogDesc, head, body });
}

function buildShopNotFoundHtml({ appUrl, altUrl, lang = 'uz' }) {
  const t = TEXTS[lang] || TEXTS.uz;
  const head = [
    '<meta property="og:site_name" content="AVA">',
    `<meta property="og:title" content="${t.nf_title}">`,
    `<meta property="og:description" content="${t.nf_desc}">`,
    '<meta name="robots" content="noindex">',
  ].join('\n');
  const body = `<div class="empty"><h1>${t.nf_title}</h1><p class="desc">${t.nf_desc}</p></div>`
    + page.ctaBlock(appUrl, altUrl);
  return page.pageShell({ title: t.nf_title, description: t.nf_desc, head, body });
}

/**
 * Ҳаволани ечиш: `{ available, ownerPhone, businessId, shopName, directionName }`. Блокланган дўкон/йўналиш ёки
 * номаълум — `available: false` (бошқа дўконга олиб бормайди).
 */
async function resolvePublicId(db, publicId) {
  if (!isPublicId(publicId)) return { available: false };
  const [shopSnap, bizSnap] = await Promise.all([
    db.collection(SHOPS).where('publicId', '==', publicId).limit(1).get(),
    db.collection(BUSINESSES).where('publicId', '==', publicId).limit(1).get(),
  ]);
  if (!shopSnap.empty) {
    const d = shopSnap.docs[0];
    const x = d.data() || {};
    if (x.status === 'blocked') return { available: false };
    return { available: true, ownerPhone: d.id, businessId: '', shopName: str(x.name, 160), directionName: '' };
  }
  if (bizSnap.empty) return { available: false };
  const b = bizSnap.docs[0];
  const x = b.data() || {};
  const owner = digits(x.ownerId);
  if (x.status === 'blocked' || owner.length !== 12) return { available: false };
  const shop = await db.collection(SHOPS).doc(owner).get();
  if (shop.exists && (shop.data() || {}).status === 'blocked') return { available: false };
  let directionId = b.id;
  let directionName = str(x.name, 160);
  if (x.branchOf) {
    const p = await db.collection(BUSINESSES).doc(String(x.branchOf)).get();
    const px = p.exists ? (p.data() || {}) : null;
    if (px && px.status !== 'blocked' && digits(px.ownerId) === owner) {
      directionId = p.id;
      directionName = str(px.name, 160);
    }
  }
  return {
    available: true, ownerPhone: owner, businessId: directionId, directionName,
    shopName: shop.exists ? str((shop.data() || {}).name, 160) : '',
  };
}

/** Саҳифа учун маҳсулотлар: эганинг фаол маҳсулотлари, йўналиш бўйича (филиаллари билан). */
async function pageItems(db, resolved) {
  const snap = await db.collection(ITEMS).where('ownerPhone', '==', resolved.ownerPhone)
    .orderBy('createdAt', 'desc').limit(60).get();
  let allowed = null;
  if (resolved.businessId) {
    const kids = await db.collection(BUSINESSES).where('branchOf', '==', resolved.businessId).get();
    allowed = new Set([resolved.businessId, ...kids.docs.map((d) => d.id)]);
  }
  return snap.docs.map((d) => d.data() || {}).filter((x) => {
    if (x.status !== 'active') return false;
    const biz = str(x.businessId, 128);
    return allowed ? allowed.has(biz) : true;
  }).slice(0, PAGE_ITEMS).map((x) => ({
    title: x.title,
    price: x.price,
    photoUrl: (Array.isArray(x.photoUrls) && x.photoUrls[0]) || x.photoUrl || '',
  }));
}

function attachShopLinks(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, publicBase, playUrl, apkUrl,
  } = deps;
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code, message) => new HttpsError(status, message || code, { code });
  const log = (o) => console.log(JSON.stringify({ module: 'shop_links', ...o }));
  const urlOf = (id) => `${publicBase}/s/${id}`;

  async function uniqueId(t) {
    for (let i = 0; i < 5; i += 1) {
      const id = newPublicId();
      const [a, b] = await Promise.all([
        t.get(db.collection(SHOPS).where('publicId', '==', id).limit(1)),
        t.get(db.collection(BUSINESSES).where('publicId', '==', id).limit(1)),
      ]);
      if (a.empty && b.empty) return id;
    }
    throw fail('aborted', 'SHOP_LINK_RETRY', 'Қайта уриниб кўринг.');
  }

  /**
   * data: { businessId? } → { ok, publicId, url }. Эганинг ўз онлайн дўкони ёки ўз йўналиши; ҳавола бир марта
   * берилади (қайта чақирилса — ўша ҳавола, 21-банд). Блокланган дўкон/йўналишга ҳавола берилмайди.
   */
  exportsObj.getMyShopLink = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    const businessId = str(data && data.businessId, 128);
    const out = await db.runTransaction(async (t) => {
      const shopRef = db.collection(SHOPS).doc(uid);
      const shopSnap = await t.get(shopRef);
      if (shopSnap.exists && (shopSnap.data() || {}).status === 'blocked') {
        throw fail('failed-precondition', 'SHOP_BLOCKED', 'Дўконингиз вақтинча блокланган.');
      }
      if (businessId) {
        if (!/^[A-Za-z0-9_-]{1,128}$/.test(businessId)) throw fail('not-found', 'BUSINESS_NOT_FOUND', 'Объект топилмади.');
        const ref = db.collection(BUSINESSES).doc(businessId);
        const snap = await t.get(ref);
        const x = snap.exists ? (snap.data() || {}) : null;
        if (!x || x.ownerId !== uid) throw fail('not-found', 'BUSINESS_NOT_FOUND', 'Объект топилмади.');
        if (x.status === 'blocked') throw fail('failed-precondition', 'BUSINESS_BLOCKED', 'Объект вақтинча блокланган.');
        if (isPublicId(x.publicId)) return { publicId: x.publicId, created: false };
        const id = await uniqueId(t);
        t.update(ref, { publicId: id });
        return { publicId: id, created: true };
      }
      const cur = shopSnap.exists ? (shopSnap.data() || {}) : null;
      if (cur && isPublicId(cur.publicId)) return { publicId: cur.publicId, created: false };
      const id = await uniqueId(t);
      t.set(shopRef, {
        ownerPhone: uid, publicId: id, ...(cur ? {} : { name: '', createdAt: admin.firestore.FieldValue.serverTimestamp() }),
      }, { merge: true });
      return { publicId: id, created: true };
    });
    log({ action: 'getMyShopLink', kind: businessId ? 'business' : 'shop', result: out.created ? 'created' : 'existing', durationMs: Date.now() - started });
    return { ok: true, publicId: out.publicId, url: urlOf(out.publicId) };
  });

  /** data: { publicId } → { ok, available, ownerPhone?, businessId? } (логинсиз; веб-ҳаволадан илова очилганда). */
  exportsObj.resolveShopLink = functions.https.onCall(async (data) => {
    const r = await resolvePublicId(db, str(data && data.publicId, 16));
    return r.available
      ? { ok: true, available: true, ownerPhone: r.ownerPhone, businessId: r.businessId }
      : { ok: true, available: false };
  });

  /** `/s/<publicId>` (hosting rewrite) — сервер HTML. */
  exportsObj.shopPage = functions
    .runWith({ memory: '256MB', timeoutSeconds: 30 })
    .https.onRequest(async (req, res) => {
      const started = Date.now();
      const lang = langOf(req.get && req.get('accept-language'));
      const raw = String(req.path || '').replace(/^\/+|\/+$/g, '');
      const id = raw.split('/').filter(Boolean).pop() || '';
      const notFound = () => {
        res.set('Cache-Control', 'public, max-age=60, s-maxage=60');
        res.status(200).send(buildShopNotFoundHtml({ appUrl: playUrl, altUrl: apkUrl, lang }));
      };
      try {
        const r = await resolvePublicId(db, id);
        if (!r.available) {
          log({ action: 'shopPage', result: 'not_found', durationMs: Date.now() - started });
          notFound();
          return;
        }
        const items = await pageItems(db, r);
        // Манба (6-босқич статистикаси): QR ёки улашилган ҳавола — иловага шу белги билан ўтади.
        const src = req.query && req.query.src === 'qr' ? 'qr' : 'link';
        // Блок тез акс этсин: CDN кэши 5 дақиқа.
        res.set('Cache-Control', 'public, max-age=120, s-maxage=300');
        res.status(200).send(buildShopPageHtml({
          shopName: r.shopName, directionName: r.directionName, items, pageUrl: urlOf(id),
          webUrl: `${publicBase}/?shop=${id}&src=${src}`, appUrl: playUrl, altUrl: apkUrl, lang,
        }));
        log({ action: 'shopPage', result: 'ok', items: items.length, durationMs: Date.now() - started });
      } catch (e) {
        console.error(JSON.stringify({ module: 'shop_links', action: 'shopPage', result: 'error', errorCode: 'SHOP_PAGE_FAILED', message: String((e && e.message) || e).slice(0, 200) }));
        notFound();
      }
    });
}

module.exports = {
  attachShopLinks, resolvePublicId, buildShopPageHtml, buildShopNotFoundHtml, newPublicId, isPublicId, langOf, pageItems,
};
