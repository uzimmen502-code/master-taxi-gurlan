'use strict';

/**
 * АНАЛИТИКАГА КИРИШ ҲУҚУҚИ.
 *
 * Аналитика ҳужжатларида агрегат рақамлар бор, лекин улар орасида
 * бизнес учун сезгир маълумот ҳам бор (мос таклифчилар сони, рад
 * этиш сабаблари). Шунинг учун фақат админ.
 *
 * Шахсни аниқлаш — репонинг модели бўйича: `token.phone_number` →
 * рақамлар → `users/{id}.role`. `request.auth.uid` ИШЛАТИЛМАЙДИ
 * (Т-2 — концепциядаги асосий тузатиш).
 *
 * `functions/index.js:1850` даги `assertAdmin` билан бир хил
 * мантиқ, лекин ядро codebase'ида мустақил нусха: деплой пайтида
 * ҳар codebase фақат ўз папкасини юклайди.
 */

const { callerIdFrom, candidateIdsFor } = require('../core/ids');

/** Админ ҳисобланадиган роллар — `assertAdmin` билан бир хил. */
const ADMIN_ROLES = new Set(['admin', 'superadmin', 'dispatcher']);

function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  return e;
}

/**
 * Pul oqimiga ta'sir qiluvchi admin amallari (yo'qolgan posilka, D1 2026-10-16)
 * uchun TORROQ ro'yxat: `dispatcher` KIRMAYDI (ega qarori 6-band: faqat
 * admin/superadmin). `functions/index.js`dagi `requireCallerRoles(['admin',
 * 'superadmin'])` bilan bir xil.
 */
const STRICT_ADMIN_ROLES = new Set(['admin', 'superadmin']);

async function assertRole(db, context, roles) {
  const callerId = callerIdFrom(context);
  if (!callerId) {
    throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
  }

  // 9 ва 12 хонали иккита шакл — эски ҳужжатлар учун (strangler).
  for (const id of candidateIdsFor(callerId)) {
    try {
      const snap = await db.collection('users').doc(id).get();
      if (!snap.exists) continue;
      const role = (snap.data() || {}).role || 'user';
      if (roles.has(role)) return callerId;
    } catch (e) {
      console.error(`rol o'qilmadi (${id}): ${e.message}`);
    }
  }

  throw fail('permission-denied', 'Ruxsat yo\'q');
}

/**
 * Чақирувчи админми.
 *
 * @returns {Promise<string>} канон ID
 */
function assertAnalyticsAdmin(db, context) {
  return assertRole(db, context, ADMIN_ROLES);
}

/** Faqat admin/superadmin (dispatcher EMAS). @returns {Promise<string>} kanon ID */
function assertStrictAdmin(db, context) {
  return assertRole(db, context, STRICT_ADMIN_ROLES);
}

module.exports = {
  ADMIN_ROLES, STRICT_ADMIN_ROLES, assertAnalyticsAdmin, assertStrictAdmin,
};
