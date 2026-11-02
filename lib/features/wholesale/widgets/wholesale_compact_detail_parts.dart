import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/price_tier.dart';
import 'wholesale_detail_actions.dart' show kWholesaleMilk, kWholesaleMilkInk;
import 'wholesale_pack_chips.dart' show WholesaleStockLine;

/// Улгуржи тафсилотининг «Б вариант» бўлаклари (эга, 2026-11-02): Аралаш
/// бозордаги AVA маҳсулоти экрани намуна — майда ҳарфлар, ихчам жойлашув.
/// Хитой бозори ҳозирча эски кўринишда (эга: «ҳозирча фақат улгуржи»).

/// Миқдор чегараси: [moq]..[max]. [max] — қолдиқ (маълум ва > 0 бўлса) ёки
/// умумий юқори чегара. Қолдиқ MOQ дан кам бўлса — MOQ (сотувчи билан келишилади).
int clampCompactQty(int value, {required int moq, required int max}) {
  final lo = moq < 1 ? 1 : moq;
  final hi = max < lo ? lo : max;
  if (value < lo) return lo;
  if (value > hi) return hi;
  return value;
}

/// «Буюртма ёзиш» чат майдонига тайёр матн (эга, 2026-11-02: танланган
/// миқдор чатга борсин). Қадоқ бўлса номдан кейин қавсда. Нарх — фақат
/// тахминий (≈), ҳақиқий нарх сотувчи билан келишилади.
String wholesaleOrderDraft({
  required String template,
  required String title,
  required String packLabel,
  required int qty,
  required String unitLabel,
  required String totalText,
}) {
  final pack = packLabel.trim();
  final product = pack.isEmpty ? title.trim() : '${title.trim()} ($pack)';
  return template
      .replaceAll('{product}', product)
      .replaceAll('{qty}', formatPrice(qty))
      .replaceAll('{unit}', unitLabel)
      .replaceAll('{total}', totalText);
}

/// «11 000 сўм / дона ··· Қолди: 120 дона» — қолдиқ нарх билан БИР қаторда.
/// Қолдиқ киритилмаган (`null`) — ўнг томон бўш; `0` — «Тугаган» (қизил).
class WholesalePriceStockRow extends StatelessWidget {
  const WholesalePriceStockRow({
    super.key,
    required this.priceText,
    required this.unitLabel,
    required this.stockQty,
  });

  final String priceText;
  final String unitLabel;
  final int? stockQty;

  @override
  Widget build(BuildContext context) {
    final q = stockQty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            priceText,
            key: const ValueKey('wholesale-compact-price'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: PdDark.brand),
          ),
        ),
        const SizedBox(width: 5),
        Text('/ $unitLabel', style: const TextStyle(fontSize: 12, color: PdDark.muted)),
        const Spacer(),
        if (q != null)
          Text(
            q == 0
                ? context.tr('wholesale_stock_out')
                : context
                    .tr('wholesale_stock_left_short')
                    .replaceAll('{qty}', formatPrice(q))
                    .replaceAll('{unit}', unitLabel),
            key: const ValueKey('wholesale-stock-line'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: q == 0 ? WholesaleStockLine.outColor : PdDark.muted,
            ),
          ),
      ],
    );
  }
}

/// Нарх поғоналари — сарлавҳасиз, тенг энли чиплар; босилса миқдор шу
/// поғона бошланишига ўтади. Битта поғона бўлса кўрсатилмайди.
class WholesaleTierRow extends StatelessWidget {
  const WholesaleTierRow({
    super.key,
    required this.tiers,
    required this.qty,
    required this.unitLabel,
    required this.onPick,
  });

  final List<PriceTier> tiers;
  final int qty;
  final String unitLabel;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    if (tiers.length < 2) return const SizedBox.shrink();
    final active = activeTierIndex(tiers, qty);
    const gap = 6.0;
    return LayoutBuilder(
      builder: (context, cons) {
        final n = tiers.length;
        final w = ((cons.maxWidth - gap * (n - 1)) / n).clamp(84.0, cons.maxWidth);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, t) in tiers.indexed)
              SizedBox(
                width: w,
                child: _TierChip(
                  key: ValueKey('wholesale-tier-$i'),
                  label: '${tierRangeText(tiers, i)} $unitLabel',
                  price: formatPrice(t.price),
                  active: i == active,
                  onTap: () => onPick(t.minQty),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
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
      excludeSemantics: true,
      child: Material(
        color: active ? PdDark.brandSoft : PdDark.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? PdDark.brand : PdDark.line, width: active ? 1.4 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? PdDark.ink : PdDark.muted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: active ? PdDark.brand : PdDark.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Тор миқдор танлагичи «− 10 +» (эга танлаган 1-вариант, 2026-11-02):
/// эни ≈ 52 px, баландлиги пастки тугмалар билан бир хил.
class WholesaleQtyStepper extends StatelessWidget {
  const WholesaleQtyStepper({
    super.key,
    required this.qty,
    required this.min,
    required this.max,
    required this.onChanged,
    this.height = 40,
  });

  final int qty;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final double height;

  static const double _btnWidth = 15;

  @override
  Widget build(BuildContext context) {
    Widget btn(String key, IconData icon, int? target) => Semantics(
          button: true,
          enabled: target != null,
          label: icon == Icons.remove_rounded ? '−' : '+',
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(8),
            onTap: target == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onChanged(target);
                  },
            child: SizedBox(
              width: _btnWidth,
              height: height,
              child: Icon(icon, size: 14, color: target == null ? PdDark.muted : PdDark.brand),
            ),
          ),
        );
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: PdDark.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn('wholesale-qty-minus', Icons.remove_rounded, qty > min ? qty - 1 : null),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 18),
            child: Text(
              formatPrice(qty),
              key: const ValueKey('wholesale-qty-value'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PdDark.ink),
            ),
          ),
          btn('wholesale-qty-plus', Icons.add_rounded, qty < max ? qty + 1 : null),
        ],
      ),
    );
  }
}

/// Пастки панел: [− 10 +] [📞] [Буюртма ёзиш · ≈ 110 000 сўм].
/// Ўз маҳсулотида «Буюртма ёзиш» йўқ — фақат қўнғироқ (тўлиқ энда).
class WholesaleCompactBottomBar extends StatelessWidget {
  const WholesaleCompactBottomBar({
    super.key,
    required this.qty,
    required this.minQty,
    required this.maxQty,
    required this.onQtyChanged,
    required this.totalText,
    required this.onCall,
    required this.onWriteOrder,
    this.showWriteOrder = true,
    this.writeBusy = false,
  });

  final int qty;
  final int minQty;
  final int maxQty;
  final ValueChanged<int> onQtyChanged;

  /// «≈ 110 000 сўм» — фақат кўрсатиш учун, буюртма нархини сервер ҳисоблайди.
  final String totalText;
  final VoidCallback onCall;
  final VoidCallback onWriteOrder;
  final bool showWriteOrder;
  final bool writeBusy;

  static const double _h = 40;

  /// Қўнғироқ тугмаси эни (аввал [_h] — квадрат эди).
  static const double callWidth = 56;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    if (!showWriteOrder) {
      return SizedBox(
        height: _h,
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('wholesale-call'),
          onPressed: onCall,
          style: FilledButton.styleFrom(
            backgroundColor: kWholesaleMilk,
            foregroundColor: kWholesaleMilkInk,
            shape: shape,
          ),
          icon: const Icon(Icons.call, size: 18),
          label: Text(context.tr('wholesale_call'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      );
    }
    return SizedBox(
      height: _h,
      child: Row(
        children: [
          WholesaleQtyStepper(qty: qty, min: minQty, max: maxQty, onChanged: onQtyChanged, height: _h),
          const SizedBox(width: 8),
          // Қўнғироқ каттароқ (эга, 2026-11-02): 40 → 56 px эн, белги 22.
          SizedBox(
            width: callWidth,
            height: _h,
            child: Tooltip(
              message: context.tr('wholesale_call'),
              child: OutlinedButton(
                key: const ValueKey('wholesale-call'),
                onPressed: onCall,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kWholesaleMilk,
                  side: const BorderSide(color: PdDark.line),
                  shape: shape,
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.call, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('wholesale-write-order'),
              onPressed: writeBusy ? null : onWriteOrder,
              style: FilledButton.styleFrom(
                backgroundColor: kWholesaleMilk,
                foregroundColor: kWholesaleMilkInk,
                disabledBackgroundColor: kWholesaleMilk.withValues(alpha: 0.6),
                disabledForegroundColor: kWholesaleMilkInk,
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: writeBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kWholesaleMilkInk),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr('deal_chat_write_order'),
                            // «Буюртма ёзиш» сал кичикроқ (эга, 2026-11-02): 13 → 12, сумма 11 → 10.5.
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, height: 1.1),
                          ),
                          Text(
                            totalText,
                            key: const ValueKey('wholesale-compact-total'),
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 10.5, height: 1.1),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
