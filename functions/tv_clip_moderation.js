/**
 * TV клип модерацияси — эгасига хабар бериш қоидаси (СОФ мантиқ).
 *
 * Эга видеони жойлаганда (`pending`) «текширувдан кейин чиқади» дейилади.
 * Аввал фақат РАД этилганда хабар бор эди (`onTvClipRejected`); тасдиқланса
 * эга билмай қоларди ва ресторан/эълон саҳифасида видео пайдо бўлганини
 * тасодифан кўрарди.
 *
 * Хабар ФАҚАТ `pending → active` ўтишида: клип дарҳол `active` яратилса
 * (авто-тасдиқ) ёки `active` қолса — хабар йўқ. Пуллик реклама (`ad`)
 * модерациядан ўтмайди — унга ҳеч қачон.
 */
'use strict';

function tvClipBecameApproved(before, after) {
  const b = before || {};
  const a = after || {};
  if (a.category === 'ad') return false;
  return b.status === 'pending' && a.status === 'active';
}

/**
 * Тасдиқланган клипнинг МАТН/МУҚОВАСИ эга томонидан ўзгардими (аудит 2026-10-31, MEDIUM-2/5).
 *
 * `onTvClipVideoReplacedV2` даги `video_replaced` шохининг жуфти: видео ўзгармаган, лекин
 * `title`/`description`/`posterUrl` ўзгарган ва клип `active` да қолган. Фақат шу уч калит —
 * ҳисоблагичлар (`likeCount`, `viewCount`, `commentCount`, `playbackStats`), transcode
 * натижалари (`hlsUrl`, `videoVariants`, …), ижтимоий тармоқ майдонлари ва бошқалар
 * ҚАЙТА МОДЕРАЦИЯГА туширмайди. Сервернинг ўз ёзуви (`status: 'pending'`) иккинчи
 * ишга тушишда `after.status !== 'active'` бўлгани учун цикл ҳосил қилмайди.
 * Пуллик реклама (`ad`) — `publishTvAd` оқими, тегилмайди.
 */
const TV_CLIP_CONTENT_KEYS = Object.freeze(['title', 'description', 'posterUrl']);

function tvClipContentEdited(before, after) {
  const b = before || {};
  const a = after || {};
  if (a.category === 'ad') return false;
  if (b.status !== 'active' || a.status !== 'active') return false;
  if ((b.videoUrl || '') !== (a.videoUrl || '')) return false; // видео шохи ўзи ҳал қилади
  const norm = (v) => (v == null ? '' : String(v));
  return TV_CLIP_CONTENT_KEYS.some((k) => norm(b[k]) !== norm(a[k]));
}

module.exports = {tvClipBecameApproved, tvClipContentEdited, TV_CLIP_CONTENT_KEYS};
