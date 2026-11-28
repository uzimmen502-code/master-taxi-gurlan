/**
 * Улгуржидаги 59 та «AVA» нусхасини ЯШИРИШ (ўчирмасдан) — эга модели 2026-11-28 (дубликат аудити F-1 / 16-банд).
 *
 * Фон: 2026-11-01 `migrate_platform_to_owner_wholesale.js` ҳар фаол `platform_products/{id}` учун
 * `wholesale_products/pp_<id>` нусха яратган (сотувчи «AVA»). 2026-11-28 эга: AVA'нинг ЎЗ маҳсулоти йўқ —
 * асл 59 таси Супермаркетда сотилмайдиган «Намуна» (`smSample`, `mark_supermarket_samples.js`). Улгуржидаги
 * нусхалар харидорга кўринмаслиги керак.
 *
 * Механизм — МАВЖУД (янги ҳолат ўйлаб топилмади): `status: 'inactive'` — админ «Ёпиш»/рад этиш ва
 * `wholesale_geo.js` legacy-архив ишлатадиган қиймат. Rules: `inactive` ни фақат админ ва эга ўқийди, барча
 * оммавий сўровлар (`getActiveProducts`, `watchActiveBySeller`, `countActiveBySeller`, Аралаш, қидирув,
 * `price_search`, `deal_chats.isActive`, буюртма `quoteWholesaleOrder/placeWholesaleOrder` — `status == 'active'`)
 * уларни кўрмайди. Қайтариш учун аввалги қийматлар ҳужжатнинг ўзида ҳам сақланади (`legacyPrev*` нақши):
 *   sampleHidden: true, sampleHiddenAt, samplePrevStatus, samplePrevAdminNote, adminNote, updatedAt.
 *
 * Нишон: ҳужжат ID `pp_` билан бошланади ВА `sellerCompanyName == 'AVA'` (иккаласи ҳам шарт). Аллақачон
 * `sampleHidden` — ўтказиб юборилади (идемпотент). Кутилган сон `--expect` (сукут 59) — мос келмаса `--apply` рад.
 *
 * Хавфсизлик (27, 28, 41-банд): DRY RUN — сукут; `--project <id>` ШАРТ; `--apply` — захира JSON
 * (functions/tools/backup/, git'га КИРМАЙДИ — sellerId телефон) → партия 200 тадан → ҳар партияга admin_audit →
 * текширув. Логда телефон тўлиқ чиқмайди.
 * Таъсир ҳисоботи (фақат ўқиш): очиқ Улгуржи буюртмалари (`wholesale_orders.productId` = pp_*), deal чатлар,
 * AVAGram клип боғланишлари, фаол акция/чегирма. Очиқ буюртма ишлашда давом этади (ўтишлар маҳсулот ҳолатини
 * қайта текширмайди — `wholesale_orders.js`, буюртма ўз нусхасидан ишлайди).
 *
 *   node functions/tools/hide_platform_copies_in_wholesale.js --project <id>                      # DRY RUN
 *   node functions/tools/hide_platform_copies_in_wholesale.js --project <id> --apply [--expect=59]
 *   node functions/tools/hide_platform_copies_in_wholesale.js --project <id> --rollback --from=<backup.json>          # DRY RUN
 *   node functions/tools/hide_platform_copies_in_wholesale.js --project <id> --rollback --from=<backup.json> --apply
 *
 * Rollback: фақат ҳали `sampleHidden == true` ВА `status == 'inactive'` бўлган ҳужжатларга аввалги status/adminNote
 * қайтади, sample* майдонлари олиб ташланади (эга орада қайта юборган бўлса — тегилмайди, рўйхатда кўрсатилади).
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ID_PREFIX = 'pp_';
const COMPANY = 'AVA';
const HIDE_NOTE = 'AVA намуна — Улгуржида яширилди (эга 2026-11-28)';
const DEFAULT_EXPECT = 59;
const OPEN_ORDER_STATUSES = Object.freeze(['placed', 'in_delivery', 'payment_dispute', 'refused', 'returning']);
const ACTOR = 'tool:hide_platform_copies_in_wholesale';

const mask = (p) => `***${String(p || '').slice(-4)}`;

/** Соф: ҳужжат яшириш нишонига тушадими. */
function isHideTarget(id, d) {
  const x = d || {};
  return typeof id === 'string' && id.startsWith(ID_PREFIX)
      && x.sellerCompanyName === COMPANY
      && x.sampleHidden !== true;
}

/** Соф: яшириш патчи (FieldValue'лар ташқаридан). */
function hidePatch(d, fv) {
  const x = d || {};
  return {
    status: 'inactive',
    sampleHidden: true,
    sampleHiddenAt: fv.ts(),
    samplePrevStatus: typeof x.status === 'string' ? x.status : null,
    samplePrevAdminNote: typeof x.adminNote === 'string' ? x.adminNote : null,
    adminNote: HIDE_NOTE,
    updatedAt: fv.ts(),
  };
}

/**
 * Соф: rollback режаси. Ҳозирги ҳужжат ҳали биз яширган ҳолатда бўлса — аввалги қиймат (захирадан, бўлмаса ҳужжатдаги
 * samplePrev*); акс ҳолда — skip (сабаби билан).
 */
function rollbackPlan(cur, backupDoc, fv) {
  if (!cur) return { skip: 'missing' };
  if (cur.sampleHidden !== true) return { skip: 'not_hidden_by_tool' };
  if (cur.status !== 'inactive') return { skip: `status_changed:${cur.status}` };
  const prevStatus = backupDoc && typeof backupDoc.status === 'string' ? backupDoc.status
    : (typeof cur.samplePrevStatus === 'string' ? cur.samplePrevStatus : null);
  if (!prevStatus) return { skip: 'no_prev_status' };
  const prevNote = backupDoc ? (typeof backupDoc.adminNote === 'string' ? backupDoc.adminNote : null)
    : (typeof cur.samplePrevAdminNote === 'string' ? cur.samplePrevAdminNote : null);
  return {
    patch: {
      status: prevStatus,
      adminNote: prevNote === null ? fv.del() : prevNote,
      sampleHidden: fv.del(),
      sampleHiddenAt: fv.del(),
      samplePrevStatus: fv.del(),
      samplePrevAdminNote: fv.del(),
      updatedAt: fv.ts(),
    },
  };
}

/** Соф: нишон сони кутилганига мосми (apply дарвозаси). */
function expectOk(count, expect) {
  return Number.isInteger(expect) && count === expect;
}

function toJson(v) {
  if (v && typeof v.toDate === 'function') return { _ts: v.toDate().toISOString() };
  if (Array.isArray(v)) return v.map(toJson);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toJson(x)]));
  return v;
}

function parseArgs(argv) {
  const get = (name) => {
    const eq = argv.find((x) => x.startsWith(`--${name}=`));
    if (eq) return eq.slice(name.length + 3);
    const i = argv.indexOf(`--${name}`);
    return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
  };
  const expectRaw = get('expect');
  return {
    project: get('project'),
    apply: argv.includes('--apply'),
    rollback: argv.includes('--rollback'),
    from: get('from'),
    expect: expectRaw === '' ? DEFAULT_EXPECT : Number(expectRaw),
  };
}

async function idsWithPrefix(db, admin, col) {
  const FP = admin.firestore.FieldPath.documentId();
  const snap = await db.collection(col).where(FP, '>=', ID_PREFIX).where(FP, '<', `${ID_PREFIX}`).get();
  return snap.docs;
}

async function impactReport(db, admin, ids) {
  const set = new Set(ids);
  const out = { openOrders: [], dealChats: 0, tvClips: 0, activePromo: [] };
  // Очиқ буюртмалар (фақат ўқиш; `in` 30 тагача — бўлаклаб).
  for (let i = 0; i < ids.length; i += 30) {
    const part = ids.slice(i, i + 30);
    const s = await db.collection('wholesale_orders').where('productId', 'in', part).get();
    for (const d of s.docs) {
      const o = d.data() || {};
      if (OPEN_ORDER_STATUSES.includes(o.status)) out.openOrders.push(`${d.id}:${o.status}:${o.productId}`);
    }
    const c = await db.collection('tv_clips').where('wholesaleProductId', 'in', part).get();
    out.tvClips += c.size;
  }
  out.dealChats = (await idsWithPrefix(db, admin, 'deal_chats')).filter((d) => {
    const pid = d.id.slice(0, d.id.lastIndexOf('_'));
    return set.has(pid);
  }).length;
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.project) {
    console.log('--project <id> шарт (DRY RUN сукут, --apply — ёзиш).');
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: args.project });
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const fv = { ts: () => FieldValue.serverTimestamp(), del: () => FieldValue.delete() };
  console.log(`MODE: ${args.rollback ? 'ROLLBACK' : 'HIDE'} ${args.apply ? 'APPLY' : 'DRY RUN (--apply йўқ)'}; project ${args.project}`);

  if (args.rollback) {
    if (!args.from) throw new Error('--from=<backup.json> керак');
    const backup = JSON.parse(fs.readFileSync(args.from, 'utf8'));
    if (backup.kind !== 'hide_platform_copies_in_wholesale' || !Array.isArray(backup.docs)) throw new Error('захира формати нотўғри');
    const plans = [];
    for (const b of backup.docs) {
      const ref = db.collection('wholesale_products').doc(b.id);
      const snap = await ref.get();
      const p = rollbackPlan(snap.exists ? snap.data() : null, b.data, fv);
      if (p.skip) console.log(`  skip ${b.id}: ${p.skip}`);
      else plans.push({ ref, id: b.id, patch: p.patch, to: p.patch.status });
    }
    plans.forEach((x) => console.log(`${args.apply ? 'RESTORE' : 'WOULD RESTORE'} ${x.id} → ${x.to}`));
    if (args.apply) {
      for (let i = 0; i < plans.length; i += 200) {
        const part = plans.slice(i, i + 200);
        const batch = db.batch();
        part.forEach((x) => batch.update(x.ref, x.patch));
        batch.set(db.collection('admin_audit').doc(), {
          kind: 'wholesale_platform_copies_unhide', actor: ACTOR, count: part.length,
          productIds: part.map((x) => x.id), backup: path.basename(args.from), at: fv.ts(),
        });
        await batch.commit();
      }
    }
    console.log(`${args.apply ? 'APPLIED' : 'DRY RUN'}: backup ${backup.docs.length}, restore ${plans.length}`);
    return;
  }

  const all = await idsWithPrefix(db, admin, 'wholesale_products');
  const targets = all.filter((d) => isHideTarget(d.id, d.data()));
  const already = all.filter((d) => (d.data() || {}).sampleHidden === true).length;
  const foreign = all.filter((d) => !isHideTarget(d.id, d.data()) && (d.data() || {}).sampleHidden !== true);
  const byStatus = {};
  for (const d of targets) { const s = (d.data() || {}).status || '-'; byStatus[s] = (byStatus[s] || 0) + 1; }
  const sellers = [...new Set(targets.map((d) => (d.data() || {}).sellerId))];
  console.log(`pp_* ҳужжатлар: ${all.length}; нишон: ${targets.length} (${JSON.stringify(byStatus)}); аллақачон яширилган: ${already}; `
    + `«AVA» эмас (тегилмайди): ${foreign.length}; сотувчилар: ${sellers.map(mask).join(',')}`);
  foreign.forEach((d) => console.log(`  НОМУВОФИҚ (тегилмайди) ${d.id}: sellerCompanyName=${JSON.stringify((d.data() || {}).sellerCompanyName)}`));
  for (const d of targets) {
    const x = d.data() || {};
    const promo = x.promoState && ['active', 'pending'].includes(x.promoState.status) ? ` promo=${x.promoState.status}/${x.promoState.kind}` : '';
    console.log(`${args.apply ? 'HIDE' : 'WOULD HIDE'} ${d.id} · ${x.status} · ${String(x.title || '').slice(0, 60)}${promo}`);
  }
  const impact = await impactReport(db, admin, targets.map((d) => d.id));
  console.log(`ТАЪСИР: очиқ буюртма ${impact.openOrders.length}; deal чат ${impact.dealChats}; AVAGram клип боғланиши ${impact.tvClips}`);
  impact.openOrders.forEach((o) => console.log(`  очиқ буюртма (давом этади): ${o}`));

  if (!args.apply) {
    console.log(`DRY RUN — ҳеч нарса ёзилмади. Кутилган сон ${args.expect}: ${expectOk(targets.length, args.expect) ? 'МОС' : 'МОС ЭМАС'}`);
    return;
  }
  if (!expectOk(targets.length, args.expect)) {
    throw new Error(`нишон ${targets.length} ≠ кутилган ${args.expect} — текширинг, керак бўлса --expect=${targets.length}`);
  }
  if (!targets.length) {
    console.log('Ёзиладиган ҳужжат йўқ (ҳаммаси аллақачон яширилган) — захира ҳам ёзилмади.');
    return;
  }

  const dir = path.join(__dirname, 'backup');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `hide-platform-copies-backup-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify({
    kind: 'hide_platform_copies_in_wholesale', project: args.project, createdAt: new Date().toISOString(),
    docs: targets.map((d) => ({ id: d.id, data: toJson(d.data()) })),
  }, null, 2));
  console.log(`захира: ${file} (git'га қўшманг — телефон рақамлари бор)`);

  for (let i = 0; i < targets.length; i += 200) {
    const part = targets.slice(i, i + 200);
    const batch = db.batch();
    part.forEach((d) => batch.update(d.ref, hidePatch(d.data(), fv)));
    batch.set(db.collection('admin_audit').doc(), {
      kind: 'wholesale_platform_copies_hide', actor: ACTOR, count: part.length,
      productIds: part.map((d) => d.id), reason: 'ega_2026_11_28_ava_no_own_products',
      backup: path.basename(file), at: fv.ts(),
    });
    await batch.commit();
    console.log(`яширилди ${Math.min(i + 200, targets.length)}/${targets.length}`);
  }
  const verify = await idsWithPrefix(db, admin, 'wholesale_products');
  const stillActive = verify.filter((d) => (d.data() || {}).sellerCompanyName === COMPANY && (d.data() || {}).status === 'active');
  console.log(`ТЕКШИРУВ: pp_* «AVA» ҳали active: ${stillActive.length} (0 бўлиши керак); sampleHidden: `
    + `${verify.filter((d) => (d.data() || {}).sampleHidden === true).length}`);
}

if (require.main === module) main().then(() => process.exit(0)).catch((e) => { console.error('FAILED:', e.message || e); process.exit(1); });

module.exports = { isHideTarget, hidePatch, rollbackPlan, expectOk, parseArgs, ID_PREFIX, HIDE_NOTE, OPEN_ORDER_STATUSES };
