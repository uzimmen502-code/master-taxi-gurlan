'use strict';

/**
 * Onlayn BOZOR (Аҳоли бозори, `ads` type=cheap_product) эълон расмлари.
 *
 * Расм сони 1..7 (эга қарори, 2026-10-17; аввал 1..5). Шу қиймат
 * `firestore.rules` (`cheapProductOwnerUpdateOk`) ва клиент
 * (`AdModel.maxImages`) билан бир хил бўлиши керак. Эски илова ≤5 юборади —
 * бу чегара ичида.
 */
const MARKET_MIN_IMAGES = 1;
const MARKET_MAX_IMAGES = 7;

/**
 * @param {unknown} urls клиент юборган `imageUrls`
 * @param {string[]} markers эгасининг `ads/{phone}/` йўл белгилари
 *   (`marketPhoneVariants(uid)` дан ясалади)
 */
function marketImageUrlsOk(urls, markers) {
  if (!Array.isArray(urls)
      || urls.length < MARKET_MIN_IMAGES
      || urls.length > MARKET_MAX_IMAGES) return false;
  return urls.every((raw) => {
    const u = String(raw || '');
    if (u.length < 20 || u.length > 2000) return false;
    if (!u.startsWith('https://')) return false;
    return markers.some((m) => u.includes(m));
  });
}

module.exports = { MARKET_MIN_IMAGES, MARKET_MAX_IMAGES, marketImageUrlsOk };
