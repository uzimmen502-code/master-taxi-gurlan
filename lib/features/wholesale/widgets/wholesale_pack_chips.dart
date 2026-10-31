import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';
import 'wholesale_tier_picker.dart' show kWholesaleTapSize;

/// Тафсилотда қадоқ танлови (эга, 2026-10-31): «1 кг · 5 кг · 25 кг қоп»,
/// ҳар бирида «дан …» нарх. Танланганда нарх, поғоналар, вазн ва расм
/// шу қадоққа ўтади.
class WholesalePackChips extends StatelessWidget {
  const WholesalePackChips({
    super.key,
    required this.product,
    required this.selectedId,
    required this.onSelected,
  });

  final WholesaleProduct product;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cur = product.currencyLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('wholesale_pick_pack'),
          style: const TextStyle(fontSize: 12, height: 1.2, color: PdDark.muted),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final pk in product.effectivePacks)
              _PackChip(
                key: ValueKey('wholesale-pack-chip-${pk.id}'),
                label: pk.label,
                price: '${pk.priceTiers.length > 1 ? '${context.tr('home_price_from')} ' : ''}'
                    '${formatPrice(pk.basePrice)} $cur',
                active: pk.id == selectedId,
                onTap: () => onSelected(pk.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _PackChip extends StatelessWidget {
  const _PackChip({
    super.key,
    required this.label,
    required this.price,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String price;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $price',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: kWholesaleTapSize, minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? PdDark.brandSoft : PdDark.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? PdDark.brand : PdDark.line,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: active ? PdDark.ink : PdDark.ink,
                ),
              ),
              Text(
                price,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: active ? PdDark.brand : PdDark.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Қолдиқ: 120 қоп» ёки «Тугаган». Сотувчи қолдиқ киритмаган бўлса
/// ([qty] == null) — ҳеч нарса кўрсатилмайди.
class WholesaleStockLine extends StatelessWidget {
  const WholesaleStockLine({super.key, required this.qty, required this.unitLabel});

  final int? qty;
  final String unitLabel;

  static const outColor = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    final q = qty;
    if (q == null) return const SizedBox.shrink();
    final out = q == 0;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        out
            ? context.tr('wholesale_stock_out')
            : context
                .tr('wholesale_stock_left')
                .replaceAll('{qty}', formatPrice(q))
                .replaceAll('{unit}', unitLabel),
        key: const ValueKey('wholesale-stock-line'),
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: out ? outColor : PdDark.ok,
        ),
      ),
    );
  }
}
