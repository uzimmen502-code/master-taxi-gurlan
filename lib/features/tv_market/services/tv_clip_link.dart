import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart' show phonesMatch;
import '../models/tv_clip.dart';
import '../screens/tv_market_feed_screen.dart';
import '../screens/tv_publish_screen.dart';

/// Эълон / хизмат / Аҳоли бозори / ресторанга ихтиёрий видео (эга, 2026-10-16:
/// «фойдаланувчи истаса шу ернинг ўзида видеоролик жойлаштирсин»).
///
/// ЯГОНА қатлам — ҳар модул учун нусха эмас (Улгуржи эски `wholesaleProductId`
/// йўлида қолади). Боғланиш КЛИП томонида: [TvClip.linkKind] / [TvClip.linkId].
/// Эълон ҳужжатига (қоида/CF) тегилмайди, шунинг учун сервер ўзгармайди;
/// эгалик кўрсатишда текширилади ([TvClipsRepository.fetchLinked]).
abstract final class TvClipLink {
  static const kindAd = 'ad';
  static const kindService = 'service';
  static const kindMarket = 'market_ad';
  static const kindRestaurant = 'restaurant';

  /// Видео боғланганда кўтарилади — рўйхатлар (`JobsScreen`) харитани қайта
  /// юклайди.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Видео жойлаш экранини ОЧАДИ: клип яратилганда `linkKind`/`linkId` шу
  /// заҳоти ёзилади. Фақат оддий видео (реклама/янгилик сегментлари йўқ).
  /// Жойланса `true`.
  static Future<bool> publish(
    NavigatorState nav, {
    required String kind,
    required String linkId,
  }) async {
    if (linkId.isEmpty) return false;
    final published = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => TvPublishScreen(
          hideShopOption: true,
          organicOnly: true,
          linkKind: kind,
          linkId: linkId,
        ),
      ),
    );
    if (published == true) changes.value++;
    return published == true;
  }

  /// [linked] (`linkId → клип`) ичидан шу эълонники: клип эгаси = эълон эгаси
  /// ([ownerPhone]) бўлсагина. Бегона одам ўз клипини чужой эълонга "боғласа"
  /// ҳам кўринмайди.
  static TvClip? ownedClip(
    Map<String, TvClip> linked,
    String linkId,
    String ownerPhone,
  ) {
    final clip = linked[linkId];
    if (clip == null) return null;
    return phonesMatch(clip.ownerPhone, ownerPhone) ? clip : null;
  }

  /// Боғланган видеони AVAGram лентасида очади.
  static Future<void> open(BuildContext context, TvClip clip) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip)),
    );
  }
}
