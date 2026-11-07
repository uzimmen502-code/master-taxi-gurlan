import 'package:ava_gurlan/services/notification_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ҳудуддаги курьерга «янги буюртма» (эга 2026-11-07): овоз + вибрация (`courier_new_order` канали),
/// сервер `functions/index.js` `notifyCouriersOrderReady` билан бир хил ном.
void main() {
  test('courier_new_order → алоҳида қўнғироқли канал, баланд приоритет', () {
    expect(NotificationDelivery.channelForType('courier_new_order'), 'courier_new_order');
    expect(NotificationDelivery.isRingAlert('courier_new_order'), isTrue);
  });

  test('бошқа турлар ўзгармаган', () {
    expect(NotificationDelivery.channelForType('courier_arrived'), 'courier_arrival_alarm');
    expect(NotificationDelivery.channelForType('order'), 'order_channel');
    expect(NotificationDelivery.isRingAlert('order'), isFalse);
  });
}
