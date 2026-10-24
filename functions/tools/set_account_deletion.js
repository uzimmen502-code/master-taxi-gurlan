/**
 * «Ҳисобни ўчириш» дарвозасини очиш/ёпиш: `settings/account_deletion` { enabled, waitDays } (docs/hisobni_ochirish_2026-10-24_uz.md).
 *
 * Хавфсизлик (28, 41-банд):
 *   - DRY RUN — стандарт; `--apply` — ёзади. Ҳужжат йўқ/enabled≠true = ЁПИҚ (сервер fail-closed).
 *   - Ёзув ва `admin_audit` (`account_deletion_gate_changed`) БИР транзакцияда; ким/қачон/нимадан-нимага.
 *   - Идемпотент: ўзгариш бўлмаса тегмайди.
 *   - Ўчириш қайтарилмас: ёқишдан олдин ҳуқуқий/солиқ масаласи ва матнлар (delete-account.html, махфийлик, Data Safety) тайёр бўлиши керак.
 *
 * Босқичлар (42-банд): OFF = `--enabled=false`; INTERNAL = `--enabled=true --allow=998901112233,...` (фақат шу
 * телефонлар сўров юбора олади); PUBLIC = `--enabled=true --allow=` (рўйхат бўш). Биринчи ҳақиқий ўчириш — фақат INTERNAL'да.
 *
 * Ишлатиш: node functions/tools/set_account_deletion.js --enabled=true [--wait-days=10] [--allow=998...,998...] [--apply]
 *          node functions/tools/set_account_deletion.js --enabled=false --apply          # ёпиш (ижро ҳам тўхтайди)
 */
'use strict';

const DEFAULT_WAIT_DAYS = 10;

const normPhones = (arr) => [...new Set(arr
  .map((x) => String(x).replace(/\D/g, ''))
  .filter(Boolean)
  .map((x) => (x.length === 9 ? `998${x}` : x)))];

/**
 * @param allow ИЧКИ синов рўйхати (INTERNAL): телефонлар массиви; `[]` — рўйхатни тозалаш (PUBLIC);
 *              берилмаса — жорий рўйхат ўзгармайди.
 */
async function setAccountDeletion(db, admin, {
  enabled, waitDays, allow, apply = false, actor = 'script:set_account_deletion',
  actorRole = 'script', source = 'script', reason = '',
} = {}) {
  if (typeof enabled !== 'boolean') throw new Error('enabled true yoki false bo\'lsin');
  let days = waitDays;
  if (days !== undefined) {
    days = Number(days);
    if (!Number.isInteger(days) || days < 1 || days > 60) throw new Error('waitDays 1..60 butun son bo\'lsin');
  }
  let allowList;
  if (allow !== undefined) {
    if (!Array.isArray(allow)) throw new Error('allow telefonlar massivi bo\'lsin');
    allowList = normPhones(allow);
    if (allowList.some((p) => !/^998\d{9}$/.test(p))) throw new Error('allow: har bir telefon 998XXXXXXXXX bo\'lsin');
  }
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const ref = db.collection('settings').doc('account_deletion');
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const cur = snap.exists ? (snap.data() || {}) : {};
    const curAllow = Array.isArray(cur.allow) ? normPhones(cur.allow) : [];
    const from = {
      enabled: cur.enabled === true,
      waitDays: Number.isInteger(cur.waitDays) ? cur.waitDays : DEFAULT_WAIT_DAYS,
      allow: curAllow,
    };
    const to = {
      enabled,
      waitDays: days === undefined ? from.waitDays : days,
      allow: allowList === undefined ? from.allow : allowList,
    };
    const same = from.enabled === to.enabled && from.waitDays === to.waitDays
      && from.allow.length === to.allow.length && from.allow.every((p, i) => p === to.allow[i]);
    if (same) return { action: 'already', from };
    if (!apply) return { action: 'would_set', from, to };
    t.set(ref, { enabled: to.enabled, waitDays: to.waitDays, allow: to.allow, updatedAt: ts, updatedBy: actor }, { merge: true });
    t.create(db.collection('admin_audit').doc(), {
      kind: 'account_deletion_gate_changed', actor, actorRole, targetId: 'settings/account_deletion',
      changes: [{ from, to }], source, ...(reason ? { reason } : {}), at: ts,
    });
    return { action: 'set', from, to };
  });
}

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-acct-gate' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const arg = (n) => ((process.argv.find((a) => a.startsWith(`--${n}=`)) || '').split('=')[1]);
  const en = arg('enabled');
  if (en !== 'true' && en !== 'false') throw new Error('--enabled=true yoki --enabled=false kerak');
  const apply = process.argv.includes('--apply');
  const wd = arg('wait-days');
  const al = process.argv.some((a) => a.startsWith('--allow=')) ? arg('allow') : undefined;
  const allow = al === undefined ? undefined : String(al || '').split(',').map((s) => s.trim()).filter(Boolean);
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} account_deletion enabled=${en}${wd ? ` waitDays=${wd}` : ''}${allow ? ` allow=${allow.length} ta` : ''}`);
  console.log(JSON.stringify(await setAccountDeletion(admin.firestore(), admin, {
    enabled: en === 'true', waitDays: wd === undefined ? undefined : Number(wd), allow, apply,
  }), null, 2));
  if (!apply) console.log('DRY RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { setAccountDeletion };
