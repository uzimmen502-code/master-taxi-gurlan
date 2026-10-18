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

module.exports = {tvClipBecameApproved};
