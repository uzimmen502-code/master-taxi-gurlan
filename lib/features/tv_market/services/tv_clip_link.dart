import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart' show phonesMatch;
import '../models/tv_clip.dart';
import '../screens/tv_market_feed_screen.dart';
import '../screens/tv_publish_screen.dart';

/// Эълон / хизмат / Аҳоли бозори / ресторанга ихтиёрий видео (эга, 2026-10-16:
/// «фойдаланувчи истаса шу ернинг ўзида видеоролик жойлаштирсин»).
///
/// ЯГОНА қатлам — ҳар модул учун нусха эмас (Улгуржи ҳам жойлашни шу [publish] орқали қилади, 2026-10-20;
/// фақат ўз `videoClipIds` / `wholesaleProductId` боғланиши қўшимча). Боғланиш КЛИП томонида: [TvClip.linkKind] / [TvClip.linkId].
/// Эълон ҳужжатига (қоида/CF) тегилмайди, шунинг учун сервер ўзгармайди;
/// эгалик кўрсатишда текширилади ([TvClipsRepository.fetchLinked]).
abstract final class TvClipLink {
  static const kindAd = 'ad';
  static const kindService = 'service';
  static const kindMarket = 'market_ad';
  static const kindRestaurant = 'restaurant';

  /// Ресторан ТАОМИга видео (2026-10-19, эга: «расм ёнига ихтиёрий видео, АВАГрамга ҳам жойлансин»):
  /// linkId — ресторан id, linkItemId — таом id. АВАГрам лентасига ОДДИЙ клип сифатида тушади
  /// (модерация, R2 — ўша қатлам); ресторан меню саҳифасида таом қаторидан очилади.
  static const kindRestaurantItem = 'restaurant_item';

  /// Кўчмас мулк эълони (`realty_listings`, 2026-10-19, эга: «сотиш / ижарада ихтиёрий, максимум
  /// 60 секундлик видео, АВАГрамга жойлансин, эълон ўчирилса видео ҳам ўчсин»): linkId — эълон id.
  /// Ваколат `firestore.rules`да (`tvClipRealtyLinkOk`), 60 с — серверда (`tv_clip_limits.js`),
  /// эълон ўчирилса клип сервердан ўчади (`functions/realty_video.js`). Кўрсатишда эгалик
  /// солиштирилмайди (`LinkedVideoButton.trustLinkKind`) — қоида ўзи кафолатлайди.
  static const kindRealty = 'realty_listing';

  /// Улгуржи бозор маҳсулоти (2026-10-17, эга қабул қилган таклиф): аввал
  /// «энг сўнгги клип»ни тахмин қилиб боғланарди, энди клип ID'си билан.
  static const kindWholesale = 'wholesale_product';

  /// Видео боғланганда кўтарилади — рўйхатлар (`JobsScreen`) харитани қайта
  /// юклайди.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Видео жойлаш экранини ОЧАДИ: клип яратилганда `linkKind`/`linkId` шу
  /// заҳоти ёзилади. Одатда фақат оддий видео (реклама/янгилик сегментлари йўқ);
  /// [organicOnly] `false` — пуллик реклама ҳам танланади (Улгуржи: «Реклама»).
  /// [onClipCreated] — янги клип ID'си (модулнинг ўз қўшимча боғланиши учун).
  /// Жойланса `true`.
  static Future<bool> publish(
    NavigatorState nav, {
    required String kind,
    required String linkId,
    String linkItemId = '',
    bool organicOnly = true,
    ValueChanged<String>? onClipCreated,
  }) async {
    if (linkId.isEmpty) return false;
    // Таом видеосида таом id шарт: у йўқ бўлса клип ресторан видеосига ўхшаб қолмасин.
    if (kind == kindRestaurantItem && linkItemId.isEmpty) return false;
    final published = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => TvPublishScreen(
          hideShopOption: true,
          organicOnly: organicOnly,
          linkKind: kind,
          linkId: linkId,
          linkItemId: linkItemId,
          onClipCreated: onClipCreated,
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

  /// Янги клип ЖОНЛИ бўлгач (`active` ва ўйнатилади) эскилари ортиқча —
  /// бир ресторанда битта видео. Янгиси ҳали текширувда/хато бўлса ҳеч нарса
  /// ўчирилмайди: мижозга эскиси кўрсатилиб туради (`fetchLinked`). Рўйхат —
  /// `TvClipsRepository.fetchOwnLinked` натижаси (янгиси биринчи).
  static List<TvClip> supersededClips(List<TvClip> ownedNewestFirst) {
    if (ownedNewestFirst.length < 2) return const [];
    final live = ownedNewestFirst.first;
    if (!live.isActive || !live.isPlayable) return const [];
    return ownedNewestFirst.sublist(1);
  }

  /// Эга панелидаги ҳолат ёрлиғи калити: `active` | `pending` | `blocked` |
  /// `error` (transcode йиқилган) | `other` (`expired` ва ҳ.к.).
  static String statusKey(TvClip c) {
    if (!c.isPlayable) return 'error';
    switch (c.status) {
      case 'active':
        return 'active';
      case 'pending':
        return 'pending';
      case 'blocked':
        return 'blocked';
      default:
        return 'other';
    }
  }

  /// Боғланган видеони AVAGram лентасида очади.
  static Future<void> open(BuildContext context, TvClip clip) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip)),
    );
  }
}
