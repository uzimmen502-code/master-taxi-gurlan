/**
 * УЛГУРЖИ / ХИТОЙ — Excel (.xlsx) орқали товарларни оммавий юклаш (эга қарори 2026-11-19, A).
 *
 * Callable'лар (default codebase, us-central1 — `china_inquiries.js` андозаси):
 *   wholesaleImportTemplate({ market })                              → { fileName, base64 }
 *   wholesaleImportPreview({ market, fileName, fileBase64, clientRequestId })
 *       → { batchId, counts, rows[], quota } — ҳеч қандай товар ЁЗИЛМАЙДИ
 *   wholesaleImportConfirm({ batchId })                              → { status, counts, rows[] }
 *
 * Оқим: файл callable'га base64 бўлиб келади (≤ 5 МБ) — Storage қоидалари ўзгармайди; асл файл
 * сервер томонидан `wholesale_imports/{sellerId}/{batchId}.xlsx` га сақланади (мижоз ўқий олмайди,
 * аудит учун). Confirm файлни Storage'дан ҚАЙТА ўқиб, қайта текширади — мижоз юборган натижага
 * ишонилмайди (18-банд).
 *
 * Ким: фақат ТАСДИҚЛАНГАН ва жўнатиш манзили бор сотувчи (rules `wholesaleProductCreateOk` билан бир хил).
 * Ҳолат: янги товар — `settings/app.wholesaleProductAutoApprove` ёқиқ бўлса `active`, акс ҳолда `pending`
 * (қўлда қўшиш билан бир хил); янгилашда контент ўзгарса — `pending` (сотувчи яширган бўлса `inactive`),
 * ўзгармаса — тегилмайди.
 * Идемпотентлик: товар ID = sha256(sellerId|market|SKU) (`productIdFor`); preview — clientRequestId бўйича;
 * confirm — batch ижара (lease) + ҳар қатор якуний ҳолати; такрорий чақирув қолганини давом эттиради.
 * Чегаралар: ≤ 500 қатор, ≤ 5 МБ, кунига ≤ 10 юклаш (preview санайди, транзакция).
 *
 * Коллекциялар (client-write ЁПИҚ — rules'да match йўқ = рад):
 *   wholesale_imports/{batchId}        — юклаш ёзуви (аудит: ким, қачон, сонлар, хатолар)
 *   wholesale_import_quota/{sellerId}  — { day, count } (Тошкент санаси)
 * Товарга қўшимча майдонлар (фақат сервер ёзади): sku, importBatchId, importedAt, importImages[{src,url}].
 *
 * Диагностика кодлари: SELLER_NOT_APPROVED, SHIP_FROM_REQUIRED, MARKET_INVALID, REQUEST_ID_INVALID,
 * FILE_EMPTY, FILE_TOO_LARGE, FILE_NOT_XLSX, HEADER_MISSING, NO_ROWS, TOO_MANY_ROWS, DAILY_LIMIT,
 * BATCH_NOT_FOUND, BATCH_EXPIRED, BATCH_BUSY, NOT_OWNER, FILE_CHANGED + қатор кодлари (wholesale_import_rules.js).
 */
'use strict';

const crypto = require('crypto');
const R = require('./wholesale_import_rules');
const X = require('./wholesale_import_xlsx');
const moderationModes = require('./moderation_modes');
const IMG = require('./wholesale_import_images');

const BATCHES = 'wholesale_imports';
const QUOTA = 'wholesale_import_quota';
const PRODUCTS = 'wholesale_products';
const SELLERS = 'wholesale_sellers';
const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const BATCH_RE = /^wsi_[a-f0-9]{24}$/;
const LEASE_MS = 9 * 60 * 1000;
const CONFIRM_BUDGET_MS = 470 * 1000; // 540 с timeout ичида захира
const ROW_CONCURRENCY = 4;
const TERMINAL = new Set(['created', 'updated', 'unchanged', 'error']);

/** Firebase Storage юклаб олиш ҳаволаси (клиент `getDownloadURL` шакли; `refFromURL` уни танийди). */
function downloadUrl(bucketName, path, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

/** Ҳаволадан Storage йўли (фақат шу bucket); бўлмаса ''. */
function pathFromDownloadUrl(bucketName, url) {
  const m = String(url || '').match(/^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/([^/]+)\/o\/([^?]+)/);
  if (!m || m[1] !== bucketName) return '';
  try { return decodeURIComponent(m[2]); } catch (_) { return ''; }
}

/** Ҳақиқий Storage (admin SDK). Тестда алмаштирилади. */
function realFileStore(admin) {
  const bucket = () => admin.storage().bucket();
  return {
    async saveFile(path, buf, contentType) {
      await bucket().file(path).save(buf, { resumable: false, contentType, metadata: { cacheControl: 'private, max-age=0' } });
    },
    async readFile(path) {
      const [buf] = await bucket().file(path).download();
      return buf;
    },
    async saveImage(path, buf) {
      const b = bucket();
      const token = crypto.randomUUID();
      await b.file(path).save(buf, {
        resumable: false,
        contentType: 'image/jpeg',
        metadata: { cacheControl: 'public, max-age=31536000', metadata: { firebaseStorageDownloadTokens: token } },
      });
      return downloadUrl(b.name, path, token);
    },
    async deleteByUrl(url, allowedPrefix) {
      const b = bucket();
      const path = pathFromDownloadUrl(b.name, url);
      if (!path || !path.startsWith(allowedPrefix)) return false;
      await b.file(path).delete({ ignoreNotFound: true });
      return true;
    },
  };
}

/** Кичик ҳовуз: [items] ни [n] параллел ишлов билан. */
async function pool(items, n, fn) {
  let i = 0;
  const workers = Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) {
      const idx = i;
      i += 1;
      await fn(items[idx], idx);
    }
  });
  await Promise.all(workers);
}

function attachWholesaleImport(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid } = deps;
  const HttpsError = functions.https.HttpsError;
  const FieldValue = admin.firestore.FieldValue;
  const ts = () => FieldValue.serverTimestamp();
  const fail = (status, code, message, extra = {}) => new HttpsError(status, message || code, { code, ...extra });
  const log = (o) => console.log(JSON.stringify({ module: 'wholesale_import', ...o }));
  const store = deps.fileStore || realFileStore(admin);
  const processImage = deps.processImage || ((url) => IMG.fetchAndProcess(url));
  const now = deps.now || (() => Date.now());

  function requireUser(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    return uid;
  }

  function marketOf(v) {
    const m = String(v == null ? 'wholesale' : v);
    if (!R.MARKETS.includes(m)) throw fail('invalid-argument', 'MARKET_INVALID');
    return m;
  }

  /** Тасдиқланган сотувчи ҳужжати (12 ёки эски 9 хонали ID). */
  async function requireSeller(uid) {
    for (const id of [uid, uid.slice(3)]) {
      const snap = await db.collection(SELLERS).doc(id).get();
      if (!snap.exists) continue;
      const s = snap.data() || {};
      if (s.approvalStatus !== 'approved') break;
      if (!String(s.districtId || '').trim()) {
        throw fail('failed-precondition', 'SHIP_FROM_REQUIRED', 'Аввал жўнатиш манзилини киритинг.');
      }
      return { id, companyName: String(s.companyName || '').trim() };
    }
    throw fail('permission-denied', 'SELLER_NOT_APPROVED', 'Фақат тасдиқланган сотувчи юклай олади.');
  }

  async function autoApproveOn() {
    return moderationModes.readModeAuto(db, 'wholesaleProduct'); // yagona o'quvchi (moderation_modes.js)
  }

  function decodeFile(b64) {
    const s = typeof b64 === 'string' ? b64 : '';
    if (!s) throw fail('invalid-argument', 'FILE_EMPTY');
    if (s.length > Math.ceil((R.LIMITS.maxFileBytes * 4) / 3) + 8) throw fail('invalid-argument', 'FILE_TOO_LARGE');
    const buf = Buffer.from(s, 'base64');
    if (buf.length === 0) throw fail('invalid-argument', 'FILE_EMPTY');
    if (buf.length > R.LIMITS.maxFileBytes) throw fail('invalid-argument', 'FILE_TOO_LARGE');
    return buf;
  }

  /** Файл → текширилган қаторлар + мавжуд товарлар билан солиштириш (ёзишсиз). */
  async function analyse(buf, market, sellerId) {
    const parsed = await X.parseXlsx(buf);
    if (!parsed.ok) return { fileError: parsed.code, rows: [] };
    const v = R.validateSheet(parsed.sheet, market);
    if (v.fileError) return { fileError: v.fileError, missing: v.missing, rows: [] };
    const withSku = v.rows.filter((r) => r.sku && !r.errors.includes('SKU_DUPLICATE'));
    const refs = withSku.map((r) => db.collection(PRODUCTS).doc(R.productIdFor(sellerId, market, r.sku)));
    const snaps = refs.length ? await db.getAll(...refs) : [];
    const existing = new Map();
    snaps.forEach((s, i) => existing.set(withSku[i].row, s.exists ? (s.data() || {}) : null));
    for (const r of v.rows) {
      r.productId = r.sku ? R.productIdFor(sellerId, market, r.sku) : '';
      const e = existing.get(r.row);
      if (e && (e.sellerId !== sellerId || (Array.isArray(e.packs) && e.packs.length > 0))) {
        r.errors.push('SKU_HAS_PACKS');
      }
      r.action = !e ? 'create' : (R.contentChanged(e, r.fields, r.imageSources) ? 'update' : 'unchanged');
    }
    return { rows: v.rows };
  }

  const countsOf = (rows) => {
    const ok = rows.filter((r) => r.errors.length === 0);
    return {
      total: rows.length,
      ready: ok.length,
      errors: rows.length - ok.length,
      create: ok.filter((r) => r.action === 'create').length,
      update: ok.filter((r) => r.action === 'update').length,
      unchanged: ok.filter((r) => r.action === 'unchanged').length,
    };
  };
  const compactRow = (r) => ({
    row: r.row,
    sku: r.sku,
    title: r.fields.title,
    price: r.fields.priceTiers.length ? r.fields.priceTiers[0].price : null,
    action: r.errors.length ? 'error' : r.action,
    errors: r.errors,
  });

  // ───────────────────────── Шаблон ─────────────────────────
  exportsObj.wholesaleImportTemplate = functions.https.onCall(async (data, context) => {
    const uid = requireUser(context);
    const market = marketOf((data || {}).market);
    await requireSeller(uid);
    const buf = await X.buildTemplate(market);
    return { fileName: market === 'china' ? 'ava_china_products.xlsx' : 'ava_ulgurji_products.xlsx', base64: buf.toString('base64') };
  });

  // ───────────────────────── Preview ─────────────────────────
  exportsObj.wholesaleImportPreview = functions.runWith({ timeoutSeconds: 120, memory: '1GB' }).https.onCall(async (data, context) => {
    const started = now();
    const uid = requireUser(context);
    const d = data || {};
    const market = marketOf(d.market);
    const clientRequestId = String(d.clientRequestId || '').trim();
    if (!ID_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID');
    const seller = await requireSeller(uid);
    const batchId = `wsi_${crypto.createHash('sha256').update(`${seller.id}|${clientRequestId}`).digest('hex').slice(0, 24)}`;
    const batchRef = db.collection(BATCHES).doc(batchId);

    const prev = await batchRef.get();
    if (prev.exists && prev.data().preview) {
      const p = prev.data();
      if (p.sellerId !== seller.id) throw fail('permission-denied', 'NOT_OWNER');
      return { batchId, duplicate: true, ...p.preview };
    }

    const buf = decodeFile(d.fileBase64);
    const fileName = String(d.fileName || 'import.xlsx').slice(0, 120);
    const fileSha256 = crypto.createHash('sha256').update(buf).digest('hex');

    // Кунлик чегара — ҳар юклаш (preview) санайди; транзакция = иккита параллел чақирув 11-чисини ўтказмайди.
    const day = R.tashkentDay(now());
    const quotaRef = db.collection(QUOTA).doc(seller.id);
    const q = await db.runTransaction(async (t) => {
      const s = await t.get(quotaRef);
      const step = R.quotaStep(s.exists ? s.data() : null, day);
      if (step.allowed) t.set(quotaRef, { ...step.next, updatedAt: ts() });
      return step;
    });
    if (!q.allowed) {
      log({ action: 'preview', userId: seller.id, result: 'DAILY_LIMIT' });
      throw fail('resource-exhausted', 'DAILY_LIMIT', 'Бугунги юклаш чегараси тугади.', { max: R.LIMITS.maxUploadsPerDay });
    }

    const a = await analyse(buf, market, seller.id);
    const quota = { used: q.count, max: R.LIMITS.maxUploadsPerDay };
    if (a.fileError) {
      await batchRef.set({
        sellerId: seller.id, market, fileName, fileSha256, fileBytes: buf.length, clientRequestId,
        status: 'rejected', fileError: a.fileError, missing: a.missing || [], createdAt: ts(),
      });
      log({ action: 'preview', userId: seller.id, batchId, result: a.fileError, duration: now() - started });
      throw fail('invalid-argument', a.fileError, a.fileError, { missing: a.missing || [], quota });
    }
    const storagePath = `wholesale_imports/${seller.id}/${batchId}.xlsx`;
    await store.saveFile(storagePath, buf, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    const preview = { market, counts: countsOf(a.rows), rows: a.rows.map(compactRow), quota };
    await batchRef.set({
      sellerId: seller.id, market, fileName, fileSha256, fileBytes: buf.length, storagePath, clientRequestId,
      status: 'previewed', preview, createdAt: ts(), createdAtMs: now(),
    });
    log({ action: 'preview', userId: seller.id, batchId, result: 'ok', counts: preview.counts, duration: now() - started });
    return { batchId, duplicate: false, ...preview };
  });

  // ───────────────────────── Confirm ─────────────────────────
  /** Битта қатор: расмлар → товар ёзуви (транзакция). Қайтаради: якуний ҳолат ёки хато коди. */
  async function writeRow(r, ctx) {
    const ref = db.collection(PRODUCTS).doc(r.productId);
    const pre = await ref.get();
    const before = pre.exists ? (pre.data() || {}) : null;
    if (before && (before.sellerId !== ctx.sellerId || (Array.isArray(before.packs) && before.packs.length))) {
      return { status: 'error', codes: ['SKU_HAS_PACKS'] };
    }
    if (before && !R.contentChanged(before, r.fields, r.imageSources)) return { status: 'unchanged' };

    // Расмлар: аввал шу маҳсулот учун ишланган ва ҳали ишлатилаётгани — қайта юклаб олинмайди.
    const cache = new Map();
    if (before && Array.isArray(before.importImages)) {
      const live = new Set(Array.isArray(before.imageUrls) ? before.imageUrls : []);
      for (const x of before.importImages) if (x && x.src && live.has(x.url)) cache.set(x.src, x.url);
    }
    const importImages = [];
    for (const src of r.imageSources) {
      let url = cache.get(src);
      if (!url) {
        try {
          const jpeg = await processImage(src);
          url = await store.saveImage(`${ctx.imagePrefix}${R.imageObjectName(r.productId, src)}`, jpeg);
        } catch (e) {
          return { status: 'error', codes: [e && e.code && /^IMAGE_/.test(e.code) ? e.code : 'IMAGE_FETCH_FAILED'] };
        }
      }
      importImages.push({ src, url });
    }
    const imageUrls = importImages.map((x) => x.url);

    const outcome = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : null;
      const common = {
        ...r.fields,
        imageUrls,
        importImages,
        sku: r.sku,
        importBatchId: ctx.batchId,
        importedAt: ts(),
        updatedAt: ts(),
      };
      if (!cur) {
        const active = ctx.autoApprove;
        t.set(ref, {
          ...common,
          sellerId: ctx.sellerId,
          sellerCompanyName: ctx.companyName,
          status: active ? 'active' : 'pending',
          views: 0,
          videoClipIds: [],
          market: ctx.market,
          createdAt: ts(),
          ...(active ? { publishedAt: ts(), moderatedAt: ts(), moderatedBy: 'auto' } : {}),
        });
        return { status: 'created', old: [] };
      }
      if (cur.sellerId !== ctx.sellerId || (Array.isArray(cur.packs) && cur.packs.length)) {
        return { status: 'error', codes: ['SKU_HAS_PACKS'] };
      }
      if (!R.contentChanged(cur, r.fields, r.imageSources)) return { status: 'unchanged' };
      const patch = { ...common, status: R.statusAfterUpdate(cur.status, !R.moderationChanged(cur, r.fields, r.imageSources)) };
      // Файлда йўқ ихтиёрий майдон — ўчирилади (файл = нарх-варақ манбаи).
      for (const k of ['currency', 'deliveryDays', 'unitWeightG', 'unitDims', 'minOrderQty']) {
        if (!(k in r.fields) && k in cur) patch[k] = FieldValue.delete();
      }
      t.update(ref, patch);
      return { status: 'updated', old: Array.isArray(cur.imageUrls) ? cur.imageUrls : [] };
    });
    if (outcome.status === 'updated') {
      const keep = new Set(imageUrls);
      for (const u of outcome.old) {
        if (keep.has(u)) continue;
        try { await store.deleteByUrl(u, `${ctx.imagePrefix}${r.productId}_`); } catch (_) { /* best-effort */ }
      }
    }
    return { status: outcome.status, codes: outcome.codes };
  }

  exportsObj.wholesaleImportConfirm = functions.runWith({ timeoutSeconds: 540, memory: '1GB' }).https.onCall(async (data, context) => {
    const started = now();
    const uid = requireUser(context);
    const batchId = String((data || {}).batchId || '');
    if (!BATCH_RE.test(batchId)) throw fail('invalid-argument', 'BATCH_NOT_FOUND');
    const seller = await requireSeller(uid);
    const batchRef = db.collection(BATCHES).doc(batchId);

    // Ижара (lease): бир вақтда фақат битта ишлов; якунланган — сақланган натижа қайтади.
    const claim = await db.runTransaction(async (t) => {
      const s = await t.get(batchRef);
      if (!s.exists) throw fail('not-found', 'BATCH_NOT_FOUND');
      const b = s.data() || {};
      if (b.sellerId !== seller.id) throw fail('permission-denied', 'NOT_OWNER');
      if (b.status === 'done') return { done: true, b };
      if (!['previewed', 'partial', 'processing'].includes(b.status)) throw fail('failed-precondition', 'BATCH_NOT_FOUND');
      if (b.status === 'previewed' && now() - Number(b.createdAtMs || 0) > R.LIMITS.batchTtlMs) {
        throw fail('failed-precondition', 'BATCH_EXPIRED', 'Файл эскирди — қайта юкланг.');
      }
      if (b.status === 'processing' && Number(b.leaseUntilMs || 0) > now()) {
        throw fail('aborted', 'BATCH_BUSY', 'Юклаш давом этмоқда.');
      }
      t.update(batchRef, { status: 'processing', leaseUntilMs: now() + LEASE_MS, confirmStartedAt: ts() });
      return { done: false, b };
    });
    if (claim.done) return { batchId, status: 'done', duplicate: true, ...claim.b.result };
    const b = claim.b;

    let rows;
    try {
      const buf = await store.readFile(b.storagePath);
      if (crypto.createHash('sha256').update(buf).digest('hex') !== b.fileSha256) throw fail('failed-precondition', 'FILE_CHANGED');
      const a = await analyse(buf, b.market, seller.id);
      if (a.fileError) throw fail('invalid-argument', a.fileError);
      rows = a.rows;
    } catch (e) {
      await batchRef.update({ status: 'previewed', leaseUntilMs: 0 });
      throw e instanceof HttpsError ? e : fail('internal', 'IMPORT_READ_FAILED');
    }

    const rowStatus = { ...(b.rowStatus || {}) };
    const ctx = {
      batchId,
      sellerId: seller.id,
      companyName: seller.companyName,
      market: b.market,
      autoApprove: await autoApproveOn(),
      imagePrefix: `${PRODUCTS}/${seller.id}/`,
    };
    for (const r of rows) {
      if (r.errors.length) rowStatus[r.row] = { status: 'error', codes: r.errors };
    }
    const todo = rows.filter((r) => !r.errors.length && !(rowStatus[r.row] && TERMINAL.has(rowStatus[r.row].status)));
    const deadline = started + CONFIRM_BUDGET_MS;
    await pool(todo, ROW_CONCURRENCY, async (r) => {
      if (now() > deadline) return;
      try {
        const res = await writeRow(r, ctx);
        rowStatus[r.row] = res.codes ? { status: res.status, codes: res.codes } : { status: res.status };
      } catch (e) {
        log({ action: 'confirm_row', batchId, userId: seller.id, row: r.row, result: 'WRITE_FAILED', errorCode: String(e && e.code || '') });
        rowStatus[r.row] = { status: 'error', codes: ['WRITE_FAILED'] };
      }
    });

    const outRows = rows.map((r) => {
      const st = rowStatus[r.row] || { status: 'pending' };
      return { row: r.row, sku: r.sku, title: r.fields.title, status: st.status, errors: st.codes || [] };
    });
    const counts = { total: outRows.length };
    for (const k of ['created', 'updated', 'unchanged', 'error', 'pending']) counts[k] = outRows.filter((x) => x.status === k).length;
    const status = counts.pending > 0 ? 'partial' : 'done';
    const result = { counts, rows: outRows, autoApprove: ctx.autoApprove };
    await batchRef.update({
      status, rowStatus, result, leaseUntilMs: 0, lastConfirmAt: ts(),
      ...(status === 'done' ? { finishedAt: ts() } : {}),
    });
    log({ action: 'confirm', batchId, userId: seller.id, result: status, counts, duration: now() - started });
    return { batchId, status, duplicate: false, ...result };
  });
}

// realFileStore — «AVA Супермаркет» импорти ҳам шу Storage қатламини ишлатади (дубликат йўқ, 2026-11-21).
module.exports = { attachWholesaleImport, downloadUrl, pathFromDownloadUrl, pool, realFileStore };
