import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

// «Менинг бизнесим» буюртмаси push'лари (functions/business_orders.js `notifyI18n` / `notifyNearbyCouriers`).
void main() {
  final t = PushNavigation.businessOrderPushTarget;

  test('курьерга таклиф → курьер панели + яқиндагилар', () {
    final r = t({'type': 'business_courier_offer', 'screen': 'courier', 'orderId': 'o1', 'businessId': 'b1'});
    expect(r?.target, BusinessOrderPushTarget.courierOffer);
    expect(r?.orderId, 'o1');
  });

  test('сотувчига (screen business_orders) → сотувчи буюртмалари + тафсилот', () {
    final r = t({'type': 'business_order', 'screen': 'business_orders', 'orderId': 'o2', 'businessId': 'b1', 'ring': '1'});
    expect(r?.target, BusinessOrderPushTarget.seller);
    expect(r?.orderId, 'o2');
  });

  test('харидорга (screen orders) → буюртма экрани', () {
    final r = t({'type': 'business_order', 'screen': 'orders', 'orderId': 'o3'});
    expect(r?.target, BusinessOrderPushTarget.buyer);
    expect(r?.orderId, 'o3');
  });

  test('курьерга ҳолат хабари (screen courier) → курьер панели', () {
    expect(t({'type': 'business_order', 'screen': 'courier', 'orderId': 'o4'})?.target, BusinessOrderPushTarget.courierRoute);
  });

  test('яроқсиз orderId — харидор экрани очилмайди; сотувчи рўйхати очилади (тафсилотсиз)', () {
    expect(t({'type': 'business_order', 'screen': 'orders', 'orderId': '../x'}), isNull);
    final s = t({'screen': 'business_orders', 'orderId': 'a/b'});
    expect(s?.target, BusinessOrderPushTarget.seller);
    expect(s?.orderId, '');
  });

  test('бошқа push\'лар тегилмайди', () {
    expect(t({'type': 'restaurant_courier_offer', 'screen': 'courier'}), isNull);
    expect(t({'type': 'order', 'screen': 'orders', 'orderId': 'o'}), isNull);
    expect(t({'type': 'wholesale_order', 'screen': 'wholesale_order', 'orderId': 'o'}), isNull);
  });
}
