/**
 * Ҳамён ёзувлари характеризацияси (W-1, 2-босқич): модулни walletPost'га кўчиришдан ОЛДИН ва КЕЙИН мавжуд
 * CF тест сюитаси айнан бир хил ҳамён ёзувларини қилишини исботлаш учун.
 *
 *   WALLET_REC_OUT=<файл.json> node -r ./test/helpers/wallet_write_recorder.js test/<suite>.test.js
 *   node test/helpers/wallet_write_recorder.js --compare before.json after.json
 *
 * Ёзиладиган (Transaction / WriteBatch / DocumentReference set|update|create, CollectionReference.add):
 *   users/{uid} (фақат bonusBalance ва balanceUpdatedAt майдонлари), users/{uid}/wallet_ledger/*,
 *   journal_entries/*, ledger_accounts/*.
 * Нормаллаштириш: wallet_ledger ҳужжат id'си → `*` (кўчиришда тасодифий id детерминистикка ўтади — атайлаб);
 * 20 белгили авто-id → <id>; 13 хонали ms → <ms>; serverTimestamp → <ts>; increment(n) → {inc:n};
 * Timestamp/Date → <time>. Солиштириш — тўплам (тартиб ва retry сони ҳисобга олинмайди).
 * Чеклов: id'даги тасодифий қисм <id> бўлгани учун «қайси буюртма» эмас, «қандай ёзув» солиштирилади.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const AUTO_ID = /[A-Za-z0-9]{16,}/g;
const MS = /\b1\d{12}\b/g;

function normStr(s) {
  return String(s).replace(AUTO_ID, '<id>').replace(MS, '<ms>');
}
function normVal(v) {
  if (v === null || v === undefined) return v;
  if (typeof v === 'number') return v > 1e12 && v < 1e14 ? '<ms>' : v;
  if (typeof v === 'string') return normStr(v);
  if (typeof v === 'boolean') return v;
  if (Array.isArray(v)) return v.map(normVal);
  const cn = v.constructor && v.constructor.name;
  if (cn === 'ServerTimestampTransform') return '<ts>';
  if (cn === 'NumericIncrementTransform') return { inc: v.operand };
  if (cn === 'DeleteTransform') return '<delete>';
  if (cn === 'Timestamp' || v instanceof Date) return '<time>';
  if (cn === 'DocumentReference') return `<ref:${normPath(v.path)}>`;
  if (cn && cn.endsWith('Transform')) return `<${cn}>`;
  const out = {};
  for (const k of Object.keys(v).sort()) out[normStr(k)] = normVal(v[k]);
  return out;
}
function normPath(p) {
  const parts = String(p).split('/');
  if (parts[0] === 'users' && parts[2] === 'wallet_ledger' && parts.length === 4) parts[3] = '*';
  return parts.map(normStr).join('/');
}
function relevant(p) {
  const parts = String(p).split('/');
  if (parts[0] === 'journal_entries' || parts[0] === 'ledger_accounts') return parts.length === 2;
  if (parts[0] === 'users') return parts.length === 2 || (parts.length === 4 && parts[2] === 'wallet_ledger');
  return false;
}
function pickData(p, data) {
  const parts = String(p).split('/');
  if (parts[0] === 'users' && parts.length === 2) {
    if (!data || typeof data !== 'object') return null;
    const o = {};
    if ('bonusBalance' in data) o.bonusBalance = data.bonusBalance;
    if (!('bonusBalance' in data)) return null; // фақат ҳамён проекцияси ёзувлари
    if ('balanceUpdatedAt' in data) o.balanceUpdatedAt = data.balanceUpdatedAt;
    return o;
  }
  return data;
}

function install(outFile) {
  const fa = require.resolve('firebase-admin');
  const gcf = require(require.resolve('@google-cloud/firestore', { paths: [path.dirname(fa)] }));
  const rec = [];
  const push = (op, ref, data, opts) => {
    try {
      if (!ref || !relevant(ref.path)) return;
      const d = pickData(ref.path, data);
      if (d === null) return;
      const merge = !!(opts && (opts.merge || opts.mergeFields));
      rec.push(JSON.stringify({ op: op === 'set' && merge ? 'set_merge' : op, path: normPath(ref.path), data: normVal(d) }));
    } catch (_) { /* ёзувчи тестни бузмасин */ }
  };
  const wrap = (proto, name, op, argMode) => {
    const orig = proto[name];
    if (!orig || orig.__walletRec) return;
    const w = function (...args) {
      if (argMode === 'ref-data') {
        const [ref, a, b] = args;
        if (op === 'update' && typeof a === 'string') push('update', ref, { [a]: b });
        else push(op, ref, a, b);
      } else if (argMode === 'self-data') {
        const [a, b] = args;
        if (op === 'update' && typeof a === 'string') push('update', this, { [a]: b });
        else push(op, this, a, b);
      }
      return orig.apply(this, args);
    };
    w.__walletRec = true;
    proto[name] = w;
  };
  for (const cls of [gcf.Transaction, gcf.WriteBatch]) {
    wrap(cls.prototype, 'set', 'set', 'ref-data');
    wrap(cls.prototype, 'update', 'update', 'ref-data');
    wrap(cls.prototype, 'create', 'create', 'ref-data');
  }
  // DocumentReference.set/update/create ички WriteBatch орқали ўтади — икки марта ёзмаслик учун ўраламаймиз.
  process.on('exit', () => {
    fs.writeFileSync(outFile, JSON.stringify(rec.sort(), null, 0));
  });
}

function compare(a, b) {
  const A = JSON.parse(fs.readFileSync(a, 'utf8'));
  const B = JSON.parse(fs.readFileSync(b, 'utf8'));
  // Тўплам (такрорсиз): транзакция қайта уриниши (retry) бир ёзувни бир неча марта қайд этади ва унинг сони
  // ишга туширишдан ишга туширишга ўзгаради. Икки марта пул юриши эса журнал калити/суммаси орқали кўринади.
  const count = (arr) => arr.reduce((m, x) => m.set(x, 1), new Map());
  const ca = count(A);
  const cb = count(B);
  const onlyA = [];
  const onlyB = [];
  for (const [k, n] of ca) { const d = n - (cb.get(k) || 0); for (let i = 0; i < d; i += 1) onlyA.push(k); }
  for (const [k, n] of cb) { const d = n - (ca.get(k) || 0); for (let i = 0; i < d; i += 1) onlyB.push(k); }
  return { total: [A.length, B.length], onlyBefore: onlyA, onlyAfter: onlyB, identical: !onlyA.length && !onlyB.length };
}

if (process.env.WALLET_REC_OUT && require.main !== module) install(process.env.WALLET_REC_OUT);

// `--check <suite>`: сюитани ёзувчи билан ишга тушириб, `test/fixtures/wallet_char/<suite>.json` (кўчиришдан
// ОЛДИН ёзилган) билан солиштиради. Emulator керак (FIRESTORE_EMULATOR_HOST).
if (require.main === module && process.argv[2] === '--check') {
  const suite = process.argv[3];
  const root = path.join(__dirname, '..', '..');
  const out = path.join(require('os').tmpdir(), `wallet_char_${suite}_${process.pid}.json`);
  const r = require('child_process').spawnSync(process.execPath,
      ['-r', path.join(__dirname, 'wallet_write_recorder.js'), path.join(root, 'test', `${suite}.test.js`)],
      { cwd: root, env: { ...process.env, WALLET_REC_OUT: out }, encoding: 'utf8' });
  const tail = String(r.stdout || '').trim().split('\n').slice(-1)[0];
  console.log(`${suite}: suite exit ${r.status} (${tail})`);
  const c = compare(path.join(root, 'test', 'fixtures', 'wallet_char', `${suite}.json`), out);
  console.log(`  fixture ${c.total[0]} / now ${c.total[1]} wallet writes; identical: ${c.identical}`);
  c.onlyBefore.slice(0, 20).forEach((x) => console.log(`  - ${x}`));
  c.onlyAfter.slice(0, 20).forEach((x) => console.log(`  + ${x}`));
  process.exit(r.status === 0 && c.identical ? 0 : 1);
}

if (require.main === module && process.argv[2] === '--compare') {
  const r = compare(process.argv[3], process.argv[4]);
  console.log(`before ${r.total[0]} / after ${r.total[1]} wallet writes; identical: ${r.identical}`);
  r.onlyBefore.slice(0, 20).forEach((x) => console.log(`  - ${x}`));
  r.onlyAfter.slice(0, 20).forEach((x) => console.log(`  + ${x}`));
  process.exit(r.identical ? 0 : 1);
}

module.exports = { install, compare, normVal, normPath };
