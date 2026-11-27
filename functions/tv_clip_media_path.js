'use strict';

/**
 * Клип файлининг Storage йўли — ФАҚАТ шу клип эгасининг папкасидан (`tv_clips/<эга телефони>/<файл>`).
 *
 * Хавфсизлик (аудит 2026-10-31, HIGH-1): `videoUrl`/`posterUrl` ни эга ўзи ёзади, rules уларни
 * текширмайди. Аввал сервер URL'дан ҳар қандай йўлни олиб, клип ўчирилганда ўша файлни Admin SDK
 * билан ЎЧИРАРДИ ва transcode'да манба қилиб оларди — бошқа фойдаланувчининг файлини ўчириш ёки
 * ёпиқ файлни очиқ вариантга чиқариш мумкин эди. Энди эганинг папкасидан ташқаридаги йўл — `null`.
 *
 * Клиент йўли: `tv_storage_service.dart` → `tv_clips/{ownerPhone}/{name}`; эски клиплар 9 рақамли
 * телефон билан ҳам бўлиши мумкин — шунинг учун охирги 9 рақам солиштирилади.
 */
function storagePathFromUrl(url) {
  const match = /\/o\/([^?]+)/.exec(url || '');
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch (_) {
    return null;
  }
}

function last9(v) {
  const d = String(v || '').replace(/\D/g, '');
  return d.length >= 9 ? d.slice(-9) : '';
}

function tvClipOwnedStoragePath(url, ownerPhone) {
  const p = storagePathFromUrl(url);
  if (!p) return null;
  const parts = p.split('/');
  if (parts.length !== 3 || parts[0] !== 'tv_clips') return null;
  if (!parts[2] || parts.some((s) => s === '' || s === '.' || s === '..')) return null;
  const ownerRaw = String(ownerPhone || '').trim();
  if (!ownerRaw) return null;
  // Айнан шу эганинг папкаси (прод'да қисқа синов ID'лари ҳам бор), ёки бир хил телефон бошқа шаклда.
  if (parts[1] === ownerRaw) return p;
  const owner = last9(ownerRaw);
  if (!owner || last9(parts[1]) !== owner) return null;
  return p;
}

module.exports = { tvClipOwnedStoragePath, storagePathFromUrl };
