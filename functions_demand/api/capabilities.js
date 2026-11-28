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
 * `readAccountId` + `commitAccountId` TRANZAKSIYADA: ikkita qurilma bir
 * vaqtda birinchi arizani bersa ham bitta accountId yoziladi (22-qoida).
 * 9 va 12 xonali `users` kalitlari ikkalasi ham qaraladi (eski hujjatlar).
 */

const caps = require('../core/capabilities');
const fcm = require('../notify/fcm');
const { callerIdFrom, requireCanonicalId, candidateIdsFor } = require('../core/ids');
const moduleGate = require('../core/module_gate');

/** Admin «Ҳудудлар ва хизматлар» modul id'si (Dart `kKnownModuleIds`). */
const COURIER_MODULE = 'courier';

const COLLECTION = 'provider_capabilities';
const USERS = 'users';
/** Append-only audit (41-qoida) — `admin_capabilities.js` ham shuni ishlatadi. */
const AUDIT = 'capability_audit';

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
 * Foydalanuvchining barqaror accountId'si — bo'lmasa YANGISI tayyorlanadi.
 *
 * FAQAT O'QIYDI. Firestore tranzaksiyasida barcha o'qishlar yozuvlardan
 * oldin bo'lishi shart — SDK aks holda `transactions require all reads to
 * be executed before all writes` deb tashlaydi. Chaqiruvchilar bundan
 * keyin ham o'qiydi (`provider_capabilities`, `service_agreements`),
 * shuning uchun yozuv alohida: o'z o'qishlarini tugatgach
 * `commitAccountId(tx, acc)`. Avval bu funksiya o'zi yozardi va yangi
 * foydalanuvchining birinchi arizasi hech qachon o'tmasdi (emulator testi:
 * `capabilities_tx_emulator.test.js`).
 *
 * @returns {Promise<{accountId: string, userRef: object, created: boolean,
 *   userExists: boolean, canon: string}>}
 */
async function readAccountId(db, tx, phoneId) {
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
    return { accountId: String(userData.accountId), userRef, created: false, userExists: true, canon };
  }
  return {
    accountId: newAccountId(db),
    // Phone Auth'dan o'tgan, lekin `users` hujjati hali yo'q — yaratiladi.
    userRef: userRef || db.collection(USERS).doc(canon),
    created: true,
    userExists: !!userRef,
    canon,
  };
}

/** `readAccountId` tayyorlagan YANGI accountId'ni yozadi (mavjud bo'lsa — hech narsa). */
function commitAccountId(tx, acc) {
  if (!acc.created) return;
  if (acc.userExists) {
    tx.update(acc.userRef, { accountId: acc.accountId });
  } else {
    tx.set(acc.userRef, { phone: acc.canon, phoneDigits: acc.canon, accountId: acc.accountId }, { merge: true });
  }
}

/**
 * «Men shu xizmatni ko'rsatmoqchiman» — ariza.
 *
 * Natija: xizmat lifecycle'ining BOSHLANG'ICH holati (kuryer `applied` —
 * admin tasdig'ini kutadi, D-15.5; taksi `starter`, qolganlari `enabled`)
 * + muddat oynasi (kuryer arizasida oyna yo'q).
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
    // MEDIUM-4 (audit 2026-10-31): admin «Ҳудудлар ва хизматлар» `courier` moduli yopiq bo'lsa
    // YANGI kuryer arizasi qabul qilinmaydi. FAQAT kuryer — taksi va boshqa xizmatlarga ta'sir YO'Q.
    // Allaqachon ishlayotgan / navbatdagi (`applied`) arizaga qayta bosish tegilmaydi (pastda,
    // o'zgarishsiz javoblardan KEYIN tekshiriladi). Konfig o'qilmasa — fail-open (module_gate.js).
    const gate = service === 'courier'
      ? await moduleGate.moduleOpenFor(db, COURIER_MODULE, callerId, { activeDistrictId: data && data.geoDistrictId })
      : null;

    return db.runTransaction(async (tx) => {
      const acc = await readAccountId(db, tx, callerId);
      const { accountId } = acc;
      const ref = db.collection(COLLECTION).doc(accountId);
      const snap = await tx.get(ref);
      const doc = snap.exists ? (snap.data() || {}) : {};
      const current = caps.statusOf(doc, service);

      if (caps.isWorking(service, current)) {
        const out = { accountId, status: current, changed: false };
        /**
         * D-TAXI-24.1: kelishuv starter'da EMAS — 4 oy o'tib
         * `verification_required` (va `verified`) bo'lganda tizim taqdim
         * qiladi. Bu INFORMATSION javob: ishlash huquqi o'zgarmaydi,
         * ilova varaqni ko'rsatadi. Versiyani server aytadi.
         */
        if (caps.agreementDue(service, current)) {
          const agr = await tx.get(db.collection('service_agreements').doc(accountId));
          if (!caps.hasCurrentAgreement(agr.exists ? agr.data() : null, service)) {
            out.agreementRequired = true;
            out.agreementVersion = caps.AGREEMENT_VERSIONS[service];
          }
        }
        return out;
      }
      // D-15.5: ariza allaqachon admin navbatida (`applied`) — qayta bosish
      // hech narsani o'zgartirmaydi, ariza vaqti ham qayta yozilmaydi (21-qoida).
      if (current === lc.initial) {
        return { accountId, status: current, changed: false };
      }
      if (gate && !gate.open) {
        console.log(JSON.stringify({
          module: 'capabilities', action: 'requestCapability', service, result: 'error',
          errorCode: moduleGate.MODULE_CLOSED, moduleStatus: gate.status,
        }));
        const e = httpError('failed-precondition', moduleGate.MODULE_CLOSED);
        e.details = { code: moduleGate.MODULE_CLOSED, moduleId: COURIER_MODULE, status: gate.status };
        throw e;
      }

      /**
       * D-SERVICE-2: `AGREEMENT_GATED[service]` bo'lsa xizmatni BIRINCHI
       * MARTA yoqishdan oldin kelishuv SHART. Taksi uchun bu darvoza
       * YO'Q (D-TAXI-24.1) — starter kelishuvsiz beriladi; hozircha
       * hech bir xizmat gated emas, matnlar egadan kutilmoqda (2-bis).
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

      // D-15.3: kuryerda admin tanlagan rejim (`settings/courier`). `auto` —
      // darhol `approved`, lekin state machine bo'ylab (trial → approved,
      // admin siyosati) va auditga tushadi. O'QISH — yozuvlardan oldin.
      let target = lc.initial;
      let autoApproval = null;
      if (service === 'courier') {
        const settings = await tx.get(db.collection('settings').doc('courier'));
        const sData = settings.exists ? (settings.data() || {}) : {};
        if (caps.courierApprovalModeOf(sData) === caps.COURIER_APPROVAL_MODES.auto
            && caps.canTransition(service, lc.initial, caps.COURIER.approved, 'admin')) {
          target = caps.COURIER.approved;
          autoApproval = { modeSetBy: String(sData.approvalModeUpdatedBy || '') };
        }
      }

      const existingWindow = ((doc.window || {})[service]) || null;
      // D-15.5: `applied` — admin navbatida, sinov soati YURMAYDI.
      const pendingReview = target === caps.COURIER.applied;
      // BIR MARTA: oyna allaqachon bo'lsa (masalan taksi starter'i), saqlanadi.
      const window = pendingReview || (existingWindow && existingWindow.startedAt)
        ? null
        : caps.windowFor(service, now);

      const patch = {
        identity: { accountId, primaryUid: requireCanonicalId(callerId, 'primaryUid') },
        [service]: { active: true },
        status: { [service]: target },
        updatedAt: now,
      };
      if (window) patch.window = { [service]: window };
      // Admin ro'yxatida «ariza qachon berilgan» ko'rinsin; tasdiq/rad
      // keyin `review.<xizmat>` ga merge bo'ladi, bu maydon saqlanadi.
      if (pendingReview) patch.review = { [service]: { submittedAt: now } };
      if (autoApproval) {
        patch.review = {
          [service]: { reviewedBy: 'auto', at: now, decision: target, reason: 'approval_mode_auto' },
        };
      }
      // Barcha o'qishlar tugadi — endi yozuvlar.
      commitAccountId(tx, acc);
      tx.set(ref, patch, { merge: true });
      if (autoApproval) {
        // 41-qoida: avtomatik tasdiq ham — kim yoqqan siyosat bo'yicha.
        tx.set(db.collection(AUDIT).doc(), {
          accountId, service, from: lc.initial, to: target, reason: 'approval_mode_auto',
          by: 'auto', modeSetBy: autoApproval.modeSetBy, at: now, kind: 'auto_approve',
        });
      }

      const out = { accountId, status: target, changed: true };
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
/**
 * D-TAXI-24.1 — starter tugaganda haydovchiga ilova ichidagi xabar.
 *
 * `admin_news` — mavjud shaxsiy inbox (`notifyUserInApp` bilan bir xil
 * shakl, `targetUserId` = kanon telefon). Hujjat ID DETERMINISTIK:
 * sweeper qayta ishlasa ham ikkinchi xabar yozilmaydi (21-qoida).
 * Matn — PROPOSED (D-TAXI-5 va D-TAXI-24.1 dan), ega tahrirlashi mumkin.
 */
const TAXI_DUE_NEWS = {
  title: 'Taksi: 4 oylik starter davri tugadi',
  bodyAgreement: 'Yangi pullik reys e\'lon qilish uchun Taksi xizmati kelishuvini qabul qiling '
    + 'va admin tekshiruvidan o\'ting. Mavjud reyslaringiz va boshqa xizmatlaringiz ishlashda davom etadi.',
  bodyVerification: 'Yangi pullik reys e\'lon qilish uchun admin tekshiruvidan o\'ting. '
    + 'Mavjud reyslaringiz va boshqa xizmatlaringiz ishlashda davom etadi.',
};

function taxiDueNewsId(accountId) {
  return `taxiVerificationDue_${accountId}`;
}

function makeCapabilitySweeper(deps) {
  const {
    db, messaging = null, now: nowFn, batchSize = 200, services = caps.SERVICES,
  } = deps;

  return async function capabilitySweeper() {
    const now = nowFn ? nowFn() : new Date();
    const out = { graceGranted: 0, suspended: 0, verificationRequired: 0 };
    const pushes = [];

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

            // D-TAXI-24.1: tranzaksiyadagi BARCHA o'qishlar yozuvdan oldin.
            let agreementPending = false;
            if (step.action === 'require_verification') {
              const agr = await tx.get(db.collection('service_agreements').doc(d.id));
              agreementPending = !caps.hasCurrentAgreement(agr.exists ? agr.data() : null, service);
            }

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
            } else if (step.action === 'require_verification') {
              // Server kaliti (`window`) — klient o'chira olmaydi, qoida
              // o'zgarmaydi. Kelishuv qabul qilinganini `service_agreements`
              // ko'rsatadi; bu yerda faqat «tizim taqdim qildi» vaqti.
              if (agreementPending) patch.window = { [service]: { agreementRequestedAt: now } };
            }
            tx.set(d.ref, patch, { merge: true });

            let uid = '';
            if (step.action === 'require_verification') {
              uid = caps.identityOf(fresh.data() || {}).primaryUid;
              if (uid) {
                tx.set(db.collection('admin_news').doc(taxiDueNewsId(d.id)), {
                  title: TAXI_DUE_NEWS.title,
                  body: agreementPending ? TAXI_DUE_NEWS.bodyAgreement : TAXI_DUE_NEWS.bodyVerification,
                  category: 'warning',
                  audience: 'user',
                  targetUserId: uid,
                  source: 'taxi_capability',
                  dataType: 'taxi_verification_due',
                  priority: 7,
                  createdAt: now,
                });
              }
            }
            return { action: step.action, uid, agreementPending };
          });

          const action = applied && applied.action;
          if (action === 'grant_grace') out.graceGranted += 1;
          else if (action === 'suspend') out.suspended += 1;
          else if (action === 'require_verification') {
            out.verificationRequired += 1;
            if (applied.uid) pushes.push(applied);
          }
        } catch (e) {
          console.error(`capabilitySweeper xato (${d.id}/${service}): ${e.message}`);
        }
      }
    }

    // Push — tranzaksiyadan TASHQARIDA va «best effort»: xabar inbox'da
    // allaqachon bor, push yetmasa ham haydovchi ilovada ko'radi.
    if (messaging) {
      for (const p of pushes) {
        try {
          const tokens = await fcm.tokensFor(db, p.uid);
          if (tokens.length === 0) continue;
          await messaging.sendEach(tokens.map((token) => ({
            token,
            notification: {
              title: TAXI_DUE_NEWS.title,
              body: (p.agreementPending ? TAXI_DUE_NEWS.bodyAgreement : TAXI_DUE_NEWS.bodyVerification).slice(0, 120),
            },
            data: { type: 'taxi_verification_due', screen: 'news' },
          })));
        } catch (e) {
          console.error(`capabilitySweeper push xato (taxi_verification_due): ${e.message}`);
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
  AUDIT,
  TAXI_DUE_NEWS,
  taxiDueNewsId,
  newAccountId,
  readAccountId,
  commitAccountId,
  makeRequestCapability,
  makeCapabilitySweeper,
  fetchByPhone,
};
