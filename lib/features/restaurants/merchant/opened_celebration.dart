import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../shared/widgets/celebration_dialog.dart';

/// Кафе-ресторан / уй ошпази ОЧИЛДИ табриги (эга, 2026-10-31: «Б» — конфетти).
/// Умумий ойна — [showCelebration]; бу ерда фақат матн ва белги.
Future<void> showOpenedCelebration(BuildContext context, {required bool homeCook}) {
  return showCelebration(
    context,
    icon: homeCook ? Icons.soup_kitchen_rounded : Icons.restaurant_rounded,
    title: context.tr(homeCook ? 'restaurants_m_submitted_approved_home_cook' : 'restaurants_m_submitted_approved'),
    subtitle: context.tr('restaurants_m_opened_sub'),
    buttonLabel: context.tr('restaurants_m_opened_go_panel'),
  );
}
