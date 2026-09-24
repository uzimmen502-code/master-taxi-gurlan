import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/app_share.dart';
import '../models/tv_clip.dart';

/// Улашиладиган матн — ҳар доим «AVA — олиб келувчи» CTA билан тугайди
/// (эга талаби, 2026-09-24). Ижтимоий тармоқ/Telegram'га улашилганда
/// қабул қилган одам AVA'га ўтиши учун ҳавола ҳам қўшилади.
String _shareCaption(TvClip clip) {
  final lines = <String>[
    if (clip.title.trim().isNotEmpty) clip.title.trim(),
    if (clip.hasPrice) formatMoney(clip.price),
    if (clip.districtLabel.trim().isNotEmpty) '📍 ${clip.districtLabel.trim()}',
    '',
    '📲 AVA иловасида кўринг: $kAvaAppDownloadPage',
    '🚚 AVA — сизга олиб келувчи',
  ];
  return lines.join('\n');
}

/// «Ҳаволани юбориш» — фақат матн + AVA ҳаволаси (енгил, дарҳол ишлайди).
/// Telegram/IG/FB'да қабул қилган одам ҳаволадан AVA'га ўтади.
Future<void> shareTvClipLink(TvClip clip) async {
  await Share.share(_shareCaption(clip), subject: 'AVA');
}

/// «Видеони юбориш» — видео файлни (прогрессив MP4) юклаб олиб, файл
/// сифатида улашади (Telegram ичида кўринади). Матнга «AVA'да кўриш»
/// ҳаволаси ҳам бирга кетади, шунда қабул қилган одам иловага ўта олади.
///
/// HLS эмас, [TvClip.mp4Url] (360p афзал — кичик, тез юкланади). Файл
/// [DefaultCacheManager] орқали кешга юкланади — кейинги улашишда қайта
/// юкланмайди.
Future<void> shareTvClipVideo(TvClip clip) async {
  final url = clip.mp4Url;
  if (url.isEmpty) {
    // Видео файл йўқ — камида ҳаволани улашамиз.
    await shareTvClipLink(clip);
    return;
  }
  final file = await DefaultCacheManager().getSingleFile(url);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'video/mp4', name: 'ava_${clip.id}.mp4')],
    text: _shareCaption(clip),
    subject: 'AVA',
  );
}
