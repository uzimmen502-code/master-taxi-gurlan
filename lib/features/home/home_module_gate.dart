import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../../models/service_module_config.dart';

/// Home grid / promo uchun modul holati.
class HomeModuleGate {
  HomeModuleGate._();

  /// Hali implement qilinmagan modullar — hamkorlik taklifi.
  static const placeholderModuleIds = {'tire', 'car_wash'};

  static bool showInGrid(String moduleId) =>
      ServiceConfigHolder.isVisible(moduleId);

  static bool canOpen(String moduleId) {
    if (placeholderModuleIds.contains(moduleId)) return false;
    return ServiceConfigHolder.isOpenable(moduleId);
  }

  static void onTapBlocked(BuildContext context, String moduleId) {
    final status = placeholderModuleIds.contains(moduleId)
        ? ModuleStatus.comingSoon
        : ServiceConfigHolder.statusOf(moduleId);
    final msg = status == ModuleStatus.comingSoon
        ? context.tr('home_coming_soon')
        : context.tr('home_not_available');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  static VoidCallback gatedTap(
    BuildContext context,
    String moduleId,
    VoidCallback onOpen,
  ) {
    return () {
      if (!canOpen(moduleId)) {
        onTapBlocked(context, moduleId);
        return;
      }
      onOpen();
    };
  }
}
