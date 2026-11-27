/**
 * SOXTA Cloud KMS (REST qatlami) — `core/card_crypto.createCardCrypto({ fetchImpl, getAccessToken })`.
 *
 * Haqiqiy AES-256-GCM + AAD: AAD mos kelmasa yoki ciphertext buzilgan bo'lsa — KMS kabi
 * 400 INVALID_ARGUMENT. Rejimlar (`kms.mode`): 'ok' | 'down' (tarmoq xatosi) | 'hang'
 * (javob yo'q, faqat abort) | '503' | '403' | 'noauth' (token xatosi) | 'tokenHang' |
 * 'decryptWrong' (dekript boshqa matn qaytaradi — migratsiya tekshiruvi uchun).
 */
const crypto = require('crypto');
const { DEFAULT_KEY_NAME, KMS_ENDPOINT } = require('../../core/card_crypto');

function resp(status, body) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

function makeFakeKms({ keyName = DEFAULT_KEY_NAME } = {}) {
  const key = crypto.randomBytes(32);
  const kms = {
    mode: 'ok',
    keyName,
    calls: [],
    tokenCalls: 0,
    count(op) { return this.calls.filter((c) => c.op === op).length; },
    reset() { this.calls = []; this.tokenCalls = 0; },
  };
  kms.getAccessToken = async () => {
    kms.tokenCalls += 1;
    if (kms.mode === 'noauth') throw new Error('Could not load the default credentials');
    if (kms.mode === 'tokenHang') return new Promise(() => {});
    return 'test-token';
  };
  kms.fetchImpl = async (url, init) => {
    const op = url.endsWith(':encrypt') ? 'encrypt' : (url.endsWith(':decrypt') ? 'decrypt' : '?');
    const body = JSON.parse(init.body);
    kms.calls.push({
      url, op, auth: init.headers.Authorization, body,
    });
    if (kms.mode === 'down') throw new TypeError('fetch failed');
    if (kms.mode === 'hang') {
      return new Promise((_, reject) => {
        if (init.signal) init.signal.addEventListener('abort', () => reject(new Error('This operation was aborted')));
      });
    }
    if (kms.mode === '503') return resp(503, { error: { code: 503, status: 'UNAVAILABLE', message: 'unavailable' } });
    if (kms.mode === '403') return resp(403, { error: { code: 403, status: 'PERMISSION_DENIED', message: 'denied' } });
    if (url !== `${KMS_ENDPOINT}/${kms.keyName}:${op}`) return resp(404, { error: { code: 404, status: 'NOT_FOUND', message: 'not found' } });
    const aad = Buffer.from(body.additionalAuthenticatedData || '', 'base64');
    if (op === 'encrypt') {
      const iv = crypto.randomBytes(12);
      const c = crypto.createCipheriv('aes-256-gcm', key, iv);
      c.setAAD(aad);
      const ct = Buffer.concat([c.update(Buffer.from(body.plaintext, 'base64')), c.final()]);
      return resp(200, { name: `${kms.keyName}/cryptoKeyVersions/1`, ciphertext: Buffer.concat([iv, c.getAuthTag(), ct]).toString('base64') });
    }
    if (op === 'decrypt') {
      const buf = Buffer.from(body.ciphertext, 'base64');
      try {
        const d = crypto.createDecipheriv('aes-256-gcm', key, buf.subarray(0, 12));
        d.setAAD(aad);
        d.setAuthTag(buf.subarray(12, 28));
        let pt = Buffer.concat([d.update(buf.subarray(28)), d.final()]);
        if (kms.mode === 'decryptWrong') pt = Buffer.from(`${pt.toString('utf8').slice(0, -1)}0`, 'utf8');
        return resp(200, { plaintext: pt.toString('base64') });
      } catch (_) {
        return resp(400, { error: { code: 400, status: 'INVALID_ARGUMENT', message: 'Decryption failed: the ciphertext is invalid.' } });
      }
    }
    return resp(400, { error: { code: 400, status: 'INVALID_ARGUMENT', message: 'bad op' } });
  };
  return kms;
}

module.exports = { makeFakeKms };
