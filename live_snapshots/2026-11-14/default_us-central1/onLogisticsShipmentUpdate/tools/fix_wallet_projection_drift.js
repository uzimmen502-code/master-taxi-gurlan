/**
 * Ҳамён аудити Y-1 — тарихий проекция дрейфини тузатиш (бир марталик).
 *
 * Сабаб: `publishTvAd`, `renewTvAd`, `purchaseRealty*` 2026-10-08 гача
 * фақат `users.bonusBalance`ни камайтирарди, `passenger_credit:{uid}`
 * камаймасди. Натижа: ledger > bonusBalance (фарқ = ledger'сиз сарф).
 *
 * Тузатиш (фақат ledger > bonusBalance ҳолати):
 *   Debit  passenger_credit:{uid}   (фарқ)
 *   Credit admin_clearing           (фарқ)   — EV/ёрдамчи сарфи билан бир хил
 *   kind 'projection_fix', калит `projection_fix_v1:{uid}`, mirrorBonus false
 *   (bonusBalance аллақачон тўғри — фақат ledger'ни унга тенглаймиз).
 * ledger < bonusBalance (ledger'сиз КРЕДИТ) ва ҳисоби йўқ ҳолатлар фақат
 * ҳисоботга чиқади — сабаби аниқланмагунча автоматик тузатилмайди.
 *
 * Хавфсизлик (CLAUDE.md 27/28):
 *   - СТАНДАРТ dry-run: фақат ўқийди ва ҳисобот беради.
 *   - `--write`: аввал режа файлга сақланади (backup), кейин ҳар бир ёзув
 *     транзакцияда ҚАЙТА текширилади — орада баланс ўзгарган бўлса (STALE)
 *     ўтказиб юборилади ва ҳисоботга чиқади. Идемпотент.
 *   - `--rollback`: ҳар бир `projection_fix` ёзувига тескари (storno) ёзув.
 *   - Терминалда рақамлар яширилади (охирги 4 хона); тўлиқ режа — файлда.
 *
 * Ишлатиш (functions/ папкасидан):
 *   node tools/fix_wallet_projection_drift.js                 # dry-run
 *   node tools/fix_wallet_projection_drift.js --write         # ёзиш
 *   node tools/fix_wallet_projection_drift.js --rollback      # қайтариш
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const FIX_KIND = 'projection_fix';
const fixKey = (uid) => `projection_fix_v1:${uid}`;
const PC_PREFIX = 'passenger_credit:';
const mask = (uid) => `***${String(uid).slice(-4)}`;

async function readUsersBonus(db, uids) {
  const out = new Map();
  for (let i = 0; i < uids.length; i += 100) {
    const refs = uids.slice(i, i + 100).map((u) => db.collection('users').doc(u));
    const snaps = refs.length ? await db.getAll(...refs) : [];
    snaps.forEach((s, j) => {
      // undefined — ҳужжат йўқ; майдон йўқ бўлса — 0.
      out.set(uids[i + j], s.exists ? ((s.data() || {}).bonusBalance ?? 0) : undefined);
    });
  }
  return out;
}

/** Фақат ўқийди. Қайтаради: { fixable[], untrackedCredit[], invalid[], noAccount[] }. */
async function planDrift(db) {
  const FieldPath = admin.firestore.FieldPath;
  const accSnap = await db.collection(ledger.COL_ACCOUNTS)
      .orderBy(FieldPath.documentId())
      .startAt(PC_PREFIX)
      .endAt(`${PC_PREFIX}`)
      .get();
  const accounts = new Map();
  accSnap.forEach((d) => accounts.set(ledger.ownerUidOf(d.id), (d.data() || {}).balance || 0));
  const bonus = await readUsersBonus(db, [...accounts.keys()]);

  const plan = { fixable: [], untrackedCredit: [], invalid: [], noAccount: [] };
  for (const [uid, ledgerBal] of accounts) {
    const raw = bonus.get(uid);
    if (raw === undefined) {
      // `users` ҳужжати йўқ — ledger қолдиғи жимгина нолга туширилмайди.
      if (ledgerBal !== 0) plan.invalid.push({ uid, ledger: ledgerBal, bonusBalance: null, reason: 'no_user_doc' });
      continue;
    }
    const b = Number(raw);
    if (!Number.isInteger(b) || !Number.isInteger(ledgerBal)) {
      plan.invalid.push({ uid, ledger: ledgerBal, bonusBalance: raw });
      continue;
    }
    const diff = ledgerBal - b;
    if (diff > 0) plan.fixable.push({ uid, ledger: ledgerBal, bonusBalance: b, diff });
    else if (diff < 0) plan.untrackedCredit.push({ uid, ledger: ledgerBal, bonusBalance: b, diff });
  }
  // bonusBalance бор, лекин ledger ҳисоби йўқ (opening balance тушиб қолган).
  const usersSnap = await db.collection('users').where('bonusBalance', '>', 0).get();
  usersSnap.forEach((d) => {
    if (!accounts.has(d.id)) {
      plan.noAccount.push({ uid: d.id, bonusBalance: (d.data() || {}).bonusBalance });
    }
  });
  return plan;
}

/** Ҳар бир `fixable` учун транзакцияда қайта текшириб пост қилади. */
async function applyPlan(db, plan) {
  const res = { posted: [], idempotent: [], stale: [], failed: [] };
  for (const row of plan.fixable) {
    const pcId = ledger.passengerCreditAccount(row.uid);
    const userRef = db.collection('users').doc(row.uid);
    try {
      const r = await ledger.postEntry(db, {
        idempotencyKey: fixKey(row.uid),
        kind: FIX_KIND,
        refType: 'migration',
        refId: 'wallet_audit_Y1',
        postedBy: 'migration',
        postedRole: 'system',
        legs: [
          { account: pcId, dr: row.diff },
          { account: 'admin_clearing', cr: row.diff },
        ],
      }, {
        mirrorBonus: false,
        meta: { ledgerBefore: row.ledger, bonusBalance: row.bonusBalance },
        precheck: async (tx) => {
          const u = await tx.get(userRef);
          return { bonus: u.exists ? (u.data() || {}).bonusBalance || 0 : 0 };
        },
        assert: ({ accounts, pre }) => {
          const pc = accounts.get(pcId);
          if (!pc || pc.prev !== row.ledger || pre.bonus !== row.bonusBalance) {
            const e = new Error('STALE');
            e.stale = true;
            throw e;
          }
        },
      });
      (r.idempotent ? res.idempotent : res.posted).push(row);
    } catch (e) {
      if (e && e.stale) res.stale.push(row);
      else res.failed.push({ ...row, error: e.message });
    }
  }
  return res;
}

/** Ҳар бир `projection_fix` ёзувига тескари (storno) ёзув. Идемпотент. */
async function rollback(db) {
  const snap = await db.collection(ledger.COL_JOURNAL).where('kind', '==', FIX_KIND).get();
  const out = { reversed: 0, idempotent: 0 };
  for (const d of snap.docs) {
    const e = d.data() || {};
    const legs = (e.legs || []).map((l) => ({ account: l.account, dr: l.cr || 0, cr: l.dr || 0 }));
    const r = await ledger.postEntry(db, {
      idempotencyKey: `${d.id}:rollback`,
      kind: `${FIX_KIND}_rollback`,
      refType: 'migration',
      refId: d.id,
      postedBy: 'migration',
      postedRole: 'system',
      legs,
    }, { mirrorBonus: false });
    if (r.idempotent) out.idempotent += 1;
    else out.reversed += 1;
  }
  return out;
}

function summarize(plan) {
  const sum = (a) => a.reduce((s, r) => s + Math.abs(r.diff || 0), 0);
  console.log(`  Тузатиладиган (ledger > bonusBalance): ${plan.fixable.length}, жами ${sum(plan.fixable)} сўм`);
  for (const r of plan.fixable) console.log(`    ${mask(r.uid)}  ledger ${r.ledger} → ${r.bonusBalance}  (−${r.diff})`);
  console.log(`  ⚠ ledger < bonusBalance (тузатилмайди, текширинг): ${plan.untrackedCredit.length}, жами ${sum(plan.untrackedCredit)} сўм`);
  for (const r of plan.untrackedCredit) console.log(`    ${mask(r.uid)}  ledger ${r.ledger}, bonusBalance ${r.bonusBalance}`);
  console.log(`  ⚠ Нотўғри қиймат: ${plan.invalid.length}; ledger ҳисоби йўқ (bonusBalance>0): ${plan.noAccount.length}`);
}

async function main() {
  const WRITE = process.argv.includes('--write');
  const ROLLBACK = process.argv.includes('--rollback');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-wallet-audit' });
    } else {
      // eslint-disable-next-line global-require
      const sa = require(path.join(__dirname, '..', 'service-account.json'));
      admin.initializeApp({ credential: admin.credential.cert(sa) });
    }
  }
  const db = admin.firestore();

  if (ROLLBACK) {
    console.log('=== Проекция тузатишини ҚАЙТАРИШ (storno) ===');
    console.log(JSON.stringify(await rollback(db)));
    return;
  }
  console.log(`=== Ҳамён проекция дрейфи ${WRITE ? '(ЁЗИШ)' : '(DRY-RUN)'} ===`);
  const plan = await planDrift(db);
  summarize(plan);
  if (!WRITE) {
    console.log('\nDry-run: ҳеч нарса ёзилмади. Ёзиш учун: --write');
    return;
  }
  // Режада телефон рақамлари бор — репо ичига эмас (тасодифий commit бўлмасин).
  const backup = path.join(require('os').tmpdir(), `projection_drift_plan_${Date.now()}.json`);
  fs.writeFileSync(backup, JSON.stringify(plan, null, 2));
  console.log(`\nРежа сақланди (backup): ${backup}`);
  const res = await applyPlan(db, plan);
  console.log(`  Ёзилди: ${res.posted.length}; аллақачон бор: ${res.idempotent.length}; ` +
      `STALE (орада ўзгарган, ўтказилди): ${res.stale.length}; хато: ${res.failed.length}`);
  for (const f of res.failed) console.log(`    ${mask(f.uid)}: ${f.error}`);
  const rep = await ledger.reconcile(db);
  console.log(`\nReconcile: balanced=${rep.balanced} identityOk=${rep.identityOk} ` +
      `projectionOk=${rep.projectionOk} mismatches=${rep.mismatches.length}`);
}

if (require.main === module) {
  main().then(() => process.exit(0)).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { planDrift, applyPlan, rollback, fixKey, FIX_KIND };
