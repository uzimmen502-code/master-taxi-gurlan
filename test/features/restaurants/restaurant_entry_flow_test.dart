import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_entry_flow.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// «＋» → «Уй ошпази бўлиш» / «Кафе-ресторан очиш» (эга, 2026-10-16): икки банд
/// битта рўйхат, фарқи — `legalType` (`individual` = уй ошпази).
void main() {
  const home = Restaurant(id: 'h1', name: 'Oshxona', legalType: 'individual');
  const home2 = Restaurant(id: 'h2', name: 'Uy somsa', legalType: 'individual');
  const cafe = Restaurant(id: 'c1', name: 'Gurlan osh', legalType: 'yatt');
  const llc = Restaurant(id: 'c2', name: 'Plov markazi', legalType: 'llc');

  group('restaurantsOfKind', () {
    const all = [home, cafe, home2, llc];

    test('уй ошпази банди фақат individual заведениеларни кўрсатади', () {
      expect(restaurantsOfKind(all, homeCook: true).map((r) => r.id), ['h1', 'h2']);
    });

    test('кафе банди фақат yatt/llc ни кўрсатади (уй ошпазиникини эмас)', () {
      expect(restaurantsOfKind(all, homeCook: false).map((r) => r.id), ['c1', 'c2']);
    });

    test('бўш рўйхат — иккиси ҳам бўш (→ рўйхатдан ўтиш экрани)', () {
      expect(restaurantsOfKind(const [], homeCook: true), isEmpty);
      expect(restaurantsOfKind(const [], homeCook: false), isEmpty);
    });

    test('фақат кафеси бор одам «Уй ошпази» босса — янги рўйхатдан ўтади (мавжуд кафега тушмайди)', () {
      expect(restaurantsOfKind(const [cafe], homeCook: true), isEmpty);
    });
  });

  group('RestaurantFormData юридик шакллар', () {
    test('кафе танлови individual ни ўз ичига ОЛМАЙДИ', () {
      expect(RestaurantFormData.cafeLegalTypes, ['yatt', 'llc']);
      expect(RestaurantFormData.cafeLegalTypes, isNot(contains('individual')));
    });

    test('уй ошпази ва кафе шакллари биргаликда сервер рўйхатини тўлиқ беради', () {
      expect(
        {...RestaurantFormData.cafeLegalTypes, RestaurantFormData.homeCookLegalType},
        RestaurantFormData.legalTypes.toSet(),
      );
    });

    test('уй ошпази payload да legalType=individual, кафе — yatt (бошланғич)', () {
      final h = RestaurantFormData(
        legalType: RestaurantFormData.homeCookLegalType,
        name: 'Oshxona',
        address: 'Markaz',
        lat: 41.8,
        lng: 60.4,
      );
      expect(h.validate(), isEmpty);
      expect(h.toRegisterPayload()['legalType'], 'individual');
      final c = RestaurantFormData(
        legalType: RestaurantFormData.cafeLegalTypes.first,
        name: 'Gurlan osh',
        address: 'Markaz',
        lat: 41.8,
        lng: 60.4,
      );
      expect(c.validate(), isEmpty);
      expect(c.toRegisterPayload()['legalType'], 'yatt');
    });

    test('Restaurant.isHomeCook ва банд мантиғи битта манбадан', () {
      expect(home.isHomeCook, isTrue);
      expect(cafe.isHomeCook, isFalse);
      expect(llc.isHomeCook, isFalse);
    });
  });
}
