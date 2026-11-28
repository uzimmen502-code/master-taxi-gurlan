'use strict';

/**
 * PUL YAXLITLASH — YAGONA MANBA (takrorlanishlar auditi T-4, ega 2026-11-28; CLAUDE.md 7, 8).
 *
 * `summa × stavka / maxraj` ni BUTUN so'mga, ANIQ ko'rsatilgan yo'nalishda yaxlitlaydi.
 * Avval bu formula 7+ joyda alohida yozilgan edi (restoran/Ulgurji/taksi AVA ulushi, kuryer
 * xizmat haqi, kuryer vazifa haqi, supermarket kuryer to'lovi va tortish ushlab turishi,
 * yetkazish haqi). Endi hammasi shu modulni chaqiradi; har chaqiruvchining OLDINGI natijasi
 * xarakterizatsiya testi bilan qulflangan: functions/test/money_rounding_characterization.test.js.
 *
 * Yo'nalishlar (MODE):
 *   'floor'   — pastga (ijrochi/kuryer ulushi: platformaga zarar qilmaydi);
 *   'ceil'    — yuqoriga (platforma ulushi / ushlab turish: AVA o'ziga zarar qilmaydi);
 *   'half_up' — yarmidan yuqoriga (x.5 → yuqoriga; yetkazish haqi — eski `Math.round` bilan teng).
 *
 * Faqat manfiy bo'lmagan sonlar (barcha chaqiruvchilar musbat summa bilan ishlaydi;
 * manfiy/nol/son emas holatlarini chaqiruvchi O'ZI hal qiladi — ularning qoidalari turlicha).
 *
 * Xavfsiz butun son chegarasi (`opts.unsafe`):
 *   'throw' (standart) — summa × stavka > Number.MAX_SAFE_INTEGER → xato `MONEY_UNSAFE_INTEGER`;
 *   'unchecked'        — tekshiruvsiz (ESKI xatti-harakat: restoran/taksi/supermarket/vazifa haqi
 *                        bu chegarani tekshirmas edi). Real summalarda farq yo'q; chegaradan
 *                        tashqarida natija float aniqligida — egaga savol (hisobot, 2026-11-28).
 * Faqat butun son kirish (aks holda `MONEY_NOT_INTEGER`). Kasr/satr kirishni eski chaqiruvchi
 * (`feeOf`, `holdExtraOf`) o'zining eski formulasi bilan hal qiladi (amalda bo'lmaydi).
 *
 * NUSXA: functions_demand/core/money_math.js — `node functions/tools/sync_money_math.js`,
 * paritet: functions/test/money_math_parity.test.js. Nusxani qo'lda tahrirlamang.
 */

const MODES = Object.freeze(['floor', 'ceil', 'half_up']);
const BPS_DENOM = 10000;
const PCT_DENOM = 100;

function moneyError(code, message) {
  const e = new Error(message || code);
  e.code = code;
  return e;
}

/**
 * round(amount × rate / denom, mode) — natija butun son.
 * @param {number} amount  ≥ 0
 * @param {number} rate    ≥ 0, butun son
 * @param {number} denom   musbat butun son (100 yoki 10000)
 * @param {'floor'|'ceil'|'half_up'} mode
 * @param {{unsafe?: 'throw'|'unchecked'}} [opts]
 */
function mulDivRound(amount, rate, denom, mode, opts) {
  const o = opts || {};
  if (!MODES.includes(mode)) throw moneyError('MONEY_MODE_INVALID', `mode: ${mode}`);
  if (!Number.isInteger(denom) || denom <= 0 || denom % 2 !== 0) throw moneyError('MONEY_DENOM_INVALID');
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0) throw moneyError('MONEY_AMOUNT_INVALID');
  if (!Number.isInteger(amount)) throw moneyError('MONEY_NOT_INTEGER');
  if (!Number.isInteger(rate) || rate < 0) throw moneyError('MONEY_RATE_INVALID');
  const p = amount * rate;
  if (o.unsafe !== 'unchecked' && !Number.isSafeInteger(p)) throw moneyError('MONEY_UNSAFE_INTEGER');
  if (mode === 'half_up') return Math.floor((p + denom / 2) / denom);
  const rem = p % denom;
  // Xavfsiz butun sonlarda ikkala shakl aniq teng; 'unchecked' hududida aynan shu shakllar
  // eski chaqiruvchilarning ko'pchiligi (vazifa haqi / restoran / Ulgurji) bilan bir xil.
  if (mode === 'floor') return (p - rem) / denom;
  return Math.floor(p / denom) + (rem === 0 ? 0 : 1);
}

/** amount × bps / 10000 (bps: 1 % = 100). */
function bpsOf(amount, bps, mode, opts) {
  return mulDivRound(amount, bps, BPS_DENOM, mode, opts);
}

/** amount × percent / 100 (butun foiz). */
function pctOf(amount, percent, mode, opts) {
  return mulDivRound(amount, percent, PCT_DENOM, mode, opts);
}

module.exports = {
  MODES,
  BPS_DENOM,
  PCT_DENOM,
  mulDivRound,
  bpsOf,
  pctOf,
};
