/**
 * Ҳамён тарихини тузатиш (W-1, I-3F) — ТАРИХ ЎЧИРИЛМАЙДИ, фақат битта тузатувчи ёзув қўшилади. СТАНДАРТ dry-run.
 *
 * Муаммо: settlement ledger 2026-06-28T08:44Z да `opening:{uid}` билан бошланган (ўша пайтдаги bonusBalance).
 * Ундан ОЛДИНГИ `wallet_ledger` тарихи баъзи ҳамёнларда тўлиқ эмас — bonusBalance тарихсиз ўзгарган:
 *   ***3355: 2026-05 нон буюртмаларида курьер киритган тест қийматлари (`change_accrued` 100 000 000, 30 000 000 …)
 *            «қайтим» бўлиб тушган, кейин bonusBalance тарихсиз камайтирилган (қўлда тозалаш — INFERRED).
 *            Базагача Σ = 153 218 076, opening = 6 475 → фарқ −153 211 601.
 *   ***8777: базагача Σ = 23 672, opening = 22 172 → тарихсиз −1 500.
 * Натижа: I-3 (базадан кейин) ЯШИЛ, I-3F (тўлиқ тарих) ҚИЗИЛ. Баланс ва ledger тўғри — фақат тарих чалкаш.
 *
 * Тузатиш (PROPOSED, эга қарори): ҳар бундай ҳамёнга БИТТА ёзув `wallet_ledger/pre_ledger_adjustment_v1`:
 *   type 'admin_adjust' (иловада аллақачон таржима қилинган ёрлиқ «…»; уч тил қоидаси бузилмайди),
 *   amount = opening − Σ(базагача), createdAt = база − 1 с (тарихда ўз ўрнида кўринади, рўйхат тепасида эмас),
 *   recordedAt = ҳозир (ҳақиқий ёзилган вақт — аудит учун), correction: true, meta.kind 'pre_ledger_adjustment',
 *   meta.preBaselineSum / opening / rows. bonusBalance ва журналга ТЕГИЛМАЙДИ (база олдидаги давр ledger'да йўқ).
 * Кейин I-3F ЯШИЛ бўлади, I-3 ўзгармайди (createdAt < база). Эски тест ёзувлари (100 млн …) ЎЧИРИЛМАЙДИ.
 *
 * Opening тарих ёзуви ҳақида: `wallet_ledger`га `opening_balance` қатори ҚЎШИЛМАЙДИ — у базагача бўлган тарих
 * билан икки марта ҳисобланарди (I-3F бузиларди). Тузатишдан кейин ҳар ҳамёнда Σ(базагача тарих) == opening —
 * ledger очилиш қолдиғи тарихдан тўлиқ келиб чиқади.
 *
 * Хавфсизлик (27/28-банд): dry-run стандарт; `--apply` — режа backup (репо ташқарисида), ҳар ҳамён
 * транзакцияда қайта ҳисобланади (STALE бўлса ёзилмайди), детерминистик id → идемпотент.
 * `--rollback` — ўчирмайди: ҳар тузатишга тескари ёзув `pre_ledger_adjustment_v1_reversal` (createdAt ҳам база − 1 с).
 * Шарт: ҳамёнда I-3 ЯШИЛ бўлиши (акс ҳолда аввал проекция/ledger тузатилади — `needsReview`).
 *
 *   node tools/wallet_history_corrections.js            # dry-run
 *   node tools/wallet_history_corrections.js --apply    # ёзиш (эга рухсати билан)
 *   node tools/wallet_history_corrections.js --rollback # тескари ёзув
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');
const inv = require(path.join(__dirname, '..', 'wallet_invariants'));

const DOC_ID = 'pre_ledger_adjustment_v1';
const REVERSAL_ID = `${DOC_ID}_reversal`;
const mask = (s) => `***${String(s).slice(-4)}`;

/** Режа: I-3F фарқи бор ҳамёнлар учун тузатиш суммаси. Фақат ўқийди. */
async function planCorrections(db) {
  const state = await inv.collectState(db);
  const rep = inv.evaluate(state);
  const i3Bad = new Set(rep.invariants.I3.mismatches.map((m) => m.uid));
  const out = [];
  for (const m of rep.invariants.I3F.mismatches) {
    const rows = state.wallet.get(m.uid) || [];
    const pre = rows.filter((r) => r.effect !== null && r.createdAtMs !== null && r.createdAtMs < inv.BASELINE_MS);
    const preSum = pre.reduce((s, r) => s + r.effect, 0);
    // Тузатишдан кейин Σ(бутун тарих) == bonusBalance. I-3 яшил бўлса, бу айнан opening − Σ(базагача).
    const amount = m.bonusBalance - m.walletAllTime;
    const row = {
      uid: m.uid, bonusBalance: m.bonusBalance, walletAllTime: m.walletAllTime, preBaselineSum: preSum,
      preBaselineRows: pre.length, amount, opening: preSum + amount,
    };
    if (!Number.isInteger(m.bonusBalance)) out.push({ ...row, status: 'needsReview', reason: 'non_integer_bonus' });
    else if (i3Bad.has(m.uid)) out.push({ ...row, status: 'needsReview', reason: 'I3_not_green' });
    else if (rows.some((r) => r.id === DOC_ID)) out.push({ ...row, status: 'needsReview', reason: 'correction_exists' });
    else out.push({ ...row, status: 'fixable' });
  }
  return out;
}

async function applyCorrections(db, plan) {
  const res = { written: [], idempotent: [], stale: [], failed: [] };
  const createdAt = admin.firestore.Timestamp.fromMillis(inv.BASELINE_MS - 1000);
  for (const p of plan.filter((x) => x.status === 'fixable')) {
    const col = db.collection('users').doc(p.uid).collection('wallet_ledger');
    try {
      const out = await db.runTransaction(async (t) => {
        const [userSnap, rowsSnap] = await Promise.all([t.get(db.collection('users').doc(p.uid)), t.get(col)]);
        if (rowsSnap.docs.some((d) => d.id === DOC_ID)) return 'idempotent';
        const bonus = userSnap.exists ? (userSnap.data() || {}).bonusBalance : null;
        const all = rowsSnap.docs.reduce((s, d) => s + (inv.walletRowEffect(d.data()) || 0), 0);
        if (bonus !== p.bonusBalance || all !== p.walletAllTime) {
          const e = new Error('STALE');
          e.stale = true;
          throw e;
        }
        t.create(col.doc(DOC_ID), {
          type: 'admin_adjust',
          amount: p.amount,
          correction: true,
          refType: 'migration',
          refId: 'wallet_history_corrections_v1',
          module: '',
          meta: {
            kind: 'pre_ledger_adjustment',
            preBaselineSum: p.preBaselineSum,
            preBaselineRows: p.preBaselineRows,
            opening: p.opening,
            baselineIso: inv.BASELINE_ISO,
          },
          createdAt,
          recordedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: 'migration',
        });
        return 'written';
      });
      (out === 'idempotent' ? res.idempotent : res.written).push(p.uid);
    } catch (e) {
      if (e && e.stale) res.stale.push(p.uid); else res.failed.push({ uid: p.uid, error: e.message });
    }
  }
  return res;
}

/** Тескари ёзув (ўчирмайди). Идемпотент. */
async function rollbackCorrections(db, uids) {
  const out = { reversed: 0, idempotent: 0, missing: 0 };
  for (const uid of uids) {
    const col = db.collection('users').doc(uid).collection('wallet_ledger');
    const r = await db.runTransaction(async (t) => {
      const [orig, rev] = await Promise.all([t.get(col.doc(DOC_ID)), t.get(col.doc(REVERSAL_ID))]);
      if (!orig.exists) return 'missing';
      if (rev.exists) return 'idempotent';
      const o = orig.data() || {};
      t.create(col.doc(REVERSAL_ID), {
        ...o,
        amount: -o.amount,
        meta: { ...(o.meta || {}), kind: 'pre_ledger_adjustment_reversal', reverses: DOC_ID },
        recordedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return 'reversed';
    });
    out[r] += 1;
  }
  return out;
}

async function main() {
  const APPLY = process.argv.includes('--apply');
  const ROLLBACK = process.argv.includes('--rollback');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-wallet-history' });
    } else {
      // eslint-disable-next-line global-require
      const sa = require(path.join(__dirname, '..', 'service-account.json'));
      admin.initializeApp({ credential: admin.credential.cert(sa) });
    }
  }
  const db = admin.firestore();
  if (ROLLBACK) {
    const users = await db.collection('users').where('bonusBalance', '!=', 0).get();
    console.log(JSON.stringify(await rollbackCorrections(db, users.docs.map((d) => d.id))));
    return;
  }
  const plan = await planCorrections(db);
  console.log(`=== Ҳамён тарихини тузатиш ${APPLY ? '(ЁЗИШ)' : '(DRY-RUN)'} ===`);
  for (const p of plan) {
    console.log(`  ${mask(p.uid)} [${p.status}${p.reason ? `: ${p.reason}` : ''}] bonusBalance ${p.bonusBalance}, ` +
        `тарих Σ ${p.walletAllTime}, базагача Σ ${p.preBaselineSum} (${p.preBaselineRows} қатор), opening ${p.opening} → ` +
        `тузатиш ${p.amount}`);
  }
  if (!plan.length) console.log('  I-3F фарқи йўқ — тузатиш керак эмас.');
  if (!APPLY) { console.log('\nDry-run: ҳеч нарса ёзилмади. Ёзиш учун: --apply'); return; }
  const backup = path.join(os.tmpdir(), `wallet_history_corrections_${Date.now()}.json`);
  fs.writeFileSync(backup, JSON.stringify(plan, null, 2));
  console.log(`Режа сақланди (backup): ${backup}`);
  const res = await applyCorrections(db, plan);
  console.log(JSON.stringify({ written: res.written.length, idempotent: res.idempotent.length, stale: res.stale.length, failed: res.failed.length }));
  const rep = inv.evaluate(await inv.collectState(db));
  console.log(`I-3F қолди: ${rep.invariants.I3F.mismatchCount}`);
  if (rep.invariants.I3F.mismatchCount) process.exitCode = 2;
}

if (require.main === module) {
  main().then(() => process.exit(process.exitCode || 0)).catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { planCorrections, applyCorrections, rollbackCorrections, DOC_ID, REVERSAL_ID };
