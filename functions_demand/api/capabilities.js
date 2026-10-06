'use strict';

/**
 * CAPABILITY API — ariza berish, kimlik va muddat sweeper'i
 * (D-12…D-16, D-TAXI-1…5, T-1a, T-2).
 *
 * D-14: «Foydalanuvchi o'ziga o'zi `approved`/`verified` berolmasin.»
 * `status`, `window`, `identity` ni FAQAT shu yerdagi funksiyalar yozadi
 * (Admin SDK, qoidalardan o'tmaydi).
 *
 * ── KIMLIK (T-1a) ──────────────────────────────────────────────────────
 * `users/{phoneId}.accountId` — barqaror, server beradi, klient
 * o'zgartirolmaydi. `provider_capabilities/{accountId}`. Telefon
 * almashsa ham starter davri shu hujjatda qoladi (D-TAXI-2).
 *
 * `ensureAccountId` TRANZAKSIYADA: ikkita qurilma bir vaqtda birinchi
 * arizani bersa ham bitta accountId yoziladi (22-qoida). 9 va 12 xonali
 * `users` kalitlari ikkalasi ham qaraladi (eski hujjatlar).
 */

const caps = require('../core/capabilities');
const { callerIdFrom, requireCanonicalId, candidateIdsFor } = require('../core/ids');

const COLLECTION = 'provider_capabilities';
const USERS = 'users';

function httpError(code, message) {
  const e = new Error(message);
  e.code = code;
  return e;
}

/**
 * Yangi accountId: `acc` + Firestore auto-ID (20 belgi, faqat harf-raqam).
 * `_` YO'Q — composite kalitlar uchun xavfsiz (`isSafeForCompositeKey`).
 */
function newAccountId(db) {
  return `acc${db.collection(USERS).doc().id}`;
}

/**
 * Foydalanuvchining barqaror accountId'si — bo'lmasa yaratadi.
 *
 * @returns {Promise<{accountId: string, userRef: object, created: boolean}>}
 */
async function ensureAccountId(db, tx, phoneId) {
  const canon = requireCanonicalId(phoneId, 'phoneId');
  const ids = candidateIdsFor(canon); // [12 xonali, 9 xonali]

  // Mavjud hujjatni topamiz — eski 9 xonali kalit bo'lishi mumkin.
  let userRef = null;
  let userData = null;
  for (const id of ids) {
    const ref = db.collection(USERS).doc(id);
    const snap = await tx.get(ref);
    if (snap.exists) {
      userRef = ref;
      userData = snap.data() || {};
      break;
    }
  }

  if (userData && userData.accountId) {
    return { accountId: String(userData.accountId), userRef, created: false };
  }

  const accountId = newAccountId(db);
  if (!userRef) {
    // Phone Auth'dan o'tgan, lekin `users` hujjati hali yo'q — yaratamiz.
    userRef = db.collection(USERS).doc(canon);
    tx.set(userRef, { phone: canon, phoneDigits: canon, accountId }, { merge: true });
  } else {
    tx.update(userRef, { accountId });
  }
  return { accountId, userRef, created: true };
}

/**
 * «Men shu xizmatni ko'rsatmoqchiman» — ariza.
 *
 * Natija: xizmat lifecycle'ining BOSHLANG'ICH holati (kuryer `trial`,
 * taksi `starter`, qolganlari `enabled`) + muddat oynasi.
 *
 * IDEMPOTENT (21-qoida, D-TAXI-2): allaqachon ishlayotgan odamda hech
 * narsa o'zgarmaydi; taksida `window.taxi.startedAt` BIR MARTA yoziladi —
 * capability'ni o'chirib-qayta yoqish, telefon almashtirish, qayta kirish
 * muddatni qayta boshlamaydi.
 */
function makeRequestCapability(deps) {
  const { db, now: nowFn } = deps;

  return async function requestCapability(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw httpError('unauthenticated', 'Telefon bilan kirish kerak');

    const service = String((data && data.service) || '');
    if (!caps.isService(service)) {
      throw httpError('invalid-argument', `noma'lum xizmat: «${service}»`);
    }
    const lc = caps.lifecycleOf(service);
    const now = nowFn ? nowFn() : new Date();

    return db.runTransaction(async (tx) => {
      const { accountId } = await ensureAccountId(db, tx, callerId);
      const ref = db.collection(COLLECTION).doc(accountId);
      const snap = await tx.get(ref);
      const doc = snap.exists ? (snap.data() || {}) : {};
      const current = caps.statusOf(doc, service);

      if (caps.isWorking(service, current)) {
        return { accountId, status: current, changed: false };
      }

      /**
       * D-TAXI-24 / D-SERVICE-2: xizmatni BIRINCHI MARTA yoqishdan oldin
       * shu xizmat kelishuvi qabul qilingan bo'lishi SHART. Avval bu
       * faqat publish'da tekshirilardi — ya'ni odam `starter` olib, lekin
       * shartlarni ko'rmagan bo'lardi. Endi huquq kelishuvsiz berilmaydi.
       */
      const agrSnap = caps.AGREEMENT_GATED[service]
        ? await tx.get(db.collection('service_agreements').doc(accountId))
        : null;
      if (caps.AGREEMENT_GATED[service]
          && !caps.hasCurrentAgreement(agrSnap.exists ? agrSnap.data() : null, service)) {
        const e = httpError('failed-precondition', `${service} kelishuvi qabul qilinmagan`);
        e.details = { reason: 'agreement_required', agreementVersion: caps.AGREEMENT_VERSIONS[service] };
        throw e;
      }
      if (!caps.canTransition(service, current, lc.initial, 'provider')) {
        // Masalan kuryer `suspended`: tiklanish yo'li HUJJAT, qayta sinov emas.
        throw httpError('failed-precondition', `«${current}» holatidan boshlab bo'lmaydi`);
      }

      const existingWindow = ((doc.window || {})[service]) || null;
      // BIR MARTA: oyna allaqachon bo'lsa (masalan taksi starter'i), saqlanadi.
      const window = existingWindow && existingWindow.startedAt
        ? null
        : caps.windowFor(service, now);

      const patch = {
        identity: { accountId, primaryUid: requireCanonicalId(callerId, 'primaryUid') },
        [service]: { active: true },
        status: { [service]: lc.initial },
        updatedAt: now,
      };
      if (window) patch.window = { [service]: window };
      tx.set(ref, patch, { merge: true });

      const out = { accountId, status: lc.initial, changed: true };
      const w = window || existingWindow;
      if (w && w.endsAt) out.trialEndsAt = new Date(caps.toMillis(w.endsAt)).toISOString();
      if (w && w.verificationDueAt) {
        out.verificationDueAt = new Date(caps.toMillis(w.verificationDueAt)).toISOString();
      }
      return out;
    });
  };
}

/**
 * MUDDAT SWEEPER'i — har xizmat uchun o'z qoidasi (`caps.nextStep`):
 *   kuryer: trial --3k--> trial_expired (BIR MARTA 5k) --> suspended
 *   taksi:  starter --4 oy--> verification_required (grace yo'q, D-TAXI-4)
 *
 * TRANZAKSIYA: grace faqat bir marta, retry muddatni cho'zmasin (21).
 * `suspended`/`verification_required` AKKAUNTNI YOPMAYDI — faqat shu
 * xizmat, boshqa capability'lar va `users` tegilmaydi (D-13, D-TAXI-5).
 */
function makeCapabilitySweeper(deps) {
  const { db, now: nowFn, batchSize = 200, services = caps.SERVICES } = deps;

  return async function capabilitySweeper() {
    const now = nowFn ? nowFn() : new Date();
    const out = { graceGranted: 0, suspended: 0, verificationRequired: 0 };

    for (const service of services) {
      const statuses = caps.sweepableStatuses(service);
      if (statuses.length === 0) continue;

      let snap;
      try {
        snap = await db.collection(COLLECTION)
          .where(`status.${service}`, 'in', statuses)
          .limit(batchSize)
          .get();
      } catch (e) {
        console.error(`capabilitySweeper so'rovi xato (${service}): ${e.message}`);
        continue;
      }

      for (const d of snap.docs) {
        // Tezkor tekshiruv — ko'p holatda tranzaksiya kerak emas (37-qoida).
        if (caps.nextStep(d.data() || {}, service, now).action === 'none') continue;

        try {
          const applied = await db.runTransaction(async (tx) => {
            const fresh = await tx.get(d.ref);
            if (!fresh.exists) return null;
            const step = caps.nextStep(fresh.data() || {}, service, now);
            if (step.action === 'none') return null;

            const patch = { status: { [service]: step.patch.status }, updatedAt: now };
            if (step.action === 'grant_grace') {
              patch.window = {
                [service]: {
                  graceGrantedAt: step.patch.graceGrantedAt,
                  graceEndsAt: step.patch.graceEndsAt,
                },
              };
            } else if (step.action === 'suspend') {
              patch.suspend = { [service]: { at: now, reason: step.patch.reason, by: 'system' } };
            }
            tx.set(d.ref, patch, { merge: true });
            return step.action;
          });

          if (applied === 'grant_grace') out.graceGranted += 1;
          else if (applied === 'suspend') out.suspended += 1;
          else if (applied === 'require_verification') out.verificationRequired += 1;
        } catch (e) {
          console.error(`capabilitySweeper xato (${d.id}/${service}): ${e.message}`);
        }
      }
    }

    if (out.graceGranted || out.suspended || out.verificationRequired) {
      console.log(
        `capabilitySweeper: ${out.graceGranted} grace, ${out.suspended} suspend, `
        + `${out.verificationRequired} verification_required`,
      );
    }
    return out;
  };
}

/**
 * Telefon bo'yicha capability hujjati (admin, teskari matching, billing).
 * `users` → accountId → hujjat. Ikki o'qish; faqat kam chaqiriladigan
 * yo'llarda ishlatiladi — matching manbasi so'rov bilan oladi.
 */
async function fetchByPhone(db, phoneId) {
  for (const id of candidateIdsFor(phoneId)) {
    const u = await db.collection(USERS).doc(id).get();
    if (!u.exists) continue;
    const accountId = (u.data() || {}).accountId;
    if (!accountId) return null;
    const snap = await db.collection(COLLECTION).doc(String(accountId)).get();
    return snap.exists ? { id: snap.id, ...(snap.data() || {}) } : null;
  }
  return null;
}

module.exports = {
  COLLECTION,
  newAccountId,
  ensureAccountId,
  makeRequestCapability,
  makeCapabilitySweeper,
  fetchByPhone,
};
