/**
 * KAFE-RESTORAN — taom kuxnalari umumiy ro'yxati (D-REST-24, docs/kafe_restoran_taklifi_uz.md §10.1).
 *
 * `restaurant_cuisines/{id}`: «Milliy» va «Dunyo» — ikkita alohida bo'lim, har kuxna
 * bittasiga tegishli (`group`). Tayyor kuxnalarni admin skripti kiritadi
 * (`tools/seed_restaurant_cuisines.js`, 3 tilda `names`); sotuvchi O'Z nomini qo'shadi
 * («Qashqadaryo milliy taomlari») — shu yerdagi callable.
 *
 * Erkin matn filtrni buzmasligi uchun (bir viloyat «Қашқадарё», «Qashqadaryo», «qashqadaryo»
 * deb uch marta yozilmasin) hujjat identifikatori NOM KALITIDAN hosil bo'ladi:
 * `cuisineKey()` (kichik harf, kirill → lotin, belgi/apostrof olib tashlanadi) →
 * `{group}_{kalit}`. Shu bilan:
 *   - bir xil nom ikkinchi marta yaratilmaydi (idempotent, 21-qoida): bor bo'lsa o'shani qaytaradi;
 *   - parallel chaqiruv — tranzaksiya, bitta g'olib (22-qoida);
 *   - klient hech qachon kalit hisoblamaydi (yagona manba shu fayl, 7-qoida).
 * Suiiste'mol: foydalanuvchi kuniga ≤ DAILY_NEW_LIMIT YANGI nom (Toshkent sanasi);
 * admin nomni yashira oladi (`hidden`, audit — 41-qoida). Birlashtirish (merge) — kelgusi qadam.
 *
 * Diagnostika kodlari (`details.code`): AUTH_REQUIRED, PHONE_TOKEN_REQUIRED,
 * RESTAURANT_ID_REQUIRED, CUISINE_GROUP_INVALID, CUISINE_NAME_INVALID,
 * NOT_RESTAURANT_MEMBER, CUISINE_BLOCKED, CUISINE_RATE_LIMIT, CUISINE_NOT_FOUND, CONTENTION_RETRY.
 * Foydalanuvchi matni klientda, 3 tilda (25-qoida). Log'da nom/telefon YO'Q (24, 40-qoida).
 */
'use strict';

const CUISINES = 'restaurant_cuisines';
const QUOTA = 'restaurant_cuisine_quota';
const RESTAURANTS = 'restaurants';
const MEMBERS = 'members';
const ADMIN_AUDIT = 'admin_audit';
const MODULE_ID = 'restaurants';

const GROUPS = Object.freeze(['national', 'world']);
const NAME_MAX = 40;
/** Bir foydalanuvchi kuniga nechta YANGI kuxna nomi qo'sha oladi (PROPOSED). */
const DAILY_NEW_LIMIT = 5;
const TASHKENT_UTC_OFFSET_H = 5;
/** Hujjat identifikatori uzunligi — `firestore.rules` (`dishCuisineOk`) va klient 80 ni kutadi. */
const ID_MAX = 80;

/** O'zbek kirill → lotin, FAQAT dedup kaliti uchun (ko'rsatish uchun emas). */
const CYR_TO_LAT = Object.freeze({
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z', и: 'i', й: 'y',
  к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f',
  х: 'x', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'shch', ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya',
  ў: 'o', қ: 'q', ғ: 'g', ҳ: 'h', ң: 'ng',
});

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** Ko'rinadigan nom: ortiqcha bo'shliq/boshqaruv belgilari tozalanadi; uzunlik NAME_MAX. */
function cleanName(v) {
  // eslint-disable-next-line no-control-regex
  return str(v, NAME_MAX * 2).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, NAME_MAX).trim();
}

/**
 * Nomning solishtirish kaliti: «Ўзбек» = «O'zbek» = «o‘zbek» → `ozbek`;
 * «Қашқадарё» = «Qashqadaryo» → `qashqadaryo`. Faqat [a-z0-9 ] qoladi.
 */
function cuisineKey(name) {
  let out = '';
  for (const ch of String(name == null ? '' : name).toLowerCase()) {
    out += Object.prototype.hasOwnProperty.call(CYR_TO_LAT, ch) ? CYR_TO_LAT[ch] : ch;
  }
  return out
    .replace(/['ʻʼʽˈ`´‘’′]/g, '') // apostrof/ʻ — ovoz belgisi, kalitda yo'q
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** `{group}_{kalit}` (bo'shliq → '-'), ID_MAX dan oshmaydi. */
function cuisineDocId(group, key) {
  return `${group}_${key.replace(/ /g, '-')}`.slice(0, ID_MAX).replace(/-+$/, '');
}

function tashkentDay(date) {
  return new Date(date.getTime() + TASHKENT_UTC_OFFSET_H * 3600 * 1000).toISOString().slice(0, 10);
}

function attachRestaurantCuisines(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, now: nowFn,
  } = deps;
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });

  function log(action, fields) {
    console.log(JSON.stringify({ module: MODULE_ID, action, ...fields }));
  }

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  /**
   * Sotuvchi o'z kuxna nomini qo'shadi (yoki bor bo'lsa o'shani oladi).
   * data: { restaurantId, name, group: 'national' | 'world' }
   * → { ok, id, name, group, existed }
   */
  exportsObj.restaurantAddCuisine = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const d = data || {};
    const restaurantId = str(d.restaurantId, 64);
    const group = str(d.group, 12);
    const name = cleanName(d.name);
    if (!restaurantId) throw fail('invalid-argument', 'RESTAURANT_ID_REQUIRED');
    if (!GROUPS.includes(group)) throw fail('invalid-argument', 'CUISINE_GROUP_INVALID');
    const key = cuisineKey(name);
    // Kamida bitta harf: «123», «!!», «--» kabi bo'sh nomlar rad.
    if (key.length < 2 || !/[a-z]/.test(key)) throw fail('invalid-argument', 'CUISINE_NAME_INVALID');

    // Faqat restoran a'zosi (autentifikatsiya ≠ avtorizatsiya, 19-qoida).
    const member = await db.collection(RESTAURANTS).doc(restaurantId).collection(MEMBERS).doc(uid).get();
    if (!member.exists) throw fail('permission-denied', 'NOT_RESTAURANT_MEMBER');

    const id = cuisineDocId(group, key);
    const ref = db.collection(CUISINES).doc(id);
    const day = tashkentDay(now());
    const quotaRef = db.collection(QUOTA).doc(`${uid}_${day}`);

    const createOrGet = () => db.runTransaction(async (t) => {
      const [snap, quotaSnap] = await Promise.all([t.get(ref), t.get(quotaRef)]);
      if (snap.exists) {
        const cur = snap.data() || {};
        if (cur.hidden === true) throw fail('failed-precondition', 'CUISINE_BLOCKED');
        return { id, name: str(cur.name, NAME_MAX) || name, group: cur.group || group, existed: true };
      }
      const used = quotaSnap.exists ? (Number((quotaSnap.data() || {}).count) || 0) : 0;
      if (used >= DAILY_NEW_LIMIT) throw fail('resource-exhausted', 'CUISINE_RATE_LIMIT', { limit: DAILY_NEW_LIMIT });
      t.set(ref, {
        name, nameKey: key, group, custom: true, hidden: false,
        createdBy: uid, createdByRestaurantId: restaurantId, createdAt: ts(),
      });
      t.set(quotaRef, { userId: uid, day, count: used + 1, updatedAt: ts() });
      return { id, name, group, existed: false };
    });

    // Parallel chaqiruvlarda tranzaksiya XOM xato bilan yiqilishi mumkin («Transaction is invalid
    // or closed» / contention — emulator ham, server ham). Mantiqiy xatolar (HttpsError) o'z
    // holicha qaytadi; xom xatoda hujjat g'olib tomonidan yaratilgan bo'lsa o'shani qaytaramiz,
    // aks holda 3 martagacha qayta uramiz — natija deterministik (22, 23, 25-qoida).
    let result = null;
    let failure = null;
    for (let attempt = 1; attempt <= 3 && !result && !failure; attempt += 1) {
      try {
        result = await createOrGet();
      } catch (e) {
        if (e instanceof HttpsError) {
          failure = e;
        } else {
          const snap = await ref.get();
          const cur = snap.exists ? (snap.data() || {}) : null;
          if (cur && cur.hidden === true) failure = fail('failed-precondition', 'CUISINE_BLOCKED');
          else if (cur) result = { id, name: str(cur.name, NAME_MAX) || name, group: cur.group || group, existed: true };
          else if (attempt === 3) failure = fail('aborted', 'CONTENTION_RETRY');
        }
      }
    }
    if (failure) {
      log('add_cuisine', {
        restaurantId, userId: uid, group, result: 'denied',
        errorCode: (failure.details && failure.details.code) || 'ABORTED', durationMs: Date.now() - t0,
      });
      throw failure;
    }    log('add_cuisine', {
      restaurantId, userId: uid, cuisineId: result.id, group, result: result.existed ? 'existed' : 'created', durationMs: Date.now() - t0,
    });
    return { ok: true, ...result };
  });

  /**
   * Admin — nomni yashirish/qaytarish (suiiste'mol, 41-qoida: audit).
   * data: { cuisineId, hidden: boolean, reason }. Idempotent.
   */
  exportsObj.adminSetRestaurantCuisineHidden = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const d = data || {};
    const id = str(d.cuisineId, ID_MAX);
    if (!id) throw fail('invalid-argument', 'CUISINE_NOT_FOUND');
    if (typeof d.hidden !== 'boolean') throw fail('invalid-argument', 'HIDDEN_REQUIRED');
    const reason = str(d.reason, 300);
    const ref = db.collection(CUISINES).doc(id);
    const changed = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      if (!s.exists) throw fail('not-found', 'CUISINE_NOT_FOUND');
      if ((s.data() || {}).hidden === d.hidden) return false;
      t.update(ref, { hidden: d.hidden, hiddenAt: ts(), hiddenBy: actor, updatedAt: ts() });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'restaurant_cuisine_hidden', actor, target: id, hidden: d.hidden, reason, at: ts(),
      });
      return true;
    });
    log('admin_cuisine_hidden', { userId: actor, cuisineId: id, hidden: d.hidden, changed, result: 'ok' });
    return { ok: true, hidden: d.hidden, changed };
  });
}

module.exports = {
  attachRestaurantCuisines,
  cuisineKey,
  cuisineDocId,
  cleanName,
  GROUPS,
  DAILY_NEW_LIMIT,
};
