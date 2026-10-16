// Мижоз тасдиғи (D2/D7) — сервер жавобини ўқиш ва матн калитлари.
//
//   flutter test test/models/customer_confirm_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/models/customer_confirm.dart';

void main() {
  group('CourierActionResult.fromResponse', () {
    test('awaitingCustomer: true + step', () {
      final r = CourierActionResult.fromResponse(
          {'ok': true, 'awaitingCustomer': true, 'step': 'handover_pickup'});
      expect(r.awaitingCustomer, isTrue);
      expect(r.step, 'handover_pickup');
    });

    test('maydon yo\'q (eski server) — kutish YO\'Q', () {
      final r = CourierActionResult.fromResponse({'ok': true, 'V': 1000});
      expect(r.awaitingCustomer, isFalse);
      expect(r.step, isEmpty);
    });

    test('awaitingCustomer false / null / "true" matn — kutish YO\'Q', () {
      expect(CourierActionResult.fromResponse({'awaitingCustomer': false}).awaitingCustomer,
          isFalse);
      expect(CourierActionResult.fromResponse({'awaitingCustomer': null}).awaitingCustomer,
          isFalse);
      expect(CourierActionResult.fromResponse({'awaitingCustomer': 'true'}).awaitingCustomer,
          isFalse);
    });

    test('Map bo\'lmagan javob (null, void) — kutish YO\'Q', () {
      expect(CourierActionResult.fromResponse(null).awaitingCustomer, isFalse);
      expect(CourierActionResult.fromResponse('ok').awaitingCustomer, isFalse);
    });

    test('step matn bo\'lmasa — bo\'sh, lekin kutish saqlanadi', () {
      final r = CourierActionResult.fromResponse(
          {'awaitingCustomer': true, 'step': 5});
      expect(r.awaitingCustomer, isTrue);
      expect(r.step, isEmpty);
    });
  });

  group('CustomerConfirmation.listFromResponse', () {
    Map<String, dynamic> item(String module, String id, String step,
            {int? ms, Object? details, String title = ''}) =>
        {
          'module': module,
          'id': id,
          'step': step,
          'title': title,
          if (ms != null) 'requestedAtMs': ms,
          if (details != null) 'details': details,
        };

    test('to\'liq element', () {
      final list = CustomerConfirmation.listFromResponse({
        'ok': true,
        'items': [
          {
            'module': 'collection',
            'id': 't1',
            'step': 'finalize',
            'title': 'Sut',
            'summary': 'Tekshiring',
            'requestedAtMs': 1700000000000,
            'details': {
              'qty': 12.5,
              'unit': 'litr',
              'amount': 87500,
              'productLabel': 'Sut',
            },
          },
        ],
      });
      expect(list, hasLength(1));
      final c = list.single;
      expect(c.module, 'collection');
      expect(c.id, 't1');
      expect(c.step, 'finalize');
      expect(c.title, 'Sut');
      expect(c.summary, 'Tekshiring');
      expect(c.requestedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(c.details!.qty, 12.5);
      expect(c.details!.unit, 'litr');
      expect(c.details!.amount, 87500);
      expect(c.details!.productLabel, 'Sut');
      expect(c.key, 'collection/t1/finalize');
    });

    test('summa butun songa o\'tadi (pul float emas)', () {
      final c = CustomerConfirmation.fromMap(item('collection', 't', 'finalize',
          details: {'amount': 87500.0}))!;
      expect(c.details!.amount, isA<int>());
      expect(c.details!.amount, 87500);
    });

    test('bo\'sh / buzuq javob — bo\'sh ro\'yxat', () {
      expect(CustomerConfirmation.listFromResponse(null), isEmpty);
      expect(CustomerConfirmation.listFromResponse({'ok': true}), isEmpty);
      expect(CustomerConfirmation.listFromResponse({'items': 'x'}), isEmpty);
      expect(CustomerConfirmation.listFromResponse({'items': []}), isEmpty);
    });

    test('module/id/step yetishmagan element tashlanadi, qolgani saqlanadi', () {
      final list = CustomerConfirmation.listFromResponse({
        'items': [
          {'module': 'carpet', 'step': 'received'},
          {'id': 'x', 'step': 'received'},
          {'module': 'carpet', 'id': 'x'},
          'matn',
          item('carpet', 'ok1', 'received'),
        ],
      });
      expect(list.map((e) => e.id), ['ok1']);
    });

    test('bir xil kalit takrorlanmaydi; bitta buyurtmada ikki qadam alohida', () {
      final list = CustomerConfirmation.listFromResponse({
        'items': [
          item('carpet', 'a', 'handover_pickup'),
          item('carpet', 'a', 'handover_pickup'),
          item('carpet', 'a', 'received'),
        ],
      });
      expect(list.map((e) => e.key),
          ['carpet/a/handover_pickup', 'carpet/a/received']);
    });

    test('eng eskisi tepada, vaqtsiz oxirida', () {
      final list = CustomerConfirmation.listFromResponse({
        'items': [
          item('agro', 'c', 'handover_pickup'),
          item('agro', 'b', 'handover_pickup', ms: 3000),
          item('agro', 'a', 'handover_pickup', ms: 1000),
        ],
      });
      expect(list.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('details bo\'sh / noto\'g\'ri — null', () {
      expect(CustomerConfirmDetails.fromMap(null), isNull);
      expect(CustomerConfirmDetails.fromMap('x'), isNull);
      expect(CustomerConfirmDetails.fromMap(<String, dynamic>{}), isNull);
    });
  });

  group('tugma / izoh / xato kalitlari', () {
    test('tugma matni qadamga qarab', () {
      expect(customerConfirmButtonKey(CustomerConfirmStep.handoverPickup),
          'customer_confirm_btn_handover'); // «Kuryerga berdim»
      expect(customerConfirmButtonKey(CustomerConfirmStep.handoverReturn),
          'customer_confirm_btn_received'); // «Oldim»
      expect(customerConfirmButtonKey(CustomerConfirmStep.received),
          'customer_confirm_btn_received'); // «Oldim»
      expect(customerConfirmButtonKey(CustomerConfirmStep.finalize),
          'customer_confirm_btn_confirm'); // «Tasdiqlayman»
    });

    test('noma\'lum qadam — umumiy «Tasdiqlayman»', () {
      expect(customerConfirmButtonKey('yangi_qadam'), 'customer_confirm_btn_confirm');
      expect(customerConfirmHintKey('yangi_qadam'), 'customer_confirm_hint_generic');
    });

    test('noma\'lum modul — umumiy sarlavha', () {
      expect(customerConfirmModuleKey('restaurant'), 'customer_confirm_module_restaurant');
      expect(customerConfirmModuleKey('boshqa'), 'customer_confirm_module_generic');
    });

    test('xato reason → matn kaliti; ichki kod ko\'rsatilmaydi', () {
      expect(customerConfirmErrorKey('NOT_AWAITING'), 'customer_confirm_err_not_awaiting');
      expect(customerConfirmErrorKey('NOT_YOUR_ORDER'), 'customer_confirm_err_not_yours');
      expect(customerConfirmErrorKey('STATE_CHANGED'), 'customer_confirm_err_state_changed');
      expect(customerConfirmErrorKey(''), 'customer_confirm_err_generic');
      expect(customerConfirmErrorKey('???'), 'customer_confirm_err_generic');
    });

    test('holat o\'zgargan xatolarda ro\'yxat yangilanadi', () {
      expect(customerConfirmErrorNeedsRefresh('NOT_AWAITING'), isTrue);
      expect(customerConfirmErrorNeedsRefresh('STATE_CHANGED'), isTrue);
      expect(customerConfirmErrorNeedsRefresh('NOT_YOUR_ORDER'), isTrue);
      expect(customerConfirmErrorNeedsRefresh(''), isFalse);
    });
  });

  group('CustomerConfirmResult.fromResponse', () {
    test('status va idempotent', () {
      final r = CustomerConfirmResult.fromResponse(
          {'ok': true, 'status': 'picked', 'idempotent': true});
      expect(r.status, 'picked');
      expect(r.idempotent, isTrue);
    });

    test('eski/bo\'sh javob', () {
      final r = CustomerConfirmResult.fromResponse({'ok': true});
      expect(r.status, isEmpty);
      expect(r.idempotent, isFalse);
      expect(CustomerConfirmResult.fromResponse(null).idempotent, isFalse);
    });
  });
}
