import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../shared/widgets/celebration_dialog.dart';

/// «Дўконингиз очилди!» табриги (эга, 2026-10-31: «янги иш бошланди» лаҳзаларида конфетти, ҳар объект учун
/// БИР МАРТА). Умумий ойна — [showCelebration]; бу ерда фақат матн, белги ва «бир марта» калити.
///
/// Уч жойдан чақирилади:
///  · биринчи кириш (`openMyShop`, Аҳоли бозори) — [id] эга телефони;
///  · «Менинг дўконим» → «Янги дўкон» — [id] янги дўкон ID'си;
///  · «Менинг бизнесларим»да янги чакана/улгуржи объект — [id] объект ID'си.
/// Ҳар учаласида тугма босилгач маҳсулот қўшиш экрани очилади («Маҳсулот қўшиш»).
///
/// Аввал кўрсатилган бўлса (шу қурилмада) ёки экран ёпилган бўлса — дарров қайтади.
Future<void> celebrateShopOpenedOnce(BuildContext context, String id) async {
  if (id.isEmpty || !context.mounted) return;
  if (!await CelebrationOnce.claim(shopOpenedCelebrationKey(id)) || !context.mounted) return;
  await showCelebration(
    context,
    icon: Icons.storefront_rounded,
    title: context.tr('my_shop_opened_title'),
    subtitle: context.tr('my_shop_opened_sub'),
    buttonLabel: context.tr('my_shop_opened_add_products'),
  );
}

/// [CelebrationOnce] калити: телефон (рақамлар) ва объект ID'си (`<телефон>_<сўров>`) тўқнашмайди.
String shopOpenedCelebrationKey(String id) => 'shop_opened_$id';
