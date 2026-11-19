'use strict';

/**
 * `tv_clips.activatedAt` — клип `active` бўлган сервер вақти (эга қарори
 * 2026-11-19: «Кун янгиликлари» 24 соати фаоллашувдан ҳисобланади).
 *
 * Чақирувчи: `onTvClipSocialPublish` (tv_social_publish.js) — у
 * `яратилди active` ва `X → active` ўтишларини аллақачон ушлайди, янги
 * триггер қўшилмайди. Клиент бу майдонни ёза олмайди (`firestore.rules`).
 *
 * Қиймат = фаоллашган ёзувнинг `updateTime`и (яратилишда = `createTime`),
 * яъни ҳодисадан олинади: retry айнан шу қийматни топади ва ёзмайди;
 * кейинроқ бўлган фаоллашув ёзилган бўлса эски ҳодиса уни босмайди
 * (`shouldStampActivation`). Хато чақирувчини йиқитмайди — фақат
 * structured log (клип «эски» ҳисобланиб AVAGram'да қолади, йўқолмайди).
 *
 * Тест: `test/tv_clip_activation_cf.test.js` (emulator).
 */
const { shouldStampActivation } = require('./tv_news_window');

/**
 * @param {{db: object, admin: object}} deps Firestore ва admin SDK.
 * @param {object} snap фаоллашган ҳужжат снапшоти (`change.after`).
 * @return {Promise<'written'|'skip'|'error'>} натижа.
 */
async function stampTvClipActivation({ db, admin }, snap) {
  const at = (snap && (snap.updateTime || snap.createTime)) || null;
  const eventMs = at && typeof at.toMillis === 'function' ? at.toMillis() : null;
  if (!eventMs) return 'skip';
  try {
    const wrote = await db.runTransaction(async (tx) => {
      const cur = await tx.get(snap.ref);
      if (!cur.exists || !shouldStampActivation(cur.data() || {}, eventMs)) return false;
      tx.update(snap.ref, { activatedAt: admin.firestore.Timestamp.fromMillis(eventMs) });
      return true;
    });
    const result = wrote ? 'written' : 'skip';
    console.log(JSON.stringify({ action: 'tv_clip_activated_at', clipId: snap.id, result }));
    return result;
  } catch (e) {
    console.error(JSON.stringify({
      action: 'tv_clip_activated_at',
      clipId: snap.id,
      result: 'error',
      errorCode: 'TV_CLIP_ACTIVATED_AT_WRITE_FAILED',
      message: String((e && e.message) || e).slice(0, 300),
    }));
    return 'error';
  }
}

module.exports = { stampTvClipActivation };
