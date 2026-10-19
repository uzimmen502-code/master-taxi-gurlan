import 'package:ava_gurlan/features/restaurants/merchant/merchant_order_actions.dart';
import 'package:ava_gurlan/features/restaurants/merchant/merchant_report_tab.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _o({
  String rs = 'placed',
  String mode = 'ava_courier',
  String pay = 'prepay',
  String paymentStatus = 'unpaid',
  DateTime? created,
  int itemsTotal = 60000,
  int packaging = 0,
  int fee = 1200,
  bool charged = true,
  bool refunded = false,
  DateTime? deadline,
}) =>
    OrderModel(
      id: 'o$rs',
      type: 'restaurant',
      total: itemsTotal,
      status: 'new',
      items: const [],
      restaurantStatus: rs,
      deliveryMode: mode,
      foodPaymentMethod: pay,
      paymentStatus: paymentStatus,
      createdAt: created,
      itemsTotal: itemsTotal,
      packagingTotal: packaging,
      avaFeeAmount: fee,
      avaFeeCharged: charged,
      avaFeeRefunded: refunded,
      acceptDeadlineAt: deadline,
    );

void main() {
  group('merchantActionsFor — server o\'tish jadvali bilan bir xil', () {
    test('placed → qabul (asosiy) + rad', () {
      expect(merchantActionsFor(_o(rs: 'placed')), [MerchantAction.accept, MerchantAction.reject, MerchantAction.confirmPayment]);
    });
    test('accepted → tayyor + rad; naqd bo\'lsa confirmPayment yo\'q', () {
      expect(merchantActionsFor(_o(rs: 'accepted', pay: 'cash_buyout')), [MerchantAction.ready, MerchantAction.reject]);
    });
    test('ready: AVA kuryeri — faqat rad (kutish); o\'z kuryeri/olib ketish — yetkazdim', () {
      expect(merchantActionsFor(_o(rs: 'ready', pay: 'cash_buyout')), [MerchantAction.reject]);
      expect(merchantActionsFor(_o(rs: 'ready', mode: 'own_courier', pay: 'cash_to_restaurant')), [MerchantAction.markDelivered, MerchantAction.reject]);
      expect(merchantActionsFor(_o(rs: 'ready', mode: 'pickup', pay: 'cash_to_restaurant')), [MerchantAction.markDelivered, MerchantAction.reject]);
    });
    test('prepay + paid → confirmPayment yo\'q; yakuniy holatlar — hech narsa', () {
      expect(merchantActionsFor(_o(rs: 'accepted', paymentStatus: 'paid')), [MerchantAction.ready, MerchantAction.reject]);
      for (final s in ['delivered', 'rejected', 'cancelled', 'delivery_failed']) {
        expect(merchantActionsFor(_o(rs: s)), isEmpty, reason: s);
      }
      expect(merchantActionsFor(_o(rs: 'picked', pay: 'cash_buyout')), isEmpty, reason: 'kuryerda — restoran hech narsa qilmaydi');
      expect(merchantActionsFor(_o(rs: 'picked')), [MerchantAction.confirmPayment], reason: 'oldindan to\'lov hali kelmagan — tasdiqlash qoladi');
    });
    test('bucket va deadline', () {
      expect(merchantBucketFor(_o(rs: 'placed')), MerchantOrderBucket.fresh);
      expect(merchantBucketFor(_o(rs: 'picked')), MerchantOrderBucket.active);
      expect(merchantBucketFor(_o(rs: 'delivered')), MerchantOrderBucket.history);
      final now = DateTime(2026, 10, 9, 12);
      expect(secondsToDeadline(_o(deadline: now.add(const Duration(seconds: 90))), now), 90);
      expect(secondsToDeadline(_o(deadline: now.subtract(const Duration(seconds: 5))), now), -5);
      expect(secondsToDeadline(_o(), now), isNull);
    });
  });

  group('RestaurantFormData.validate', () {
    RestaurantFormData ok() => RestaurantFormData(name: 'Gurlan osh', address: 'Markaz', lat: 41.8, lng: 60.4);

    test('to\'g\'ri forma — xato yo\'q; payload serverga mos', () {
      final f = ok();
      expect(f.validate(), isEmpty);
      final p = f.toRegisterPayload();
      expect(p['delivery'], {'mode': 'ava_courier', 'pickup': true, 'ownFee': {'type': 'fixed', 'fixed': 0, 'base': 0, 'perKm': 0, 'freeAbove': null, 'maxKm': null}});
      expect(p['openingHours'], isNull, reason: 'har doim ochiq');
      expect((p['payment'] as Map)['cardNumber'], '');
    });
    test('nom qisqa, joylashuv yo\'q, manzil bo\'sh', () {
      final f = RestaurantFormData(name: 'A');
      expect(f.validate(), containsAll(['name', 'location', 'address']));
    });
    test('«Yetkazmayman» yo\'q (ega, 2026-10-19): faqat AVA kuryeri yoki o\'z kuryeri; eski `none` hujjat formada xato — egasi birini tanlaydi', () {
      expect(RestaurantFormData.deliveryModes, ['ava_courier', 'own_courier']);
      expect((ok()..deliveryMode = 'none').validate(), ['delivery_mode']);
      expect((ok()..deliveryMode = 'none'..pickup = false).validate(), ['delivery_mode']);
      expect((ok()..deliveryMode = 'own_courier').validate(), isEmpty);
      expect((ok()..deliveryMode = 'ava_courier'..pickup = false).validate(), isEmpty, reason: 'olib ketish — alohida qo\'shimcha, majburiy emas');
    });
    test('to\'lov usuli bo\'sh; karta 16 raqam; tayyorlash chegarasi; ish vaqti', () {
      expect((ok()..prepay = false..cash = false).validate(), ['payment_method']);
      expect((ok()..cardNumber = '8600 1234').validate(), ['card_number']);
      expect((ok()..cardNumber = '8600 1234 5678 9012').validate(), isEmpty);
      expect((ok()..prepTimeMin = 3).validate(), ['prep_time']);
      expect((ok()..alwaysOpen = false..openTime = 'x').validate(), ['hours']);
      final hours = (ok()..alwaysOpen = false..openTime = '09:00'..closeTime = '22:00').toRegisterPayload();
      expect(hours['openingHours'], {'open': '09:00', 'close': '22:00'});
    });
    test('maxQtyPerItem (D-REST-26): default 50; 1…500 ok; 0, 501 → max_qty; profil patch yuboradi, ro\'yxatdan o\'tish payload\'i yo\'q', () {
      expect(ok().maxQtyPerItem, 50);
      expect((ok()..maxQtyPerItem = 1).validate(), isEmpty, reason: 'quyi chegara');
      expect((ok()..maxQtyPerItem = 500).validate(), isEmpty, reason: 'yuqori chegara');
      expect((ok()..maxQtyPerItem = 0).validate(), ['max_qty'], reason: 'bo\'sh maydon (_int → 0) jim default bo\'lmaydi');
      expect((ok()..maxQtyPerItem = 501).validate(), ['max_qty']);
      expect((ok()..maxQtyPerItem = 120).toProfilePatch()['maxQtyPerItem'], 120);
      expect(ok().toRegisterPayload().containsKey('maxQtyPerItem'), isFalse, reason: 'server restaurantRegister qabul qilmaydi');
    });
    test('cuisineTags 3 tadan ko\'p bo\'lsa kesiladi; profil patch server-only maydonlarsiz', () {
      final f = ok()..cuisineTags = ['a', 'b', 'c', 'd'];
      expect((f.toRegisterPayload()['cuisineTags'] as List).length, 3);
      final patch = f.toProfilePatch();
      expect(patch.containsKey('status'), isFalse);
      expect(patch.containsKey('ownerUid'), isFalse);
      expect(patch.containsKey('legalType'), isFalse);
      expect(patch['payment'], {'prepay': true, 'cash': true});
    });
  });

  group('MerchantDailyStats', () {
    test('bugungi buyurtmalar, yetkazilgan tushumi, AVA haqi (qaytarilgan emas), jarayondagilar', () {
      final now = DateTime(2026, 10, 9, 15);
      final today = DateTime(2026, 10, 9, 10);
      final yesterday = DateTime(2026, 10, 8, 10);
      final s = MerchantDailyStats.compute([
        _o(rs: 'delivered', created: today, itemsTotal: 60000, packaging: 1000, fee: 1200),
        _o(rs: 'delivered', created: today, itemsTotal: 40000, fee: 800),
        _o(rs: 'rejected', created: today, fee: 1200, refunded: true),
        _o(rs: 'accepted', created: today, fee: 1200),
        _o(rs: 'delivered', created: yesterday, itemsTotal: 99000, fee: 1980),
        _o(rs: 'placed', created: yesterday, fee: 0, charged: false),
      ], now);
      expect(s.orders, 4);
      expect(s.delivered, 2);
      expect(s.revenue, 101000);
      expect(s.avaFee, 1200 + 800 + 1200, reason: 'rejected+refunded sanalmaydi, accepted sanaladi');
      expect(s.active, 2, reason: 'accepted (bugun) + placed (kecha)');
    });
  });
}
