import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/price_tier.dart';
import '../models/wholesale_product.dart';

/// Миқдорнинг юқори чегараси (UI). Сотувчи товарида қолдиқ йўқ, шунинг
/// учун бу фақат «999999999 кг» каби тасодифий киритишдан сақлайди.
const int kWholesaleMaxQty = 1000000;

/// Киритилган миқдорни [moq] (энг паст поғона) ва [kWholesaleMaxQty]
/// орасига солади. Минимал буюртмадан кам миқдор — минимумга кўтарилади.
int clampWholesaleQty(int value, int moq) {
  final floor = moq < 1 ? 1 : moq;
  if (value < floor) return floor;
  if (value > kWholesaleMaxQty) return kWholesaleMaxQty;
  return value;
}

/// Улгуржи нарх поғоналари: харидор поғонани босиб танлайди ёки миқдорни
/// ўзи киритади; сумма миқдорга қараб жонли ўзгаради.
///
/// Бу ФАҚАТ кўрсатиш ва ҳисоб-китоб: савват ва буюртма сотувчи товарида
/// ҳали йўқ (D-ULG-1…9), нархни ҳақиқатда сервер ҳисоблайди (CLAUDE.md 18).
/// Миқдор ушбу виджетда эмас, юқорида сақланади ([qty], [onQtyChanged]) —
/// шунда пастки панел ҳам шу суммани кўрсатади.
class WholesaleTierPicker extends StatefulWidget {
  const WholesaleTierPicker({
    super.key,
    required this.product,
    required this.qty,
    required this.onQtyChanged,
  });

  final WholesaleProduct product;
  final int qty;
  final ValueChanged<int> onQtyChanged;

  @override
  State<WholesaleTierPicker> createState() => _WholesaleTierPickerState();
}

class _WholesaleTierPickerState extends State<WholesaleTierPicker> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.qty}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commitText();
    });
  }

  @override
  void didUpdateWidget(covariant WholesaleTierPicker old) {
    super.didUpdateWidget(old);
    // Миқдор ташқаридан (поғона босилди, ± ) ўзгарса — майдон мослашади.
    // Фойдаланувчи ёзаётганда уни бузмаймиз.
    if (!_focus.hasFocus && _ctrl.text != '${widget.qty}') {
      _ctrl.text = '${widget.qty}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  int get _moq => widget.product.moq;

  void _set(int v) {
    final q = clampWholesaleQty(v, _moq);
    _ctrl.text = '$q';
    if (q != widget.qty) widget.onQtyChanged(q);
  }

  void _commitText() => _set(int.tryParse(_ctrl.text.trim()) ?? widget.qty);

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final tiers = p.priceTiers;
    if (tiers.isEmpty) return const SizedBox.shrink();
    final qty = widget.qty;
    final active = activeTierIndex(tiers, qty);
    final price = tiers[active].price;
    final total = price * qty;
    final saved = tiers.first.price * qty - total;
    final next = nextTierAfter(tiers, qty);
    final cur = p.currencyLabel;

    String money(int v) => '${formatPrice(v)} $cur';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tiers.length > 1) ...[
          Text(
            context.tr('wholesale_pick_tier'),
            style: const TextStyle(fontSize: 12, color: PdDark.muted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, t) in tiers.indexed)
                _TierChip(
                  label: _tierLabel(p, i),
                  price: formatPrice(t.price),
                  active: i == active,
                  onTap: () => _set(t.minQty),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            _StepBtn(
              icon: Icons.remove_rounded,
              onTap: qty > _moq ? () => _set(qty - 1) : null,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              height: 40,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _commitText(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: PdDark.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: PdDark.surface,
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: PdDark.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: PdDark.brand),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _StepBtn(
              icon: Icons.add_rounded,
              onTap: qty < kWholesaleMaxQty ? () => _set(qty + 1) : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context
                    .tr('wholesale_min_order')
                    .replaceAll('{qty}', '$_moq')
                    .replaceAll('{unit}', p.unit),
                style: const TextStyle(fontSize: 12, color: PdDark.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PdDark.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line(
                label: '$qty ${p.unit} × ${money(price)}',
                value: money(total),
                bold: true,
              ),
              if (saved > 0)
                _Line(
                  label: context.tr('wholesale_savings'),
                  value: money(saved),
                  valueColor: PdDark.ok,
                ),
              if (next != null) ...[
                const Divider(height: 14, color: PdDark.line),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      context
                          .tr('wholesale_next_tier_hint')
                          .replaceAll('{need}', '${next.minQty - qty}')
                          .replaceAll('{unit}', p.unit)
                          .replaceAll('{price}', money(next.price)),
                      style:
                          const TextStyle(fontSize: 12, color: PdDark.muted),
                    ),
                    InkWell(
                      onTap: () => _set(next.minQty),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          context
                              .tr('wholesale_set_qty')
                              .replaceAll('{qty}', '${next.minQty}')
                              .replaceAll('{unit}', p.unit),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: PdDark.brand,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// «1–9 кг», «10–49 кг», «50+ кг» (`tierRangeText`).
  static String _tierLabel(WholesaleProduct p, int i) =>
      '${tierRangeText(p.priceTiers, i)} ${p.unit}';
}

class _TierChip extends StatelessWidget {
  const _TierChip({
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
          constraints: const BoxConstraints(minWidth: 92),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: PdDark.ink)),
              const SizedBox(height: 2),
              Text(
                price,
                style: TextStyle(
                  fontSize: 13,
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

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PdDark.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? PdDark.muted : PdDark.ink,
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor = PdDark.ink,
  });

  final String label;
  final String value;
  final bool bold;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: PdDark.muted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
