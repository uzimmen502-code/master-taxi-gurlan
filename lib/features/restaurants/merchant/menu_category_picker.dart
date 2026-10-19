// Таом формасидаги категория танлови (D-REST-29, эга 2026-10-19: «категорияни тизим
// таклиф қилсин, танлаш имконияти сотувчида бўлсин»).
//
// Чиплар: сотувчининг ўз категориялари · тизим таклифи (ҳали яратилмаган тайёр
// бўлимлар, «+» билан — танланса таом сақланаётганда яратилади) · «Бошқалар»
// (категориясиз) · «+ Ўз категориям». Ҳеч бири ўзи танланиб қолмайди: танлов сотувчида.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/menu_category_choice.dart';
import '../domain/restaurant_models.dart';
import 'form_chip_style.dart';

class MenuCategoryPicker extends StatelessWidget {
  const MenuCategoryPicker({
    super.key,
    required this.categories,
    required this.suggestions,
    required this.selectedId,
    required this.lang,
    required this.onSelected,
    required this.onCreateOwn,
  });

  /// Сотувчининг мавжуд категориялари.
  final List<MenuCategory> categories;

  /// Тизим таклифи — ҳали яратилмаган тайёр бўлимлар (калит + эганинг тилидаги ном).
  final List<({String key, String name})> suggestions;

  /// Мавжуд категория id, [MenuCategoryChoice.none] ёки [MenuCategoryChoice.suggest].
  final String selectedId;
  final String lang;
  final ValueChanged<String> onSelected;
  final VoidCallback onCreateOwn;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    Widget chip({
      required Key key,
      required String label,
      required String id,
      Widget? avatar,
    }) {
      final selected = selectedId == id;
      return ChoiceChip(
        key: key,
        avatar: avatar,
        label: Text(label, style: FormChipStyle.label(c, selected)),
        selected: selected,
        showCheckmark: false,
        side: FormChipStyle.side(c, selected),
        selectedColor: c.brandSoft,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => onSelected(id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('restaurants_m_item_category'),
          style: AvaText.body.copyWith(color: c.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(context.tr('restaurants_m_item_category_hint'), style: AvaText.caption.copyWith(color: c.ink2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final cat in categories)
              chip(key: ValueKey('category-${cat.id}'), label: cat.displayName(lang), id: cat.id),
            for (final s in suggestions)
              chip(
                key: ValueKey('category-suggest-${s.key}'),
                label: s.name,
                id: MenuCategoryChoice.suggest(s.key),
                avatar: Icon(Icons.add_rounded, size: 18, color: c.brandText),
              ),
            chip(
              key: const ValueKey('category-none'),
              label: context.tr('restaurants_menu_other'),
              id: MenuCategoryChoice.none,
            ),
            ActionChip(
              key: const ValueKey('category-create-own'),
              avatar: Icon(Icons.edit_outlined, size: 18, color: c.brandText),
              label: Text(context.tr('restaurants_m_category_own')),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onPressed: onCreateOwn,
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(context.tr('restaurants_m_item_category_suggest_hint'), style: AvaText.caption.copyWith(color: c.ink2)),
        ],
      ],
    );
  }
}
