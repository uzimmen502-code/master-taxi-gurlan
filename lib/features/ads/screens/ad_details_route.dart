import 'package:flutter/widgets.dart';

import '../models/ad_model.dart';
import 'ad_details_screen.dart';
import 'ad_swipe_screen.dart';

/// Аҳоли бозори эълонининг тафсилот экрани — ЯГОНА кириш нуқтаси.
///
/// Эга талаби (2026-10-21): свайп (контент охирида юқорига = кейинги, тепада
/// пастга = олдинги) эълонга ҚАЙСИ ЖОЙДАН кирилса ҳам ишласин. Аввал у фақат
/// бозор рўйхатидан ишларди; бош саҳифа бўлими ва «ўхшаш эълонлар» эълонни
/// биттадан очарди.
///
/// [catalog] — эълон турган рўйхат (суриш шулар орасида боради). Эълон унда
/// йўқ ёки рўйхатда биттагина бўлса — одатдаги битта экран.
Widget adDetailsFor(AdModel ad, List<AdModel> catalog) {
  final i = catalog.indexWhere((e) => e.id == ad.id);
  if (i < 0 || catalog.length < 2) return AdDetailsScreen(ad: ad);
  return AdSwipeScreen(ads: catalog, initialIndex: i);
}
