import '../../models/order_model.dart';
import 'formatters.dart';

/// Буюртма чеки — матн ва қаторлар (мижоз савати билан бир хил).
class OrderReceiptFormat {
  OrderReceiptFormat._();

  static List<String> lines(OrderModel order) {
    final out = <String>[];
    switch (order.type) {
      case 'food':
        out.addAll(_foodItemLines(order));
        break;
      case 'bread':
        out.addAll(_breadItemLines(order));
        out.addAll(_breadExtraLines(order.extras));
        if (order.saltYeastCost > 0) {
          out.add(_saltYeastLine(order));
        }
        break;
      default:
        for (final it in order.items) {
          out.add('• ${_genericItemLine(it)}');
        }
        out.addAll(_breadExtraLines(order.extras));
    }
    if (out.isEmpty) out.add('• (маҳсулот йўқ)');
    out.addAll(_footerLines(order));
    return out;
  }

  static String bodyText(OrderModel order) => lines(order).join('\n');

  // ─── Нон (bread_cart_sheet _PriceSummary) ───────────────────────────

  static Iterable<String> _breadItemLines(OrderModel order) sync* {
    for (final it in order.items) {
      yield '• ${_breadBaseLine(it)}';
      if (it.flourMilkCost > 0) {
        yield '• 🌾 Un+Sut (${it.name}): ${formatPrice(it.flourMilkCost)} сўм';
      }
    }
  }

  static String _breadBaseLine(OrderItem it) {
    final prefix = it.emoji.trim().isNotEmpty ? '${it.emoji.trim()} ' : '';
    final amount = it.baseLineTotal > 0
        ? it.baseLineTotal
        : (it.unitPrice > 0 ? it.unitPrice * it.count : 0);
    final priceSuffix =
        amount > 0 ? ' = ${formatPrice(amount)} сўм' : '';
    return '$prefix${it.name} × ${it.count}$priceSuffix';
  }

  static Iterable<String> _breadExtraLines(
    List<Map<String, dynamic>> extras,
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
        yield '• 🎁 Bonus: -${formatPrice(discount)} сўм';
      }
    }
  }

  static String _saltYeastLine(OrderModel order) {
    final label = order.cartHadYopishBread
        ? '🧂 Tuz · xamirturush · drojya'
        : '🧂 Tuz va drojya';
    return '• $label: ${formatPrice(order.saltYeastCost)} сўм';
  }

  // ─── Овқат (food_screen / cart_sheet) ───────────────────────────────

  static Iterable<String> _foodItemLines(OrderModel order) sync* {
    for (final it in order.items) {
      yield '• ${_foodItemLine(it)}';
    }
  }

  static String _foodItemLine(OrderItem it) {
    final prefix = it.emoji.trim().isNotEmpty ? '${it.emoji.trim()} ' : '';
    if (it.qty != null && it.qty! > 0) {
      final q = it.qty!;
      final qty = q == q.roundToDouble() ? '${q.toInt()}' : '$q';
      final unit = it.unit.isNotEmpty ? ' $it.unit' : '';
      final lineTotal = it.itemTotal > 0
          ? it.itemTotal
          : (it.unitPrice > 0 ? (it.unitPrice * q).round() : 0);
      if (lineTotal > 0) {
        return '$prefix${it.name}: $qty$unit = ${formatPrice(lineTotal)} сўм';
      }
      return '$prefix${it.name}: $qty$unit';
    }
    final amount = it.itemTotal > 0
        ? it.itemTotal
        : (it.unitPrice > 0 ? it.unitPrice * it.count : 0);
    if (amount > 0) {
      return '$prefix${it.name} × ${it.count} = ${formatPrice(amount)} сўм';
    }
    return '$prefix${it.name} × ${it.count}';
  }

  static String _genericItemLine(OrderItem it) {
    if (it.qty != null && it.qty! > 0) {
      return _foodItemLine(it);
    }
    return _breadBaseLine(it);
  }

  // ─── Жами, манзил ───────────────────────────────────────────────────

  static Iterable<String> _footerLines(OrderModel order) sync* {
    yield 'Жами: ${formatPrice(order.total)} сўм';
    if (order.balanceApplied > 0) {
      yield 'Кошелёкдан: ${formatPrice(order.balanceApplied)} сўм';
    }
    if (order.cashDue > 0) {
      yield 'Нақд тўлов: ${formatPrice(order.cashDue)} сўм';
    }
    if (order.cashPaid > 0 && order.cashPaid != order.cashDue) {
      yield 'Берилган нақд: ${formatPrice(order.cashPaid)} сўм';
    }
    if (order.address.isNotEmpty) yield '📍 ${order.address}';
    if (order.userPhone.isNotEmpty) yield '📞 ${order.userPhone}';
    if (order.userName.isNotEmpty) yield '👤 ${order.userName}';
  }
}
