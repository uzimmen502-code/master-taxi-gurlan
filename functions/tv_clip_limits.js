/**
 * AVAGram klip davomiyligi chegaralari (server tomoni).
 *
 * Umumiy chegara `TV_CLIP_MAX_SECONDS = 600` (functions/index.js — o'lchovdan chiqqan raqam,
 * 2-avlodda butun zanjir byudjetning ~5 %i). TAOM videosi (`linkKind: 'restaurant_item'`,
 * D-REST-30) uchun — QISQAROQ: 60 soniya (ega qarori, 2026-10-19). Klient jufti:
 * `tvClipItemMaxUploadSeconds` (lib/features/tv_market/models/tv_clip.dart) — ikkalasi mos
 * turishi shart, buni `tv_clip_duration_limit_test.dart` tekshiradi.
 *
 * Nima uchun serverda ham: klient `maxDuration` va mahalliy kesishni FAQAT isrofni oldini olish
 * uchun qiladi (galereyadan uzun video kelishi mumkin) — haqiqiy chegara transcode'da
 * (`-t`), klientga ishonilmaydi (18-qoida). Chegara klipning o'z `linkKind`idan olinadi.
 */
'use strict';

/** Taom videosi uchun eng uzun davomiylik, soniya. */
const TV_CLIP_ITEM_MAX_SECONDS = 60;

/** Taom videosiga bog'langan klip turi (firestore.rules `tvClipRestaurantLinkOk`). */
const ITEM_LINK_KIND = 'restaurant_item';

/**
 * Klip uchun transcode chegarasi (soniya): taom videosi — 60, qolganlari — [defaultSeconds].
 * [clip] — `tv_clips` hujjati (yo'q/bo'sh bo'lsa umumiy chegara: eski klip buzilmaydi).
 */
function tvClipMaxSecondsFor(clip, defaultSeconds) {
  return clip && clip.linkKind === ITEM_LINK_KIND ? TV_CLIP_ITEM_MAX_SECONDS : defaultSeconds;
}

module.exports = { TV_CLIP_ITEM_MAX_SECONDS, ITEM_LINK_KIND, tvClipMaxSecondsFor };
