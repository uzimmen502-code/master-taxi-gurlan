import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/sm_cart.dart' show kSmWeighedHoldPercent;
import '../domain/sm_qty.dart';
import '../supermarket_controller.dart';

/// Супермаркет илдиз маршрути номи — «Каталог» тугмаси шу ергача қайтаради.
const kSmHomeRouteName = '/supermarket';

/// Бирлик номи (lang калити).
String smUnitLabel(BuildContext context, String unit) =>
    unit.isEmpty ? '' : context.tr('sm_unit_$unit');

/// «12 000 сўм/кг».
String smPricePerUnit(BuildContext context, int price, String unit) {
  final u = smUnitLabel(context, unit);
  return u.isEmpty ? formatMoney(price) : '${formatMoney(price)}/$u';
}

/// Пастки панел: Каталог · Сават (сават ҳар экрандан очилади).
class SmBottomBar extends StatelessWidget {
  const SmBottomBar({super.key, required this.controller, required this.onCart, this.cartActive = false});

  final SupermarketController controller;
  final VoidCallback onCart;
  final bool cartActive;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final n = controller.cart.count;
        return Material(
          color: c.surface,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Row(
                children: [
                  Expanded(
                    child: _BarButton(
                      key: const ValueKey('sm_bar_catalog'),
                      icon: Icons.grid_view_rounded,
                      label: context.tr('sm_tab_catalog'),
                      active: !cartActive,
                      onTap: () => Navigator.of(context).popUntil(
                        (r) => r.settings.name == kSmHomeRouteName || r.isFirst,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _BarButton(
                      key: const ValueKey('sm_bar_cart'),
                      icon: Icons.shopping_cart_outlined,
                      label: context.tr('cart'),
                      active: cartActive,
                      badge: n,
                      onTap: cartActive ? null : onCart,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({super.key, required this.icon, required this.label, required this.active, this.badge = 0, this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final color = active ? c.brandText : c.ink2;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Саватча иконкаси (миқдор нишони билан) — AppBar учун.
class SmCartAction extends StatelessWidget {
  const SmCartAction({super.key, required this.controller, required this.onTap});

  final SupermarketController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => IconButton(
        key: const ValueKey('sm_cart_action'),
        tooltip: context.tr('cart'),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onTap,
        icon: Badge(
          isLabelVisible: controller.cart.count > 0,
          label: Text('${controller.cart.count}'),
          child: const Icon(Icons.shopping_cart_outlined),
        ),
      ),
    );
  }
}

/// Миқдор: − [1,5 кг] + ; қадам [stepMilli], энг ками бир қадам, энг кўпи [maxMilli].
class SmQtyStepper extends StatelessWidget {
  const SmQtyStepper({
    super.key,
    required this.qtyMilli,
    required this.stepMilli,
    required this.unitLabel,
    required this.onChanged,
    this.maxMilli,
    this.enabled = true,
    this.allowZero = false,
  });

  final int qtyMilli;
  final int stepMilli;
  final String unitLabel;
  final int? maxMilli;
  final bool enabled;

  /// Саватда: «−» бир қадамдан пастга туширса — 0 (қатор олиб ташланади).
  final bool allowZero;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final min = allowZero ? 0 : stepMilli;
    final canDec = enabled && qtyMilli - stepMilli >= min;
    final canInc = enabled && (maxMilli == null || qtyMilli + stepMilli <= maxMilli!);
    return Container(
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('sm_qty_dec'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: canDec ? () => onChanged(qtyMilli - stepMilli) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Text(
                '${smFormatQty(qtyMilli)} $unitLabel'.trim(),
                key: const ValueKey('sm_qty_value'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('sm_qty_inc'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: canInc ? () => onChanged(qtyMilli + stepMilli) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

/// Тортиладиган маҳсулот изоҳи (эга 2026-11-20 матни).
class SmWeighedNote extends StatelessWidget {
  const SmWeighedNote({super.key, this.percent = kSmWeighedHoldPercent});

  /// Сервер `weighHoldPercent` (сукут 10; 0.01 % аниқлик бўлиши мумкин).
  final num percent;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('sm_weighed_note'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.scale_outlined, color: c.warn, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(context.tr('sm_weighed_note').replaceAll('{p}', smPercentText(percent)), style: TextStyle(fontSize: 15, color: c.ink))),
        ],
      ),
    );
  }
}

/// Сумма қатори: «Маҳсулотлар      120 000 сўм».
class SmSumRow extends StatelessWidget {
  const SmSumRow({super.key, required this.label, required this.amount, this.bold = false, this.valueKey});

  final String label;
  final int amount;
  final bool bold;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final style = TextStyle(
      fontSize: bold ? 18 : 15,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: c.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(label, style: style)),
          const SizedBox(width: 8),
          Flexible(flex: 2, child: Text(formatMoney(amount), key: valueKey, style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// Таклиф/гуруҳ расми (тармоқ) ёки ўрин.
class SmThumb extends StatelessWidget {
  const SmThumb({super.key, required this.url, this.size = 64});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final ph = ColoredBox(color: c.surface2, child: Icon(Icons.local_grocery_store_outlined, color: c.ink3));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? ph
            : Image.network(url, fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, __, ___) => ph),
      ),
    );
  }
}
