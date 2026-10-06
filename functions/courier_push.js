'use strict';

/**
 * KURYERGA PUSH — токен ва «ким ҳозир онлайн» манбалари (13.6.4).
 *
 * Нега алоҳида модул: аввал учта жой `couriers` ҳужжатидан ЎҚИР эди
 * (`index.js` даги `onDeliveryRouteCreate` x2 ва `onDeliveryRouteAssign`),
 * яъни бир хил мантиқ уч марта ёзилган эди (7-қоида). Энди битта манба.
 *
 * ── НИМА ЎЗГАРДИ ВА НЕГА ───────────────────────────────────────────────
 *
 * 1. ТОКЕН: аввал фақат `couriers/{uid}.fcmToken`. У ҳужжатга ФАҚАТ
 *    курьер онлайн бўлганда ёзилади (`couriers_repository.upsertStatus`),
 *    админ янги курьер яратганда эса умуман бўлмайди
 *    (`courier_management_screen` фақат phone/name/isOnline ёзади).
 *    Натижа: ҳеч қачон онлайн бўлмаган курьерга reys тайинланса, у
 *    PUSH ОЛМАЙДИ ва тайинлашни билмайди.
 *
 *    Энди биринчи манба — `users/{uid}.fcmToken`. Уни `FcmService`
 *    иловани ҳар очганда ва токен янгиланганда ёзади
 *    (`lib/services/fcm_service.dart:150`), яъни онлайн бўлишни
 *    кутмайди. `couriers` эса ЗАҲИРА сифатида қолади — ўтиш даврида
 *    эски ёзувлар йўқолмасин.
 *
 *    Ўлчов (2026-10-06, продакшн, фақат ўқиш): учта `couriers`
 *    ҳужжатининг ҳаммасида ҳам `users.fcmToken` бор.
 *
 * 2. «КИМ ОНЛАЙН»: аввал фақат `couriers where isOnline == true`.
 *    Янги ядро эса `provider_presence`ни ўқийди
 *    (`functions_demand/sources/presence_geo.js`). Ўтиш даврида
 *    иловани янгилаган курьер ИККАЛА коллекцияга ёзади, янгиламагани
 *    эса фақат `couriers`га — шунинг учун бу ерда ИККАЛАСИ ҳам
 *    ўқилади ва канон ID бўйича бирлаштирилади. Биттасига ўтиш
 *    4-босқичдан кейин, `couriers` чиқарилганда.
 *
 * 3. ЭСКИРИШ: `provider_presence.isOnline` га кўр-кўрона ишониб
 *    бўлмайди — илова ёпилса, у `true` бўлиб қолади. Чегара
 *    `maxLocationAgeSec` (120 с) — matching ва sweep билан АЙНАН бир
 *    хил (`functions_demand/core/config.js`). `couriers` учун бу
 *    текширув ҚЎЛЛАНМАЙДИ: уни `cleanupStaleDrivers` ҳар 2 дақиқада
 *    тозалайди ва у ерда `updatedAt` маъноси бошқача (sweep уни
 *    ўзгартириб юборади).
 */

const PRESENCE = 'provider_presence';
const COURIERS = 'couriers';
const USERS = 'users';

/**
 * Matching билан бир хил чегара. Иккита раqам бўлса, «push кетди,
 * лекин matching кўрмайди» оралиғи пайдо бўлади.
 */
const MAX_LOCATION_AGE_SEC = 120;

const COURIER_MODULE = 'courier';

function tokenOk(t) {
  return typeof t === 'string' && t.length > 10;
}

function toMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * @param {object} deps
 * @param {object} deps.db Firestore
 * @param {function} deps.canonicalUid `index.js` даги жуфти (9 -> 12)
 * @param {function} [deps.now] тест учун
 */
function createCourierPush(deps) {
  const { db, canonicalUid } = deps;
  const nowFn = deps.now || (() => new Date());

  /** Бир одамнинг барча мумкин ID шакллари — такрорсиз. */
  function idForms(courierId) {
    const raw = String(courierId || '').trim();
    if (!raw) return [];
    const canon = canonicalUid(raw);
    const short = canon.length === 12 && canon.startsWith('998')
      ? canon.slice(3)
      : '';
    return [...new Set([canon, short, raw].filter(Boolean))];
  }

  /**
   * Курьернинг push токени.
   *
   * Тартиб: `users` (ишончли, доим янгиланади) → `couriers` (заҳира).
   * Топилмаса бўш сатр — чақирувчи push юбормайди.
   */
  async function resolveToken(courierId) {
    const ids = idForms(courierId);
    if (ids.length === 0) return '';

    // D-CLEAN-1: faqat `users.fcmToken` — `couriers` zahirasi olib tashlandi.
    for (const col of [USERS]) {
      for (const id of ids) {
        try {
          const snap = await db.collection(col).doc(id).get();
          if (!snap.exists) continue;
          const t = (snap.data() || {}).fcmToken;
          if (tokenOk(t)) return t;
        } catch (e) {
          console.error(`fcmToken o'qilmadi (${col}/${id}): ${e.message}`);
        }
      }
    }
    return '';
  }

  /**
   * Ҳозир онлайн курьерларнинг КАНОН ID рўйхати.
   *
   * Иккита манба бирлаштирилади (ўтиш даври, 2-банд).
   */
  async function onlineCourierIds() {
    const cutoffMs = nowFn().getTime() - MAX_LOCATION_AGE_SEC * 1000;
    const out = new Set();

    try {
      const snap = await db.collection(PRESENCE)
        .where('isOnline', '==', true)
        .where('module', '==', COURIER_MODULE)
        .get();
      for (const d of snap.docs) {
        const p = d.data() || {};
        const ms = toMillis(p.updatedAt);
        // `updatedAt` йўқ ҳужжат — нотўғри шаклда, ишонилмайди.
        if (!ms || ms < cutoffMs) continue;
        // Кимлик ФАҚАТ калитдан (18-қоида): ҳужжат ичидаги
        // `providerId` майдонини клиент ёзади.
        const id = canonicalUid(d.id);
        if (id) out.add(id);
      }
    } catch (e) {
      console.error(`provider_presence o'qilmadi: ${e.message}`);
    }

    // D-CLEAN-1: legacy `couriers` manbasi OLIB TASHLANDI — faqat
    // `provider_presence`. Eski ilova versiyalari qo'llab-quvvatlanmaydi
    // (ega qarori, 2026-10-06).

    return [...out];
  }

  /**
   * Онлайн курьерларнинг токенлари — ТАКРОРСИЗ.
   *
   * Бир одам иккита ID шаклида учраса ҳам (9 ва 12 хонали), токен
   * битта бўлади ва у БИР МАРТА қайтади: акс ҳолда одам битта
   * хабарни икки марта оларди.
   */
  async function onlineCourierTokens() {
    const ids = await onlineCourierIds();
    const tokens = new Set();
    for (const id of ids) {
      const t = await resolveToken(id);
      if (tokenOk(t)) tokens.add(t);
    }
    return [...tokens];
  }

  return {
    MAX_LOCATION_AGE_SEC,
    idForms,
    resolveToken,
    onlineCourierIds,
    onlineCourierTokens,
  };
}

module.exports = { createCourierPush, tokenOk, MAX_LOCATION_AGE_SEC };
