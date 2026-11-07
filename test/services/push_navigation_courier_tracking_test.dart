import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Курьерга топширилди — кузатиш учун ҳаволага ўтинг» push'и (AVA дўкони, эга 2026-11-07):
/// сервер `functions/index.js` `onOrderUpdate` → `{type: order, screen: courier_tracking, orderId}`.
void main() {
  group('courierTrackingOrderIdFromPush', () {
    test('courier_tracking + тўғри orderId → orderId', () {
      expect(
        PushNavigation.courierTrackingOrderIdFromPush(
            {'type': 'order', 'screen': 'courier_tracking', 'orderId': 'AbC_12-x'}),
        'AbC_12-x',
      );
    });

    test('бошқа экран (news/orders) → null, аввалги йўл ўзгармайди', () {
      expect(PushNavigation.courierTrackingOrderIdFromPush({'type': 'order', 'screen': 'news', 'orderId': 'a1'}), isNull);
      expect(PushNavigation.courierTrackingOrderIdFromPush({'type': 'order', 'orderId': 'a1'}), isNull);
    });

    test('orderId йўқ ёки Firestore ID шаклида эмас → null (йўл/инъекция йўқ)', () {
      expect(PushNavigation.courierTrackingOrderIdFromPush({'screen': 'courier_tracking'}), isNull);
      expect(PushNavigation.courierTrackingOrderIdFromPush({'screen': 'courier_tracking', 'orderId': '../x'}), isNull);
      expect(PushNavigation.courierTrackingOrderIdFromPush({'screen': 'courier_tracking', 'orderId': ''}), isNull);
    });
  });
}
