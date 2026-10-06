'use strict';

/**
 * XIZMAT KELISHUVLARI — D-SERVICE-2, D-TAXI-24.
 *
 *   service_agreements/{accountId}
 *     taxi:    { version, acceptedAt, acceptedByUid }
 *     courier: { version, acceptedAt, acceptedByUid }
 *
 * FAQAT SERVER yozadi (qoida: write false). Klient `acceptServiceAgreement`
 * ni chaqiradi; versiya `core/capabilities.AGREEMENT_VERSIONS` dan —
 * ikkala codebase (demand va default/taxi billing) bir xil raqamni
 * ko'radi (nusxa pariteti).
 *
 * Kalit `accountId` (T-1a): kelishuv AKKAUNTGA tegishli, telefon
 * almashsa ham saqlanadi. accountId bo'lmasa shu yerda yaratiladi
 * (`ensureAccountId`) — chunki D-TAXI-24 bo'yicha kelishuv xizmat
 * yoqilishidan OLDIN qabul qilinadi.
 */

const caps = require('../core/capabilities');
const { callerIdFrom } = require('../core/ids');
const { ensureAccountId } = require('./capabilities');

const COLLECTION = 'service_agreements';

function httpError(code, message) {
  const e = new Error(message);
  e.code = code;
  return e;
}

function makeAcceptServiceAgreement(deps) {
  const { db, now: nowFn } = deps;

  return async function acceptServiceAgreement(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw httpError('unauthenticated', 'Telefon bilan kirish kerak');

    const service = String((data && data.service) || '');
    if (!caps.isService(service)) throw httpError('invalid-argument', `noma'lum xizmat: «${service}»`);

    const required = caps.AGREEMENT_VERSIONS[service];
    const version = Number(data && data.version);
    // Eski matnni «qabul qildim» deb yuborib bo'lmaydi — faqat JORIY.
    if (version !== required) {
      throw httpError('failed-precondition', `kelishuv versiyasi ${required} bo'lishi kerak`);
    }

    const now = nowFn ? nowFn() : new Date();
    return db.runTransaction(async (tx) => {
      const { accountId } = await ensureAccountId(db, tx, callerId);
      const ref = db.collection(COLLECTION).doc(accountId);
      const snap = await tx.get(ref);
      const doc = snap.exists ? (snap.data() || {}) : {};
      // IDEMPOTENT: shu versiya allaqachon qabul qilingan bo'lsa — qayta yozilmaydi.
      if (caps.hasCurrentAgreement(doc, service)) {
        return { accountId, service, version: required, changed: false };
      }
      tx.set(ref, {
        accountId,
        [service]: { version: required, acceptedAt: now, acceptedByUid: callerId },
        updatedAt: now,
      }, { merge: true });
      return { accountId, service, version: required, changed: true };
    });
  };
}

module.exports = { COLLECTION, makeAcceptServiceAgreement };
