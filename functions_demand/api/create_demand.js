'use strict';

/**
 * 13.2.2 — `createDemand` CALLABLE.
 *
 * Konsepsiyada `onDemandCreated` trigger'i taklif qilingan edi. U
 * `createDemand` callable'i bilan almashtirildi, sabab: validatsiya,
 * limit va moderatsiya YOZISHDAN OLDIN bajarilishi kerak. Trigger esa
 * yozilgandan keyin ishlaydi — ya'ni taqiqlangan talab bir lahza bazada
 * yashab, boshqa triggerlarni ham ishga tushirib yuborardi.
 *
 * Qadamlar (tartib muhim, har biri keyingisining shartini ta'minlaydi):
 *   1) Autentifikatsiya  — kanon telefon ID (veb/Anonymous ruxsat etilmaydi)
 *   2) Kill switch       — global VA modul flaglari
 *   3) Sxema             — klient yubora olmaydigan maydonlar shu yerda kesiladi
 *   4) Idempotentlik     — ikki marta tap -> bitta talab (Т-12)
 *   5) Limitlar          — soxta talab va spam himoyasi
 *   6) Moderatsiya       — taqiqlangan so'zlar
 *   7) Geo muhri         — regionId/districtId SERVERDA (klientdan emas)
 *   8) Yozish            — `demands` + `demands/{id}/private/stats`
 *   9) Matching          — SINXRON (Т-5: Cloud Tasks P0 da ishlatilmaydi)
 *  10) Push              — Notification Policy orqali
 */

const { callerIdFrom, toCanonicalId } = require('../core/ids');
const { resolveFlags } = require('../core/config');
const { validateCreateDemand } = require('../core/schema');
const { getAdapter } = require('../core/registry');
const { STATUS, MATCHING_STATE } = require('../core/state_machine');
const { runMatching } = require('../matching/orchestrator');
const geoHash = require('../geo/geo_hash');

const DEMANDS = 'demands';
const IDEMPOTENCY = 'demand_idempotency';

/** Callable xatosi — `firebase-functions` HttpsError shakliga mos. */
function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  return e;
}

/**
 * @param {object} deps
 * @param {object} deps.db
 * @param {object} deps.admin firebase-admin (FieldValue uchun)
 * @param {object} deps.keywordIndex
 * @param {object} [deps.moderation]
 * @param {Function} [deps.notify] `(db, demand, matchResult) => Promise`
 * @param {Date} [deps.now]
 */
function makeCreateDemand(deps) {
  const {
    db, admin, keywordIndex, moderation, notify, now: nowFn,
  } = deps;

  return async function createDemand(data, context) {
    const now = nowFn ? nowFn() : new Date();

    // ── 1) Autentifikatsiya ────────────────────────────────────────────
    const ownerId = callerIdFrom(context);
    if (!ownerId) {
      // Veb foydalanuvchilari (Anonymous Auth) `phone_number` claim'iga
      // ega emas — Т-2.4 bo'yicha bu ATAYLAB shunday.
      throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    }

    // ── 3) Sxema (2-qadamdan oldin: modulni bilmasdan flag o'qib bo'lmaydi)
    const v = validateCreateDemand(data);
    if (!v.valid) {
      console.warn(`createDemand sxema xatosi (${ownerId}): ${v.errors.join('; ')}`);
      throw fail('invalid-argument', v.errors[0] || 'Yuklama noto\'g\'ri');
    }
    const input = v.value;

    const adapter = getAdapter(input.module);
    if (!adapter) {
      throw fail('unimplemented', `«${input.module}» moduli yadroga hali ulanmagan`);
    }

    // ── 7a) Geo muhri — hududni ANIQLAB OLAMIZ (flaglar hududga bog'liq)
    const geoStamp = await resolveGeoStamp(db, ownerId, input);
    if (!geoStamp.regionId) {
      throw fail('failed-precondition', 'Hududingiz aniqlanmadi — profilni to\'ldiring');
    }

    // ── 2) Kill switch ────────────────────────────────────────────────
    const flags = await resolveFlags(db, input.module, geoStamp.regionId);
    if (!flags.enabled) {
      throw fail(
        'unavailable',
        flags.killReason
          ? 'Xizmat vaqtincha to\'xtatilgan'
          : 'Bu xizmat sizning hududingizda hali ishga tushmagan',
      );
    }
    const config = flags.config;

    // ── 4) Idempotentlik (Т-12) ───────────────────────────────────────
    const idemKey = `${ownerId}_${input.clientRequestId}`;
    const existing = await db.collection(IDEMPOTENCY).doc(idemKey).get();
    if (existing.exists) {
      const d = existing.data() || {};
      const ageMin = (now.getTime() - toMs(d.createdAt)) / 60000;
      if (ageMin <= (config.limits.idempotencyWindowMinutes || 10)) {
        // Ikki marta tap yoki tarmoq qayta urinishi — YANGI talab emas.
        return { demandId: d.demandId, duplicate: true };
      }
    }

    // ── 5) Limitlar ───────────────────────────────────────────────────
    await assertLimits(db, ownerId, config, now);

    // ── 6) Moderatsiya ────────────────────────────────────────────────
    const textForCheck = [input.title, input.description, (input.input || {}).rawText]
      .filter(Boolean).join(' ');
    if (moderation) {
      const m = await moderation.check(textForCheck, config);
      if (m.blocked) {
        await logModeration(db, ownerId, textForCheck, m, now);
        throw fail('invalid-argument', 'Matnda ruxsat etilmagan so\'zlar bor');
      }
    }

    // ── Kategoriya: matndan chiqarish (klient bermasa) ────────────────
    let categoryId = input.categoryId || null;
    let categoryGroup = null;
    if (categoryId) {
      if (!keywordIndex.categoryById.has(categoryId)) {
        throw fail('invalid-argument', `Noma'lum kategoriya: ${categoryId}`);
      }
      categoryGroup = keywordIndex.groupOf.get(categoryId) || null;
    }

    // ── 8) Yozish ─────────────────────────────────────────────────────
    const ref = db.collection(DEMANDS).doc();
    const expiresAt = computeExpiresAt(input.timeWindow, config, now);

    const doc = {
      schemaVersion: input.schemaVersion || 1,
      ownerId,
      module: input.module,
      /** Rejim ADAPTERDAN — klient tanlamaydi. */
      mode: adapter.mode,
      categoryId,
      categoryGroup,

      status: STATUS.ACTIVE,
      matching: {
        state: MATCHING_STATE.PENDING,
        matchedBucket: '0',
        wave: 0,
      },

      source: input.source || 'module',
      input: input.input || {},
      title: input.title || '',
      description: input.description || '',

      location: geoStamp.location,
      destination: geoStamp.destination,

      timeWindow: {
        neededBy: (input.timeWindow || {}).neededBy || null,
        expiresAt,
      },
      budget: input.budget || null,
      quantity: input.quantity == null ? null : input.quantity,
      /** `quantity >= 5` -> ulgurji (konsepsiyada tasdiqlangan chegara). */
      wholesale: Number(input.quantity) >= 5,
      media: { images: ((input.media || {}).images || []), imageEmbedding: null },
      contact: normalizeContact(input.contact),
      attributes: input.attributes || {},
      payerSide: input.payerSide || null,
      termsAcceptedAt: input.termsAcceptedAt || null,

      assignment: { providerId: null, offerId: null, acceptedAt: null },
      /** Tarif versiyasi — keyingi o'zgarish eski buyurtmaga ta'sir qilmaydi. */
      tariffVersion: null,
      payment: null,

      createdAt: now,
      updatedAt: now,
    };

    await ref.set(doc);
    // Aniq `matchedCount` MIJOZGA ko'rinmaydigan joyda (Т-8).
    await ref.collection('private').doc('stats').set({
      matchedCount: 0, candidateCount: 0, rejectedCount: 0, updatedAt: now,
    });
    await db.collection(IDEMPOTENCY).doc(idemKey).set({
      ownerId, demandId: ref.id, module: input.module, createdAt: now,
    });

    const demand = { id: ref.id, ...doc };

    // ── 9) Matching — SINXRON (Т-5) ───────────────────────────────────
    //
    // Konsepsiyada bu Cloud Task edi. P0 da nomzodlar soni kichik
    // (<500, bitta tuman, bitta modul), sinxron hisob ~200 ms oladi va
    // foydalanuvchi uchun sezilmaydi. Buning o'rniga butun bir Cloud
    // Tasks infratuzilmasi kerak bo'lmaydi (loyihada u umuman yo'q).
    let matchResult = null;
    if (flags.matchingEnabled) {
      try {
        matchResult = await runMatching({
          db, demand, config, adapter,
          sources: adapter.sources,
          keywordIndex,
        });
        await ref.update({
          'matching.state': matchResult.state,
          'matching.matchedBucket': matchResult.matchedBucket,
          updatedAt: new Date(),
        });
        await ref.collection('private').doc('stats').set({
          matchedCount: matchResult.matchedCount,
          candidateCount: matchResult.candidateCount,
          rejectedCount: (matchResult.rejected || []).length,
          rejectReasons: countReasons(matchResult.rejected),
          durationMs: matchResult.durationMs,
          updatedAt: new Date(),
        }, { merge: true });
      } catch (e) {
        // Matching yiqilsa TALAB SAQLANIB QOLADI: mijoz ishini qaytadan
        // kiritmaydi. Teskari matching (`onProviderAvailable`) keyinroq
        // uni baribir topadi.
        console.error(`runMatching xatosi (${ref.id}): ${e.stack || e.message}`);
        await ref.update({ 'matching.state': MATCHING_STATE.FAILED });
      }
    }

    // ── 10) Push — faqat Notification Policy orqali ───────────────────
    if (notify && matchResult && matchResult.matchedCount > 0) {
      try {
        await notify(db, demand, matchResult, { flags, config });
      } catch (e) {
        // Push yiqilishi talabni buzmaydi — taklifchilar inbox'da ko'radi.
        console.error(`dispatchNotifications xatosi (${ref.id}): ${e.message}`);
      }
    }

    return {
      demandId: ref.id,
      duplicate: false,
      /** Mijozga ANIQ raqam emas, bucket (Т-8). */
      matchedBucket: matchResult ? matchResult.matchedBucket : '0',
      matchingState: matchResult ? matchResult.state : MATCHING_STATE.PENDING,
    };
  };
}

/**
 * 7-QADAM — GEO MUHRI.
 *
 * `regionId`/`districtId` KLIENTDAN OLINMAYDI. Sabab (repoda allaqachon
 * hal qilingan muammo, `functions/index.js:651` `ownerGeoStamp`):
 * foydalanuvchi o'z talabini istalgan hududga «joylashtirib» qo'ya olardi.
 *
 * Shuning uchun hudud `users/{id}` profilidan, geohash esa klient bergan
 * koordinatadan hisoblanadi (koordinatani soxtalashtirish mumkin, lekin
 * u faqat masofaga ta'sir qiladi, hududga emas).
 */
async function resolveGeoStamp(db, ownerId, input) {
  const snap = await db.collection('users').doc(ownerId).get();
  const u = snap.exists ? (snap.data() || {}) : {};
  const regionId = u.regionId || '';
  const districtId = u.districtId || '';

  const stampPoint = (p) => {
    if (!p || !Number.isFinite(p.lat) || !Number.isFinite(p.lng)) return null;
    return {
      lat: p.lat,
      lng: p.lng,
      geohash: geoHash.encode(p.lat, p.lng, 7),
      regionId,
      districtId,
      addressText: String(p.addressText || '').slice(0, 300),
    };
  };

  return {
    regionId,
    districtId,
    location: stampPoint(input.location) || {
      lat: null, lng: null, geohash: '', regionId, districtId, addressText: '',
    },
    destination: stampPoint(input.destination),
  };
}

/** 5-QADAM — limitlar. Soxta talab va spam himoyasi. */
async function assertLimits(db, ownerId, config, now) {
  const dayAgo = new Date(now.getTime() - 24 * 3600 * 1000);

  const [todaySnap, activeSnap] = await Promise.all([
    db.collection(DEMANDS)
      .where('ownerId', '==', ownerId)
      .where('createdAt', '>=', dayAgo)
      .count().get(),
    db.collection(DEMANDS)
      .where('ownerId', '==', ownerId)
      .where('status', '==', STATUS.ACTIVE)
      .count().get(),
  ]);

  const today = todaySnap.data().count;
  const active = activeSnap.data().count;

  if (today >= config.limits.demandsPerDay) {
    throw fail(
      'resource-exhausted',
      `Kuniga ${config.limits.demandsPerDay} tadan ko'p so'rov yuborib bo'lmaydi`,
    );
  }
  if (active >= config.limits.activeDemands) {
    throw fail(
      'resource-exhausted',
      `Sizda ${active} ta ochiq so'rov bor. Avval ularni yoping`,
    );
  }
}

/** Muddat — `timeWindow` bermasa konfigdagi standart. */
function computeExpiresAt(timeWindow, config, now) {
  const tw = timeWindow || {};
  let minutes = Number(tw.ttlMinutes);
  if (!Number.isFinite(minutes)) {
    if (tw.mode === 'now') minutes = 180;
    else if (tw.mode === 'today') minutes = Math.max(60, minutesUntilEndOfDay(now));
    else minutes = config.defaultTtlMinutes;
  }
  return new Date(now.getTime() + minutes * 60 * 1000);
}

/** Asia/Tashkent bo'yicha kun oxirigacha daqiqa. */
function minutesUntilEndOfDay(now) {
  const local = new Date(now.getTime() + 300 * 60 * 1000);
  const endLocal = Date.UTC(
    local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate(), 23, 59, 0,
  );
  return Math.round((endLocal - local.getTime()) / 60000);
}

/** Qabul qiluvchi telefoni kanon shaklga. */
function normalizeContact(contact) {
  if (!contact) return null;
  const phone = toCanonicalId(contact.recipientPhone || '');
  return {
    recipientName: String(contact.recipientName || '').slice(0, 80),
    recipientPhone: phone || null,
  };
}

async function logModeration(db, ownerId, text, result, now) {
  try {
    await db.collection('complaints').add({
      kind: 'demand_moderation',
      ownerId,
      text: String(text).slice(0, 500),
      matched: result.matched || [],
      status: 'pending',
      createdAt: now,
    });
  } catch (e) {
    console.error(`moderatsiya jurnali yozilmadi: ${e.message}`);
  }
}

function countReasons(rejected) {
  const out = {};
  for (const r of (rejected || [])) {
    out[r.reason] = (out[r.reason] || 0) + 1;
  }
  return out;
}

function toMs(v) {
  if (!v) return 0;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.toDate === 'function') return v.toDate().getTime();
  return Number(v) || 0;
}

module.exports = {
  DEMANDS,
  IDEMPOTENCY,
  makeCreateDemand,
  resolveGeoStamp,
  assertLimits,
  computeExpiresAt,
  normalizeContact,
  minutesUntilEndOfDay,
};
