import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/home_module.dart';

/// Бош экран modullari — tartib va `enabled` shu yerda.
///
/// [HomeModule.label] — `AppLocalizations` kaliti (matn emas).
/// Ko‘rsatish: [resolveLabel] yoki widget qatlamida `context.tr(module.label)`.
///
/// Vaqtincha yopish: `enabled: false` (masalan, `food` yoki `jobs`).
class HomeModulesCatalog {
  HomeModulesCatalog._();

  static String resolveLabel(BuildContext context, HomeModule module) =>
      AppLocalizations.of(context)!.translate(module.label);

  static HomeModule byId(String id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    throw ArgumentError.value(id, 'id', 'Unknown home module');
  }

  static const List<HomeModule> modules = [
    HomeModule(
      id: 'bread',
      image: 'assets/images/bread.png',
      label: 'home_module_bread',
    ),
    HomeModule(
      id: 'food',
      image: 'assets/images/food.png',
      label: 'home_module_food',
      enabled: false,
    ),
    HomeModule(
      id: 'sell',
      image: 'assets/images/sell.png',
      label: 'home_module_sell',
    ),
    HomeModule(
      id: 'cheap_products_home',
      image: 'assets/images/online_bozor.png',
      label: 'home_module_cheap_products',
    ),
    HomeModule(
      id: 'marshrut',
      image: 'assets/images/taxi_marshrut.png',
      label: 'home_module_marshrut',
    ),
    HomeModule(
      id: 'local_taxi',
      image: 'assets/images/taxi_local.png',
      label: 'home_module_local',
    ),
    HomeModule(
      id: 'intercity',
      image: 'assets/images/luggage.png',
      label: 'home_module_intercity',
    ),
    HomeModule(
      id: 'jobs',
      image: 'assets/images/ishtop.png',
      label: 'home_module_jobs',
    ),
  ];
}
