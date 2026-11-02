import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/business_orders/data/business_order_session.dart';
import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order_errors.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/models/customer_confirm.dart';
import 'package:ava_gurlan/models/delivery_failed.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

TvShopItem item(
  String id, {
  String businessId = 'b1',
  String kind = 'product',
  int price = 5000,
  PriceUnit unit = PriceUnit.fixed,
  String status = 'active',
}) =>
    TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'Дўкон',
      title: 'Маҳсулот $id',
      price: price,
      photoUrl: '',
      kind: kind,
      districtId: 'd1',
      districtLabel: '',
      businessId: businessId,
      priceUnit: unit,
      status: status,
    );

Map<String, dynamic> _lang(String l) =>
    jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('буюртма қилиса бўладиган таклиф (сервер чеклари кўзгуси)', () {
    test('фақат объект маҳсулоти, фаол, нарх > 0, бирлик: белгиланган/дона/кг/м²', () {
      expect(businessItemOrderable(item('a')), isTrue);
      for (final u in [PriceUnit.piece, PriceUnit.kg, PriceUnit.m2]) {
        expect(businessItemOrderable(item('a', unit: u)), isTrue, reason: u.name);
      }
      for (final u in [PriceUnit.from, PriceUnit.negotiable, PriceUnit.hour, PriceUnit.day, PriceUnit.session]) {
        expect(businessItemOrderable(item('a', unit: u)), isFalse, reason: u.name);
      }
      expect(businessItemOrderable(item('a', kind: 'service')), isFalse);
      expect(businessItemOrderable(item('a', price: 0)), isFalse);
      expect(businessItemOrderable(item('a', businessId: '')), isFalse);
      expect(businessItemOrderable(item('a', status: 'blocked')), isFalse);
    });
  });

  group('сават', () {
    test('қўшиш/қўшилиш, 1..100 чегара, нарх юборилмайди', () {
      final c = BusinessCart(businessId: 'b1');
      expect(c.add(item('a'), 3), isTrue);
      expect(c.add(item('a'), 2), isTrue);
      expect(c.qtyOf('a'), 5);
      expect(c.add(item('a'), 500), isTrue);
      expect(c.qtyOf('a'), BusinessOrderLimits.maxQtyPerItem, reason: 'чегарада тўхтайди');
      c.setQty('a', 0);
      expect(c.isEmpty, isTrue, reason: '0 — қатор олиб ташланади');
      c.add(item('a', price: 7000), 2);
      expect(c.itemsTotal, 14000);
      expect(c.toItems(), [
        {'itemId': 'a', 'qty': 2},
      ]);
      expect(c.toItems().first.containsKey('price'), isFalse);
    });

    test('бошқа объект, хизмат, келишиладиган нарх — рад; 30 қатордан ошмайди', () {
      final c = BusinessCart(businessId: 'b1');
      expect(c.add(item('x', businessId: 'b2'), 1), isFalse);
      expect(c.add(item('x', kind: 'service'), 1), isFalse);
      expect(c.add(item('x', unit: PriceUnit.negotiable), 1), isFalse);
      for (var i = 0; i < BusinessOrderLimits.maxItems; i++) {
        expect(c.add(item('i$i'), 1), isTrue);
      }
      expect(c.add(item('extra'), 1), isFalse, reason: '31-қатор');
      expect(c.lines.length, BusinessOrderLimits.maxItems);
    });

    test('имзо мазмунга боғлиқ (идемпотентлик нияти)', () {
      final c = BusinessCart(businessId: 'b1')..add(item('a'), 1);
      final s1 = c.signature;
      c.setQty('a', 2);
      expect(c.signature, isNot(s1));
    });

    test('сават омбори: объект бўйича битта сават, тозалаш', () {
      final s = BusinessCartStore();
      final a = s.cartFor('b1', businessName: 'A');
      expect(identical(s.cartFor('b1'), a), isTrue);
      expect(a.businessName, 'A');
      s.clear('b1');
      expect(s.existing('b1'), isNull);
    });
  });

  group('ҳолатлар (сервер жадвали кўзгуси)', () {
    test('якуний / фаол / вақт чизиғи', () {
      for (final s in ['delivered', 'rejected', 'cancelled', 'delivery_failed']) {
        expect(BusinessOrderStatus.isFinal(s), isTrue, reason: s);
      }
      for (final s in ['placed', 'accepted', 'ready', 'picked', 'arrived']) {
        expect(BusinessOrderStatus.isActive(s), isTrue, reason: s);
      }
      expect(BusinessOrderStatus.timeline.first, 'placed');
      expect(BusinessOrderStatus.timeline.last, 'delivered');
      expect(BusinessOrderStatus.labelKey('weird'), 'biz_order_status_placed');
    });

    test('ҳужжатдан ўқиш: эшик олдидаги нақд = маҳсулот пули + нақд етказиш', () {
      final o = BusinessOrder.fromMap('o1', {
        'type': 'business',
        'businessStatus': 'arrived',
        'items': [
          {'itemId': 'a', 'title': 'Ун', 'unitPrice': 1000, 'priceUnit': 'kg', 'qty': 3, 'lineTotal': 3000},
          'бузуқ',
        ],
        'itemsTotal': 3000,
        'deliveryFee': 8000,
        'total': 11000,
        'deliveryPaymentMethod': 'cash',
        'awaitingCustomerConfirm': {'step': 'delivery_failed', 'module': 'business', 'failReason': 'customer_absent'},
      });
      expect(o.items.single.priceUnit, PriceUnit.kg);
      expect(o.cashAtDoor, 11000);
      expect(o.deliveryFailedPending, isTrue);
      expect(o.courierCanReportFailed, isFalse);
      expect(o.deliveryFailed.reason, 'customer_absent');
      final w = BusinessOrder.fromMap('o2', {'businessStatus': 'picked', 'itemsTotal': 3000, 'deliveryFee': 8000, 'deliveryPaymentMethod': 'wallet'});
      expect(w.cashAtDoor, 3000, reason: 'ҳамён — етказиш ҳақи нақдга қўшилмайди');
      expect(w.courierCanReportFailed, isTrue);
    });

    test('OrderModel: бизнес буюртмаси — ўз ҳолати, бекор фақат placed', () {
      const placed = OrderModel(id: 'o', type: 'business', total: 1, status: 'new', items: [], businessStatus: 'placed');
      const accepted = OrderModel(id: 'o', type: 'business', total: 1, status: 'accepted', items: [], businessStatus: 'accepted');
      expect(placed.isBusiness, isTrue);
      expect(placed.canCustomerCancel, isTrue);
      expect(accepted.canCustomerCancel, isFalse, reason: 'эски status «accepted» бекорга рухсат берарди');
      expect(placed.typeLabelKey, 'biz_order_module');
    });
  });

  group('дарвоза', () {
    test('жавоб ўқиш: хато/номаълум — ёпиқ; курьер кириши', () {
      expect(BusinessOrdersAccess.fromMap(null).allowed, isFalse);
      expect(BusinessOrdersAccess.fromMap({'allowed': true, 'stage': 'public'}).allowed, isTrue);
      expect(const BusinessOrdersAccess(allowed: false, stage: 'internal', reason: 'MODULE_INTERNAL_ONLY').courierVisible, isFalse);
      expect(const BusinessOrdersAccess(allowed: false, stage: 'off', reason: 'MODULE_OFF').courierVisible, isFalse);
      expect(const BusinessOrdersAccess(allowed: false, stage: 'pilot', reason: 'MODULE_NOT_IN_PILOT').courierVisible, isTrue);
    });

    test('кеш: 5 дақиқа ичида қайта чақирилмайди; хато кешланмайди', () async {
      var now = DateTime(2026, 11, 3, 10);
      final cache = BusinessOrdersAccessCache(now: () => now);
      var calls = 0;
      Future<BusinessOrdersAccess> ok() async {
        calls++;
        return const BusinessOrdersAccess(allowed: true, stage: 'public');
      }

      await cache.get('b1', ok);
      await cache.get('b1', ok);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 6));
      await cache.get('b1', ok);
      expect(calls, 2);

      var errCalls = 0;
      Future<BusinessOrdersAccess> err() async {
        errCalls++;
        return BusinessOrdersAccess.closed;
      }

      await cache.get('b2', err);
      await cache.get('b2', err);
      expect(errCalls, 2);
    });
  });

  test('сотувчи сўрови шакли: sellerUid == канон телефон, createdAt desc', () {
    final s = BusinessOrdersRepository.sellerQuerySpec('+998 (90) 111-11-11');
    expect(s.field, 'sellerUid');
    expect(s.isEqualTo, '998901111111');
    expect(s.orderBy, 'createdAt');
    expect(s.descending, isTrue);
    expect(BusinessOrdersRepository.sellerQuerySpec('901111111').isEqualTo, '998901111111');
  });

  group('хато кодлари → 3 тилли матн', () {
    const contract = [
      'MODULE_OFF', 'MODULE_INTERNAL_ONLY', 'MODULE_NOT_IN_PILOT', 'TARIFF_NOT_CONFIGURED', 'DELIVERY_TOO_FAR',
      'BUSINESS_NOT_FOUND', 'BUSINESS_NOT_ACTIVE', 'BUSINESS_ONLINE_NO_PICKUP', 'OWN_BUSINESS', 'ITEM_NOT_FOUND',
      'ITEM_UNAVAILABLE', 'ITEM_NOT_PRODUCT', 'PRICE_NOT_FIXED', 'QTY_LIMIT_EXCEEDED', 'IDEMPOTENCY_KEY_CONFLICT',
      'NOT_ORDER_SELLER', 'ORDER_INVALID_TRANSITION', 'CANCEL_NOT_ALLOWED', 'ORDER_NOT_CLAIMABLE',
      'COURIER_ASSIGNMENT_CONFLICT', 'BUYOUT_LIMIT_EXCEEDED', 'PICKUP_CODE_MISMATCH', 'PICKUP_CODE_LOCKED',
      'CONTENTION_RETRY', //
    ];
    final langs = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: _lang(l)};

    test('шартномадаги ҳар бир код калитга тушади', () {
      for (final c in contract) {
        expect(bizOrderErrorKeyOrNull(c), isNotNull, reason: c);
      }
      expect(bizOrderErrorKeyOrNull('SOMETHING_NEW'), isNull);
    });

    test('ҳамма калит (+ умумий) учала тилда бор ва бўш эмас', () {
      final keys = {...bizOrderErrorKeys.values, bizOrderErrorGeneric};
      for (final k in keys) {
        for (final e in langs.entries) {
          expect((e.value[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$k / ${e.key}');
        }
      }
    });

    test('{param}лар сервер details дан', () {
      expect(bizOrderErrorParams('DELIVERY_TOO_FAR', {'maxKm': 25}), {'km': '25'});
      expect(bizOrderErrorParams('PICKUP_CODE_MISMATCH', {'attemptsLeft': 2}), {'n': '2'});
      expect(bizOrderErrorParams('QTY_LIMIT_EXCEEDED', null), {'max': '100'});
      for (final l in langs.values) {
        expect(l['biz_order_err_delivery_too_far'], contains('{km}'));
        expect(l['biz_order_err_pickup_code_mismatch'], contains('{n}'));
      }
    });

    test('ҳолат ва қадам калитлари учала тилда', () {
      for (final s in [...BusinessOrderStatus.timeline, 'rejected', 'cancelled', 'delivery_failed']) {
        for (final e in langs.entries) {
          expect(e.value.containsKey(BusinessOrderStatus.labelKey(s)), isTrue, reason: '$s / ${e.key}');
        }
      }
      for (final s in BusinessOrderStatus.timeline) {
        for (final e in langs.entries) {
          expect(e.value.containsKey(BusinessOrderStatus.stepKey(s)), isTrue, reason: '$s step / ${e.key}');
        }
      }
    });
  });

  test('модул номи: «етказилмади» ва мижоз тасдиғи рўйхатларида', () {
    expect(deliveryFailedModuleKey(DeliveryFailedModule.business, ''), 'biz_order_module');
    expect(customerConfirmModuleKey(CustomerConfirmModule.business), 'biz_order_module');
  });
}
