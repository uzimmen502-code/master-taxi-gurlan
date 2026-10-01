/**
 * TV клип transcode «run»лари — соф мантиқ (Firebase'сиз, тестланадиган).
 *
 * Ҳар transcode ўз йўлига ёзади: `{root}/{clipId}/{runId}/...`. Сабаби ва
 * тўлиқ изоҳи `index.js` даги [cleanupOldTvClipRuns] устида.
 *
 * Бу файлда фақат ҚАРОР бор (нимани ўчириш керак), ЎЧИРИШнинг ўзи эмас —
 * шунинг учун уни Storage'сиз, эмуляторсиз синаб кўриш мумкин.
 */

/** Янги run учун идентификатор. Вақт бўйича ўсади, йўлда хавфсиз. */
function tvClipRunId() {
  return Date.now().toString(36);
}

/**
 * `{root}/{clipId}/` префиксидаги файллардан ҚАЙСИЛАРИ эскиргани.
 *
 * @param {string[]} fileNames Storage'даги тўлиқ объект номлари.
 * @param {string} root 'tv_clip_variants' ёки 'tv_clip_hls'.
 * @param {string} clipId клип ҳужжати id'си.
 * @param {string} keepRun сақланадиган run (ҳужжатдаги `variantRun`).
 * @return {string[]} ўчириладиган объект номлари.
 *
 * [keepRun] БЎШ бўлса — бўш рўйхат қайтади, яъни ҲЕЧ НАРСА ўчирилмайди.
 * Бу — клипнинг версияли йўлга БИРИНЧИ марта ўтиши: ҳужжатда ҳали
 * `variantRun` йўқ, демак ҳозир томоша қилинаётган нарса — айнан эски,
 * версиясиз файллар. Уларни ўчириш биз тузатаётган муаммонинг ўзини
 * (эски URL ишламай қолиши) такрорларди.
 */
function staleRunFiles(fileNames, root, clipId, keepRun) {
  if (!keepRun) return [];
  const prefix = `${root}/${clipId}/`;
  return (fileNames || []).filter((name) => {
    if (!name.startsWith(prefix)) return false;
    const rest = name.slice(prefix.length);
    // Папкасиз эски (версиясиз) файллар ҳам эскирган ҳисобланади —
    // улар `rest`да «/» сақламайди.
    if (!rest.includes('/')) return true;
    return rest.split('/')[0] !== keepRun;
  });
}

module.exports = {tvClipRunId, staleRunFiles};
