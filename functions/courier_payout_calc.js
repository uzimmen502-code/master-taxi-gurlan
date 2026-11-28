'use strict';

/**
 * KURYER HAQI HISOBI — YAGONA MANBA (takrorlanishlar auditi T-2, ega 2026-11-28; CLAUDE.md 7, 8, 14).
 *
 * Avval «kuryerga qancha tegadi» 4 joyda o'zicha hisoblanardi. Endi barcha SERVER hisoblari shu
 * modulda (sozlama o'qish, versiya, tarix, audit — o'z modullarida qoladi, bu yerda faqat sof hisob):
 *
 *   1. taskPayout          — gilam / agro / yig'ib olish vazifasi (`courier_task_payout.js`):
 *                            floor(base × bps / 10000); base ≤ 0 yoki noto'g'ri → null ("hisoblanmadi").
 *   2. supermarketPayout   — supermarket buyurtmasi (`supermarket.js` courierPayoutSnapshot):
 *                            percent → floor(deliveryFee × foiz / 100); fixed → fixedAmount;
 *                            deliveryFee ≤ 0 / butun emas → 0 (null EMAS — eski xatti-harakat).
 *   3. serviceFee / net    — relay LEG to'lovidan AVA xizmat haqi (`courier_payout.js`):
 *                            fee = ceil(gross × feeBps / 10000), net = gross − fee; noto'g'ri → xato.
 *   4. relay LEG ulushlari — `logistics_tariff.splitInternal` (nusxa; manba functions_demand/core/tariff.js,
 *                            paritet testi bor) — bu yerdan qayta eksport qilinadi, formula O'ZGARMADI.
 *                            Admin qo'lda bergan LEG summalari (`applyPayoutOverrides`) yaxlitlamaydi.
 *
 * Yaxlitlash qoidasi umumiy: ijrochi (kuryer) ulushi — floor, platforma ulushi — ceil (money_math.js).
 *
 * MOS KELMASLIKLAR (egaga savol, 2026-11-28 hisobot): yaroqsiz baza uchun 1 → null, 2 → 0, 3 → xato;
 * stavka formati 1,3 → bps (0.01 %), 2 → butun foiz; xavfsiz butun son chegarasi 3 → xato, 1,2 → tekshiruvsiz.
 * Har chaqiruvchining natijasi ataylab saqlangan (`opts` orqali) — g'olib tanlanmagan.
 */

const money = require('./money_math');
const { splitInternal } = require('./logistics_tariff');

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);

/** 1. Vazifa haqi: floor(base × bps / 10000); base butun > 0, bps butun 0..10000 — aks holda null. */
function taskPayout(base, bps) {
  if (!isInt(base) || base <= 0 || !isInt(bps) || bps < 0 || bps > money.BPS_DENOM) return null;
  return money.bpsOf(base, bps, 'floor', { unsafe: 'unchecked' });
}

/**
 * 2. Supermarket kuryer to'lovi (cp allaqachon tekshirilgan: {mode:'percent', percent 0..100} yoki
 * {mode:'fixed', fixedAmount ≥ 0}). Natija — butun so'm.
 */
function supermarketPayoutAmount(cp, deliveryFee) {
  if (cp.mode === 'fixed') return cp.fixedAmount;
  const fee = isInt(deliveryFee) && deliveryFee > 0 ? deliveryFee : 0;
  return money.pctOf(fee, cp.percent, 'floor', { unsafe: 'unchecked' });
}

/**
 * 3. AVA xizmat haqi relay LEG to'lovidan: ceil(gross × feeBps / 10000).
 * Chegaralar va xato matnlari `courier_payout.js` dagi bilan AYNAN bir xil (chaqiruvchi beradi).
 */
function serviceFee(gross, feeBps, { feeBpsMax }) {
  if (!isInt(gross) || gross <= 0) throw new Error('courierPayout: amount must be a positive integer');
  if (!isInt(feeBps) || feeBps < 0 || feeBps > feeBpsMax) throw new Error('courierPayout: feeBps out of range');
  try {
    return money.bpsOf(gross, feeBps, 'ceil');
  } catch (e) {
    if (e && e.code === 'MONEY_UNSAFE_INTEGER') throw new Error('courierPayout: amount too large');
    throw e;
  }
}

/** Kuryer hamyoniga tushadigan sof summa: gross − ceil(fee) (= floor(gross × (10000 − bps) / 10000)). */
function netAfterServiceFee(gross, feeBps, opts) {
  return gross - serviceFee(gross, feeBps, opts);
}

module.exports = {
  taskPayout,
  supermarketPayoutAmount,
  serviceFee,
  netAfterServiceFee,
  legSplit: splitInternal,
};
