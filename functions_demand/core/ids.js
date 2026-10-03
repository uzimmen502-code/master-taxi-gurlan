'use strict';

/**
 * 13.1.3 — KANON FOYDALANUVCHI ID.
 *
 * Bu loyihada foydalanuvchi ID = telefon raqami (`users/{998901234567}`),
 * `request.auth.uid` EMAS. Rules `token.phone_number`dan oladi.
 *
 * Muammo: production'da ikkita shakl yonma-yon yashaydi — 9 xonali
 * (`901234567`) va 12 xonali (`998901234567`). `functions/index.js:633`dagi
 * `canonicalUid()` 9 -> 12 ga keltiradi; yadro ayni shu mantiqni ishlatadi,
 * lekin ikkita qo'shimcha bilan:
 *
 *   1) Yadro bazaga FAQAT 12 xonali shaklni yozadi (Т-2). Shuning uchun
 *      `requireCanonicalId` yozishdan oldin qattiq tekshiradi.
 *   2) `demand_matches/{demandId}_{providerId}` kaliti uchun ID da `_`
 *      bo'lmasligi SHART — `isSafeForCompositeKey` shuni kafolatlaydi.
 *
 * Eski 9 xonali hujjatlar MIGRATSIYA QILINMAYDI (strangler pattern):
 * `candidateIdsFor` ikkala shaklni ham o'qishga beradi, yozish esa doim
 * kanon shaklda ketadi.
 */

/** Faqat raqamlar. `+998 90 123-45-67` -> `998901234567`. */
function digits(v) {
  return String(v == null ? '' : v).replace(/\D/g, '');
}

/**
 * Kanon shakl: `998` + 9 raqam (jami 12).
 *
 * 9 xonali -> `998` qo'shiladi. Boshqa uzunlik -> bo'sh satr (noto'g'ri ID
 * jimgina «tuzatilmaydi»: chaqiruvchi xatoni ko'rishi kerak).
 */
function toCanonicalId(v) {
  const d = digits(v);
  if (d.length === 9) return `998${d}`;
  if (d.length === 12 && d.startsWith('998')) return d;
  return '';
}

/** Kanon shaklmi? */
function isCanonicalId(v) {
  return /^998\d{9}$/.test(String(v || ''));
}

/**
 * Yozishdan oldin majburiy tekshiruv. Noto'g'ri bo'lsa xato tashlaydi —
 * bazaga hech qachon 9 xonali yoki chala ID tushmaydi.
 */
function requireCanonicalId(v, fieldName) {
  const id = toCanonicalId(v);
  if (!id) {
    const err = new Error(
      `${fieldName || 'id'}: kanon bo'lmagan foydalanuvchi ID («${v}»). `
      + 'Kutilgan shakl: 998XXXXXXXXX',
    );
    err.code = 'invalid-argument';
    throw err;
  }
  return id;
}

/**
 * Firestore `in` so'rovi uchun ikkala shakl (eski hujjatlarni o'qish uchun).
 * Doim [12 xonali, 9 xonali] tartibida — kanon birinchi.
 */
function candidateIdsFor(v) {
  const canon = toCanonicalId(v);
  if (!canon) return [];
  return [canon, canon.slice(3)];
}

/** Ikkita ID bir odammi (9/12 aralashganda ham)? Rules `phoneDocIdsMatch` bilan bir xil. */
function sameUser(a, b) {
  const ca = toCanonicalId(a);
  const cb = toCanonicalId(b);
  return ca !== '' && ca === cb;
}

/**
 * Composite hujjat kaliti uchun xavfsizmi?
 * `{demandId}_{providerId}` kaliti `_` bo'yicha bo'linadi, shuning uchun
 * bo'laklarning o'zida `_` va `/` bo'lishi mumkin emas.
 */
function isSafeForCompositeKey(v) {
  const s = String(v || '');
  return s.length > 0 && s.length <= 120 && !/[_/]/.test(s);
}

/**
 * `demand_matches` hujjat kaliti.
 *
 * DIQQAT: kalitga ishonib qoidalar yozilmaydi — `providerId` hujjat ichida
 * MAYDON sifatida ham saqlanadi va `allow read` ayni shu maydonni tekshiradi
 * (Т-2.1). Kalit faqat idempotentlik uchun.
 */
function matchKey(demandId, providerId) {
  const pid = requireCanonicalId(providerId, 'providerId');
  if (!isSafeForCompositeKey(demandId)) {
    const err = new Error(`demandId composite kalit uchun xavfsiz emas: «${demandId}»`);
    err.code = 'invalid-argument';
    throw err;
  }
  return `${demandId}_${pid}`;
}

/** `demand_push_log` kaliti — matchKey bilan bir xil shakl. */
function pushLogKey(demandId, providerId) {
  return matchKey(demandId, providerId);
}

/** `provider_capabilities/{uid}_{module}` kaliti. */
function capabilityKey(uid, module) {
  const id = requireCanonicalId(uid, 'uid');
  if (!isSafeForCompositeKey(module)) {
    const err = new Error(`module composite kalit uchun xavfsiz emas: «${module}»`);
    err.code = 'invalid-argument';
    throw err;
  }
  return `${id}_${module}`;
}

/** `module_config/{module}_{regionId}` va `module_tariffs/{module}_{regionId}` kaliti. */
function moduleRegionKey(module, regionId) {
  const m = String(module || '');
  const r = String(regionId || '');
  if (!isSafeForCompositeKey(m) || !isSafeForCompositeKey(r)) {
    const err = new Error(`module/regionId composite kalit uchun xavfsiz emas: «${m}_${r}»`);
    err.code = 'invalid-argument';
    throw err;
  }
  return `${m}_${r}`;
}

/**
 * Callable chaqiruvchisining kanon ID'si.
 *
 * `context.auth.token.phone_number` — yagona ishonchli manba. Veb
 * (Anonymous Auth) foydalanuvchilarida bu claim YO'Q, shuning uchun ular
 * yadroga yozolmaydi (Т-2.4) va bu ataylab shunday.
 */
function callerIdFrom(context) {
  const phone = context
    && context.auth
    && context.auth.token
    && context.auth.token.phone_number;
  return toCanonicalId(phone || '');
}

module.exports = {
  digits,
  toCanonicalId,
  isCanonicalId,
  requireCanonicalId,
  candidateIdsFor,
  sameUser,
  isSafeForCompositeKey,
  matchKey,
  pushLogKey,
  capabilityKey,
  moduleRegionKey,
  callerIdFrom,
};
