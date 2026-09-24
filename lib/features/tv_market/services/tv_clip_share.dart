import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_share.dart';
import '../models/tv_clip.dart';

/// Улашилганда видео тагида кетадиган чақирув матни (эга қарори, 2026-09-24).
///
/// Атайин **фақат шу CTA** — клип сарлавҳаси, нархи ва ҳудуди қўшилмайди:
/// Telegram каналидаги пост «видео + битта чақирув + ҳавола» кўринишида
/// бўлиши керак.
const String kAvaShareCta =
    '👉 АВАга ўтинг! Фойдали видеолар, керакли хизматлар ва эълонлар — '
    'барчаси бир жойда. Сизга кераклиси ҳам шу ерда!';

/// CTA + босиладиган манзил. Ҳавола `/clip/{id}` саҳифасига боради:
/// илова ўрнатилган бўлса — иловада очилади (App Links), акс ҳолда
/// браузерда видео кўринади ва иловани юклаб олиш тугмаси чиқади.
String shareCaptionFor(TvClip clip) {
  final id = clip.id.trim();
  final link = id.isEmpty ? kAvaAppDownloadPage : avaClipShareUrl(id);
  return '$kAvaShareCta\n$link';
}

/// Клипни **видео файл** сифатида улашади (Telegram'да видеонинг ўзи
/// кўринади). Матн — [shareCaptionFor]: CTA + клип ҳаволаси.
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
    text: shareCaptionFor(clip),
    subject: 'AVA',
  );
}
