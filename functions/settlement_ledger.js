/**
 * Settlement Ledger — yadro (V1, Qadam 1).
 *
 * Double-entry (ikki tomonlama) buxgalteriya yadrosi:
 *   - journal_entries/{idempotencyKey}  — o'zgarmas (append-only) jurnal
 *   - ledger_accounts/{accountId}        — materialized (kesh) balans
 *
 * Asosiy invariant: har bir yozuvda Σdebit == Σcredit.
 * Balanslar HECH QACHON qo'lda emas — faqat shu post() orqali o'zgaradi.
 *
 * To'liq dizayn: docs/settlement_ledger_v1_uz.md
 */
const admin = require('firebase-admin');

const COL_ACCOUNTS = 'ledger_accounts';
const COL_JOURNAL = 'journal_entries';
const COL_SETTLEMENTS = 'settlements';

/**
 * Hisob turlari va ularning "normal" tomoni:
 *   asset      → balans (debit - credit) ni kuzatadi
 *   liability  → balans (credit - debit) ni kuzatadi
 * admin_clearing — ichki muvozanat/equity hisobi (debit-normal).
 */
const ACCOUNT_TYPES = {
  admin_cash: 'asset',
  admin_clearing: 'asset',
  driver_float: 'liability',
  passenger_credit: 'liability',
  supplier_payable: 'liability',
  earnings: 'liability',
};

function accountTypeOf(accountId) {
  const prefix = String(accountId).split(':')[0];
  return ACCOUNT_TYPES[prefix] || null;
}

function ownerUidOf(accountId) {
  const parts = String(accountId).split(':');
  return parts.length > 1 ? parts.slice(1).join(':') : '';
}

/** Hisobning natural-belgili o'zgarishi (delta) — turga qarab. */
function naturalDelta(accountId, dr, cr) {
  return accountTypeOf(accountId) === 'liability' ? cr - dr : dr - cr;
}

function isPositiveInt(n) {
  return typeof n === 'number' && Number.isFinite(n) && Math.floor(n) === n && n >= 0;
}

/** Account id'lari (`type:uid`) — passenger_credit yordamchilari. */
function passengerCreditAccount(uid) {
  return `passenger_credit:${uid}`;
}
function driverFloatAccount(uid) {
  return `driver_float:${uid}`;
}

/**
 * Legs'ni tekshiradi va normallashtiradi.
 * Har leg: { account, dr?, cr? } — dr yoki cr dan FAQAT bittasi > 0.
 * Σdr == Σcr va > 0 bo'lishi shart.
 */
function buildEntry(input) {
  const {
    idempotencyKey,
    kind,
    legs,
    refType = '',
    refId = '',
    postedBy = 'system',
    postedRole = 'system',
  } = input || {};

  if (!idempotencyKey || typeof idempotencyKey !== 'string') {
    throw new Error('settlement: idempotencyKey required');
  }
  if (!kind || typeof kind !== 'string') {
    throw new Error('settlement: kind required');
  }
  if (!Array.isArray(legs) || legs.length < 2) {
    throw new Error('settlement: at least 2 legs required');
  }

  let sumDr = 0;
  let sumCr = 0;
  const normLegs = legs.map((l) => {
    const account = String((l && l.account) || '');
    if (!accountTypeOf(account)) {
      throw new Error(`settlement: unknown account "${account}"`);
    }
    const dr = (l && l.dr) || 0;
    const cr = (l && l.cr) || 0;
    if (!isPositiveInt(dr) || !isPositiveInt(cr)) {
      throw new Error(`settlement: dr/cr must be non-negative integers (${account})`);
    }
    if ((dr > 0) === (cr > 0)) {
      throw new Error(`settlement: leg needs exactly one of dr/cr > 0 (${account})`);
    }
    sumDr += dr;
    sumCr += cr;
    return { account, dr, cr };
  });

  if (sumDr !== sumCr) {
    throw new Error(`settlement: unbalanced entry (dr=${sumDr}, cr=${sumCr})`);
  }
  if (sumDr <= 0) {
    throw new Error('settlement: zero-amount entry');
  }

  return {
    idempotencyKey,
    kind,
    legs: normLegs,
    refType,
    refId,
    postedBy,
    postedRole,
    amount: sumDr,
  };
}

/**
 * Atomar jurnal yozuvini post qiladi. Idempotent: hujjat id = idempotencyKey,
 * agar mavjud bo'lsa qayta yozmaydi.
 *
 * options:
 *   mirrorBonus      (default true)  — passenger_credit delta'sini
 *                                      users/{uid}.bonusBalance ga ko'chiradi
 *   walletLedgerType (default null)  — berilsa, users/{uid}/wallet_ledger ga
 *                                      foydalanuvchiga ko'rinadigan yozuv qo'shadi
 *   meta             (default {})    — qo'shimcha ma'lumot
 *   precheck         (default null)  — TRANSACTION ICHIDA, yozuvdan OLDIN (READ
 *                                      fazasi): precheck(tx) → pre. Settlement
 *                                      holatini o'qish/validatsiya uchun.
 *   assert           (default null)  — TRANSACTION ICHIDA chaqiriladi:
 *                                      assert({ accounts: Map(id -> {prev,delta,next}), pre }).
 *                                      Error tashlasa, post bekor qilinadi (atomar
 *                                      precondition: float cap, manfiylik, h.k.)
 *   onCommit         (default null)  — TRANSACTION ICHIDA, yozuv fazasida:
 *                                      onCommit(tx, { entryId, balances, pre }).
 *                                      Settlement holatini ATOMAR yangilash uchun.
 *   accountExtras    (default null)  — accountExtras(accountId, {prev,delta,next})
 *                                      → hisob hujjatiga qo'shimcha merge maydonlari
 *                                      (masalan float blok/lastTopUp) — ikkilanmas yozuv.
 *
 * Qaytaradi: { id, idempotent, amount, balances, pre }.
 */
async function postEntry(db, entryInput, options = {}) {
  const {
    mirrorBonus = true, walletLedgerType = null, meta = {},
    assert = null, precheck = null, onCommit = null, accountExtras = null,
  } = options;
  const entry = buildEntry(entryInput);
  const entryRef = db.collection(COL_JOURNAL).doc(entry.idempotencyKey);

  return db.runTransaction(async (tx) => {
    // 1) Idempotentlik — allaqachon postlangan bo'lsa, hech narsa qilmaymiz.
    const existing = await tx.get(entryRef);
    if (existing.exists) {
      return {
        id: entryRef.id, idempotent: true, amount: entry.amount, balances: {}, pre: null,
      };
    }

    // READ fazasi: caller validatsiyasi (settlement holati va h.k.) — yozuvdan oldin.
    const pre = (typeof precheck === 'function') ? await precheck(tx) : null;

    // Hisob bo'yicha umumiy delta'lar.
    const accDelta = new Map();
    for (const leg of entry.legs) {
      const d = naturalDelta(leg.account, leg.dr, leg.cr);
      accDelta.set(leg.account, (accDelta.get(leg.account) || 0) + d);
    }
    const accIds = [...accDelta.keys()];
    const accRefs = accIds.map((id) => db.collection(COL_ACCOUNTS).doc(id));

    // passenger_credit egalari (bonus proeksiyasi uchun).
    const pcUids = mirrorBonus
      ? accIds
          .filter((id) => id.startsWith('passenger_credit:'))
          .map((id) => ownerUidOf(id))
          .filter((u) => u)
      : [];
    const userRefs = pcUids.map((u) => db.collection('users').doc(u));

    // 2) BARCHA o'qishlar yozuvdan OLDIN (transaction qoidasi).
    const accSnaps = await Promise.all(accRefs.map((r) => tx.get(r)));

    // Hisob holatlari (prev/delta/next) — assert va yozuv uchun.
    const state = new Map();
    const balances = {};
    for (let i = 0; i < accIds.length; i++) {
      const id = accIds[i];
      const prev = accSnaps[i].exists ? (accSnaps[i].data().balance || 0) : 0;
      const delta = accDelta.get(id);
      const next = prev + delta;
      state.set(id, { prev, delta, next });
      balances[id] = next;
    }

    // Atomar precondition (ixtiyoriy): float cap, manfiylik tekshiruvi va h.k.
    if (typeof assert === 'function') {
      await assert({ accounts: state, pre });
    }

    // 3) Yozuvlar.
    tx.set(entryRef, {
      ts: admin.firestore.FieldValue.serverTimestamp(),
      kind: entry.kind,
      idempotencyKey: entry.idempotencyKey,
      refType: entry.refType,
      refId: entry.refId,
      postedBy: entry.postedBy,
      postedRole: entry.postedRole,
      amount: entry.amount,
      legs: entry.legs,
      meta,
      status: 'posted',
    });

    for (let i = 0; i < accIds.length; i++) {
      const id = accIds[i];
      const extra = (typeof accountExtras === 'function')
        ? (accountExtras(id, state.get(id)) || {})
        : {};
      tx.set(accRefs[i], {
        type: accountTypeOf(id),
        ownerUid: ownerUidOf(id),
        balance: state.get(id).next,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...extra,
      }, { merge: true });
    }

    if (mirrorBonus) {
      for (let i = 0; i < pcUids.length; i++) {
        const uid = pcUids[i];
        const delta = accDelta.get(passengerCreditAccount(uid)) || 0;
        if (delta === 0) continue;
        tx.set(userRefs[i], {
          bonusBalance: admin.firestore.FieldValue.increment(delta),
        }, { merge: true });
        if (walletLedgerType) {
          const wlRef = userRefs[i].collection('wallet_ledger').doc();
          tx.set(wlRef, {
            type: walletLedgerType,
            amount: delta,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            refType: entry.refType,
            refId: entry.refId,
            meta,
          });
        }
      }
    }

    // Qo'shimcha atomar yozuvlar (ixtiyoriy): settlement holatini yangilash.
    if (typeof onCommit === 'function') {
      await onCommit(tx, { entryId: entryRef.id, balances, pre });
    }

    return { id: entryRef.id, idempotent: false, amount: entry.amount, balances, pre };
  });
}

// ─────────────────────────────────────────────────────────────────────
// Float sozlamalari va zona siyosati (settings/settlement).
// To'liq dizayn: docs/settlement_ledger_v1_uz.md (8-bo'lim)
// ─────────────────────────────────────────────────────────────────────
const DEFAULT_CONFIG = {
  floatMin: 100000, // 🟢 sog'lom chegarasi
  floatCritical: 20000, // 🔴 kritik chegara (settlement o'chadi)
  floatMax: 500000, // ⛔ maksimal float (deposit cap)
  deferredNegativeFloatPct: 10, // deferred: manfiy float % (oxirgi depozitdan)
  deferredTimeoutHours: 48, // deferred reconcile muddati
};

function numOr(v, def) {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

/** `settings/settlement` config (default'lar bilan). */
async function getConfig(db) {
  try {
    const doc = await db.collection('settings').doc('settlement').get();
    const d = doc.exists ? (doc.data() || {}) : {};
    return {
      floatMin: numOr(d.floatMin, DEFAULT_CONFIG.floatMin),
      floatCritical: numOr(d.floatCritical, DEFAULT_CONFIG.floatCritical),
      floatMax: numOr(d.floatMax, DEFAULT_CONFIG.floatMax),
      deferredNegativeFloatPct: numOr(
          d.deferredNegativeFloatPct, DEFAULT_CONFIG.deferredNegativeFloatPct),
      deferredTimeoutHours: numOr(
          d.deferredTimeoutHours, DEFAULT_CONFIG.deferredTimeoutHours),
    };
  } catch (e) {
    return { ...DEFAULT_CONFIG };
  }
}

/** Float zonasi: 'critical' | 'low' | 'healthy'. */
function floatZone(balance, config) {
  if (balance < config.floatCritical) return 'critical';
  if (balance < config.floatMin) return 'low';
  return 'healthy';
}

/** Settlement shu float bilan ishlay oladimi (kritik emas va > 0). */
function settlementEnabled(balance, config) {
  return balance > 0 && floatZone(balance, config) !== 'critical';
}

/**
 * Deferred (offline-lite) uchun ruxsat etilgan ENG PAST float (manfiy).
 * = -(oxirgi depozitning deferredNegativeFloatPct %i), butun songacha.
 * lastTopUpAmount yo'q bo'lsa → 0 (deferred ruxsat etilmaydi, naqd shart).
 */
function deferredFloor(lastTopUpAmount, config) {
  const base = numOr(lastTopUpAmount, 0);
  if (base <= 0) return 0;
  const pct = numOr(config.deferredNegativeFloatPct, 0);
  return -Math.round((base * pct) / 100);
}

/**
 * Sverka (reconciliation): invariantlarni tekshiradi.
 *   1) Global Σdebit == Σcredit
 *   2) Buxgalteriya tengligi: Σ asset balanslar == Σ liability balanslar
 *   3) passenger_credit.balance == users/{uid}.bonusBalance (proeksiya)
 */
async function reconcile(db) {
  const [accSnap, jSnap] = await Promise.all([
    db.collection(COL_ACCOUNTS).get(),
    db.collection(COL_JOURNAL).get(),
  ]);

  let totalDr = 0;
  let totalCr = 0;
  jSnap.forEach((d) => {
    const legs = (d.data() || {}).legs || [];
    for (const l of legs) {
      totalDr += l.dr || 0;
      totalCr += l.cr || 0;
    }
  });

  let assets = 0;
  let liabilities = 0;
  const pcAccounts = [];
  accSnap.forEach((d) => {
    const a = d.data() || {};
    const t = a.type || accountTypeOf(d.id);
    const bal = a.balance || 0;
    if (t === 'liability') liabilities += bal;
    else assets += bal;
    if (d.id.startsWith('passenger_credit:')) {
      pcAccounts.push({ uid: ownerUidOf(d.id), balance: bal });
    }
  });

  const mismatches = [];
  for (const a of pcAccounts) {
    const u = await db.collection('users').doc(a.uid).get();
    const bonus = u.exists ? (u.data().bonusBalance || 0) : 0;
    if (bonus !== a.balance) {
      mismatches.push({ uid: a.uid, ledger: a.balance, bonusBalance: bonus });
    }
  }

  return {
    balanced: totalDr === totalCr,
    totalDr,
    totalCr,
    identityOk: assets === liabilities,
    assets,
    liabilities,
    projectionOk: mismatches.length === 0,
    mismatches,
    accountCount: accSnap.size,
    entryCount: jSnap.size,
    checkedAt: new Date().toISOString(),
  };
}

module.exports = {
  COL_ACCOUNTS,
  COL_JOURNAL,
  COL_SETTLEMENTS,
  ACCOUNT_TYPES,
  DEFAULT_CONFIG,
  accountTypeOf,
  ownerUidOf,
  naturalDelta,
  passengerCreditAccount,
  driverFloatAccount,
  buildEntry,
  postEntry,
  getConfig,
  floatZone,
  settlementEnabled,
  deferredFloor,
  reconcile,
};
