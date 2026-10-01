/**
 * TV клип transcode НАТИЖАЛАРИ қаерга ёзилиши — абстракция.
 *
 * Transcode мантиғи (FFmpeg, поғона, HLS пакетлаш) бу файлга ҳеч қандай
 * алоқадор эмас ва ўзгармайди. Бу ерда фақат ЧИҚИШ бор: тайёр локал
 * файлни қаергадир юклаб, ўйнатса бўладиган URL қайтариш.
 *
 * Иккита реализация:
 *   FirebaseStorageOutput — ҳозирги йўл (`tv_clip_variants/`,
 *     `tv_clip_hls/`, token'ли `firebasestorage.googleapis.com` URL).
 *   R2Output — Cloudflare R2 (S3 API) + `video.ava-uz.com` CDN домени,
 *     барчаси ягона `processed/{clipId}/{runId}/` префиксида.
 *
 * ФЛАГ ЎЧИҚ БЎЛГАНДА ҲЕЧ НАРСА ЎЗГАРМАЙДИ: `FirebaseStorageOutput`
 * айнан олдинги йўл ва URL шаклини беради (тест шуни текширади).
 *
 * FALLBACK ЙЎҚ: R2 ёзуви йиқилса хато юқорига отилади ва клип `error`
 * бўлади. Атайин — яримта R2, яримта Firebase'да ётган клип кейинчалик
 * тузатиб бўлмайдиган чалкашлик беради.
 */
'use strict';

const crypto = require('crypto');
const {staleRunFiles} = require('./tv_clip_runs');

/** Барча видео объектлари учун — йўл ҳар transcode'да янги (`{runId}`). */
const TV_CLIP_CACHE_CONTROL = 'public, max-age=31536000, immutable';

/** Оммавий CDN домени (Cloudflare → R2 origin). */
const R2_PUBLIC_BASE = 'https://video.ava-uz.com';

/** R2 да ҳамма натижа шу префиксда. */
const R2_PREFIX = 'processed';

const CONTENT_TYPES = {
  '.m3u8': 'application/vnd.apple.mpegurl',
  '.m4s': 'video/mp4',
  '.mp4': 'video/mp4',
  '.webp': 'image/webp',
  '.ts': 'video/mp2t',
  '.jpg': 'image/jpeg',
};

/**
 * Файл кенгайтмасидан Content-Type. Чақирувчи аниқ тур берса ҳам,
 * кенгайтма устувор — объект нотўғри тур билан кэшланиб қолмаслиги учун
 * (CDN уни бир йилга сақлайди).
 * @param {string} name файл номи.
 * @param {string} fallback номаълум кенгайтма учун.
 * @return {string} MIME тури.
 */
function contentTypeFor(name, fallback) {
  const dot = String(name || '').lastIndexOf('.');
  const ext = dot >= 0 ? name.slice(dot).toLowerCase() : '';
  return CONTENT_TYPES[ext] || fallback || 'application/octet-stream';
}

/**
 * Firebase Storage — ҳозирги (ва флаг ўчиқдаги) йўл.
 *
 * Йўл иккита илдизга бўлинади, чунки ҳозирги тозалаш ва ўчириш мантиғи
 * айнан шу префиксларга таянади: `tv_clip_variants/` ва `tv_clip_hls/`.
 */
class FirebaseStorageOutput {
  /**
   * @param {object} bucket Admin SDK bucket.
   * @param {string} bucketName bucket номи (URL учун).
   */
  constructor(bucket, bucketName) {
    this.backend = 'firebase';
    this.bucket = bucket;
    this.bucketName = bucketName;
  }

  /**
   * @param {{clipId: string, runId: string, kind: string, name: string}} o
   * @return {string} Storage'даги тўлиқ йўл.
   */
  pathFor(o) {
    const root = o.kind === 'hls' ? 'tv_clip_hls' : 'tv_clip_variants';
    return `${root}/${o.clipId}/${o.runId}/${o.name}`;
  }

  /**
   * @param {string} localPath локал файл.
   * @param {object} o объект тавсифи (қаранг: [pathFor]).
   * @param {string} [contentType] чақирувчи таклиф қилган тур.
   * @return {Promise<string>} ўйнатса бўладиган URL.
   */
  async upload(localPath, o, contentType) {
    const destPath = this.pathFor(o);
    const token = crypto.randomUUID();
    await this.bucket.upload(localPath, {
      destination: destPath,
      metadata: {
        contentType: contentTypeFor(o.name, contentType),
        cacheControl: TV_CLIP_CACHE_CONTROL,
        metadata: {firebaseStorageDownloadTokens: token},
      },
    });
    return `https://firebasestorage.googleapis.com/v0/b/${this.bucketName}` +
        `/o/${encodeURIComponent(destPath)}?alt=media&token=${token}`;
  }

  /**
   * [keepRun]дан бошқа авлодларни ўчиради. Best-effort.
   * @param {string} clipId клип id.
   * @param {string} keepRun сақланадиган run.
   * @return {Promise<void>}
   */
  async cleanupOldRuns(clipId, keepRun) {
    if (!keepRun) return;
    for (const root of ['tv_clip_variants', 'tv_clip_hls']) {
      try {
        const [files] =
            await this.bucket.getFiles({prefix: `${root}/${clipId}/`});
        const stale = new Set(
            staleRunFiles(files.map((f) => f.name), root, clipId, keepRun));
        const victims = files.filter((f) => stale.has(f.name));
        for (const f of victims) {
          try {
            await f.delete();
          } catch (_) {}
        }
        if (victims.length > 0) {
          console.log(`tv clip ${clipId}: ${root} — ${victims.length} ` +
              `ta eski fayl tozalandi`);
        }
      } catch (e) {
        console.error(`cleanupOldRuns ${root} ${clipId}:`, e.message || e);
      }
    }
  }
}

/**
 * Cloudflare R2 (S3 API) + `video.ava-uz.com`.
 *
 * Token йўқ: объект йўли (`{runId}` туфайли) тахмин қилиб бўлмайдиган ва
 * ўзгармас, уни Cloudflare edge бир йилга кэшлайди. Сегментга token
 * қўйиш кэшни бузган бўларди.
 */
class R2Output {
  /**
   * @param {{client: object, bucket: string, publicBase?: string,
   *          sdk?: object}} opts
   *   `client` — S3 мижози (`send(command)`); тестда сохтаси берилади.
   *   `sdk` — командалар (`PutObjectCommand` ва ҳк.); берилмаса
   *   `@aws-sdk/client-s3` кеч юкланади. Тест SDK ўрнатилмасдан ҳам
   *   ишлаши учун шундай.
   */
  constructor(opts) {
    this.backend = 'r2';
    this.client = opts.client;
    this.bucket = opts.bucket;
    this.publicBase = (opts.publicBase || R2_PUBLIC_BASE).replace(/\/+$/, '');
    this._sdk = opts.sdk || null;
  }

  /** @return {object} S3 команда синфлари (кеч юкланади). */
  sdk() {
    if (!this._sdk) this._sdk = require('@aws-sdk/client-s3');
    return this._sdk;
  }

  /**
   * @param {{clipId: string, runId: string, name: string}} o
   * @return {string} R2 даги калит. Вариант ҳам, HLS ҳам битта
   *   префиксда — номлар тўқнашмайди (`.mp4`/`.ts`/`.m3u8` фарқли).
   */
  pathFor(o) {
    return `${R2_PREFIX}/${o.clipId}/${o.runId}/${o.name}`;
  }

  /**
   * @param {string} localPath локал файл.
   * @param {object} o объект тавсифи.
   * @param {string} [contentType] чақирувчи таклиф қилган тур.
   * @return {Promise<string>} CDN URL.
   */
  async upload(localPath, o, contentType) {
    const fs = require('fs');
    const {PutObjectCommand} = this.sdk();
    const key = this.pathFor(o);
    await this.client.send(new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      Body: fs.createReadStream(localPath),
      ContentLength: fs.statSync(localPath).size,
      ContentType: contentTypeFor(o.name, contentType),
      CacheControl: TV_CLIP_CACHE_CONTROL,
    }));
    return `${this.publicBase}/${key}`;
  }

  /**
   * [keepRun]дан бошқа авлодларни ўчиради. Best-effort.
   * @param {string} clipId клип id.
   * @param {string} keepRun сақланадиган run.
   * @return {Promise<void>}
   */
  async cleanupOldRuns(clipId, keepRun) {
    if (!keepRun) return;
    const {ListObjectsV2Command, DeleteObjectsCommand} = this.sdk();
    const prefix = `${R2_PREFIX}/${clipId}/`;
    try {
      const names = [];
      let token;
      do {
        const page = await this.client.send(new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: prefix,
          ContinuationToken: token,
        }));
        for (const obj of page.Contents || []) names.push(obj.Key);
        token = page.IsTruncated ? page.NextContinuationToken : undefined;
      } while (token);

      const stale = staleRunFiles(names, R2_PREFIX, clipId, keepRun);
      for (let i = 0; i < stale.length; i += 1000) {
        await this.client.send(new DeleteObjectsCommand({
          Bucket: this.bucket,
          Delete: {Objects: stale.slice(i, i + 1000).map((k) => ({Key: k}))},
        }));
      }
      if (stale.length > 0) {
        console.log(
            `tv clip ${clipId}: R2 — ${stale.length} ta eski fayl tozalandi`);
      }
    } catch (e) {
      console.error(`cleanupOldRuns r2 ${clipId}:`, e.message || e);
    }
  }
}

/**
 * Ҳақиқий R2 мижози. `@aws-sdk/client-s3` АЙНАН шу ерда, кеч
 * (lazy) юкланади — флаг ўчиқ бўлса модул умуман талаб қилинмайди ва
 * пакет йўқлиги бутун `index.js` ни йиқитмайди.
 * @param {{accountId: string, accessKeyId: string, secretAccessKey: string}} c
 * @return {object} S3Client.
 */
function createR2Client(c) {
  const {S3Client} = require('@aws-sdk/client-s3');
  return new S3Client({
    region: 'auto',
    endpoint: `https://${c.accountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
    },
  });
}

module.exports = {
  TV_CLIP_CACHE_CONTROL,
  R2_PUBLIC_BASE,
  R2_PREFIX,
  contentTypeFor,
  FirebaseStorageOutput,
  R2Output,
  createR2Client,
};
