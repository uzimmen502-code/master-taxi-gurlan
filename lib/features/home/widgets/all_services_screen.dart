import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../home_module_gate.dart';
import 'service_circle_tile.dart';
import 'services_spotlight_carousel.dart';

/// Барча кўринадиган хизматлар — OLX бош экранидаги «Разделы на сервисе
/// OLX» услубидаги грид.
///
/// Услуб olx.uz дан 2026-09-26 да жонли ўлчанган — қаранг:
/// [ServiceCircleTile] ҳужжати (88px доира, 156px катак, 16/600 ёрлиқ,
/// рамкасиз ва соясиз).
class AllServicesScreen extends StatelessWidget {
  const AllServicesScreen({super.key, required this.items});

  final List<ServiceSpotlightItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final visible = items
        .where((e) => HomeModuleGate.showInGrid(e.moduleId))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: c.line)),
        title: Text(
          context.tr('home_services_all_title'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: c.ink,
          ),
        ),
      ),
      body: visible.isEmpty
          ? Center(
              child: Text(
                context.tr('home_not_available'),
                style: TextStyle(color: c.ink2, fontWeight: FontWeight.w600),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 32),
              // `mainAxisExtent` — катак баландлиги АНИҚ 156px (OLX'даги
              // қиймат); `maxCrossAxisExtent` эса устун сонини экран
              // кенглигига қараб ўзи танлайди: телефонда 3, кенгроқ
              // экранда 4–5. Шунда доира ҳамма жойда бир хил ўлчамда
              // қолади — фақат оралиқ ўзгаради.
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 132,
                mainAxisExtent: ServiceCircleTile.tileHeight,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) =>
                  ServiceCircleTile(item: visible[index]),
            ),
    );
  }
}
