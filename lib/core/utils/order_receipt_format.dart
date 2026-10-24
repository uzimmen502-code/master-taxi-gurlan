import '../../models/order_model.dart';
import 'formatters.dart';

/// Tarjimon: `context.trMsg` bilan mos (kalit + `{param}` lar).
typedef ReceiptTr = String Function(String key,
    {Map<String, String> params});

String _identityTr(String key, {Map<String, String> params = const {}}) => key;

/// Буюртма чеки — матн ва қаторлар (мижоз савати билан бир хил).
///
/// Matn qismlari l10n kalitlari orqali [ReceiptTr] bilan tarjima qilinadi
/// (ekranda `context.trMsg`). [tr] berilmasa kalitning o'zi chiqadi (testlar).
class OrderReceiptFormat {
  OrderReceiptFormat._();

  static List<String> lines(OrderModel order, {ReceiptTr tr = _identityTr}) {
    final out = <String>[];
    switch (order.type) {
      case 'bread':
        out.addAll(_breadItemLines(order, tr));
        out.addAll(_breadExtraLines(order.extras, tr));
        if (order.saltYeastCost > 0) {
          out.add(_saltYeastLine(order, tr));
        }
        break;
      default:
        for (final it in order.items) {
          out.add('• ${_genericItemLine(it)}');
        }
        out.addAll(_breadExtraLines(order.extras, tr));
    }
    if (out.isEmpty) out.add('• ${tr('rcpt_no_items')}');
    out.addAll(_footerLines(order, tr));
    return out;
  }

  static String bodyText(OrderModel order, {ReceiptTr tr = _identityTr}) =>
      lines(order, tr: tr).join('\n');

  /// «Жами: …» қатори (чек кўринишида алоҳида ажратилади).
  static bool isTotalLine(String line, {ReceiptTr tr = _identityTr}) =>
      line.startsWith('${tr('total')}:');

  // ─── Нон (bread_cart_sheet _PriceSummary) ───────────────────────────

  static Iterable<String> _breadItemLines(
    OrderModel order,
    ReceiptTr tr,
  ) sync* {
    for (final it in order.items) {
      yield '• ${_breadBaseLine(it)}';
      if (it.flourMilkCost > 0) {
        yield '• ${tr('rcpt_flour_milk', params: {'name': it.name})}: '
            '${formatMoney(it.flourMilkCost)}';
      }
    }
  }

  static String _breadBaseLine(OrderItem it) {
    final prefix = it.emoji.trim().isNotEmpty ? '${it.emoji.trim()} ' : '';
    final amount = it.baseLineTotal > 0
        ? it.baseLineTotal
        : (it.unitPrice > 0 ? it.unitPrice * it.count : 0);
    final priceSuffix =
        amount > 0 ? ' = ${formatMoney(amount)}' : '';
    return '$prefix${it.name} × ${it.count}$priceSuffix';
  }

  static Iterable<String> _breadExtraLines(
    List<Map<String, dynamic>> extras,
    ReceiptTr tr,
  ) sync* {
    for (final ex in extras) {
      final name = (ex['name'] ?? '') as String;
      if (name.isEmpty) continue;
      final emoji = (ex['emoji'] ?? '') as String;
      final prefix = emoji.trim().isNotEmpty ? '${emoji.trim()} ' : '';
      final qtyLabel = (ex['qtyLabel'] ?? '') as String;
      final count = ex['count'];
      final unit = (ex['unit'] ?? '') as String;
      final total = ex['total'];
      final discount = (ex['bonusDiscount'] as num?)?.toInt() ?? 0;

      String qtyPart;
      if (qtyLabel.isNotEmpty) {
        qtyPart = qtyLabel;
      } else if (count is num && count > 0) {
        final qty = count == count.roundToDouble()
            ? '${count.toInt()}'
            : '$count';
        qtyPart = unit.isNotEmpty ? '$qty $unit' : qty;
      } else {
        qtyPart = '';
      }

      final priceSuffix =
          total is num ? ' = ${formatPrice(total.round())} сўм' : '';
      if (qtyPart.isNotEmpty) {
        yield '• $prefix$name ($qtyPart)$priceSuffix';
      } else {
        yield '• $prefix$name$priceSuffix';
      }

      if (discount > 0) {
        yield '• ${tr('rcpt_bonus')}: -${formatMoney(discount)}';
      }
    }
  }

  static String _saltYeastLine(OrderModel order, ReceiptTr tr) {
    final label = order.cartHadYopishBread
        ? tr('rcpt_salt_yeast_dough')
        : tr('rcpt_salt_yeast');
    return '• $label: ${formatMoney(order.saltYeastCost)}';
  }

  // ─── Миқдорли қатор (кг/л — улгуржи ва бошқалар) ────────────────────

  static String _qtyItemLine(OrderItem it) {
    final prefix = it.emoji.trim().isNotEmpty ? '${it.emoji.trim()} ' : '';
    if (it.qty != null && it.qty! > 0) {
      final q = it.qty!;
      final qty = q == q.roundToDouble() ? '${q.toInt()}' : '$q';
      final unit = it.unit.isNotEmpty ? ' ${it.unit}' : '';
      final lineTotal = it.itemTotal > 0
          ? it.itemTotal
          : (it.unitPrice > 0 ? (it.unitPrice * q).round() : 0);
      if (lineTotal > 0) {
        return '$prefix${it.name}: $qty$unit = ${formatMoney(lineTotal)}';
      }
      return '$prefix${it.name}: $qty$unit';
    }
    final amount = it.itemTotal > 0
        ? it.itemTotal
        : (it.unitPrice > 0 ? it.unitPrice * it.count : 0);
    if (amount > 0) {
      return '$prefix${it.name} × ${it.count} = ${formatMoney(amount)}';
    }
    return '$prefix${it.name} × ${it.count}';
  }

  static String _genericItemLine(OrderItem it) {
    if (it.qty != null && it.qty! > 0) {
      return _qtyItemLine(it);
    }
    return _breadBaseLine(it);
  }

  // ─── Жами, манзил ───────────────────────────────────────────────────

  static Iterable<String> _footerLines(OrderModel order, ReceiptTr tr) sync* {
    yield '${tr('total')}: ${formatMoney(order.total)}';
    if (order.balanceApplied > 0) {
      yield '${tr('crr_pay_from_wallet')}: ${formatMoney(order.balanceApplied)}';
    }
    if (order.cashDue > 0) {
      yield '${tr('rcpt_cash_due')}: ${formatMoney(order.cashDue)}';
    }
    if (order.cashPaid > 0 && order.cashPaid != order.cashDue) {
      yield '${tr('rcpt_cash_given')}: ${formatMoney(order.cashPaid)}';
    }
    if (order.address.isNotEmpty) yield '📍 ${order.address}';
    if (order.userPhone.isNotEmpty) yield '📞 ${order.userPhone}';
    if (order.userName.isNotEmpty) yield '👤 ${order.userName}';
  }
}
