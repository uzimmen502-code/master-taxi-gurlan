import 'package:flutter/material.dart';

import '../../../models/home_module.dart';
import '../home_grid_layout.dart';
import 'home_featured_module_card.dart';
import 'home_taxi_module_card.dart';

/// 2+4 layout: Non|Ish yonma-yon, pastda 4 ta service kartasi.
class HomeModulesGrid extends StatelessWidget {
  const HomeModulesGrid({
    super.key,
    required this.layout,
    required this.onModuleTap,
  });

  final HomeScreenLayout layout;
  final void Function(HomeModule module) onModuleTap;

  @override
  Widget build(BuildContext context) {
    final featuredH =
        HomeGridLayout.featuredRowHeight(MediaQuery.sizeOf(context).height);

    return SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(
        HomeGridLayout.horizontalPadding,
        0,
        HomeGridLayout.horizontalPadding,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (layout.hasFeaturedRow) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: layout.featuredLeft != null
                      ? HomeFeaturedModuleCard(
                          module: layout.featuredLeft!,
                          height: featuredH,
                          onTap: () => onModuleTap(layout.featuredLeft!),
                        )
                      : SizedBox(height: featuredH),
                ),
                const SizedBox(width: HomeGridLayout.spacing),
                Expanded(
                  child: layout.featuredRight != null
                      ? HomeFeaturedModuleCard(
                          module: layout.featuredRight!,
                          height: featuredH,
                          onTap: () => onModuleTap(layout.featuredRight!),
                        )
                      : SizedBox(height: featuredH),
                ),
              ],
            ),
            const SizedBox(height: HomeGridLayout.spacing),
          ],
          for (var i = 0; i < layout.taxiModules.length; i++) ...[
            HomeTaxiModuleCard(
              module: layout.taxiModules[i],
              onTap: () => onModuleTap(layout.taxiModules[i]),
            ),
            if (i < layout.taxiModules.length - 1)
              const SizedBox(height: HomeGridLayout.spacing),
          ],
          if (layout.extraModules.isNotEmpty) ...[
            const SizedBox(height: HomeGridLayout.spacing),
            for (var i = 0; i < layout.extraModules.length; i++) ...[
              HomeTaxiModuleCard(
                module: layout.extraModules[i],
                onTap: () => onModuleTap(layout.extraModules[i]),
              ),
              if (i < layout.extraModules.length - 1)
                const SizedBox(height: HomeGridLayout.spacing),
            ],
          ],
        ],
      ),
    );
  }
}
