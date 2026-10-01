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

/** Cloudflare `purge_cache` бир сўровда шунча URL қабул қилади. */
const CF_PURGE_BATCH = 30;

/**
 * `ava-uz.com` зонасининг идентификатори. МАХФИЙ ЭМАС — у Cloudflare
 * панелида очиқ туради ва ўзи ҳеч нарсага рухсат бермайди; рухсатни
 * фақат `CLOUDFLARE_API_TOKEN` беради (у Secret Manager'да).
 */
const CF_ZONE_ID = '96ca162bdd9bda9caac303197163ef77';

/** Purge уринишлари ва улар орасидаги кутиш (мс). */
const CF_PURGE_ATTEMPTS = 3;
const CF_PURGE_BACKOFF_MS = [500, 1500];

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
 * Клип эгаси R2 синов рўйхатидами?
 *
 * Клип ҳужжатида `uid` ЙЎҚ — эгани фақат `ownerPhone` аниқлайди
 * (`"998941133355"`). Рўйхат эса қўлда ёзилади, шунинг учун формат
 * ҳар хил бўлиши мумкин: `+998 94 113-33-55`, `998941133355`,
 * `94 113 33 55`. Фақат рақамлар солиштирилади, шунда формат фарқи
 * сабабли синов жимгина ишламай қолмайди.
 *
 * Қисқа (миллий) формат ҳам тушунилади: бири иккинчисининг охири
 * бўлса ва камида 9 рақам бўлса — мос деб ҳисобланади.
 * @param {string} ownerPhone клип эгасининг телефони.
 * @param {Array} owners `settings/app.tvR2OutputOwners`.
 * @return {boolean}
 */
function r2OwnerAllowed(ownerPhone, owners) {
  const digits = (v) => String(v == null ? '' : v).replace(/[^\d]/g, '');
  const me = digits(ownerPhone);
  if (me.length < 9 || !Array.isArray(owners)) return false;
  return owners.some((o) => {
    const x = digits(o);
    if (x.length < 9) return false;
    return x === me || me.endsWith(x) || x.endsWith(me);
  });
}

/**
 * Клип ҳужжатига қараб унинг тайёр файллари ҚАЕРДА турганини аниқлайди.
 *
 * Нима учун флагга қараб бўлмайди: флаг «ЭНДИ қаерга ёзамиз» дегани.
 * Эски файллар эса ўзи ёзилган пайтдаги backend'да ётади. Флаг ўчирилса,
 * R2'даги клипларни Firebase'дан излаб, ҳеч нарса топилмас ва улар
 * ўчмай қолар эди.
 *
 * Тартиб: аниқ майдон → URL хости → `firebase` (эски клиплар).
 * @param {object} data клип ҳужжати.
 * @return {string} 'r2' ёки 'firebase'.
 */
function resolveClipBackend(data) {
  const d = data || {};
  if (d.variantBackend === 'r2' || d.variantBackend === 'firebase') {
    return d.variantBackend;
  }
  const urls = [d.hlsUrl || '', ...Object.values(d.videoVariants || {})]
      .join(' ');
  return urls.includes(new URL(R2_PUBLIC_BASE).host) ? 'r2' : 'firebase';
}

/**
 * Cloudflare edge кэшидан URL'ларни чиқаради.
 *
 * ШАРТ: объектлар `immutable, max-age=31536000` билан берилади, яъни
 * R2'дан ўчириш ЕТАРЛИ ЭМАС — edge уларни бир йилгача беришда давом
 * этади. Ўчирилган клип CDN'да очиқ қолмаслиги учун purge керак.
 *
 * Калитлар бўлмаса — огоҳлантириб, ўтказиб юборади (ўчиришнинг ўзи
 * барибир бажарилган бўлади). Best-effort: purge йиқилса ҳам ўчириш
 * бекор қилинмайди.
 * @param {string[]} urls тўлиқ CDN URL'лари.
 * @return {Promise<number>} purge қилинган URL сони.
 */
async function purgeCdnUrls(urls, opts) {
  const list = (urls || []).filter(Boolean);
  if (list.length === 0) return 0;
  const token = (opts && opts.token) || process.env.CLOUDFLARE_API_TOKEN || '';
  const zoneId = (opts && opts.zoneId) || CF_ZONE_ID;
  const sleep = (opts && opts.sleep) || ((ms) =>
    new Promise((r) => setTimeout(r, ms)));
  if (!token) {
    console.warn(
        `CDN purge o'tkazib yuborildi (${list.length} URL): ` +
        'CLOUDFLARE_API_TOKEN yo\'q. Obyektlar R2\'dan o\'chdi, lekin ' +
        'edge keshida qolishi mumkin.');
    return 0;
  }

  let done = 0;
  for (let i = 0; i < list.length; i += CF_PURGE_BATCH) {
    const files = list.slice(i, i + CF_PURGE_BATCH);
    for (let attempt = 1; attempt <= CF_PURGE_ATTEMPTS; attempt++) {
      let retryable = true;
      try {
        const res = await fetch(
            `https://api.cloudflare.com/client/v4/zones/${zoneId}/purge_cache`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({files}),
            });
        if (res.ok) {
          done += files.length;
          break;
        }
        // 4xx (429'дан бошқа) — токен/ҳуқуқ/сўров хатоси. Қайта уриниш
        // уни тузатмайди, фақат вақт ейди.
        retryable = res.status === 429 || res.status >= 500;
        console.error(
            `CDN purge javobi (${attempt}/${CF_PURGE_ATTEMPTS}):`,
            res.status, (await res.text()).slice(0, 300));
      } catch (e) {
        // Тармоқ узилиши — қайта уриниб кўришга арзийди.
        console.error(
            `CDN purge xatosi (${attempt}/${CF_PURGE_ATTEMPTS}):`,
            e.message || e);
      }
      if (!retryable || attempt === CF_PURGE_ATTEMPTS) {
        if (!retryable) {
          console.error('CDN purge: qayta urinilmaydi (tuzatib bo\'lmaydigan ' +
              'xato) — tokenni va uning Zone.Cache Purge huquqini tekshiring');
        }
        break;
      }
      await sleep(CF_PURGE_BACKOFF_MS[attempt - 1] ||
          CF_PURGE_BACKOFF_MS[CF_PURGE_BACKOFF_MS.length - 1]);
    }
  }

  if (done < list.length) {
    // Ўчириш бажарилган, лекин кэшда қолгани бор — бу жимгина ўтмаслиги
    // керак: ўчирилган клип CDN'да очиқ қолиши мумкин.
    console.error(
        `CDN purge TO'LIQ EMAS: ${done}/${list.length} URL. Qolganlari ` +
        'edge keshida qolishi mumkin — Cloudflare panelidan qo\'lda ' +
        'purge qiling.');
  }
  return done;
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
   * @return {Promise<string[]>} purge керак URL'лар — Firebase учун
   *   доим бўш (объектлар CDN'да эмас).
   */
  async cleanupOldRuns(clipId, keepRun) {
    if (!keepRun) return [];
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
    return [];
  }

  /**
   * Клип ўчирилганда — унинг БАРЧА авлодлари.
   * @param {string} clipId клип id.
   * @return {Promise<string[]>} purge қилиниши керак URL'лар (бу ерда
   *   доим бўш: Firebase объектлари CDN'да эмас).
   */
  async deleteAllForClip(clipId) {
    for (const root of ['tv_clip_variants', 'tv_clip_hls']) {
      try {
        await this.bucket.deleteFiles({prefix: `${root}/${clipId}/`});
      } catch (e) {
        console.error(`deleteAllForClip ${root} ${clipId}:`, e.message || e);
      }
    }
    return [];
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
    try {
      const names = await this.listKeys(`${R2_PREFIX}/${clipId}/`);
      const stale = staleRunFiles(names, R2_PREFIX, clipId, keepRun);
      await this.deleteKeys(stale);
      if (stale.length > 0) {
        console.log(
            `tv clip ${clipId}: R2 — ${stale.length} ta eski fayl tozalandi`);
      }
      return stale.map((k) => `${this.publicBase}/${k}`);
    } catch (e) {
      console.error(`cleanupOldRuns r2 ${clipId}:`, e.message || e);
      return [];
    }
  }

  /**
   * Клип ўчирилганда — унинг БАРЧА авлодлари R2'дан кетади.
   * @param {string} clipId клип id.
   * @return {Promise<string[]>} ўчирилганларнинг CDN URL'лари — улар
   *   edge кэшдан ҳам чиқарилиши керак (қаранг: [purgeCdnUrls]).
   */
  async deleteAllForClip(clipId) {
    try {
      const keys = await this.listKeys(`${R2_PREFIX}/${clipId}/`);
      await this.deleteKeys(keys);
      if (keys.length > 0) {
        console.log(`tv clip ${clipId}: R2 — ${keys.length} ta obyekt o'chdi`);
      }
      return keys.map((k) => `${this.publicBase}/${k}`);
    } catch (e) {
      console.error(`deleteAllForClip r2 ${clipId}:`, e.message || e);
      return [];
    }
  }

  /**
   * @param {string} prefix калит префикси.
   * @return {Promise<string[]>} барча калитлар (саҳифалаб).
   */
  async listKeys(prefix) {
    const {ListObjectsV2Command} = this.sdk();
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
    return names;
  }

  /**
   * @param {string[]} keys ўчириладиган калитлар.
   * @return {Promise<void>}
   */
  async deleteKeys(keys) {
    if (!keys || keys.length === 0) return;
    const {DeleteObjectsCommand} = this.sdk();
    for (let i = 0; i < keys.length; i += 1000) {
      await this.client.send(new DeleteObjectsCommand({
        Bucket: this.bucket,
        Delete: {Objects: keys.slice(i, i + 1000).map((k) => ({Key: k}))},
      }));
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
  r2OwnerAllowed,
  resolveClipBackend,
  purgeCdnUrls,
  FirebaseStorageOutput,
  R2Output,
  createR2Client,
};
