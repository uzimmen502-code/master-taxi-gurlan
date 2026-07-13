import 'package:flutter/material.dart';

import '../../core/service_config_holder.dart';
import '../../models/service_module_config.dart';

/// Home grid / promo uchun modul holati.
class HomeModuleGate {
  HomeModuleGate._();

  /// Hali implement qilinmagan modullar — har doim "Tez orada".
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
        ? 'Tez orada'
        : 'Hozircha mavjud emas';
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
