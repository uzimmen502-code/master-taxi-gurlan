import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../home_module_gate.dart';
import 'services_spotlight_carousel.dart';

/// Барча кўринадиган хизматлар — битта экранда грид.
class AllServicesScreen extends StatelessWidget {
  const AllServicesScreen({super.key, required this.items});

  final List<ServiceSpotlightItem> items;

  @override
  Widget build(BuildContext context) {
    final visible = items
        .where((e) => HomeModuleGate.showInGrid(e.moduleId))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF2),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          context.tr('home_services_all_title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: visible.isEmpty
          ? Center(
              child: Text(
                context.tr('home_not_available'),
                style: const TextStyle(
                  color: Color(0xFF4A6741),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: 0.88,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                return ServiceSpotlightTile(item: visible[index]);
              },
            ),
    );
  }
}
