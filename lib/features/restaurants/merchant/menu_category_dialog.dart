// Категория номини сўраш диалоги — «Меню» табидаги «＋ Категория» ҳам, «Таом
// қўшиш» экранидаги «＋ Категория қўшиш» ҳам ШУ ердан (иккита нусха йўқ).
//
// Янги категорияда эгага ёрдам: категория нима эканини айтадиган қатор ва
// босилса майдонга ёзиладиган тайёр номлар (таҳрирланади). Қайта номлашда
// таклиф кўрсатилмайди.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../domain/menu_category_suggestions.dart';
import '../domain/restaurant_models.dart';

/// Тозаланган ном ёки `null` (бекор қилинди/бўш).
///
/// [categories] — мавжудлари (таклифдан аллақачон борлари чиқарилади),
/// [homeCook] — қайси рўйхат таклиф қилинади.
///
/// Контроллер қасддан `dispose` қилинмайди: диалог ёпилиш анимацияси
/// давомида майдон ундан ҳали фойдаланади (listener йўқ — оқиб кетиш йўқ).
Future<String?> promptMenuCategoryName(
  BuildContext context, {
  MenuCategory? existing,
  Iterable<MenuCategory> categories = const [],
  bool homeCook = false,
}) async {
  final ctrl = TextEditingController(text: existing?.name ?? '');
  final suggestions = existing != null
      ? const <String>[]
      : MenuCategorySuggestions.missingNames(
          keys: MenuCategorySuggestions.keysFor(homeCook: homeCook),
          lang: context.contentLang,
          existing: categories,
        );
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr(existing == null ? 'restaurants_m_add_category' : 'restaurants_m_rename')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (existing == null) ...[
              Text(ctx.tr('restaurants_m_category_explain'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const ValueKey('category-name-field'),
              controller: ctrl,
              maxLength: 60,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: ctx.tr('restaurants_m_category_name')),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(ctx.tr('restaurants_m_category_examples'), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      key: ValueKey('category-suggestion-$s'),
                      label: Text(s),
                      onPressed: () => ctrl.value = TextEditingValue(
                        text: s,
                        selection: TextSelection.collapsed(offset: s.length),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(ctx.tr('restaurants_m_save'))),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  return name;
}
