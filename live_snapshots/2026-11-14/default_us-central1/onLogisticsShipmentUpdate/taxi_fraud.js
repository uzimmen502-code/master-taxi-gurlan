'use strict';

/**
 * YOLG'ON OTMENA — anti-fraud baholash (D-TAXI-16…19, D-TAXI-CANCEL-1…8).
 * SOF FUNKSIYA.
 *
 * ── ASOSIY QOIDA (D-TAXI-CANCEL-8) ─────────────────────────────────────
 * Haydovchining keyin yana reys e'lon qilishi yoki safarni bir necha
 * kunga kechiktirishi O'Z-O'ZIDAN fraud EMAS. Haqiqiy bekor — normal
 * holat (reja o'zgardi, mashina, shaxsiy sabab). Moliyaviy chora FAQAT
 * bir nechta MUSTAQIL dalil bilan.
 *
 * Shuning uchun baholash «ball yig'ish» emas, DALIL QATLAMLARI:
 *
 *   1. JOYLASHUV dalili bo'lmasa — HAR DOIM `normal`. Teskari yo'nalish +
 *      vaqt oynasi (CANCEL-2 misoli: «ertasiga Toshkent→Urganch») o'zi
 *      HECH NARSA emas.
 *   2. Joylashuv dalili YOLG'IZ — ham `normal` («bir dona GPS nuqtasi
 *      hukm emas», CANCEL-4).
 *   3. Joylashuv + 1 ta tasdiqlovchi — `suspicious` (faqat yoziladi).
 *   4. Joylashuv + AVA booking + yana 1 ta — `manual_review` (admin ko'radi).
 *   5. Joylashuv + AVA booking + yana 2 ta (≥4 mustaqil) — `confirmed`.
 *      AVA booking MAJBURIY: AVA yo'lovchi bermagan bo'lsa, komissiya
 *      «ishlamagan», pulni qaytarib olishga asos yo'q.
 *
 * Pul faqat `confirmed`da harakatlanadi (CANCEL-7). Chegaralar konfigdan.
 *
 * Signallar:
 *   location_at_dest   keyingi e'londagi GPS oldingi destination yaqinida
 *   movement_to_dest   cancel joyi origin yaqinida, keyingi joy destination
 *                      yaqinida — ya'ni haydovchi yo'lni BOSIB O'TGAN
 *   had_ava_booking    oldingi reysda AVA orqali tasdiqlangan bron
 *   route_reversed     keyingi reys origin == oldingi reys destination
 *   time_window        bekor → keyingi e'lon yo'l vaqtiga mos (2–36 soat)
 *   late_cancel        jo'nashga yaqin yoki undan keyin bekor — CANCEL-9:
 *                      bekorni TAQIQLAMAYDI va `confirmed` uchun sanalmaydi
 *                      (faqat `manual_review` ga olib keladi)
 */

const DEFAULT_THRESHOLDS = {
  minHoursAfterCancel: 2,
  maxHoursAfterCancel: 36,
  destinationRadiusKm: 30,
  originRadiusKm: 30,
  lateCancelHours: 3,
  /** `suspicious` uchun joylashuvdan tashqari signallar soni. */
  suspiciousExtra: 1,
  /** `manual_review` uchun (booking bilan birga) qo'shimcha signallar. */
  reviewExtra: 1,
  /** `confirmed` uchun (booking bilan birga) qo'shimcha signallar. */
  confirmedExtra: 2,
};

const EARTH_KM = 6371;
function haversineKm(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.sqrt(a));
}

const norm = (s) => String(s || '').trim().toLowerCase().replace(/\s+/g, ' ');
function ms(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}
const hasCoord = (lat, lng) => lat !== null && lat !== undefined && lng !== null && lng !== undefined
  && Number.isFinite(Number(lat)) && Number.isFinite(Number(lng));

/**
 * @param {object} input.prev  bekor qilingan reys: { from, to, originLat?, originLng?,
 *        destLat?, destLng?, cancelLat?, cancelLng?, cancelledAt, departureAt?, hadAvaBooking }
 * @param {object} input.next  yangi e'lon: { from, to, publishedAt, driverLat?, driverLng? }
 */
function evaluateCancelFraud({ prev, next, thresholds }) {
  const t = { ...DEFAULT_THRESHOLDS, ...(thresholds || {}) };
  const signals = [];
  if (!prev || !next) return { verdict: 'normal', signals, reason: 'no_data' };

  const destOk = hasCoord(prev.destLat, prev.destLng);
  const driverOk = hasCoord(next.driverLat, next.driverLng);

  // Joylashuv dalili.
  let locationEvidence = false;
  if (destOk && driverOk) {
    const km = haversineKm(Number(prev.destLat), Number(prev.destLng), Number(next.driverLat), Number(next.driverLng));
    if (km <= t.destinationRadiusKm) { signals.push('location_at_dest'); locationEvidence = true; }
  }
  // Harakat dalili: bekor paytida origin yaqinida edi, keyin destination yaqinida.
  if (locationEvidence && hasCoord(prev.cancelLat, prev.cancelLng) && hasCoord(prev.originLat, prev.originLng)) {
    const kmOrigin = haversineKm(Number(prev.originLat), Number(prev.originLng), Number(prev.cancelLat), Number(prev.cancelLng));
    if (kmOrigin <= t.originRadiusKm) signals.push('movement_to_dest');
  }

  if (prev.hadAvaBooking === true) signals.push('had_ava_booking');
  if (norm(next.from) && norm(next.from) === norm(prev.to)) signals.push('route_reversed');

  const cancelMs = ms(prev.cancelledAt);
  const pubMs = ms(next.publishedAt);
  if (cancelMs && pubMs && pubMs > cancelMs) {
    const hours = (pubMs - cancelMs) / 3600000;
    if (hours >= t.minHoursAfterCancel && hours <= t.maxHoursAfterCancel) signals.push('time_window');
  }
  const depMs = ms(prev.departureAt);
  if (cancelMs && depMs && cancelMs >= depMs - t.lateCancelHours * 3600000) signals.push('late_cancel');

  // ── Qatlamlar ───────────────────────────────────────────────────────
  if (!locationEvidence) {
    // CANCEL-2: keyingi reys, teskari yo'nalish, vaqt — joylashuvsiz HECH NARSA.
    return { verdict: 'normal', signals, reason: 'no_location_evidence' };
  }
  const hasBooking = signals.includes('had_ava_booking');
  if (!hasBooking) {
    // AVA yo'lovchi bermagan bo'lsa, haydovchi AVA'dan hech narsa olmagan —
    // «qaytarib olinadigan» foyda yo'q. Bunday bekorni hatto `suspicious`
    // deb belgilash ham qonuniy haydovchini tamg'alash bo'lardi (CANCEL-7).
    return { verdict: 'normal', signals, reason: 'no_ava_booking' };
  }
  const BASE = new Set(['location_at_dest', 'had_ava_booking']);
  const extra = signals.filter((s) => !BASE.has(s)).length;
  // D-TAXI-CANCEL-9: jo'nashdan keyin bekor qilish QONUNIY (yo'lovchi o'z
  // vaqtida topilmasligi mumkin). Shuning uchun `late_cancel` avtomatik pul
  // yechish (`confirmed`) uchun SANALMAYDI — faqat admin ko'rigiga
  // (`manual_review`) olib keladigan tasdiqlovchi signal bo'lib qoladi.
  const strong = signals.filter((s) => !BASE.has(s) && s !== 'late_cancel').length;

  if (strong >= t.confirmedExtra) return { verdict: 'confirmed', signals, reason: 'sufficient_evidence' };
  if (extra >= t.reviewExtra) return { verdict: 'manual_review', signals, reason: 'needs_admin' };
  // Joylashuv + bron, boshqa hech narsa — faqat yoziladi (CANCEL-7).
  return { verdict: 'suspicious', signals, reason: 'recorded_only' };
}

/** D-TAXI-14 — origin mismatch: SIGNAL, HUKM EMAS. */
function evaluateOriginMismatch({ originLat, originLng, driverLat, driverLng,
  publishedAt, departureAt, radiusKm = 50, soonHours = 2 }) {
  if (!hasCoord(originLat, originLng) || !hasCoord(driverLat, driverLng)) {
    return { flagged: false, reason: 'no_location' };
  }
  const km = haversineKm(Number(originLat), Number(originLng), Number(driverLat), Number(driverLng));
  const pubMs = ms(publishedAt);
  const depMs = ms(departureAt);
  const departsSoon = pubMs && depMs && (depMs - pubMs) <= soonHours * 3600000;
  if (km > radiusKm && departsSoon) {
    return { flagged: true, reason: 'far_from_origin_departing_soon', distanceKm: Math.round(km) };
  }
  return { flagged: false, reason: km > radiusKm ? 'far_but_not_soon' : 'near_origin', distanceKm: Math.round(km) };
}

module.exports = { DEFAULT_THRESHOLDS, haversineKm, evaluateCancelFraud, evaluateOriginMismatch };
