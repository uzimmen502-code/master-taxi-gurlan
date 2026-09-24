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

/// Улашиш матни — CTA + **тўғридан Google Play** ҳаволаси.
///
/// Оралиқ `/clip/{id}` саҳифаси улашиш оқимидан чиқарилди (эга қарори,
/// 2026-09-24): видео постнинг ўзида файл сифатида кетади ва одам уни
/// аллақачон кўриб бўлади — уни яна браузерда кўрсатиш ортиқча қадам эди.
/// Play ҳаволаси иккала ҳолатни қоплайди: илова бор бўлса «Очиш»,
/// йўқ бўлса «Ўрнатиш».
///
/// Матн клипга боғлиқ эмас, шунинг учун константа.
const String kAvaShareMessage = '$kAvaShareCta\n$kAvaPlayStoreUrl';

/// Клипни **видео файл** сифатида улашади (Telegram'да видеонинг ўзи
/// кўринади). Матн — [kAvaShareMessage].
///
/// HLS эмас, [TvClip.shareMp4Url] — устида AVA сув белгиси бор нусха.
/// Instagram/Facebook улашиш ойнасидаги МАТННИ ташлаб юборади (IG'да
/// caption майдонининг ўзи йўқ), шунинг учун ягона ўтадиган CTA —
/// видеонинг ўзига босилган белги. Эски клипларда `share` бўлмаса,
/// одатдаги mp4'га қайтади. Файл [DefaultCacheManager] орқали кешга
/// юкланади — кейинги улашишда қайта юкланмайди.
///
/// Видео файли топилмаса — улашмасдан [StateError] отилади, чақирувчи
/// «Улашиб бўлмади» хабарини кўрсатади (матнни ёлғиз юбормаймиз).
Future<void> shareTvClipVideo(TvClip clip) async {
  final url = clip.shareMp4Url;
  if (url.isEmpty) {
    throw StateError('tv_clip_share: mp4 yo\'q (clip ${clip.id})');
  }
  final file = await DefaultCacheManager().getSingleFile(url);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'video/mp4', name: 'ava_${clip.id}.mp4')],
    text: kAvaShareMessage,
    subject: 'AVA',
  );
}
