'use strict';

/**
 * Т-7 — NOTIFICATION POLICY.
 *
 * KONSEPSIYANING ENG MUHIM G'OYASI: «ko'rinish» va «push» ikki xil narsa.
 *
 *   KO'RINISH — barcha mos taklifchi talabni DARHOL `demand_matches`da
 *               ko'radi. Bu yerda hech qanday limit YO'Q va bo'lmaydi.
 *   PUSH      — telefonni ovoz bilan jiringlatish. BU chegaralanadi.
 *
 * Konsepsiyada «quote rejimida kunlik limit yo'q» deb yozilgan edi. Urganch
 * hajmida keng imkoniyatli sotuvchi kunda 20-40 push oladi -> push'ni
 * o'chiradi yoki ilovani o'chiradi. Konsepsiyaning o'zi buni xavf sifatida
 * tan oladi (`push o'chirish ulushi` ko'rsatkichi), lekin himoya qo'ymaydi.
 *
 * Shuning uchun: soatlik va kunlik limit + limitdan oshganlar DAYJESTGA.
 * Taklifchi talabni baribir ko'radi, faqat telefon jiringlamaydi.
 *
 * dispatch rejimi istisno: bitta kuryer kerak, har soniya muhim -> limitsiz.
 */

/** Push qaroriga sabab kodlari (analitika uchun — Т-22). */
const REASON = {
  SEND: 'send',
  DIGEST: 'digest',
  ALREADY_SENT: 'already_sent',
  PUSH_DISABLED_GLOBAL: 'push_disabled_global',
  PUSH_DISABLED_MODULE: 'push_disabled_module',
  PUSH_DISABLED_BY_PROVIDER: 'push_disabled_by_provider',
  QUIET_HOURS: 'quiet_hours',
  HOURLY_LIMIT: 'hourly_limit',
  DAILY_LIMIT: 'daily_limit',
  NO_TOKEN: 'no_token',
  SEEN_ALREADY: 'seen_already',
  /** Moslik bor, lekin score `push.minScore` dan past — push yo'q, ko'rinish saqlanadi. */
  BELOW_MIN_SCORE: 'below_min_score',
  /** `push.minScore` hali o'lchab tanlanmagan (null) — quote/alert push ketmaydi. */
  SCORE_NOT_CALIBRATED: 'score_not_calibrated',
};

/**
 * Asia/Tashkent bo'yicha soat.
 *
 * Server UTC'da ishlaydi. Repoda `timezone` paketi FAQAT Dart tomonda bor,
 * shuning uchun serverda offset qo'lda (+05:00). O'zbekistonda yozgi vaqt
 * yo'q, shuning uchun doimiy offset to'g'ri ishlaydi.
 */
function localHour(date, offsetMinutes = 300) {
  const ms = date.getTime() + offsetMinutes * 60 * 1000;
  return new Date(ms).getUTCHours();
}

/**
 * Tinch soatlar ichidami.
 *
 * `from: 23, to: 7` — yarim kechadan o'tadigan oraliq, shuning uchun
 * oddiy `>=` va `<` yetmaydi.
 */
function inQuietHours(date, quietHours) {
  const q = quietHours || {};
  const from = Number(q.from);
  const to = Number(q.to);
  if (!Number.isFinite(from) || !Number.isFinite(to) || from === to) return false;
  const h = localHour(date, q.timezoneOffsetMinutes);
  return from < to ? (h >= from && h < to) : (h >= from || h < to);
}

/**
 * Tinch soatlar tugashi — dayjest qachon yuborilishi.
 * «Ertalab dayjest» (Т-7) ayni shu vaqtda ketadi.
 */
function quietHoursEndAt(date, quietHours) {
  const q = quietHours || {};
  const offset = Number.isFinite(q.timezoneOffsetMinutes) ? q.timezoneOffsetMinutes : 300;
  const to = Number(q.to);
  if (!Number.isFinite(to)) return date;
  const local = new Date(date.getTime() + offset * 60 * 1000);
  const next = new Date(Date.UTC(
    local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate(), to, 0, 0, 0,
  ));
  if (next.getTime() <= local.getTime()) next.setUTCDate(next.getUTCDate() + 1);
  return new Date(next.getTime() - offset * 60 * 1000);
}

/** Rejim uchun push limiti. dispatch -> limitsiz. */
function limitsForMode(mode, config) {
  const p = (config && config.push) || {};
  const l = p[mode] || p.quote || { perHour: 5, perDay: 20 };
  return {
    perHour: Number(l.perHour) || 0,
    perDay: Number(l.perDay) || 0,
  };
}

/**
 * PUSH QARORI — sof funksiya, Firestore'ga tegmaydi.
 *
 * @param {object} input
 * @param {string} input.mode              dispatch | quote | alert | recurring
 * @param {object} input.config            module_config
 * @param {boolean} input.pushEnabled      global VA modul flagi natijasi
 * @param {object} input.provider          taklifchi holati
 * @param {boolean} input.provider.moduleOptOut   shu modulda push'ni o'chirgan
 * @param {boolean} input.provider.digestOnly     «faqat kechki dayjest» tanlagan
 * @param {boolean} input.provider.hasToken       FCM tokeni bormi
 * @param {number}  input.provider.sentLastHour   oxirgi 1 soatda nechta push
 * @param {number}  input.provider.sentToday      bugun nechta push
 * @param {boolean} input.alreadyLogged    `demand_push_log`da yozuv bormi
 * @param {boolean} input.alreadySeen      taklifchi talabni allaqachon ko'rganmi
 * @param {number}  [input.score]          moslikning yakuniy score'i (0..1);
 *                                         dispatch'dan boshqa rejimlarda `push.minScore` bilan solishtiriladi
 * @param {Date}    input.now
 * @returns {{send: boolean, digest: boolean, reason: string, retryAt: Date|null}}
 */
function decidePush(input) {
  const {
    mode, config, pushEnabled, provider = {},
    alreadyLogged = false, alreadySeen = false,
    score,
    now = new Date(),
  } = input;

  // 1) Idempotentlik eng oldin: «Bir taklifchiga bir talab bo'yicha bitta
  //    push, hech qachon takrorlanmaydi» (konsepsiya, qat'iy qoida).
  if (alreadyLogged) {
    return { send: false, digest: false, reason: REASON.ALREADY_SENT, retryAt: null };
  }

  // 2) Kill switch.
  if (!pushEnabled) {
    return {
      send: false,
      digest: false,
      reason: REASON.PUSH_DISABLED_MODULE,
      retryAt: null,
    };
  }

  // 3) Taklifchining o'z qarori — har qanday limitdan ustun.
  if (provider.moduleOptOut) {
    return {
      send: false, digest: false, reason: REASON.PUSH_DISABLED_BY_PROVIDER, retryAt: null,
    };
  }

  // 4) Talabni allaqachon ko'rgan odamni jiringlatmaymiz.
  if (alreadySeen) {
    return { send: false, digest: false, reason: REASON.SEEN_ALREADY, retryAt: null };
  }

  // 5) Token yo'q -> yuborib bo'lmaydi (inbox'da baribir ko'rinadi).
  if (provider.hasToken === false) {
    return { send: false, digest: false, reason: REASON.NO_TOKEN, retryAt: null };
  }

  // 6) dispatch — limitsiz, yuqori prioritet, tinch soatlar ham to'xtatmaydi.
  //    Sabab: mijoz hozir kutib turibdi, 136 kishiga «kech qoldingiz»
  //    yubormaslik uchun to'lqinlar bor (bu limitning o'rnini bosadi).
  if (mode === 'dispatch') {
    return { send: true, digest: false, reason: REASON.SEND, retryAt: null };
  }

  // 6-bis) HAR MOSLIK UCHUN PUSH CHEGARASI (ega 2026-10-20, variant 3).
  //    Faqat dispatch'dan boshqa rejimlar (quote/alert/recurring). Chegaradan
  //    past moslik dayjestga ham TUSHMAYDI — u faqat ro'yxatda ko'rinadi
  //    (dayjest «yaxshi, lekin limitdan oshgan» uchun). `null` — o'lchov yo'q:
  //    push ketmaydi (xavfsiz tomon, 28-band).
  const minScore = (config.push || {}).minScore;
  if (minScore === null || minScore === undefined) {
    return { send: false, digest: false, reason: REASON.SCORE_NOT_CALIBRATED, retryAt: null };
  }
  if (typeof score !== 'number' || !Number.isFinite(score) || score < minScore) {
    return { send: false, digest: false, reason: REASON.BELOW_MIN_SCORE, retryAt: null };
  }

  // 7) Taklifchi «faqat dayjest» tanlagan.
  if (provider.digestOnly) {
    return { send: false, digest: true, reason: REASON.DIGEST, retryAt: null };
  }

  // 8) Tinch soatlar -> dayjest, ertalab.
  const quiet = (config.push || {}).quietHours;
  if (inQuietHours(now, quiet)) {
    return {
      send: false,
      digest: true,
      reason: REASON.QUIET_HOURS,
      retryAt: quietHoursEndAt(now, quiet),
    };
  }

  // 9) Limitlar -> dayjest (ko'rinish saqlanadi, faqat ovoz yo'q).
  const limits = limitsForMode(mode, config);
  if (limits.perHour > 0 && (provider.sentLastHour || 0) >= limits.perHour) {
    return { send: false, digest: true, reason: REASON.HOURLY_LIMIT, retryAt: null };
  }
  if (limits.perDay > 0 && (provider.sentToday || 0) >= limits.perDay) {
    return { send: false, digest: true, reason: REASON.DAILY_LIMIT, retryAt: null };
  }

  return { send: true, digest: false, reason: REASON.SEND, retryAt: null };
}

/**
 * Dayjest yuborish vaqti keldimi.
 *
 * `minItems` dan kam bo'lsa kutamiz: bitta talab uchun «Sizga mos 1 ta
 * yangi talab» dayjesti oddiy push'dan yomonroq.
 */
function shouldSendDigest(pending, lastDigestAt, config, now = new Date()) {
  const d = (config.push || {}).digest || {};
  if (d.enabled === false) return false;
  const count = Array.isArray(pending) ? pending.length : Number(pending) || 0;
  if (count < (d.minItems || 2)) return false;
  if (!lastDigestAt) return true;
  const everyMs = (d.everyMinutes || 180) * 60 * 1000;
  const last = lastDigestAt instanceof Date ? lastDigestAt.getTime() : Number(lastDigestAt) || 0;
  return now.getTime() - last >= everyMs;
}

/**
 * Push matni — Т-6.4 va maxfiylik qoidasi.
 *
 * ANIQ MANZIL VA TELEFON PUSH MATNIDA BO'LMAYDI. Konsepsiyada namuna:
 * «Urganch, Al-Xorazmiy atrofi». Shuning uchun bu funksiya `addressText`
 * ni UMUMAN qabul qilmaydi — faqat tuman nomi va mo'ljal.
 */
function buildPushText({ mode, categoryName, districtName, landmark, distanceKm, detourKm }) {
  const place = [districtName, landmark].filter(Boolean).join(', ');
  const title = mode === 'dispatch'
    ? `${categoryName || 'Yangi buyurtma'} — qabul qilasizmi?`
    : `${categoryName || 'Yangi talab'} — taklif bering`;

  const bits = [];
  if (place) bits.push(place);
  if (Number.isFinite(distanceKm)) bits.push(`Sizdan ${distanceKm.toFixed(1)} km`);
  if (Number.isFinite(detourKm)) bits.push(`Yo'lingiz ustida, +${detourKm.toFixed(1)} km`);

  return { title, body: bits.join(' · ') };
}

/** Dayjest matni. */
function buildDigestText(count, moduleName) {
  return {
    title: 'Sizga mos yangi talablar',
    body: `${count} ta yangi talab${moduleName ? ` (${moduleName})` : ''} — ko'rib chiqing`,
  };
}

module.exports = {
  REASON,
  localHour,
  inQuietHours,
  quietHoursEndAt,
  limitsForMode,
  decidePush,
  shouldSendDigest,
  buildPushText,
  buildDigestText,
};
