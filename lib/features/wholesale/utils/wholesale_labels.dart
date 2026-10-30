import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';

/// Базада сақланадиган «ўрнатилган» бирлик: сотувчи бирлик ёзмаса ёки эски
/// ҳужжатда шу ёзилган. Барча эски мижозлар билан мос қолиши учун ЎЗГАРМАЙДИ
/// (CLAUDE.md 26), фақат кўрсатилганда тилга мослаштирилади.
const String kWholesaleDefaultUnit = 'дона';

/// Матн калити таржима қилинмаса (`tr` калитнинг ўзини қайтарса) — [fallback].
String _trOr(BuildContext context, String key, String fallback) {
  final t = context.tr(key);
  return t == key ? fallback : t;
}

/// Бирликнинг кўринадиган номи. Фақат ўрнатилган «дона» тилга мослашади
/// (дона / dona / шт); сотувчи ўзи ёзган бирлик («қути», «палет») ўзгармайди.
String wholesaleUnitLabel(BuildContext context, String unit) =>
    unit.trim() == kWholesaleDefaultUnit
        ? _trOr(context, 'piece', unit)
        : unit;

/// «дан 9 000 сўм / дона» — карточка ва лентадаги нарх сатри (тилга мос).
/// [WholesaleProduct.priceLine] нинг кўриниши билан бир хил, фақат матнлар
/// тилга мослаштирилган.
String wholesalePriceLine(BuildContext context, WholesaleProduct p) {
  // Бир нечта қадоқ ёки поғона — «дан» (нарх энг арзон қадоқдан, 2026-10-31).
  final from = p.priceTiers.length > 1 || p.packs.length > 1
      ? '${_trOr(context, 'home_price_from', 'дан')} '
      : '';
  return '$from${formatPrice(p.basePrice)} ${p.currencyLabel}'
      ' / ${wholesaleUnitLabel(context, p.unit)}';
}
