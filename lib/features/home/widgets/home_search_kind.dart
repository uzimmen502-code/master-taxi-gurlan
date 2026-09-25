import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/search_index_entry.dart';

/// Универсал қидирув натижасининг тури — тавсифдаги тўртта тоифа.
enum HomeSearchKind { ad, service, product, video }

extension HomeSearchKindX on HomeSearchKind {
  String get l10nKey => switch (this) {
        HomeSearchKind.ad => 'home_search_kind_ad',
        HomeSearchKind.service => 'home_search_kind_service',
        HomeSearchKind.product => 'home_search_kind_product',
        HomeSearchKind.video => 'home_search_kind_video',
      };

  String label(BuildContext context) => context.tr(l10nKey);

  IconData get icon => switch (this) {
        HomeSearchKind.ad => Icons.campaign_outlined,
        HomeSearchKind.service => Icons.handyman_outlined,
        HomeSearchKind.product => Icons.shopping_bag_outlined,
        HomeSearchKind.video => Icons.play_circle_outline_rounded,
      };
}

/// `search_index` даги ички турни тавсифдаги тўртта тоифага келтиради.
///
/// Индексда 9 та тур бор, тавсиф эса фойдаланувчига тўрттасини кўрсатишни
/// сўрайди — шунинг учун харита шу ерда, битта жойда.
HomeSearchKind homeSearchKindOf(SearchIndexEntry e) {
  switch (e.type) {
    case SearchIndexEntry.typeMarketAd:
    case SearchIndexEntry.typeJob:
    case SearchIndexEntry.typeYukListing:
      return HomeSearchKind.ad;

    case SearchIndexEntry.typeService:
    case SearchIndexEntry.typeIntercityRoute:
    case SearchIndexEntry.typeLocalPlace:
      return HomeSearchKind.service;

    case SearchIndexEntry.typePlatformProduct:
    case SearchIndexEntry.typeBreadProduct:
    case SearchIndexEntry.typeFoodProduct:
      return HomeSearchKind.product;
  }
  // Номаълум тур (индекс янгиланса) — «Эълон» энг нейтрал тоифа.
  return HomeSearchKind.ad;
}
