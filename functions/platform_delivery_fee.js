'use strict';

/**
 * AVA DO'KONI / SUPERMARKET YETKAZISH HAQI — YAGONA MANBA (T-1, takrorlanishlar auditi
 * 2026-11-28, ega 2026-11-28; 7-qoida).
 *
 * Qoida (jonli `placeOrderPostPaid` bilan AYNAN bir xil — o'zgartirilmadi):
 *   - manba: `settings/app.platformDeliveryFeePercent` (admin `adminSetPlatformDeliveryFeePercent`,
 *     versiya `platformDeliveryFeeVersion`, yo'q → 0);
 *   - hardcode fallback YO'Q: yo'q / bo'sh satr / son emas / manfiy → `TARIFF_NOT_CONFIGURED`
 *     (fail closed, 9-qoida); 100 dan katta → 100;
 *   - bps = round(percent × 100) (butun son, 8-qoida);
 *   - fee = floor((goods × bps + 5000) / 10000) — butun so'mga yarmidan yuqoriga yaxlitlash
 *     (musbat butun sonlarda eski `Math.round(goods × pct / 100)` bilan teng).
 *
 * Foydalanuvchilar: `functions/index.js` `platformDeliveryFeeFromSettings` (placeOrderPostPaid).
 * TODO (T-1 davomi): `functions/supermarket.js` `feeConfigFromApp`/`feeBpOf`/`feeOf` — shu modulga
 * o'tkaziladi (nomlar va natijalar ataylab bir xil); `holiday.js` ham shu foizni o'qiydi.
 * Ekvivalentlik testi: functions/test/platform_delivery_fee.test.js.
 */

const moneyMath = require('./money_math');

const TARIFF_NOT_CONFIGURED = 'TARIFF_NOT_CONFIGURED';
const BPS_PER_PERCENT = 100;
const BPS_DENOMINATOR = 10000;
const MAX_PERCENT = 100;

/** `settings/app` → `{ percent, bps, version }` yoki `null` (sozlanmagan / buzuq). */
function feeConfigFromApp(appData) {
  const d = appData || {};
  const raw = d.platformDeliveryFeePercent;
  const pctIn = (typeof raw === 'number' || (typeof raw === 'string' && raw.trim() !== ''))
    ? Number(raw)
    : NaN;
  if (!Number.isFinite(pctIn) || pctIn < 0) return null;
  const percent = Math.min(pctIn, MAX_PERCENT);
  const verRaw = Number(d.platformDeliveryFeeVersion);
  return {
    percent,
    bps: Math.round(percent * BPS_PER_PERCENT),
    version: Number.isInteger(verRaw) && verRaw > 0 ? verRaw : 0,
  };
}

/** Buyurtmada saqlangan % dan bps (tortish/olishda buyurtma paytidagi % — 9-qoida). */
function feeBpOf(pct) {
  const n = Number(pct);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(Math.min(n, MAX_PERCENT) * BPS_PER_PERCENT);
}

/** fee = floor((goods × bps + 5000) / 10000); goods yoki bps ≤ 0 / son emas → 0. */
function feeOf(goods, bps) {
  if (!(goods > 0) || !(bps > 0)) return 0;
  // Butun kirish — yagona yaxlitlash manbai money_math (T-4, ega 2026-11-28), natija aynan.
  if (Number.isInteger(goods) && Number.isInteger(bps)) return moneyMath.bpsOf(goods, bps, 'half_up', { unsafe: 'unchecked' });
  // Kasr / satr kirish (eski xatti-harakat; amalda itemsTotal butun) — formula o'zgarmadi.
  return Math.floor((goods * bps + BPS_DENOMINATOR / 2) / BPS_DENOMINATOR);
}

module.exports = {
  TARIFF_NOT_CONFIGURED,
  feeConfigFromApp,
  feeBpOf,
  feeOf,
};
