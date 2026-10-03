'use strict';

/**
 * Т-4 — GEO: OSRM O'RNIGA.
 *
 * Konsepsiya har bir to'lqin uchun o'z serverida OSRM ishlatishni taklif
 * qilgan edi. Urganch hajmida bu oqlanmaydi: server + OSM ma'lumotini
 * yangilab turish + monitoring, va u ishdan chiqsa dispatch butunlay to'xtaydi.
 *
 * Uch pog'onali yechim (13.0 auditida tasdiqlangan):
 *   1) To'lqin filtri   — geohash prefiks -> haversine x yo'l koeffitsienti.
 *                         Tashqi so'rov NOL.
 *   2) Mijoz ETA'si     — mavjud `getDirections` callable (Google Directions),
 *                         FAQAT qabul qilingandan keyin, 1-3 so'rov.
 *   3) OSRM             — faqat shadow mode «to'lqin sifati yomon» desa.
 *
 * Yo'l koeffitsienti nega 1.35: to'g'ri chiziq masofasi haqiqiy yo'ldan
 * qisqa. Urganch ko'cha to'ri to'rtburchak (sovet rejasi), shuning uchun
 * koeffitsient Yevropa o'rtachasidan (1.3) bir oz yuqori olingan.
 * SHADOW MODE'DA O'LCHANADI va `module_config.roadFactor`dan olinadi.
 */
const { encode, decodeBounds } = require('./geo_hash');

const EARTH_RADIUS_KM = 6371.0088;

/** Standart yo'l koeffitsienti — `module_config` bermasa shu ishlatiladi. */
const DEFAULT_ROAD_FACTOR = 1.35;

/**
 * Transport turi -> o'rtacha shahar tezligi (km/soat).
 *
 * Bu «maksimal tezlik» emas, svetofor va to'xtashlar bilan ESHIKDAN ESHIKKA
 * o'rtacha. Shuning uchun piyodada 4.5, mashinada 24 — Urganch markazida
 * mashina velosipeddan unchalik tez emas.
 */
const SPEED_KMH = {
  foot: 4.5,
  bicycle: 12,
  moto: 22,
  car: 24,
  truck: 18,
  intercity_car: 65,
};

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

/** Ikki nuqta orasidagi to'g'ri chiziq masofasi (km). */
function haversineKm(aLat, aLng, bLat, bLng) {
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s1 = Math.sin(dLat / 2);
  const s2 = Math.sin(dLng / 2);
  const h = s1 * s1
    + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * s2 * s2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Taxminiy yo'l masofasi (km) — to'g'ri chiziq x koeffitsient. */
function roadKm(aLat, aLng, bLat, bLng, roadFactor = DEFAULT_ROAD_FACTOR) {
  return haversineKm(aLat, aLng, bLat, bLng) * roadFactor;
}

/**
 * To'lqin uchun ETA (daqiqa). Butun songa yaxlitlanadi.
 *
 * DIQQAT: bu MIJOZGA KO'RSATILADIGAN ETA emas. Mijoz ko'radigan vaqt
 * `getDirections` (Google) orqali, qabul qilingandan keyin olinadi.
 * Bu funksiya faqat «kim birinchi to'lqinga kiradi» savoliga javob beradi.
 */
function etaMinutes(aLat, aLng, bLat, bLng, vehicle, roadFactor) {
  const speed = SPEED_KMH[vehicle] || SPEED_KMH.car;
  const km = roadKm(aLat, aLng, bLat, bLng, roadFactor);
  return Math.max(1, Math.round((km / speed) * 60));
}

/**
 * Geohash prefiks uzunligi -> taxminiy katak o'lchami (km).
 * Qancha nomzod o'qishni hal qilish uchun.
 */
const CELL_KM = {
  1: 5000, 2: 1250, 3: 156, 4: 39, 5: 4.9, 6: 1.2, 7: 0.15, 8: 0.038,
};

/**
 * Radius uchun mos geohash prefiks uzunligi.
 *
 * Kam o'qish uchun eng uzun prefiks tanlanadi, lekin radius katakdan
 * kattaroq bo'lsa chegara qo'shnilari ham kerak (`neighborPrefixes`).
 */
function precisionForRadiusKm(radiusKm) {
  const r = Math.max(0.1, Number(radiusKm) || 1);
  for (let p = 7; p >= 2; p -= 1) {
    if (CELL_KM[p] >= r) return p;
  }
  return 2;
}

/**
 * Nuqta atrofidagi geohash prefikslari (o'zi + 8 qo'shni).
 *
 * Firestore `in` so'rovi 30 ta qiymat qabul qiladi, 9 ta prefiks bemalol
 * sig'adi. Qo'shnilar HISOBLANADI, jadvaldan olinmaydi: katak chegarasidagi
 * kuryer tushib qolmasin (konsepsiyadagi «x1.4 zahira»ning aniq shakli).
 */
function neighborPrefixes(lat, lng, precision) {
  const cell = encode(lat, lng, precision);
  const b = decodeBounds(cell);
  const latStep = b.maxLat - b.minLat;
  const lngStep = b.maxLng - b.minLng;
  const out = new Set();
  for (let dy = -1; dy <= 1; dy += 1) {
    for (let dx = -1; dx <= 1; dx += 1) {
      const nLat = Math.max(-89.9, Math.min(89.9, lat + dy * latStep));
      let nLng = lng + dx * lngStep;
      if (nLng > 180) nLng -= 360;
      if (nLng < -180) nLng += 360;
      out.add(encode(nLat, nLng, precision));
    }
  }
  return Array.from(out).sort();
}

/**
 * `geohash >= start && geohash < end` oralig'i — bitta prefiks uchun.
 * Firestore'da prefiks bo'yicha so'rov shu tarzda yoziladi.
 */
function prefixRange(prefix) {
  const p = String(prefix || '');
  return { start: p, end: `${p}~` };
}

/**
 * Т-20 — PROYEKSIYA UCHUN «TAXMINIY NUQTA».
 *
 * Konsepsiya «~500 m taxminiy nuqta» degan, lekin usulini aytmagan.
 * Kesib tashlash (truncate) MUMKIN EMAS: u to'r (grid) hosil qiladi va bir
 * nechta talabdan aniq joyni tiklash mumkin bo'ladi.
 *
 * Shuning uchun: `demandId` hash'idan DETERMINISTIK og'ish. Natija
 *   - har doim bir xil (talab qayta ko'rsatilganda nuqta sakramaydi),
 *   - 300-600 m radiusda, yo'nalishi oldindan aytib bo'lmaydigan,
 *   - aniq joyni tiklashga yaramaydi.
 *
 * Masofa va ETA serverda ANIQ koordinata bo'yicha hisoblanadi; klientga
 * faqat natija («Sizdan 1,4 km») boradi.
 */
function approxPoint(lat, lng, demandId, minM = 300, maxM = 600) {
  const seed = hashString(String(demandId || ''));
  const angle = ((seed % 3600) / 3600) * 2 * Math.PI;
  const spanM = Math.max(0, maxM - minM);
  const distM = minM + (Math.floor(seed / 3600) % (spanM + 1));
  const distKm = distM / 1000;
  const dLat = (distKm / 111.32) * Math.cos(angle);
  const cosLat = Math.cos(toRad(lat)) || 1;
  const dLng = (distKm / (111.32 * cosLat)) * Math.sin(angle);
  return {
    lat: Number((lat + dLat).toFixed(5)),
    lng: Number((lng + dLng).toFixed(5)),
  };
}

/** FNV-1a — kichik, barqaror, kriptografik emas (shart ham emas). */
function hashString(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/**
 * Marshrutdan chetlashish (km) — «Yo'lim ustida» uchun.
 *
 * Haqiqiy chetlashish = (A->olish + olish->topshirish + topshirish->B) - (A->B).
 * Polyline bo'yicha emas, uchta nuqta bo'yicha hisoblanadi: shaharlararo
 * yo'lda bu yetarli aniq va tashqi so'rov talab qilmaydi.
 */
function detourKm(from, pickup, dropoff, to, roadFactor = DEFAULT_ROAD_FACTOR) {
  const direct = roadKm(from.lat, from.lng, to.lat, to.lng, roadFactor);
  const viaParcel = roadKm(from.lat, from.lng, pickup.lat, pickup.lng, roadFactor)
    + roadKm(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng, roadFactor)
    + roadKm(dropoff.lat, dropoff.lng, to.lat, to.lng, roadFactor);
  return Math.max(0, Number((viaParcel - direct).toFixed(2)));
}

module.exports = {
  EARTH_RADIUS_KM,
  DEFAULT_ROAD_FACTOR,
  SPEED_KMH,
  CELL_KM,
  haversineKm,
  roadKm,
  etaMinutes,
  precisionForRadiusKm,
  neighborPrefixes,
  prefixRange,
  approxPoint,
  detourKm,
  hashString,
};
