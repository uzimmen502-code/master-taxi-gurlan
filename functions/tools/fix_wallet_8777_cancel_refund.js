/**
 * Ҳамён W-1, 0-қадам — журналсиз қолган буюртма бекор қайтимларини ledger'га ёзиш (бир марталик).
 *
 * Сабаб (prod текшируви 2026-11-28): `***8777` да bonusBalance 19 562, passenger_credit 0.
 * 2026-07-27 да иккита платформа буюртмаси бекор қилинганда қайтим `bonusBalance` ва
 * `wallet_ledger` (`order_cancel_refund`) га ёзилган, лекин `journal_entries` да
 * `bonus:order_cancel_refund_{orderId}` ЙЎҚ (ечимнинг ўзи — `order_wallet` — журналда бор).
 * Ҳозирги код (`commitOrderCancelInTx`) бу калитни ёзади; 07-27 даги жонли версия ёзмаган (INFERRED).
 *
 * Тузатиш (ҳар бир журналсиз қайтим учун):
 *   Dr admin_clearing / Cr passenger_credit:{uid}  (қайтим суммаси)
 *   kind 'order_cancel_refund', журнал id `bonus:order_cancel_refund_{orderId}` (жонли код билан
 *   АЙНАН бир калит — кейин буюртма яна бекор йўлидан ўтса, иккинчи марта ёзилмайди),
 *   bonusBalance'га ТЕГИЛМАЙДИ (mirrorBonus:false маъноси — у аллақачон тўғри).
 *
 * Фақат ҚАТЪИЙ ҳолат тузатилади (акс ҳолда `needsReview`):
 *   - bonusBalance − passenger_credit == Σ журналсиз қайтимлар (айнан тенг);
 *   - ҳар қайтим учун буюртма бор ва `balanceApplied` == қайтим суммаси;
 *   - ҳар қайтим учун ечим (Dr passenger_credit:{uid}, шу сумма) журналда бор.
 *
 * Хавфсизлик (CLAUDE.md 21/27/28):
 *   - СТАНДАРТ dry-run: фақат ўқийди.
 *   - `--apply`: аввал режа backup файлга (репо ташқарисида), кейин ҳар ёзув транзакцияда ҚАЙТА
 *     текширилади (bonusBalance ва passenger_credit режадагидек бўлмаса — STALE, ёзилмайди).
 *     Идемпотент (журнал id мавжуд бўлса — ўтказилади).
 *   - `--rollback`: шу восита ёзган ҳар бир ёзувга тескари (storno) ёзув, идемпотент.
 *   - Терминалда рақамлар яширилади (охирги 4 хона).
 *   - Prod'га ёзиш — фақат эга рухсати билан (28-банд). Эслатма: 2026-10-08 да эга «бу ҳамёнга
 *     тегманг» деган; 2026-11-28 да 0-қадамни тайёрлашни сўради — ишга тушириш яна эганинг қарори.
 *
 * Ишлатиш (functions/ папкасидан):
 *   node tools/fix_wallet_8777_cancel_refund.js                     # dry-run (bonusBalance>0 бўлганлар)
 *   node tools/fix_wallet_8777_cancel_refund.js --uid 998XXXXXXXXX  # dry-run, битта ҳамён
 *   node tools/fix_wallet_8777_cancel_refund.js --uid ... --apply   # ёзиш
 *   node tools/fix_wallet_8777_cancel_refund.js --rollback          # қайтариш
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const TAG = 'fix_cancel_refund_journal_v1';
const KIND = 'order_cancel_refund';
const refundKey = (orderId) => `order_cancel_refund_${orderId}`; // index.js orderCancelRefundKey билан бир хил
const journalId = (orderId) => `bonus:${refundKey(orderId)}`;
const mask = (s) => `***${String(s).slice(-4)}`;
const isPosInt = (n) => Number.isInteger(n) && n > 0;

async function candidateUids(db, onlyUid) {
  if (onlyUid) return [String(onlyUid)];
  const snap = await db.collection('users').where('bonusBalance', '>', 0).get();
  return snap.docs.map((d) => d.id);
}

/** Битта ҳамён режаси (фақат ўқийди). */
async function planUser(db, uid) {
  const [uSnap, pcSnap] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get(),
  ]);
  if (!uSnap.exists) return { uid, status: 'skip', reason: 'no_user_doc' };
  const bonusBalance = (uSnap.data() || {}).bonusBalance ?? 0;
  const pc = pcSnap.exists ? ((pcSnap.data() || {}).balance || 0) : 0;
  if (!Number.isInteger(bonusBalance) || !Number.isInteger(pc)) {
    return { uid, status: 'needsReview', reason: 'non_integer', bonusBalance, ledger: pc };
  }
  const drift = bonusBalance - pc;
  if (drift <= 0) return { uid, status: 'skip', reason: drift === 0 ? 'in_sync' : 'ledger_gt_bonus', bonusBalance, ledger: pc };

  const wl = await db.collection('users').doc(uid).collection('wallet_ledger')
      .where('type', '==', KIND).get();
  const rows = [];
  for (const d of wl.docs) {
    const w = d.data() || {};
    const orderId = String(w.refId || '');
    const amount = w.amount;
    if (!orderId) continue;
    const jSnap = await db.collection(ledger.COL_JOURNAL).doc(journalId(orderId)).get();
    if (jSnap.exists) continue; // журнал бор — тузатиш керак эмас
    const [oSnap, debitSnap] = await Promise.all([
      db.collection('orders').doc(orderId).get(),
      db.collection(ledger.COL_JOURNAL).where('refId', '==', orderId).get(),
    ]);
    const od = oSnap.exists ? (oSnap.data() || {}) : null;
    const pcId = ledger.passengerCreditAccount(uid);
    const debitEntry = debitSnap.docs.find((e) => ((e.data() || {}).legs || [])
        .some((l) => l.account === pcId && l.dr === amount));
    rows.push({
      walletLedgerId: d.id,
      orderId,
      amount,
      orderFound: !!od,
      orderStatus: od ? String(od.status || '') : null,
      balanceApplied: od ? Math.trunc(Number(od.balanceApplied || 0)) : null,
      debitJournalId: debitEntry ? debitEntry.id : null,
    });
  }
  const sumMissing = rows.reduce((s, r) => s + (isPosInt(r.amount) ? r.amount : 0), 0);
  const base = { uid, bonusBalance, ledger: pc, drift, rows, sumMissing };
  if (!rows.length) return { ...base, status: 'needsReview', reason: 'no_missing_refunds_found' };
  const bad = rows.find((r) => !isPosInt(r.amount) || !r.orderFound
      || r.balanceApplied !== r.amount || !r.debitJournalId);
  if (bad) return { ...base, status: 'needsReview', reason: 'row_check_failed', badOrderId: bad.orderId };
  if (sumMissing !== drift) return { ...base, status: 'needsReview', reason: 'sum_ne_drift' };
  return { ...base, status: 'fixable' };
}

async function planAll(db, { uid } = {}) {
  const uids = await candidateUids(db, uid);
  const out = [];
  for (const u of uids) out.push(await planUser(db, u));
  return out;
}

/** Транзакцияда қайта текшириб ёзади. Режадаги кетма-кетликда; STALE бўлса — шу ҳамён тўхтайди. */
async function applyPlan(db, plan) {
  const res = { posted: [], idempotent: [], stale: [], failed: [] };
  for (const p of plan.filter((x) => x.status === 'fixable')) {
    let expectedPc = p.ledger;
    for (const r of p.rows) {
      const userRef = db.collection('users').doc(p.uid);
      try {
        const out = await db.runTransaction(async (t) => {
          const u = await t.get(userRef);
          const ctx = await ledger.prepareBonusInTx(t, db, p.uid, { idempotencyKey: refundKey(r.orderId) });
          if (ctx.jExists) return 'idempotent';
          const bonusNow = u.exists ? ((u.data() || {}).bonusBalance ?? 0) : null;
          if (bonusNow !== p.bonusBalance || ctx.pcPrev !== expectedPc) {
            const e = new Error('STALE');
            e.stale = true;
            e.detail = { bonusNow, pcNow: ctx.pcPrev, expectedPc };
            throw e;
          }
          ledger.commitBonusInTx(t, ctx, {
            delta: r.amount,
            kind: KIND,
            refType: 'order',
            refId: r.orderId,
            meta: {
              walletRefund: r.amount,
              status: r.orderStatus || '',
              migration: TAG,
              walletLedgerId: r.walletLedgerId,
              debitJournalId: r.debitJournalId,
            },
            postedBy: 'migration',
            postedRole: 'system',
          });
          return 'posted';
        });
        if (out === 'idempotent') res.idempotent.push({ uid: p.uid, orderId: r.orderId });
        else {
          res.posted.push({ uid: p.uid, orderId: r.orderId, amount: r.amount });
          expectedPc += r.amount;
        }
        if (out === 'idempotent') expectedPc += r.amount; // аввалги ишга туширишда ёзилган
      } catch (e) {
        if (e && e.stale) {
          res.stale.push({ uid: p.uid, orderId: r.orderId, ...e.detail });
          break; // кейинги қаторларнинг кутилган қолдиғи нотўғри бўлади
        }
        res.failed.push({ uid: p.uid, orderId: r.orderId, error: e.message });
        break;
      }
    }
  }
  return res;
}

/** Шу восита ёзган ёзувларга тескари (storno) ёзув. Идемпотент. */
async function rollback(db) {
  const snap = await db.collection(ledger.COL_JOURNAL).where('meta.migration', '==', TAG).get();
  const out = { reversed: 0, idempotent: 0 };
  for (const d of snap.docs) {
    const e = d.data() || {};
    if (e.kind !== KIND) continue;
    const legs = (e.legs || []).map((l) => ({ account: l.account, dr: l.cr || 0, cr: l.dr || 0 }));
    const r = await ledger.postEntry(db, {
      idempotencyKey: `${d.id}:rollback`,
      kind: `${KIND}_fix_rollback`,
      refType: 'migration',
      refId: d.id,
      postedBy: 'migration',
      postedRole: 'system',
      legs,
    }, { mirrorBonus: false, meta: { migration: `${TAG}_rollback` } });
    if (r.idempotent) out.idempotent += 1; else out.reversed += 1;
  }
  return out;
}

function summarize(plan) {
  for (const p of plan) {
    if (p.status === 'skip') continue;
    console.log(`  ${mask(p.uid)} [${p.status}${p.reason ? `: ${p.reason}` : ''}] bonusBalance ${p.bonusBalance}, ` +
        `ledger ${p.ledger}, фарқ ${p.drift}, журналсиз қайтимлар ${p.sumMissing}`);
    for (const r of p.rows || []) {
      console.log(`      буюртма ${mask(r.orderId)}: ${r.amount} сўм, ҳолат ${r.orderStatus}, ` +
          `balanceApplied ${r.balanceApplied}, ечим журнали ${r.debitJournalId ? 'бор' : 'ЙЎҚ'}`);
    }
  }
  const fix = plan.filter((p) => p.status === 'fixable');
  console.log(`  Тузатиладиган ҳамёнлар: ${fix.length}, жами ${fix.reduce((s, p) => s + p.sumMissing, 0)} сўм; ` +
      `кўриб чиқиш керак: ${plan.filter((p) => p.status === 'needsReview').length}; мос: ${plan.filter((p) => p.status === 'skip').length}`);
}

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  const APPLY = process.argv.includes('--apply');
  const ROLLBACK = process.argv.includes('--rollback');
  const uid = argValue('--uid');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-wallet-fix' });
    } else {
      // eslint-disable-next-line global-require
      const sa = require(path.join(__dirname, '..', 'service-account.json'));
      admin.initializeApp({ credential: admin.credential.cert(sa) });
    }
  }
  const db = admin.firestore();
  if (ROLLBACK) {
    console.log('=== Бекор қайтими журнал тузатишини ҚАЙТАРИШ (storno) ===');
    console.log(JSON.stringify(await rollback(db)));
    return;
  }
  console.log(`=== Журналсиз бекор қайтимлари ${APPLY ? '(ЁЗИШ)' : '(DRY-RUN)'} ===`);
  const plan = await planAll(db, { uid });
  summarize(plan);
  if (!APPLY) {
    console.log('\nDry-run: ҳеч нарса ёзилмади. Ёзиш учун: --apply');
    return;
  }
  const backup = path.join(os.tmpdir(), `cancel_refund_fix_plan_${Date.now()}.json`);
  fs.writeFileSync(backup, JSON.stringify(plan, null, 2));
  console.log(`\nРежа сақланди (backup): ${backup}`);
  const res = await applyPlan(db, plan);
  console.log(`  Ёзилди: ${res.posted.length}; аллақачон бор: ${res.idempotent.length}; ` +
      `STALE: ${res.stale.length}; хато: ${res.failed.length}`);
  for (const f of res.failed) console.log(`    ${mask(f.uid)} ${mask(f.orderId)}: ${f.error}`);
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

module.exports = { planAll, planUser, applyPlan, rollback, TAG, journalId, refundKey };
