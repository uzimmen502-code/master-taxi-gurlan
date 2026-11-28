'use strict';

/**
 * KURYER HAQI HISOBI — YAGONA MANBA (takrorlanishlar auditi T-2, ega 2026-11-28; CLAUDE.md 7, 8, 14).
 *
 * Avval «kuryerga qancha tegadi» 4 joyda o'zicha hisoblanardi. Endi barcha SERVER hisoblari shu
 * modulda (sozlama o'qish, versiya, tarix, audit — o'z modullarida qoladi, bu yerda faqat sof hisob):
 *
 *   1. taskPayout          — gilam / agro / yig'ib olish vazifasi (`courier_task_payout.js`):
 *                            half_up(base × bps / 10000); base ≤ 0 yoki noto'g'ri → null ("hisoblanmadi").
 *   2. supermarketPayout   — supermarket buyurtmasi (`supermarket.js` courierPayoutSnapshot):
 *                            percent → half_up(deliveryFee × bps / 10000); fixed → fixedAmount;
 *                            deliveryFee ≤ 0 / butun emas → null + sabab `fee_unknown` (ega 2026-11-28 «ҳа»).
 *   3. serviceFee / net    — relay LEG to'lovidan AVA xizmat haqi (`courier_payout.js`):
 *                            fee = half_up(gross × feeBps / 10000), net = gross − fee; noto'g'ri → xato.
 *   4. relay LEG ulushlari — `logistics_tariff.splitInternal` (nusxa; manba functions_demand/core/tariff.js,
 *                            paritet testi bor) — bu yerdan qayta eksport qilinadi, formula O'ZGARMADI
 *                            (tarif versiyasi bilan boshqariladi — egaga alohida savol).
 *
 * Yaxlitlash (ega 2026-11-28 «ҳа бир хил бўлсин»): HAMMA joyda yarmidan yuqoriga — `half_up`
 * (avval kuryer ulushi floor, platforma ulushi ceil edi). Stavka — bps (0.01 %, «ҳамма жойда 0,01%»).
 */

const money = require('./money_math');
const { splitInternal } = require('./logistics_tariff');

const ROUNDING = 'half_up';
const isInt = (n) => typeof n === 'number' && Number.isInteger(n);

/** 1. Vazifa haqi: half_up(base × bps / 10000); base butun > 0, bps butun 0..10000 — aks holda null. */
function taskPayout(base, bps) {
  if (!isInt(base) || base <= 0 || !isInt(bps) || bps < 0 || bps > money.BPS_DENOM) return null;
  return money.bpsOf(base, bps, ROUNDING, { unsafe: 'unchecked' });
}

/**
 * 2. Supermarket kuryer to'lovi. `cp` allaqachon tekshirilgan va normallangan:
 * {mode:'percent', percentBps 0..10000} yoki {mode:'fixed', fixedAmount ≥ 0}.
 * @returns {{amount: number|null, reason: string|null}}
 */
function supermarketPayout(cp, deliveryFee) {
  if (cp.mode === 'fixed') return { amount: cp.fixedAmount, reason: null };
  if (!isInt(deliveryFee) || deliveryFee <= 0) return { amount: null, reason: 'fee_unknown' };
  return { amount: money.bpsOf(deliveryFee, cp.percentBps, ROUNDING, { unsafe: 'unchecked' }), reason: null };
}

/**
 * 3. AVA xizmat haqi relay LEG to'lovidan: half_up(gross × feeBps / 10000).
 * Chegaralar va xato matnlari `courier_payout.js` dagi bilan AYNAN bir xil (chaqiruvchi beradi).
 */
function serviceFee(gross, feeBps, { feeBpsMax }) {
  if (!isInt(gross) || gross <= 0) throw new Error('courierPayout: amount must be a positive integer');
  if (!isInt(feeBps) || feeBps < 0 || feeBps > feeBpsMax) throw new Error('courierPayout: feeBps out of range');
  try {
    return money.bpsOf(gross, feeBps, ROUNDING);
  } catch (e) {
    if (e && e.code === 'MONEY_UNSAFE_INTEGER') throw new Error('courierPayout: amount too large');
    throw e;
  }
}

/** Kuryer hamyoniga tushadigan sof summa: gross − serviceFee. */
function netAfterServiceFee(gross, feeBps, opts) {
  return gross - serviceFee(gross, feeBps, opts);
}

module.exports = {
  ROUNDING,
  taskPayout,
  supermarketPayout,
  serviceFee,
  netAfterServiceFee,
  legSplit: splitInternal,
};
