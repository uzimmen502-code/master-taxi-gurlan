import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/home_module.dart';

/// Бosh экран modullari — tartib va `enabled` shu yerda.
///
/// [HomeModule.label] — `AppLocalizations` kaliti (matn emas).
/// Ko‘rsatish: [resolveLabel] yoki widget qatlamida `context.tr(module.label)`.
///
/// Vaqtincha yopish: `enabled: false` (masalan, `jobs`).
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
      label: 'home_module_bread',
    ),
    // `food` («Овқат», AVA'нинг ягона менюси) ОЛИБ ТАШЛАНДИ (эга, 2026-10-11):
    // ўрнига кафе-ресторанлар. Конфиг калити (`kKnownModuleIds`) эски илова
    // версиялари учун қолди; эски `type:'food'` буюртмалар тарихда кўринади.
    HomeModule(
      id: 'restaurants',
      label: 'home_module_restaurants',
    ),
    HomeModule(
      id: 'cheap_products_home',
      label: 'home_module_cheap_products',
    ),
    HomeModule(
      id: 'marshrut',
      label: 'home_module_marshrut',
    ),
    HomeModule(
      id: 'local_taxi',
      label: 'home_module_local',
    ),
    HomeModule(
      id: 'intercity',
      label: 'home_module_intercity',
    ),
    HomeModule(
      id: 'jobs',
      label: 'home_module_jobs',
    ),
    // `platform_store` («AVA ДЎКОНИ») ОЛИБ ТАШЛАНДИ (2026-10-07): алоҳида
    // дўкон экрани йўқ, AVA товарлари — Улгуржи бозорда. Конфиг калити
    // (`kKnownModuleIds`) эса эски илова версиялари учун қолди.
    HomeModule(
      id: 'tv_market',
      label: 'home_module_tv_market',
    ),
  ];
}
