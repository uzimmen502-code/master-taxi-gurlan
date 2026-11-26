/**
 * KAFE-RESTORAN — oldindan buyurtma (S4b, D-REST-21/35; docs/kafe_restoran_taklifi_uz.md §10.1).
 *
 * Ega qarori (2026-10-19, «мақул»): kamida 60 daqiqa oldin, ko'pi bilan 7 kun, restoran profilida
 * «oldindan buyurtma olaman» belgisi (`acceptsPreorder`), ish vaqti SHU vaqt bo'yicha tekshiriladi.
 * Qolgan qiymatlar — PROPOSED (ega aytmagan, 47-qoida):
 *   - restoran qabul qilish muddati: buyurtmadan 2 soat YOKI bajarilish vaqtidan 30 daqiqa oldin
 *     (qaysi biri avval) — oddiy buyurtmadagi 5 daqiqa kunlar oldingi buyurtma uchun mantiqsiz;
 *   - kuryer chaqiruvi va «tayyor» belgisi bajarilish vaqtidan 90 daqiqa oldin ochiladi: qabul qilingan
 *     oldindan buyurtma kunlar davomida kuryer ro'yxatida turmasin, restoran tasodifan «tayyor» bosib
 *     kuryerni erta chaqirmasin.
 *
 * Vaqt FAQAT serverda tekshiriladi (18-qoida): klient `scheduledForMs` yuboradi, hamma chegara shu yerda.
 * Sof funksiyalar — testlanadi (functions/test/restaurant_preorder.test.js); ishlatilishi —
 * restaurant_orders.js (`placeRestaurantOrder`, qabul, tayyor, kuryer ro'yxati).
 *
 * Diagnostika kodlari: PREORDER_NOT_ACCEPTED, PREORDER_TIME_INVALID, PREORDER_TOO_SOON, PREORDER_TOO_FAR,
 * PREORDER_CLOSED_AT_TIME, PREORDER_TOO_EARLY (tayyor/kuryer uchun hali erta).
 */
'use strict';

const MIN_LEAD_MIN = 60;
// Ega 2026-11-27: 7 -> 14 kun (tuğilgan kun/bayram uçun tort va taomlar oldindan).
const MAX_DAYS = 14;
const MAX_LEAD_DAYS = 14;
const DAY = 24 * 60 * 60 * 1000;
const ACCEPT_CAP_MIN = 120;
const ACCEPT_BEFORE_MIN = 30;
const COURIER_WINDOW_MIN = 90;

const MIN = 60 * 1000;

/** `scheduledForMs` xom qiymati → `{ ms }` yoki `{ error }`. Bo'sh/yo'q → `{ ms: null }` (oddiy buyurtma). */
function parseScheduled(raw) {
  if (raw == null || raw === '') return { ms: null };
  if (typeof raw !== 'number' || !Number.isInteger(raw) || raw <= 0) return { error: 'PREORDER_TIME_INVALID' };
  return { ms: raw };
}

/** Oldindan buyurtma oynasi: null — to'g'ri; aks holda xato kodi. */
function checkWindow(nowMs, scheduledMs) {
  const lead = scheduledMs - nowMs;
  if (lead < MIN_LEAD_MIN * MIN) return 'PREORDER_TOO_SOON';
  if (lead > MAX_DAYS * 24 * 60 * MIN) return 'PREORDER_TOO_FAR';
  return null;
}

/** Restoran qabul qilish muddati (ms): buyurtmadan 2 soat yoki bajarilishdan 30 daqiqa oldin — qaysi biri avval. */
function acceptDeadlineMs(nowMs, scheduledMs) {
  return Math.min(nowMs + ACCEPT_CAP_MIN * MIN, scheduledMs - ACCEPT_BEFORE_MIN * MIN);
}

/** Kuryer chaqiruvi / «tayyor» ochilganmi (bajarilishdan 90 daqiqa oldin boshlanadi). */
function courierWindowOpen(nowMs, scheduledMs) {
  return nowMs >= scheduledMs - COURIER_WINDOW_MIN * MIN;
}

/**
 * Taom darajasidagi oldindan buyurtma (ega 2026-11-27). Menyu hujjati (restoran yozadi — 18-qoida, ishonilmaydi):
 *   - `preorderable === false` — oldindan buyurtmada bu taom YO'Q (PREORDER_ITEM_NOT_ALLOWED);
 *   - `preorderLeadDays` N (butun 0..14): N >= 1 bo'lsa taom FAQAT oldindan, bajarilish vaqti >= hozir + N×24 soat
 *     (oddiy buyurtmada — PREORDER_ITEM_REQUIRED, erta — PREORDER_ITEM_LEAD_TOO_SHORT); 0 — qo'shimcha cheklov yo'q;
 *   - maydonlar yo'q (eski taomlar) — avvalgidek, cheklov yo'q (backward compatible);
 *   - noto'g'ri tip/chegara (qoida chetlab o'tilgan) — xavfsiz tomonga: MENU_ITEM_PREORDER_INVALID.
 * null — to'g'ri; aks holda `{ code, leadDays? }`.
 */
function dishPreorderProblem(item, nowMs, scheduledMs) {
  const m = item || {};
  const has = (k) => Object.prototype.hasOwnProperty.call(m, k) && m[k] !== undefined;
  if (has('preorderable') && typeof m.preorderable !== 'boolean') return { code: 'MENU_ITEM_PREORDER_INVALID' };
  let lead = 0;
  if (has('preorderLeadDays')) {
    if (!Number.isInteger(m.preorderLeadDays) || m.preorderLeadDays < 0 || m.preorderLeadDays > MAX_LEAD_DAYS) return { code: 'MENU_ITEM_PREORDER_INVALID' };
    lead = m.preorderLeadDays;
  }
  if (scheduledMs == null) return lead > 0 ? { code: 'PREORDER_ITEM_REQUIRED', leadDays: lead } : null;
  if (m.preorderable === false) return { code: 'PREORDER_ITEM_NOT_ALLOWED' };
  if (lead > 0 && scheduledMs < nowMs + lead * DAY) return { code: 'PREORDER_ITEM_LEAD_TOO_SHORT', leadDays: lead };
  return null;
}

/** Hujjatdagi `scheduledFor` (Timestamp) → ms; yo'q/noto'g'ri — null. */
function scheduledMsOf(od) {
  const t = od && od.scheduledFor;
  return t && typeof t.toMillis === 'function' ? t.toMillis() : null;
}

module.exports = {
  parseScheduled, checkWindow, acceptDeadlineMs, courierWindowOpen, scheduledMsOf, dishPreorderProblem,
  MIN_LEAD_MIN, MAX_DAYS, MAX_LEAD_DAYS, ACCEPT_CAP_MIN, ACCEPT_BEFORE_MIN, COURIER_WINDOW_MIN,
};
