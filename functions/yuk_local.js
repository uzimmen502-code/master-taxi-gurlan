'use strict';

/**
 * Туман ичида юк (`yuk_local_drivers`) — Cloud Functions қисми.
 *
 * Эълон клиентдан тўғридан-тўғри ёзилади (эски APK'лар ҳам), шунинг учун
 * бизнес қоидалари СЕРВЕРДА шу ерда мажбурий қилинади (аудит 2026-10-31,
 * эга қарорлари):
 *
 * - `onYukLocalDriverWrite` (триггер): янги эълон муддати — эганинг биринчи
 *   эълони 60 кун, кейингилари 30 кун (сервер вақтидан, клиент ёзгани
 *   устидан); `phone` = эга рақами; йўқ `districtId` → `''` (ҳудудсизлар
 *   аниқ сўров билан келади); ҳисоб `yuk_local_created_log` га (намуналарни
 *   ўчириш учун).
 * - `renewYukLocalListing` (callable): «Узайтириш» — бугундан +30 кун;
 *   муддат тугашига ≤3 кун қолганда ёки ўтгандан кейин (30 кун ичида).
 * - `yukLocalDailyMaintenance` (ҳар куни 10:00 Тошкент): муддат тугашига 3, 2,
 *   1 кун қолганда эгасига кунига бир марта пуш; муддати 30 кундан олдин
 *   ўтганларни ўчиради.
 * - Намуналар (`isDemo`): шу триггер ишга тушгандан кейин берилган 10 та
 *   ҳақиқий эълон тўпланганда барчаси автоматик ўчирилади.
 * - `refreshYukDemoPresence`: намуналар муддатини фақат керак бўлганда
 *   чўзади ва `updatedAt`ни ЁЗМАЙДИ (аввал ҳар 10 дақиқада барча тингловчиларга
 *   ўзгариш юборарди ва намуналарни рўйхат тепасига чиқарарди).
 *
 * Deploy бирлиги ўзгармаган — index.js require қилади.
 */
const BATCH_LIMIT = 450;
const DAY_MS = 24 * 60 * 60 * 1000;
const DEMO_TTL_MS = 180 * DAY_MS;
/** Намуна муддати шундан кам қолганда чўзилади (кунлик job). */
const DEMO_REFRESH_BEFORE_MS = 30 * DAY_MS;

// Эга қарорлари, 2026-10-31 (CLAUDE.md 46-банд — docs/yuk_local_audit_fix_2026-10-31_uz.md).
const FIRST_LISTING_TTL_MS = 60 * DAY_MS;
// Эга, 2026-10-31 (кейинроқ): кейинги эълонлар 10 → 30 кун.
const NEXT_LISTING_TTL_MS = 30 * DAY_MS;
const RENEW_TTL_MS = 30 * DAY_MS;
const RENEW_WINDOW_MS = 3 * DAY_MS;
const EXPIRED_DELETE_AFTER_MS = 30 * DAY_MS;
const REMIND_DAYS = [3, 2, 1];
const DEMO_DELETE_AFTER_REAL = 10;

const COL = 'yuk_local_drivers';
/** Эски клиент белгиси (`everPublished`) — фақат тарихни аниқлаш учун ўқилади. */
const OWNER_META = 'yuk_local_owner_meta';
/** meta шу эълондан камида шунча олдин яратилган бўлса — эга аввал эълон берган. */
const META_SKEW_MS = 2000;
const OWNER_STATE = 'yuk_local_owner_state';
const CREATED_LOG = 'yuk_local_created_log';
const DEMO_STATE_DOC = 'config/yuk_local_demo';

function digits(v) {
  return String(v || '').replace(/[^\d]/g, '');
}

function canonicalId(v) {
  const d = digits(v);
  return d.length === 9 ? `998${d}` : d;
}

function ms(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts._seconds != null) return Number(ts._seconds) * 1000;
  return 0;
}

/** Муддат тугашига қолган кунлар (юқорига яхлитланган): 2.1 кун → 3. */
function daysLeft(expiresMs, nowMs) {
  return Math.ceil((expiresMs - nowMs) / DAY_MS);
}

function log(fields) {
  console.log(JSON.stringify({ module: 'yuk_local', ...fields }));
}

function createYukLocal(deps) {
  const { db, admin } = deps;
  const { FieldValue, Timestamp } = admin.firestore;

  /**
   * Триггер танаси (тест учун алоҳида). [before]/[after] — DocumentSnapshot.
   * Ўз ёзувидан қайта ишга тушганда ҳеч нарса ёзмайди (фарқ бўлмаса).
   */
  async function onListingWrite(id, before, after) {
    if (!after || !after.exists) return { action: 'deleted' };
    const d = after.data() || {};
    if (d.isDemo === true) return { action: 'demo' };
    const created = !before || !before.exists;
    const ownerId = canonicalId(d.ownerId);
    const patch = {};

    // Эга рақами — ownerId дан (rules ҳам талаб қилади; эски ҳужжатлар учун).
    if (ownerId.length >= 9) {
      const want = `+${ownerId}`;
      if (digits(d.phone) !== ownerId) patch.phone = want;
    }
    if (typeof d.districtId !== 'string') patch.districtId = '';

    let first = null;
    if (created && ownerId.length >= 9) {
      const ref = db.collection(COL).doc(id);
      const createdMs = after.createTime && typeof after.createTime.toMillis === 'function'
        ? after.createTime.toMillis()
        : Date.now();
      const result = await db.runTransaction(async (tx) => {
        const stateRef = db.collection(OWNER_STATE).doc(ownerId);
        const logRef = db.collection(CREATED_LOG).doc(id);
        const [state, logged, others, meta] = await Promise.all([
          tx.get(stateRef),
          tx.get(logRef),
          tx.get(db.collection(COL).where('ownerId', '==', ownerId).limit(5)),
          tx.get(db.collection(OWNER_META).doc(ownerId)),
        ]);
        if (logged.exists) {
          // Триггер қайта чақирилди (retry) — аввалги қарор.
          return { first: logged.data().first === true, retried: true };
        }
        // Сервер ҳолати бўлмаса (триггердан олдинги эгалар) — тарихдан: бошқа
        // эълони бор ёки эски `yuk_local_owner_meta` шу эълондан АВВАЛ яратилган
        // (клиент meta'ни эълондан кейин ёзади — шунинг учун updatedAt эмас,
        // ҳужжат яратилган вақт солиштирилади).
        let isFirst = !state.exists;
        if (isFirst) {
          const hasOther = others.docs.some((x) => x.id !== id);
          const metaEarlier = meta.exists && meta.createTime
            && meta.createTime.toMillis() < createdMs - META_SKEW_MS;
          if (hasOther || metaEarlier) isFirst = false;
        }
        tx.set(stateRef, {
          ownerId,
          listingsCreated: FieldValue.increment(1),
          lastCreatedAt: FieldValue.serverTimestamp(),
          ...(isFirst ? { firstListingId: id, firstListingAt: FieldValue.serverTimestamp() } : {}),
        }, { merge: true });
        tx.set(logRef, { ownerId, first: isFirst, createdAt: FieldValue.serverTimestamp() });
        return { first: isFirst, retried: false };
      });
      first = result.first;
      const baseMs = ms(d.createdAt) || Date.now();
      const want = baseMs + (first ? FIRST_LISTING_TTL_MS : NEXT_LISTING_TTL_MS);
      // Клиент ёзган муддат 1 дақиқадан кўп фарқ қилса — сервер қиймати.
      if (Math.abs(ms(d.expiresAt) - want) > 60 * 1000) {
        patch.expiresAt = Timestamp.fromMillis(want);
      }
      if (Object.keys(patch).length) await ref.update(patch);
      log({ action: 'listingCreated', listingId: id, first, retried: result.retried, patched: Object.keys(patch) });
      await maybeDeleteDemos();
      return { action: 'created', first, patch };
    }

    if (Object.keys(patch).length) {
      await db.collection(COL).doc(id).update(patch);
      log({ action: 'listingNormalized', listingId: id, patched: Object.keys(patch) });
    }
    return { action: 'updated', patch };
  }

  /** 10 та ҳақиқий эълондан кейин намуналар ўчирилади (бир марта). */
  async function maybeDeleteDemos() {
    const stateRef = db.doc(DEMO_STATE_DOC);
    const state = await stateRef.get();
    if (state.exists && state.data().deletedAt) return { skipped: 'already' };
    const agg = await db.collection(CREATED_LOG).count().get();
    const realCount = agg.data().count;
    if (realCount < DEMO_DELETE_AFTER_REAL) return { skipped: 'few', realCount };
    const demos = await db.collection(COL).where('isDemo', '==', true).get();
    let batch = db.batch();
    let n = 0;
    for (const doc of demos.docs) {
      batch.delete(doc.ref);
      n += 1;
      if (n % BATCH_LIMIT === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    batch.set(stateRef, {
      deletedAt: FieldValue.serverTimestamp(),
      deletedCount: demos.size,
      realListingsAtDelete: realCount,
    }, { merge: true });
    await batch.commit();
    log({ action: 'demosDeleted', count: demos.size, realCount });
    return { deleted: demos.size, realCount };
  }

  /** «Узайтириш». [callerId] — токендаги телефон (digits). */
  async function renew(callerId, listingId, nowMs = Date.now()) {
    const id = String(listingId || '').trim();
    const caller = canonicalId(callerId);
    if (!id || caller.length < 9) {
      return { ok: false, code: caller.length < 9 ? 'YUK_RENEW_UNAUTHENTICATED' : 'YUK_RENEW_BAD_INPUT' };
    }
    const ref = db.collection(COL).doc(id);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { ok: false, code: 'YUK_LISTING_NOT_FOUND' };
      const d = snap.data() || {};
      if (d.isDemo === true || canonicalId(d.ownerId) !== caller) {
        return { ok: false, code: 'YUK_RENEW_NOT_OWNER' };
      }
      const exp = ms(d.expiresAt);
      if (exp && exp - nowMs > RENEW_WINDOW_MS) {
        // Аллақачон узайтирилган (қайта босилди) ёки ҳали эрта — ўзгариш йўқ.
        return { ok: false, code: 'YUK_RENEW_TOO_EARLY', expiresAtMs: exp };
      }
      const until = nowMs + RENEW_TTL_MS;
      tx.update(ref, {
        expiresAt: Timestamp.fromMillis(until),
        expiryPushDays: FieldValue.delete(),
        renewCount: FieldValue.increment(1),
        renewedAt: FieldValue.serverTimestamp(),
      });
      return { ok: true, expiresAtMs: until };
    });
  }

  /** Кунлик: 3/2/1 кун пуш + 30 кундан олдин ўтганларни ўчириш. */
  async function runDaily(nowMs = Date.now()) {
    const stats = { reminded: 0, deleted: 0, skipped: 0 };
    const soon = await db.collection(COL)
      .where('expiresAt', '>', Timestamp.fromMillis(nowMs))
      .where('expiresAt', '<=', Timestamp.fromMillis(nowMs + RENEW_WINDOW_MS))
      .get();
    let batch = db.batch();
    let writes = 0;
    async function flush(force) {
      if (writes > 0 && (force || writes >= BATCH_LIMIT)) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    for (const doc of soon.docs) {
      const d = doc.data() || {};
      const owner = canonicalId(d.ownerId);
      const left = daysLeft(ms(d.expiresAt), nowMs);
      const sent = Array.isArray(d.expiryPushDays) ? d.expiryPushDays : [];
      if (d.isDemo === true || owner.length < 9 || !REMIND_DAYS.includes(left) || sent.includes(left)) {
        stats.skipped += 1;
        continue;
      }
      const plate = String(d.plateNumber || '').trim();
      batch.update(doc.ref, { expiryPushDays: FieldValue.arrayUnion(left) });
      batch.set(db.collection('notifications').doc(), {
        targetPhone: owner,
        title: 'Эълон муддати тугамоқда',
        body: `«Туман ичида юк» эълонингиз${plate ? ` (${plate})` : ''} муддати тугашига ${left} кун қолди. Узайтириш учун эълонни очинг.`,
        sent: false,
        type: 'yuk_local_expire_soon',
        screen: 'yuk_local',
        listingId: doc.id,
        daysLeft: left,
        createdAt: FieldValue.serverTimestamp(),
      });
      writes += 2;
      stats.reminded += 1;
      await flush(false);
    }
    await flush(true);

    const old = await db.collection(COL)
      .where('expiresAt', '<', Timestamp.fromMillis(nowMs - EXPIRED_DELETE_AFTER_MS))
      .get();
    for (const doc of old.docs) {
      if ((doc.data() || {}).isDemo === true) continue;
      batch.delete(doc.ref);
      writes += 1;
      stats.deleted += 1;
      await flush(false);
    }
    await flush(true);
    log({ action: 'dailyMaintenance', ...stats });
    return stats;
  }

  /** Намуналар: муддати 30 кундан кам қолса чўзилади; `updatedAt` ёзилмайди. */
  async function refreshDemos(nowMs = Date.now()) {
    const snap = await db.collection(COL).where('isDemo', '==', true).get();
    let batch = db.batch();
    let writes = 0;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      const needTtl = ms(d.expiresAt) - nowMs < DEMO_REFRESH_BEFORE_MS;
      const needHours = d.workStartMinutes !== 0 || d.workEndMinutes !== 24 * 60;
      const legacy = d.online !== undefined || d.lastOnlineAt !== undefined;
      if (!needTtl && !needHours && !legacy) continue;
      batch.set(doc.ref, {
        workStartMinutes: 0,
        workEndMinutes: 24 * 60,
        ...(needTtl ? { expiresAt: Timestamp.fromMillis(nowMs + DEMO_TTL_MS) } : {}),
        online: FieldValue.delete(),
        lastOnlineAt: FieldValue.delete(),
      }, { merge: true });
      writes += 1;
      if (writes >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
    return { total: snap.size };
  }

  return { onListingWrite, maybeDeleteDemos, renew, runDaily, refreshDemos };
}

function attachYukLocal(exportsObj, deps) {
  const { functions } = deps;
  const yuk = createYukLocal(deps);

  exportsObj.refreshYukDemoPresence = functions.pubsub
    .schedule('every 24 hours')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const r = await yuk.refreshDemos();
      log({ action: 'refreshYukDemoPresence', ...r });
      return null;
    });

  if (!functions.firestore || !functions.https) return;

  exportsObj.onYukLocalDriverWrite = functions.firestore
    .document(`${COL}/{id}`)
    .onWrite(async (change, context) => {
      try {
        await yuk.onListingWrite(context.params.id, change.before, change.after);
      } catch (e) {
        log({ action: 'listingWrite', listingId: context.params.id, result: 'error', errorCode: 'YUK_LOCAL_TRIGGER_FAILED', message: e.message || String(e) });
        throw e; // retry ўчиқ бўлса ҳам — лог бор; транзакция idempotent.
      }
    });

  exportsObj.renewYukLocalListing = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const raw = context && context.auth && context.auth.token
      ? context.auth.token.phone_number || ''
      : '';
    if (!context || !context.auth || digits(raw).length < 9) {
      throw new functions.https.HttpsError('unauthenticated', 'Phone sign-in required',
        { code: 'YUK_RENEW_UNAUTHENTICATED' });
    }
    const listingId = String((data && data.listingId) || '');
    const r = await yuk.renew(digits(raw), listingId);
    log({ action: 'renewYukLocalListing', listingId, result: r.ok ? 'ok' : 'rejected', errorCode: r.code || '', durationMs: Date.now() - started });
    if (r.ok) return { ok: true, expiresAtMs: r.expiresAtMs };
    const status = r.code === 'YUK_LISTING_NOT_FOUND' ? 'not-found'
      : r.code === 'YUK_RENEW_NOT_OWNER' ? 'permission-denied'
        : r.code === 'YUK_RENEW_TOO_EARLY' ? 'failed-precondition'
          : 'invalid-argument';
    throw new functions.https.HttpsError(status, r.code, { code: r.code, expiresAtMs: r.expiresAtMs || 0 });
  });

  exportsObj.yukLocalDailyMaintenance = functions.pubsub
    .schedule('every day 10:00')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      await yuk.runDaily();
      return null;
    });
}

module.exports = { attachYukLocal, createYukLocal, daysLeft };
