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
 * Чақирувчи админми.
 *
 * @returns {Promise<string>} канон ID
 */
async function assertAnalyticsAdmin(db, context) {
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
      if (ADMIN_ROLES.has(role)) return callerId;
    } catch (e) {
      console.error(`rol o'qilmadi (${id}): ${e.message}`);
    }
  }

  throw fail('permission-denied', 'Ruxsat yo\'q');
}

module.exports = { ADMIN_ROLES, assertAnalyticsAdmin };
