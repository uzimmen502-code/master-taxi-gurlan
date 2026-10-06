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
const { ensureAccountId } = require('./capabilities');

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
          const { accountId } = await ensureAccountId(db, tx, phone);
          const ref = db.collection(COLLECTION).doc(accountId);
          const cap = await tx.get(ref);
          const doc = cap.exists ? (cap.data() || {}) : {};
          const current = caps.statusOf(doc, 'taxi');
          if (current === caps.TAXI.verified) return { accountId, skipped: 'already_verified' };
          if (dryRun) return { accountId, from: current, to: caps.TAXI.verified, dryRun: true };

          const existing = ((doc.window || {}).taxi) || {};
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
  AUDIT, resolveAccountId, makeAdminSetCapabilityStatus, makeAdminMigrateTaxiDrivers,
};
