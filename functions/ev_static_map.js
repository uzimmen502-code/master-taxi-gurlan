/**
 * EV xaritasi — Maps Static API so'rovini yig'ish (kalitsiz qism).
 *
 * Alohida modul, chunki mantiqni test qilish kerak: `index.js` ni test
 * faylidan require qilib bo'lmaydi (u butun Firebase muhitini ko'taradi).
 */

/** O'zbekiston taxminiy chegarasi — begona hududga so'rov ketmasin. */
const UZ_BOUNDS = { latMin: 37.0, latMax: 46.0, lngMin: 55.0, lngMax: 74.0 };

/** Sonni chegarada ushlab, berilgan kasrgacha yaxlitlaydi. */
function clampNum(raw, min, max, fallback, digits = 3) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  const c = Math.min(max, Math.max(min, n));
  return Number(c.toFixed(digits));
}

/**
 * `markers=lat,lng|lat,lng` — eng ko'pi 10 ta, har biri chegarada.
 * Noto'g'ri qiymatlar shunchaki tashlab yuboriladi.
 */
function parseStaticMapMarkers(raw) {
  if (!raw) return [];
  return String(raw)
    .split('|')
    .slice(0, 10)
    .map((pair) => {
      const [a, b] = String(pair).split(',');
      const lat = clampNum(a, UZ_BOUNDS.latMin, UZ_BOUNDS.latMax, NaN);
      const lng = clampNum(b, UZ_BOUNDS.lngMin, UZ_BOUNDS.lngMax, NaN);
      return Number.isFinite(lat) && Number.isFinite(lng)
        ? `${lat},${lng}`
        : null;
    })
    .filter(Boolean);
}

/**
 * So'rov parametrlaridan Google Static Maps query satrini yig'adi.
 * Kalit BU YERDA QO'SHILMAYDI — uni chaqiruvchi (CF) qo'shadi.
 *
 * Barcha qiymatlar qat'iy chegarada: o'lcham, zoom, marker soni va
 * koordinata. Koordinata 3 kasrgacha yaxlitlanadi — shunda bir tumandagi
 * foydalanuvchilar uchun havola bir xil bo'lib, kesh ishlaydi.
 */
function buildStaticMapQuery(query = {}) {
  const lat = clampNum(query.lat, UZ_BOUNDS.latMin, UZ_BOUNDS.latMax, 41.55);
  const lng = clampNum(query.lng, UZ_BOUNDS.lngMin, UZ_BOUNDS.lngMax, 60.39);
  const zoom = clampNum(query.zoom, 5, 16, 12, 0);
  const w = clampNum(query.w, 120, 640, 400, 0);
  const h = clampNum(query.h, 80, 640, 200, 0);
  const markers = parseStaticMapMarkers(query.markers);

  const params = [
    `center=${lat},${lng}`,
    `zoom=${zoom}`,
    `size=${w}x${h}`,
    'scale=2',
    'maptype=roadmap',
  ];
  if (markers.length > 0) {
    params.push(
      'markers=' +
        encodeURIComponent(`size:small|color:0x1E4FD8|${markers.join('|')}`),
    );
  }
  return params.join('&');
}

module.exports = {
  UZ_BOUNDS,
  clampNum,
  parseStaticMapMarkers,
  buildStaticMapQuery,
};
