'use strict';

/**
 * ADAPTER REESTRI.
 *
 * Yangi modul qo'shish = shu ro'yxatga bitta qator. Yadroning boshqa
 * hech bir joyi o'zgarmaydi — konsepsiyaning asosiy talabi.
 *
 * P0 da ATAYLAB bitta adapter. Konsepsiya 16 modulni sanaydi, lekin
 * yadro sinalmagan holda 16 tasini bir vaqtda yoqish eng katta xavf.
 * Qolganlari fazalar bo'yicha qo'shiladi (5-bo'lim, 13.6.6 va 13.7.18).
 */

const serviceAdapter = require('../adapters/service');
const courierAdapter = require('../adapters/courier');

/** @type {Map<string, object>} */
const adapters = new Map([
  [serviceAdapter.module, serviceAdapter],
  // 13.6.3 — shahar ichi kuryer, `dispatch` rejimi. `provider_presence`
  // manbasini ishlatadigan birinchi modul.
  [courierAdapter.module, courierAdapter],
]);

/** Modul adapteri. Topilmasa `null` — chaqiruvchi xato qaytaradi. */
function getAdapter(module) {
  return adapters.get(module) || null;
}

/** Yadroga ulangan modullar. */
function enabledModules() {
  return Array.from(adapters.keys());
}

/**
 * Modulning rejimi.
 *
 * Konsepsiya: «Rejimni foydalanuvchi tanlamaydi» — modul e'lon qiladi.
 * Shuning uchun `mode` klient yuklamasida YO'Q (sxema uni rad etadi).
 */
function modeFor(module) {
  const a = adapters.get(module);
  return a ? a.mode : null;
}

module.exports = { getAdapter, enabledModules, modeFor, adapters };
