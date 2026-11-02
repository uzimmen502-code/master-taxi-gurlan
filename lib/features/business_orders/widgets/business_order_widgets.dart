// «Менинг бизнесим» буюртмаси — умумий кичик виджетлар ва матн ёрдамчилари (мижоз, сотувчи, курьер экранлари).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../tv_market/domain/price_unit.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../domain/business_order_errors.dart';

/// Хато → фойдаланувчи матни (ички код йўқ, 25-қоида). Сервер коди маълум бўлса — ўз матни ({param} билан),
/// бўлмаса тармоқ/вақт/умумий матн.
String bizOrderErrorText(BuildContext context, Object e) {
  if (e is BusinessOrderException) {
    final key = bizOrderErrorKeyOrNull(e.reason);
    if (key != null) {
      var s = context.tr(key);
      bizOrderErrorParams(e.reason, e.details).forEach((k, v) => s = s.replaceAll('{$k}', v));
      return s;
    }
    return context.tr(userErrorKeyFromCode(e.code, fallbackKey: bizOrderErrorGeneric));
  }
  return userErrorMessage(context, e, fallbackKey: bizOrderErrorGeneric);
}

/// «3 кг», «2 дона», «× 2» (белгиланган нархда бирликсиз).
String bizOrderQtyLabel(BuildContext context, int qty, PriceUnit unit) {
  final k = businessQtyUnitKey(unit);
  return k == null ? '× $qty' : '$qty ${context.tr(k)}';
}

/// Ҳолат ранглари: якуний салбий — қизил, етказилди — яшил, бошқа фаол — бренд.
(Color, Color) bizOrderStatusColors(BuildContext context, String status) {
  final c = context.ava;
  return switch (status) {
    BusinessOrderStatus.delivered => (c.ok, c.okSoft),
    BusinessOrderStatus.rejected || BusinessOrderStatus.cancelled || BusinessOrderStatus.deliveryFailed =>
      (c.danger, c.dangerSoft),
    BusinessOrderStatus.placed => (c.warn, c.warnSoft),
    _ => (c.brandText, c.brandSoft),
  };
}

class BusinessOrderStatusPill extends StatelessWidget {
  const BusinessOrderStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = bizOrderStatusColors(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AvaRadius.chip)),
      child: Text(
        context.tr(BusinessOrderStatus.labelKey(status)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Вақт чизиғи: Юборилди → Қабул қилинди → Тайёр → Курьерда → Етиб келди → Етказилди. Якуний салбий
/// ҳолатда — қизил хабар (сабаби билан).
class BusinessOrderTimeline extends StatelessWidget {
  const BusinessOrderTimeline({super.key, required this.order});

  final BusinessOrder order;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final s = order.status;
    if (s == BusinessOrderStatus.rejected || s == BusinessOrderStatus.cancelled || s == BusinessOrderStatus.deliveryFailed) {
      final reason = order.rejectReason;
      final text = s == BusinessOrderStatus.rejected && reason == 'timeout'
          ? context.tr('biz_order_rejected_timeout')
          : context.tr(BusinessOrderStatus.labelKey(s));
      final showReason = s == BusinessOrderStatus.rejected && reason.isNotEmpty && reason != 'timeout' && reason != 'seller';
      return Container(
        key: const ValueKey('biz_order_timeline_final'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(AvaRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.danger)),
            if (showReason)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr('biz_order_reject_reason').replaceAll('{reason}', reason),
                  style: TextStyle(fontSize: 13, color: c.ink),
                ),
              ),
          ],
        ),
      );
    }
    final current = BusinessOrderStatus.timelineIndex(s);
    return Column(
      key: const ValueKey('biz_order_timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < BusinessOrderStatus.timeline.length; i++)
          _TimelineRow(
            label: context.tr(BusinessOrderStatus.stepKey(BusinessOrderStatus.timeline[i])),
            done: i <= current,
            current: i == current,
            last: i == BusinessOrderStatus.timeline.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.done, required this.current, required this.last});

  final String label;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final color = done ? c.ok : c.line;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: done ? c.ok : c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: done ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
                ),
                if (!last) Expanded(child: Container(width: 2, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                  color: done ? c.ink : c.ink2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Буюртма қаторлари ва ҳисоб: маҳсулотлар · етказиш · жами (+ эшик олдида нақд).
class BusinessOrderSummary extends StatelessWidget {
  const BusinessOrderSummary({super.key, required this.order, this.showCashAtDoor = true});

  final BusinessOrder order;
  final bool showCashAtDoor;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in o.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${l.title} · ${bizOrderQtyLabel(context, l.qty, l.priceUnit)}',
                    style: TextStyle(fontSize: 13, color: c.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatMoney(l.lineTotal), style: TextStyle(fontSize: 13, color: c.ink)),
              ],
            ),
          ),
        Divider(color: c.line),
        BizOrderMoneyLine(label: context.tr('biz_order_items_total'), amount: o.itemsTotal),
        BizOrderMoneyLine(label: context.tr('biz_order_delivery_fee'), amount: o.deliveryFee),
        BizOrderMoneyLine(label: context.tr('biz_order_total'), amount: o.total, bold: true),
        if (showCashAtDoor && o.cashAtDoor > 0) ...[
          const SizedBox(height: 6),
          Text(
            context.tr('biz_order_pay_at_door').replaceAll('{amount}', formatMoney(o.cashAtDoor)),
            key: const ValueKey('biz_order_cash_at_door'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.brandText),
          ),
        ],
        if (o.deliveryPaymentMethod == 'wallet') ...[
          const SizedBox(height: 4),
          Text(context.tr('biz_order_wallet_note'), style: TextStyle(fontSize: 12, color: c.ink2)),
        ],
      ],
    );
  }
}

class BizOrderMoneyLine extends StatelessWidget {
  const BizOrderMoneyLine({super.key, required this.label, required this.amount, this.bold = false, this.valueText});

  final String label;
  final int amount;
  final bool bold;

  /// Сумма ўрнига матн (масалан «ҳисобланмоқда…»).
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final style = TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w400, color: c.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Flexible(child: Text(valueText ?? formatMoney(amount), textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

/// Оддий ранг блок (изоҳ/огоҳлантириш).
class BizOrderNotice extends StatelessWidget {
  const BizOrderNotice({super.key, required this.icon, required this.text, required this.color, required this.background});

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AvaRadius.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: context.ava.ink, height: 1.3))),
        ],
      ),
    );
  }
}

String bizOrderTimeLabel(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

String bizOrderDateLabel(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
