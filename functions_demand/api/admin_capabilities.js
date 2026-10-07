'use strict';

/**
 * ADMIN — capability statusi va T-6 migratsiyasi (D-TAXI-4, 41-qoida).
 *
 * `verified`/`approved`/`suspended` ni FAQAT shu yerdan (admin) yoki
 * sweeper (system) beradi. Har bir admin amali `capability_audit`
 * kolleksiyasiga APPEND-ONLY yoziladi: kim, kimga, qaysi xizmat,
 * qaysi holatdan qaysiga, sabab, qachon (41-qoida).
 */

const caps = require('../core/capabilities');
const { candidateIdsFor, toCanonicalId } = require('../core/ids');
const { assertAnalyticsAdmin } = require('../analytics/access');
const { readAccountId, commitAccountId } = require('./capabilities');

const COLLECTION = 'provider_capabilities';
const AUDIT = 'capability_audit';

function httpError(code, message) {
  const e = new Error(message);
  e.code = code;
  return e;
}

/** accountId yoki telefon → accountId. */
async function resolveAccountId(db, data) {
  if (data && data.accountId) return String(data.accountId);
  const phone = toCanonicalId(data && data.phone);
  if (!phone) throw httpError('invalid-argument', 'accountId yoki phone kerak');
  for (const id of candidateIdsFor(phone)) {
    const u = await db.collection('users').doc(id).get();
    if (u.exists && (u.data() || {}).accountId) return String(u.data().accountId);
  }
  throw httpError('not-found', 'Bu telefonda capability yo\'q');
}

/**
 * Statusni o'zgartirish — `canTransition(service, from, to, 'admin')`.
 * Noto'g'ri o'tish RAD etiladi (17-qoida), masalan taksida `approved`.
 */
function makeAdminSetCapabilityStatus(deps) {
  const { db, now: nowFn } = deps;

  return async function adminSetCapabilityStatus(data, context) {
    const adminId = await assertAnalyticsAdmin(db, context);
    const service = String((data && data.service) || '');
    if (!caps.isService(service)) throw httpError('invalid-argument', `noma'lum xizmat: «${service}»`);
    const to = String((data && data.status) || '');
    const reason = String((data && data.reason) || '').slice(0, 500);
    const accountId = await resolveAccountId(db, data);
    const now = nowFn ? nowFn() : new Date();

    return db.runTransaction(async (tx) => {
      const ref = db.collection(COLLECTION).doc(accountId);
      const snap = await tx.get(ref);
      if (!snap.exists) throw httpError('not-found', 'capability hujjati yo\'q');
      const doc = snap.data() || {};
      const from = caps.statusOf(doc, service);
      if (!caps.canTransition(service, from, to, 'admin')) {
        throw httpError('failed-precondition', `${service}: «${from}» → «${to}» o'tishi admin uchun yopiq`);
      }
      // D-TAXI-24.1: `verified` (pullik e'lon huquqi) faqat joriy kelishuv
      // qabul qilingandan keyin. Kelishuvni haydovchi O'ZI qabul qiladi —
      // admin uning o'rniga belgilay olmaydi.
      // Faqat PULLIK huquq beradigan holatga o'tishda (taksi: `verified`);
      // `verification_required`/`suspended` ga qaytarish kelishuvsiz ham mumkin.
      if (caps.agreementDue(service, to) && caps.lifecycleOf(service).paidPublish.includes(to)) {
        const agr = await tx.get(db.collection('service_agreements').doc(accountId));
        if (!caps.hasCurrentAgreement(agr.exists ? agr.data() : null, service)) {
          const e = httpError('failed-precondition', `${service} kelishuvi haydovchi tomonidan hali qabul qilinmagan`);
          e.details = { reason: 'agreement_required', agreementVersion: caps.AGREEMENT_VERSIONS[service] };
          throw e;
        }
      }

      const patch = { status: { [service]: to }, updatedAt: now };
      if (to === caps.COMMON.suspended) {
        patch.suspend = { [service]: { at: now, reason: reason || 'admin', by: adminId } };
      } else {
        patch.review = { [service]: { reviewedBy: adminId, at: now, decision: to, reason } };
      }
      tx.set(ref, patch, { merge: true });

      // 41-qoida: audit — append-only, o'zgarmas.
      tx.set(db.collection(AUDIT).doc(), {
        accountId, service, from, to, reason, by: adminId, at: now, kind: 'status_change',
      });
      return { accountId, service, from, to };
    });
  };
}

/**
 * ADMIN QO'SHADI — telefon bo'yicha (D-CLEAN-1 dan keyin `couriers`
 * hujjati huquq bermaydi; admin panelning «Kuryer qo'shish»i shu yerga).
 *
 * Faqat `not_registered` dan: allaqachon ro'yxatda bo'lgan odamning
 * holati (masalan `suspended` — sababi bor) «qo'shish» tugmasi bilan
 * jimgina tiklanmasin; buning uchun ro'yxatdagi amal
 * (`adminSetCapabilityStatus`, sabab bilan) bor.
 *
 * Odam ilovaga kamida bir marta kirgan bo'lishi shart (`users` hujjati):
 * kirmagan raqamga `users` hujjatini server o'ylab yaratmaydi.
 *
 * `<xizmat>.active` (XOHISH, T-3) yozilmaydi — uni odamning o'zi yoqadi.
 * IDEMPOTENT: qayta chaqiruv `changed: false` qaytaradi (21-qoida).
 */
function makeAdminGrantCapability(deps) {
  const { db, now: nowFn } = deps;

  return async function adminGrantCapability(data, context) {
    const adminId = await assertAnalyticsAdmin(db, context);
    const service = String((data && data.service) || '');
    const path = caps.ADMIN_GRANT_PATH[service];
    if (!path) throw httpError('invalid-argument', `«${service}» xizmatini admin qo'sha olmaydi`);
    const phone = toCanonicalId(data && data.phone);
    if (!phone) throw httpError('invalid-argument', 'telefon raqam noto\'g\'ri');
    const reason = String((data && data.reason) || '').slice(0, 500) || 'admin_grant';
    const target = path[path.length - 1];
    const now = nowFn ? nowFn() : new Date();

    return db.runTransaction(async (tx) => {
      const acc = await readAccountId(db, tx, phone);
      if (!acc.userExists) {
        const e = httpError('not-found', 'bu raqam ilovaga hali kirmagan');
        e.details = { reason: 'user_not_registered' };
        throw e;
      }
      const { accountId } = acc;
      const ref = db.collection(COLLECTION).doc(accountId);
      const snap = await tx.get(ref);
      const doc = snap.exists ? (snap.data() || {}) : {};
      const current = caps.statusOf(doc, service);

      if (current === target) return { accountId, service, status: current, changed: false };
      if (current !== caps.COMMON.notRegistered) {
        const e = httpError('failed-precondition', `${service}: allaqachon «${current}» holatida`);
        e.details = { reason: 'already_registered', status: current };
        throw e;
      }

      // Har qadam state machine bo'yicha — yangi o'tish qo'shilmaydi (17-qoida).
      const steps = [];
      let from = current;
      for (const to of path) {
        if (!caps.canTransition(service, from, to, 'admin')) {
          throw httpError('failed-precondition', `${service}: «${from}» → «${to}» o'tishi admin uchun yopiq`);
        }
        steps.push({ from, to });
        from = to;
      }

      // Barcha o'qishlar tugadi — endi yozuvlar.
      commitAccountId(tx, acc);
      const existingWindow = ((doc.window || {})[service]) || null;
      const patch = {
        identity: { accountId, primaryUid: phone },
        status: { [service]: target },
        review: { [service]: { reviewedBy: adminId, at: now, decision: target, reason } },
        updatedAt: now,
      };
      if (!(existingWindow && existingWindow.startedAt)) {
        const window = caps.windowFor(service, now);
        if (window) patch.window = { [service]: window };
      }
      tx.set(ref, patch, { merge: true });

      // 41-qoida: har qadam alohida, append-only.
      for (const s of steps) {
        tx.set(db.collection(AUDIT).doc(), {
          accountId, service, from: s.from, to: s.to, reason, by: adminId, at: now, kind: 'admin_grant',
        });
      }
      return { accountId, service, status: target, changed: true };
    });
  };
}

/**
 * T-6 MIGRATSIYASI: mavjud tasdiqlangan haydovchilar (`drivers.approved`)
 * → `taxi.status = verified` + `billingGraceUntil = now + 4 oy`.
 * Starter'ga TUSHIRILMAYDI (ega qarori).
 *
 * `dryRun` STANDART TRUE (27-qoida): avval ro'yxat, keyin yozish.
 * IDEMPOTENT: allaqachon `verified` bo'lganlar o'tkazib yuboriladi,
 * grace qayta yozilmaydi.
 */
function makeAdminMigrateTaxiDrivers(deps) {
  const { db, now: nowFn } = deps;

  return async function adminMigrateTaxiDrivers(data, context) {
    const adminId = await assertAnalyticsAdmin(db, context);
    const dryRun = !(data && data.dryRun === false);
    const now = nowFn ? nowFn() : new Date();
    const graceUntil = caps.addMonths(now, caps.BILLING_GRACE_MONTHS);

    const snap = await db.collection('drivers').where('approved', '==', true).get();
    const out = { dryRun, total: snap.size, migrated: [], skipped: [], errors: [] };

    for (const d of snap.docs) {
      const phone = toCanonicalId(d.id);
      if (!phone) { out.skipped.push({ id: d.id, reason: 'non_canonical_id' }); continue; }
      try {
        const result = await db.runTransaction(async (tx) => {
          const acc = await readAccountId(db, tx, phone);
          const { accountId } = acc;
          const ref = db.collection(COLLECTION).doc(accountId);
          const cap = await tx.get(ref);
          const doc = cap.exists ? (cap.data() || {}) : {};
          const current = caps.statusOf(doc, 'taxi');
          if (current === caps.TAXI.verified) return { accountId, skipped: 'already_verified' };
          // dryRun hech narsa yozmaydi — `users.accountId` ham.
          if (dryRun) return { accountId, from: current, to: caps.TAXI.verified, dryRun: true };

          const existing = ((doc.window || {}).taxi) || {};
          commitAccountId(tx, acc);
          tx.set(ref, {
            identity: { accountId, primaryUid: phone },
            taxi: { active: true },
            status: { taxi: caps.TAXI.verified },
            window: {
              taxi: {
                startedAt: existing.startedAt || now,
                verificationDueAt: existing.verificationDueAt || null,
                billingGraceUntil: existing.billingGraceUntil || graceUntil,
              },
            },
            review: { taxi: { reviewedBy: adminId, at: now, decision: caps.TAXI.verified, reason: 'migration_t6' } },
            updatedAt: now,
          }, { merge: true });
          tx.set(db.collection(AUDIT).doc(), {
            accountId, service: 'taxi', from: current, to: caps.TAXI.verified,
            reason: 'migration_t6', by: adminId, at: now, kind: 'migration',
          });
          return { accountId, from: current, to: caps.TAXI.verified };
        });
        if (result.skipped) out.skipped.push({ id: d.id, ...result });
        else out.migrated.push({ id: d.id, ...result });
      } catch (e) {
        out.errors.push({ id: d.id, error: e.message });
      }
    }
    out.migratedCount = out.migrated.length;
    return out;
  };
}

module.exports = {
  AUDIT, resolveAccountId, makeAdminSetCapabilityStatus, makeAdminGrantCapability,
  makeAdminMigrateTaxiDrivers,
};
