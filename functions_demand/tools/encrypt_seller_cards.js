/**
 * ULGURJI SOTUVCHI KARTASI — ochiq matndan Cloud KMS shifrlashga MIGRATSIYA (ega, 2026-10-31).
 *
 *   node functions_demand/tools/encrypt_seller_cards.js --project master-taxi-gurlan                 # dry-run (default)
 *   node functions_demand/tools/encrypt_seller_cards.js --project master-taxi-gurlan --write
 *   node functions_demand/tools/encrypt_seller_cards.js --project master-taxi-gurlan --write --restore-plaintext   # FAVQULODDA orqaga
 *
 * Ixtiyoriy: --batch 50 (sahifa hajmi, 1..200), --limit N (ko'pi bilan N ta hujjat yoziladi),
 *            --credentials <service-account.json> (Firestore + KMS uchun; berilmasa — ADC).
 * Kalit: env WHOLESALE_CARD_KMS_KEY yoki core/card_crypto.js DEFAULT_KEY_NAME.
 * Ishga tushiruvchi identifikatorga SHU kalitda cryptoKeyEncrypterDecrypter kerak.
 *
 * TARTIB (deploy'dan KEYIN): 1) default `placeWholesaleOrder` (payoutDocHasCard — ikkala shakl)
 * va demand `setWholesaleSellerCard`/`getWholesaleCardPaymentInfo` jonli; 2) dry-run; 3) --write.
 *
 * Nima qiladi (`wholesale_sellers/*` sahifalab, har sahifada `private/payout` getAll bilan):
 *   plaintext (cardNumber/holderName bor, *Enc yo'q):
 *     A) ikkala maydon shifrlanadi (AAD = sotuvchi hujjati ID'si + maydon, card_crypto.aadFor);
 *     B) tranzaksiya: hujjat hali O'SHA ochiq qiymatda bo'lsa — *Enc maydonlari QO'SHILADI
 *        (ochiq maydonlar hali turadi);
 *     C) TEKSHIRUV: hujjat Firestore'dan qayta o'qiladi, saqlangan *Enc dekript qilinadi va ochiq
 *        qiymat bilan solishtiriladi — mos kelmasa *Enc olib tashlanadi, ochiq qoladi (failed);
 *     D) tranzaksiya: hujjat o'zgarmagan bo'lsa — ochiq maydonlar O'CHIRILADI (hujjat to'liq
 *        almashtiriladi) + `admin_audit` yozuvi (AYNI tranzaksiyada, append-only).
 *   ikkalasi bor (B dan keyin uzilgan) — C dan davom etadi (idempotent qayta ishga tushirish).
 *   faqat kms — tegilmaydi (alreadyEncrypted).
 *   --restore-plaintext: faqat-kms hujjatlarga dekript qilingan ochiq maydonlar QAYTA qo'shiladi
 *     (*Enc saqlanadi) + audit — eski kodga rollback qilish kerak bo'lsa. Keyingi oddiy --write
 *     ularni yana tozalaydi.
 *
 * Log/konsol: telefon, to'liq raqam, ism, ciphertext CHIQMAYDI — faqat tartib raqami va ****last4.
 */
'use strict';

const path = require('path');
const cardCryptoLib = require('../core/card_crypto');

const SELLERS = 'wholesale_sellers';
const ADMIN_AUDIT = 'admin_audit';
const PROJECT = 'master-taxi-gurlan';
const BY = 'tools/encrypt_seller_cards.js';
const AUDIT_KIND = 'wholesale_card_encrypt_migration';

const mask = (last4) => `****${/^\d{4}$/.test(String(last4 || '')) ? last4 : '????'}`;
const hasPlain = (d) => d.cardNumber !== undefined || d.holderName !== undefined;
const hasEnc = (d) => d.cardNumberEnc !== undefined || d.holderNameEnc !== undefined;
const plainValid = (d) => typeof d.cardNumber === 'string' && /^\d{16}$/.test(d.cardNumber)
  && typeof d.holderName === 'string' && d.holderName !== '';
const encValid = (d) => cardCryptoLib.isEncryptedValue(d.cardNumberEnc) && cardCryptoLib.isEncryptedValue(d.holderNameEnc)
  && typeof d.last4 === 'string' && /^\d{4}$/.test(d.last4);

function omit(obj, keys) {
  const out = { ...obj };
  for (const k of keys) delete out[k];
  return out;
}

async function decryptPair(cardCrypto, sellerId, d) {
  const [cardNumber, holderName] = await Promise.all([
    cardCrypto.decryptCard(d.cardNumberEnc, { sellerId, field: 'cardNumber' }),
    cardCrypto.decryptCard(d.holderNameEnc, { sellerId, field: 'holderName' }),
  ]);
  return { cardNumber, holderName };
}

/**
 * @param {object} deps
 * @param {object} deps.db            Firestore (Admin SDK yoki FakeFirestore + runTransaction)
 * @param {object} deps.cardCrypto    core/card_crypto createCardCrypto() natijasi
 * @param {boolean} [deps.write]      false (default) — dry-run, hech narsa yozilmaydi
 * @param {boolean} [deps.restorePlaintext]
 * @param {number} [deps.batchSize]
 * @param {number} [deps.limit]       ko'pi bilan nechta hujjatga yoziladi
 * @param {Function} [deps.now]
 * @param {Function} [deps.print]     konsol (testda yig'iladi)
 */
async function runMigration(deps) {
  const {
    db, cardCrypto, write = false, restorePlaintext = false, batchSize = 50, limit = Infinity, now: nowFn, print = console.log,
  } = deps;
  const sum = {
    mode: restorePlaintext ? 'restore-plaintext' : 'encrypt',
    write: !!write,
    sellersScanned: 0,
    payoutDocs: 0,
    plaintext: 0,
    halfMigrated: 0,
    alreadyEncrypted: 0,
    invalid: 0,
    migrated: 0,
    restored: 0,
    skippedChanged: 0,
    failed: 0,
  };
  let n = 0;
  let writes = 0;
  let last = null;
  for (;;) {
    let q = db.collection(SELLERS).orderBy('__name__').limit(batchSize);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    last = page.docs[page.docs.length - 1];
    sum.sellersScanned += page.docs.length;
    const refs = page.docs.map((s) => db.collection(SELLERS).doc(s.id).collection('private').doc('payout'));
    const snaps = await db.getAll(...refs);
    for (let i = 0; i < snaps.length; i += 1) {
      const snap = snaps[i];
      if (!snap.exists) continue;
      sum.payoutDocs += 1;
      n += 1;
      const sellerId = page.docs[i].id;
      const ref = refs[i];
      const d = snap.data() || {};
      const plain = hasPlain(d);
      const enc = hasEnc(d);
      const last4 = plainValid(d) ? d.cardNumber.slice(-4) : d.last4;
      const tag = `#${n} ${mask(last4)}`;

      if (restorePlaintext) {
        if (plain || !encValid(d)) continue;
        sum.alreadyEncrypted += 1;
        if (!write) { print(`  ${tag}: dry-run — ochiq maydonlar qaytariladi`); continue; }
        if (writes >= limit) continue;
        writes += 1;
        try {
          const p = await decryptPair(cardCrypto, sellerId, d);
          if (!/^\d{16}$/.test(p.cardNumber) || p.cardNumber.slice(-4) !== d.last4 || !p.holderName) throw new Error('plaintext_invalid');
          const r = await db.runTransaction(async (tx) => {
            const s = await tx.get(ref);
            const c = s.exists ? (s.data() || {}) : {};
            if (hasPlain(c) || c.cardNumberEnc !== d.cardNumberEnc || c.holderNameEnc !== d.holderNameEnc) return 'changed';
            const at = nowFn ? nowFn() : new Date();
            tx.set(ref, { ...c, cardNumber: p.cardNumber, holderName: p.holderName, plaintextRestoredAt: at });
            tx.set(db.collection(ADMIN_AUDIT).doc(), {
              kind: AUDIT_KIND, actor: BY, target: `${SELLERS}/${sellerId}/private/payout`, from: 'kms:v1', to: 'kms:v1+plaintext',
              reason: 'restore_plaintext', detail: { last4: d.last4, keyName: cardCrypto.keyName || null }, at,
            });
            return 'ok';
          });
          if (r === 'ok') { sum.restored += 1; print(`  ${tag}: ochiq maydonlar qaytarildi`); } else { sum.skippedChanged += 1; print(`  ${tag}: o'zgargan — o'tkazildi`); }
        } catch (e) {
          sum.failed += 1;
          print(`  ${tag}: XATO ${cardCryptoLib.isCardCryptoError(e) ? e.code : 'RESTORE_FAILED'}`);
        }
        continue;
      }

      if (!plain) {
        if (encValid(d)) sum.alreadyEncrypted += 1;
        else { sum.invalid += 1; print(`  ${tag}: karta maydonlari yaroqsiz — tegilmadi`); }
        continue;
      }
      if (!plainValid(d)) { sum.invalid += 1; print(`  ${tag}: ochiq karta yaroqsiz — tegilmadi`); continue; }
      if (enc && !encValid(d)) { sum.invalid += 1; print(`  ${tag}: *Enc buzilgan — tegilmadi`); continue; }
      if (enc) sum.halfMigrated += 1; else sum.plaintext += 1;
      if (!write) { print(`  ${tag}: dry-run — ${enc ? 'tekshiruv + ochiq maydonlar o\'chiriladi' : 'shifrlanadi'}`); continue; }
      if (writes >= limit) continue;
      writes += 1;

      try {
        // A + B: shifrlash va *Enc qo'shish (ochiq maydonlar hali turadi).
        if (!enc) {
          const [cardNumberEnc, holderNameEnc] = await Promise.all([
            cardCrypto.encryptCard(d.cardNumber, { sellerId, field: 'cardNumber' }),
            cardCrypto.encryptCard(d.holderName, { sellerId, field: 'holderName' }),
          ]);
          const r = await db.runTransaction(async (tx) => {
            const s = await tx.get(ref);
            const c = s.exists ? (s.data() || {}) : {};
            if (c.cardNumber !== d.cardNumber || c.holderName !== d.holderName || hasEnc(c)) return 'changed';
            tx.set(ref, {
              ...c, cardNumberEnc, holderNameEnc, last4: d.cardNumber.slice(-4), encVersion: cardCryptoLib.ENC_VERSION,
            });
            return 'ok';
          });
          if (r !== 'ok') { sum.skippedChanged += 1; print(`  ${tag}: o'zgargan — o'tkazildi`); continue; }
        }
        // C: Firestore'dagi saqlangan qiymatni dekript qilib tekshirish.
        const stored = (await ref.get()).data() || {};
        let verified = false;
        try {
          const p = await decryptPair(cardCrypto, sellerId, stored);
          verified = p.cardNumber === stored.cardNumber && p.holderName === stored.holderName
            && stored.last4 === String(stored.cardNumber || '').slice(-4);
        } catch (e) {
          if (!cardCryptoLib.isCardCryptoError(e) || e.transient) throw e; // KMS ishlamayapti — hech narsa o'zgarmaydi
          verified = false;
        }
        if (!verified) {
          // Mos kelmadi: *Enc olib tashlanadi (faqat O'ZIMIZ hozir yozgan bo'lsa), ochiq qoladi.
          if (!enc) {
            await db.runTransaction(async (tx) => {
              const s = await tx.get(ref);
              const c = s.exists ? (s.data() || {}) : {};
              if (c.cardNumberEnc === stored.cardNumberEnc && c.holderNameEnc === stored.holderNameEnc) {
                tx.set(ref, omit(c, ['cardNumberEnc', 'holderNameEnc', 'encVersion']));
              }
            });
          }
          sum.failed += 1;
          print(`  ${tag}: XATO VERIFY_MISMATCH — ochiq qoldi`);
          continue;
        }
        // D: ochiq maydonlarni o'chirish + audit (bitta tranzaksiya).
        const r = await db.runTransaction(async (tx) => {
          const s = await tx.get(ref);
          const c = s.exists ? (s.data() || {}) : {};
          if (c.cardNumber !== stored.cardNumber || c.holderName !== stored.holderName
            || c.cardNumberEnc !== stored.cardNumberEnc || c.holderNameEnc !== stored.holderNameEnc) return 'changed';
          const at = nowFn ? nowFn() : new Date();
          tx.set(ref, {
            ...omit(c, ['cardNumber', 'holderName', 'plaintextRestoredAt']),
            encVersion: cardCryptoLib.ENC_VERSION,
            encryptedAt: at,
            encryptedBy: BY,
          });
          tx.set(db.collection(ADMIN_AUDIT).doc(), {
            kind: AUDIT_KIND, actor: BY, target: `${SELLERS}/${sellerId}/private/payout`, from: enc ? 'plaintext+kms:v1' : 'plaintext', to: 'kms:v1',
            reason: 'owner_decision_2026-10-31', detail: { last4: c.last4, version: Number.isInteger(c.version) ? c.version : null, keyName: cardCrypto.keyName || null }, at,
          });
          return 'ok';
        });
        if (r === 'ok') { sum.migrated += 1; print(`  ${tag}: shifrlandi, ochiq maydonlar o'chirildi`); } else { sum.skippedChanged += 1; print(`  ${tag}: o'zgargan — o'tkazildi`); }
      } catch (e) {
        sum.failed += 1;
        print(`  ${tag}: XATO ${cardCryptoLib.isCardCryptoError(e) ? e.code : 'MIGRATION_FAILED'} — ochiq qoldi`);
      }
    }
    if (page.docs.length < batchSize) break;
  }
  return sum;
}

// ─── CLI ──────────────────────────────────────────────────────────────
function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return undefined;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}

async function main() {
  const project = arg('project');
  if (project !== PROJECT) {
    console.error(`--project ${PROJECT} AYNAN ko'rsatilishi shart (xavfsizlik: tasodifiy loyiha yo'q).`);
    process.exit(2);
  }
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('FIRESTORE_EMULATOR_HOST o\'rnatilgan — emulator bilan haqiqiy KMS aralashmasin. O\'chirib qayta ishga tushiring.');
    process.exit(2);
  }
  const write = process.argv.includes('--write');
  const restorePlaintext = process.argv.includes('--restore-plaintext');
  const batchSize = Number(arg('batch') || 50);
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 200) { console.error('--batch 1..200'); process.exit(2); }
  const limitArg = arg('limit');
  const limit = limitArg === undefined ? Infinity : Number(limitArg);
  if (limit !== Infinity && (!Number.isInteger(limit) || limit < 1)) { console.error('--limit musbat butun son'); process.exit(2); }
  const credentials = arg('credentials');

  // eslint-disable-next-line global-require, import/no-dynamic-require
  const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: PROJECT,
      // eslint-disable-next-line global-require, import/no-dynamic-require
      credential: typeof credentials === 'string' ? admin.credential.cert(require(path.resolve(credentials))) : admin.credential.applicationDefault(),
    });
  }
  const db = admin.firestore();
  const cardCrypto = cardCryptoLib.createCardCrypto(typeof credentials === 'string' ? { keyFile: path.resolve(credentials) } : {});
  console.log(`Loyiha: ${PROJECT}; kalit: ${cardCrypto.keyName}; rejim: ${restorePlaintext ? 'RESTORE-PLAINTEXT' : 'ENCRYPT'}; ${write ? 'YOZILADI' : 'DRY-RUN (hech narsa yozilmaydi)'}`);
  const sum = await runMigration({
    db, cardCrypto, write, restorePlaintext, batchSize, limit,
  });
  console.log('\nNatija:', JSON.stringify(sum, null, 2));
  if (!write) console.log('\n(--write bilan ishga tushiring)');
  process.exitCode = sum.failed > 0 ? 1 : 0;
}

if (require.main === module) {
  main().catch((e) => {
    console.error(`XATO: ${cardCryptoLib.isCardCryptoError(e) ? e.code : String((e && e.message) || e).slice(0, 200)}`);
    process.exit(1);
  });
}

module.exports = { runMigration, AUDIT_KIND };
