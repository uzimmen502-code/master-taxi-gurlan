import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../models/tv_clip.dart';

/// Улашилганда видео тагида кетадиган ягона матн (эга қарори, 2026-09-24).
///
/// Атайин **фақат шу CTA** — клип сарлавҳаси, нархи, ҳудуди ва ҳавола
/// қўшилмайди: Telegram каналига жойлашда пост «видео + битта чақирув»
/// кўринишида бўлиши керак.
const String kAvaShareCta =
    '👉 АВАга ўтинг! Фойдали видеолар, керакли хизматлар ва эълонлар — '
    'барчаси бир жойда. Сизга кераклиси ҳам шу ерда!';

/// Клипни **видео файл** сифатида улашади (Telegram'да видеонинг ўзи
/// кўринади, ҳавола эмас). Матн — фақат [kAvaShareCta].
///
/// HLS эмас, [TvClip.mp4Url] (360p афзал — кичик, тез юкланади). Файл
/// [DefaultCacheManager] орқали кешга юкланади — кейинги улашишда қайта
/// юкланмайди.
///
/// Видео файли топилмаса — улашмасдан [StateError] отилади, чақирувчи
/// «Улашиб бўлмади» хабарини кўрсатади (матнни ёлғиз юбормаймиз).
Future<void> shareTvClipVideo(TvClip clip) async {
  final url = clip.mp4Url;
  if (url.isEmpty) {
    throw StateError('tv_clip_share: mp4 yo\'q (clip ${clip.id})');
  }
  final file = await DefaultCacheManager().getSingleFile(url);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'video/mp4', name: 'ava_${clip.id}.mp4')],
    text: kAvaShareCta,
    subject: 'AVA',
  );
}
