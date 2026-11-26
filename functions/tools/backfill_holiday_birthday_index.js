/**
 * Байрам саватчаси — мавжуд қариндошлар учун holiday_birthday_index (эга 2026-11-26).
 * Триггер (onRelativeBirthdayIndex) фақат ЯНГИ ёзувларни кўради; эскилари шу тул билан бир марта индексланади.
 * Индексда исм ЙЎҚ: {ownerId, personId, md}. Бонус БЕРИЛМАЙДИ (фақат триггер/claimRelativesBonus).
 * + holiday_self_birthday_index (эга 2026-11-27): «Мен» ёзувидан, бўлмаса users.birthDate'дан (фақат ёзади/янгилайди).
 *
 * Хавфсизлик (27, 28-банд): DRY RUN — сукут; `--project <id>` шарт; `--apply` — фақат фарқ бўлган ҳужжатлар (идемпотент);
 * relatives/{uid}/people ўқилади, ЎЗГАРТИРИЛМАЙДИ. Rollback: holiday_birthday_index коллекциясини ўчириш (ҳосила маълумот).
 *
 *   node functions/tools/backfill_holiday_birthday_index.js --project <id>            # DRY RUN
 *   node functions/tools/backfill_holiday_birthday_index.js --project <id> --apply
 */
'use strict';

const h = require('../holiday');

async function main() {
  const argv = process.argv.slice(2);
  const pi = argv.indexOf('--project');
  const project = pi >= 0 ? argv[pi + 1] : null;
  const apply = argv.includes('--apply');
  if (!project) { console.error('--project <id> kerak'); process.exit(2); }
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const owners = await db.collection('relatives').listDocuments();
  const stat = { owners: owners.length, people: 0, eligible: 0, write: 0, remove: 0, same: 0 };
  let batch = db.batch();
  let n = 0;
  const flush = async () => { if (apply && n) await batch.commit(); batch = db.batch(); n = 0; };
  // Ўз туғилган куни (эга 2026-11-27): holiday_self_birthday_index/{userDocId} — «Мен» ёзувидан, бўлмаса users.birthDate'дан.
  const selfWant = new Map(); // ownerId → {personId, md}
  for (const o of owners) {
    const people = await o.collection('people').get();
    for (const p of people.docs) {
      stat.people += 1;
      const d = p.data() || {};
      if (d.isSelf === true) { const smd = h.mdOfBirth(d.birthDate); if (smd) selfWant.set(o.id, { personId: p.id, md: smd }); }
      const md = h.relativeEligible(d) ? h.mdOfBirth(d.birthDate) : null;
      const ref = db.collection(h.BD_INDEX).doc(`${o.id}_${p.id}`);
      const cur = (await ref.get()).data();
      if (md) stat.eligible += 1;
      if ((cur ? cur.md : null) === md) { stat.same += 1; continue; }
      if (md) { batch.set(ref, { ownerId: o.id, personId: p.id, md, updatedAt: admin.firestore.FieldValue.serverTimestamp() }); stat.write += 1; } else { batch.delete(ref); stat.remove += 1; }
      n += 1;
      if (n >= 400) await flush();
    }
  }
  // «Мен» ёзуви йўқ, лекин профилда сана бор — users.birthDate (сатр) бўйича (personId: null; триггер кейин тўлдиради).
  const users = await db.collection('users').where('birthDate', '>', '').get();
  for (const u of users.docs) {
    if (selfWant.has(u.id)) continue;
    const md = h.mdOfUserBirth((u.data() || {}).birthDate);
    if (md) selfWant.set(u.id, { personId: null, md });
  }
  stat.self = selfWant.size; stat.selfWrite = 0;
  for (const [ownerId, w] of selfWant) {
    const ref = db.collection(h.SELF_BD_INDEX).doc(ownerId);
    const cur = (await ref.get()).data();
    if (cur && cur.md === w.md) continue;
    batch.set(ref, { ownerId, personId: w.personId, md: w.md, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    stat.selfWrite += 1; n += 1;
    if (n >= 400) await flush();
  }
  await flush();
  console.log(`${apply ? 'APPLIED' : 'DRY RUN'} ${JSON.stringify(stat)}`);
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
