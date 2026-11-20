import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/sm_taxonomy.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_widgets.dart';
import 'supermarket_home_screen.dart';

/// 2-экран: категория → гуруҳлар. Орқага қайтганда скролл ўрни сақланади (PageStorageKey —
/// маршрут тирик турганда гуруҳ экранидан қайтишда ҳам).
class SmCategoryScreen extends StatelessWidget {
  const SmCategoryScreen({super.key, required this.controller, required this.category});

  final SupermarketController controller;
  final SmCategory category;

  @override
  Widget build(BuildContext context) {
    final lang = context.contentLang;
    return Scaffold(
      backgroundColor: context.ava.bg,
      appBar: AppBar(
        title: Text(category.name(lang)),
        actions: [SmCartAction(controller: controller, onTap: () => smOpenCart(context, controller))],
      ),
      bottomNavigationBar: SmBottomBar(controller: controller, onCart: () => smOpenCart(context, controller)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final groups = controller.visibleGroups(category);
          if (groups.isEmpty) {
            return Center(child: Text(context.tr('sm_empty_category'), style: const TextStyle(fontSize: 15)));
          }
          return ListView.separated(
            key: PageStorageKey('sm_category_list_${category.id}'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => SmGroupRow(controller: controller, group: groups[i], lang: lang),
          );
        },
      ),
    );
  }
}
