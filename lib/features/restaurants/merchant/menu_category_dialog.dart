// Категория номини сўраш диалоги — «Меню» табидаги «＋ Категория» ҳам, «Таом
// қўшиш» экранидаги «＋ Категория қўшиш» ҳам ШУ ердан (иккита нусха йўқ).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../domain/restaurant_models.dart';

/// Тозаланган ном ёки `null` (бекор қилинди/бўш).
///
/// Контроллер қасддан `dispose` қилинмайди: диалог ёпилиш анимацияси
/// давомида майдон ундан ҳали фойдаланади (listener йўқ — оқиб кетиш йўқ).
Future<String?> promptMenuCategoryName(BuildContext context, {MenuCategory? existing}) async {
  final ctrl = TextEditingController(text: existing?.name ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr(existing == null ? 'restaurants_m_add_category' : 'restaurants_m_rename')),
      content: TextField(
        controller: ctrl,
        maxLength: 60,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: ctx.tr('restaurants_m_category_name')),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
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
