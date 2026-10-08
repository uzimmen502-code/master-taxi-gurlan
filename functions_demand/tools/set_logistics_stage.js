/**
 * AVA LOGISTICS — ISHGA TUSHIRISH BOSQICHI VA SINOVCHILAR (CLAUDE.md 42).
 *
 *   node functions_demand/tools/set_logistics_stage.js                                # holat (faqat o'qish)
 *   node functions_demand/tools/set_logistics_stage.js --add 998901234567,+998 90 765 43 21
 *   node functions_demand/tools/set_logistics_stage.js --remove 998901234567
 *   node functions_demand/tools/set_logistics_stage.js --stage public
 *   ... yuqoridagilarga --write qo'shilmaguncha DRY-RUN.
 *
 * NIMA QILADI: `module_config/logistics_all.logistics.{stage,testerIds}`
 * ni yangilaydi (boshqa maydonlar tegilmaydi) va `logistics_audit` ga
 * yozadi (41-band). Telefonlar kanonik shaklga keltiriladi (998XXXXXXXXX);
 * noto'g'ri raqam — to'xtaydi. Telefonlar logga to'liq chiqmaydi (40-band).
 *
 * Server konfigni 60 s keshlaydi — o'zgarish shu muddat ichida kuchga kiradi.
 */
const path = require('path');
const { toCanonicalId } = require('../core/ids');
const L = require('../core/logistics');

const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
const SA = path.join(__dirname, '..', '..', 'functions', 'service-account.json');

const DOC = 'module_config/logistics_all';

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return null;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : '';
}

function parsePhones(raw, flag) {
  if (raw === null) return [];
  const parts = String(raw).split(',').map((s) => s.trim()).filter(Boolean);
  if (!parts.length) throw new Error(`--${flag} bo'sh`);
  return parts.map((p) => {
    const id = toCanonicalId(p);
    if (!id) throw new Error(`--${flag}: noto'g'ri telefon («${p.slice(0, 4)}…»)`);
    return id;
  });
}

const mask = (id) => `${id.slice(0, 5)}****${id.slice(-3)}`;

async function main() {
  const write = process.argv.includes('--write');
  const add = parsePhones(arg('add'), 'add');
  const remove = parsePhones(arg('remove'), 'remove');
  const stageArg = arg('stage');
  if (stageArg !== null && !Object.values(L.STAGE).includes(stageArg)) {
    throw new Error(`--stage faqat: ${Object.values(L.STAGE).join(' | ')}`);
  }

  if (admin.apps.length === 0) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
  }
  const db = admin.firestore();
  const ref = db.doc(DOC);
  const snap = await ref.get();
  if (!snap.exists) throw new Error(`${DOC} yo'q — avval enable_module.js`);
  const cur = (snap.data() || {}).logistics || {};
  const curStage = L.stageOf({ logistics: cur });
  const curList = (Array.isArray(cur.testerIds) ? cur.testerIds : []).map((t) => toCanonicalId(String(t))).filter(Boolean);

  console.log(`${DOC}: stage=${curStage}${cur.stage ? '' : ' (yozilmagan → standart)'}; sinovchilar ${curList.length}: ${curList.map(mask).join(', ') || '—'}`);
  if (!add.length && !remove.length && stageArg === null) return;

  const next = [...new Set([...curList.filter((t) => !remove.includes(t)), ...add])];
  const nextStage = stageArg === null ? curStage : stageArg;
  console.log(`\n${write ? 'YOZILADI' : 'DRY-RUN'}: stage=${nextStage}; sinovchilar ${next.length}: ${next.map(mask).join(', ') || '—'}`);
  if (nextStage === L.STAGE.PUBLIC && curStage !== L.STAGE.PUBLIC) {
    console.log('  DIQQAT: public — xizmat HAMMA uchun ochiladi (faol tarif bo\'lsa).');
  }
  if (!write) { console.log('\n(--write bilan ishga tushiring)'); return; }

  const now = new Date();
  const by = 'set_logistics_stage.js';
  await ref.update({
    'logistics.stage': nextStage,
    'logistics.testerIds': next,
    updatedAt: now,
    updatedBy: by,
  });
  await db.collection('logistics_audit').add({
    kind: 'stage_update',
    from: { stage: curStage, testerCount: curList.length },
    to: { stage: nextStage, testerCount: next.length },
    added: add.filter((t) => !curList.includes(t)).length,
    removed: remove.filter((t) => curList.includes(t)).length,
    by,
    at: now,
  });
  console.log('  yozildi (60 s ichida kuchga kiradi).');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
