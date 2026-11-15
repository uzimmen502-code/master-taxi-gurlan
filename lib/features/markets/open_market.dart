import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../home/home_module_gate.dart';
import 'data/market_taxonomy_repository.dart';
import 'domain/market_taxonomy.dart';
import 'screens/market_screen.dart';

/// Бозор экранига кириш — ЯГОНА йўл (бош экран кейинги босқичда шуни чақиради). Модул дарвозаси (фаол туман)
/// таксономиядаги `moduleId` бўйича: ёпиқ бўлса — мавжуд «Тез кунда / мавжуд эмас» хабари.
/// `loadTaxonomy`, `canOpen`, `push` — тест учун.
Future<void> openMarket(
  BuildContext context,
  String marketId, {
  Future<MarketTaxonomy> Function()? loadTaxonomy,
  bool Function(String moduleId)? canOpen,
  Future<void> Function(Widget screen)? push,
}) async {
  MarketTaxonomy t;
  try {
    t = await (loadTaxonomy ?? MarketTaxonomyRepository.load)();
  } catch (e) {
    debugPrint('[OpenMarket] MARKET_TAXONOMY_LOAD_FAILED market=$marketId: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('market_err_taxonomy'))));
    }
    return;
  }
  if (!context.mounted) return;
  final def = t.market(marketId);
  if (def == null) {
    debugPrint('[OpenMarket] MARKET_UNKNOWN market=$marketId');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('home_not_available'))));
    return;
  }
  if (!(canOpen ?? HomeModuleGate.canOpen)(def.moduleId)) {
    HomeModuleGate.onTapBlocked(context, def.moduleId);
    return;
  }
  final screen = MarketScreen(marketId: marketId, loadTaxonomy: loadTaxonomy);
  await (push ?? (s) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => s)))(screen);
}
