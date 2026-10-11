import 'package:ava_gurlan/core/utils/order_receipt_format.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Миқдорли қатор (улгуржи): `' $it.unit'` — `$it` объектни, кейин «.unit»
/// матнини ёзарди → чекда «1 Instance of 'OrderItem'.unit» (админ ва
/// мижоз чеки, 2026-10-11 скриншоти).
void main() {
  OrderModel order(List<OrderItem> items) => OrderModel(
        id: 'o1',
        type: 'platform',
        total: 36750,
        status: 'ready',
        items: items,
      );

  test('бирлик номи чиқади, объект матни эмас', () {
    final lines = OrderReceiptFormat.lines(order(const [
      OrderItem(name: 'Қопқоқ', qty: 1, unit: 'дона', itemTotal: 36750),
    ]));
    expect(lines.first, contains('Қопқоқ: 1 дона'));
    expect(lines.join('\n'), isNot(contains('Instance of')));
  });

  test('бирлик бўлмаса — фақат миқдор', () {
    final lines = OrderReceiptFormat.lines(order(const [
      OrderItem(name: 'Чой', qty: 2, itemTotal: 1000),
    ]));
    expect(lines.first, startsWith('• Чой: 2 ='));
  });
}
