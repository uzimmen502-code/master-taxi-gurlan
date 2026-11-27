/**
 * «AVA Супермаркет» ҳамкор модели (эга 2026-11-28, а-вариант): AVA'нинг ўз маҳсулоти йўқ — мавжуд «AVA» супермаркет
 * таклифлари харидорга «Намуна» бўлиб кўринади ва СОТИЛМАЙДИ (`smSample: true`; placeSupermarketOrder рад этади).
 *
 * Нишон: platform_products, `smGroupId` бор, `smPartnerKey` ЙЎҚ (ҳамкорники эмас), ҳали намуна эмас.
 * Ихтиёрий `--ids <file.txt>` — фақат шу ID'лар (ҳар қаторда биттадан). Эга текшириши учун рўйхат чиқарилади.
 *
 * Хавфсизлик (27, 28, 41-банд): DRY RUN — сукут; лойиҳа ФАҚАТ `--project <id>`; `--apply` — ёзиш (партия 200 тадан),
 * ҳар ҳужжатга admin_audit; `--undo` — белгини олиб ташлайди (rollback). Қайта ишга тушириш хавфсиз (идемпотент).
 * Бир хил ёзиш йўли админ панелида ҳам бор: callable `adminSetSupermarketSample`.
 *
 *   node functions/tools/mark_supermarket_samples.js --project <id>                  # DRY RUN
 *   node functions/tools/mark_supermarket_samples.js --project <id> --apply
 *   node functions/tools/mark_supermarket_samples.js --project <id> --undo --apply   # қайтариш
 */
'use strict';

const fs = require('fs');

/** Соф: ҳужжат намуна нишонига тушадими. */
function isSampleTarget(d, undo = false) {
  const x = d || {};
  if (!x.smGroupId || x.smPartnerKey) return false;
  return undo ? x.smSample === true : x.smSample !== true;
}

async function main() {
  const argv = process.argv.slice(2);
  const pi = argv.indexOf('--project');
  const project = pi >= 0 ? argv[pi + 1] : null;
  const apply = argv.includes('--apply');
  const undo = argv.includes('--undo');
  const ii = argv.indexOf('--ids');
  if (!project) {
    console.log('--project <id> шарт (DRY RUN сукут, --apply — ёзиш).');
    process.exit(2);
  }
  const only = ii >= 0 ? new Set(fs.readFileSync(argv[ii + 1], 'utf8').split(/\r?\n/).map((s) => s.trim()).filter(Boolean)) : null;
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const snap = await db.collection('platform_products').where('smGroupId', '>', '').get();
  const targets = snap.docs.filter((d) => (!only || only.has(d.id)) && isSampleTarget(d.data(), undo));
  for (const d of targets) console.log(`${apply ? (undo ? 'UNMARK' : 'MARK') : 'WOULD ' + (undo ? 'UNMARK' : 'MARK')} ${d.id} · ${(d.data() || {}).name || ''}`);
  if (apply) {
    const ts = admin.firestore.FieldValue.serverTimestamp();
    for (let i = 0; i < targets.length; i += 200) {
      const b = db.batch();
      for (const d of targets.slice(i, i + 200)) {
        b.update(d.ref, { smSample: !undo, updatedAt: ts });
        b.set(db.collection('admin_audit').doc(), {
          kind: 'supermarket_offer_sample', actor: 'tool:mark_supermarket_samples', target: `platform_products/${d.id}`, sample: !undo, at: ts,
        });
      }
      await b.commit();
    }
  }
  console.log(`${apply ? 'APPLIED' : 'DRY RUN'}: ${snap.size} supermarket offers, ${targets.length} ${undo ? 'unmark' : 'mark'}`);
}

if (require.main === module) main().catch((e) => { console.error(e.message || e); process.exit(1); });

module.exports = { isSampleTarget };
