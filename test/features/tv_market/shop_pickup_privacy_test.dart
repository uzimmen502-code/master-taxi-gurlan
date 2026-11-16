// Эга 2026-11-16: ўз дўкони АНИҚ олиб кетиш нуқтаси оммавий эмас — private ҳужжат + оммавий тахминий нуқта.

import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('approxShopCoord (0.005° тўр)', () {
    test('яхлитлайди, 3 хона, float шовқинисиз', () {
      expect(approxShopCoord(41.8406), 41.84);
      expect(approxShopCoord(41.8426), 41.845);
      expect(approxShopCoord(60.3917), 60.39);
      expect(approxShopCoord(60.3938), 60.395);
      expect(approxShopCoord(-12.3474), -12.345);
      expect(approxShopCoord(41.845).toString(), '41.845');
    });
    test('аниқ нуқтадан узоқлиги ≤ 0.0025°', () {
      for (final v in [41.0001, 41.0024, 41.0026, 69.2797, 55.7558]) {
        expect((approxShopCoord(v) - v).abs() <= 0.0025 + 1e-9, isTrue, reason: '$v');
      }
    });
  });

  group('TvShop.hasPickup / ShopPickup', () {
    test('тахминий нуқта ёки эски майдонлар — бор; иккаласи йўқ / 0,0 — йўқ', () {
      expect(const TvShop(ownerPhone: 'x', name: 'a', areaLat: 41.84, areaLng: 60.39).hasPickup, isTrue);
      expect(const TvShop(ownerPhone: 'x', name: 'a', pickupLat: 41.8, pickupLng: 60.3).hasPickup, isTrue);
      expect(const TvShop(ownerPhone: 'x', name: 'a').hasPickup, isFalse);
      expect(const TvShop(ownerPhone: 'x', name: 'a', areaLat: 0, areaLng: 0).hasPickup, isFalse);
    });
    test('fromMap: areaLat/areaLng/showExactLocation ўқилади, эски ҳужжатда сукут', () {
      final s = TvShop.fromMap('998901111111', {'name': 'D', 'areaLat': 41.84, 'areaLng': 60.39, 'showExactLocation': true});
      expect((s.areaLat, s.areaLng, s.showExactLocation), (41.84, 60.39, true));
      final old = TvShop.fromMap('998901111111', {'name': 'D'});
      expect((old.areaLat, old.showExactLocation), (null, false));
    });
    test('ShopPickup.fromMap: сатр/чегарадан ташқари — null', () {
      expect(ShopPickup.fromMap({'lat': 41.8, 'lng': 60.3, 'address': 'A'})!.address, 'A');
      expect(ShopPickup.fromMap({'lat': '41.8', 'lng': 60.3}), isNull);
      expect(ShopPickup.fromMap({'lat': 91, 'lng': 60.3}), isNull);
      expect(ShopPickup.fromMap(null), isNull);
    });
  });

  group('TvShopRepository.pickupWrites', () {
    test('сукут: private — аниқ; оммавий — тахминий, showExactLocation false, эски pickup* ўчирилади', () {
      final w = TvShopRepository.pickupWrites(
        ownerPhone: '998901111111', lat: 41.8406, lng: 60.3917, address: '  Gurlan bozor 7 ', showExact: false, shopExists: true,
      );
      expect(w.private['lat'], 41.8406);
      expect(w.private['lng'], 60.3917);
      expect(w.private['address'], 'Gurlan bozor 7');
      expect(w.private['updatedAt'], isA<FieldValue>());
      expect(w.private.keys.toSet(), {'lat', 'lng', 'address', 'updatedAt'}, reason: 'rules hasOnly');
      expect(w.public['areaLat'], 41.84);
      expect(w.public['areaLng'], 60.39);
      expect(w.public['showExactLocation'], false);
      for (final k in ['pickupLat', 'pickupLng', 'pickupAddress']) {
        expect(w.public[k], isA<FieldValue>(), reason: '$k ўчирилади');
      }
      expect(w.public.containsKey('lat'), isFalse, reason: 'аниқ нуқта оммавийга тушмайди');
    });
    test('«Аниқ жойимни кўрсат»: оммавий area = аниқ', () {
      final w = TvShopRepository.pickupWrites(
        ownerPhone: '998901111111', lat: 41.8406, lng: 60.3917, address: 'A', showExact: true, shopExists: true,
      );
      expect((w.public['areaLat'], w.public['areaLng'], w.public['showExactLocation']), (41.8406, 60.3917, true));
    });
    test('дўкон ҳужжати йўқ: яратиш шакли (ownerPhone, createdAt), FieldValue.delete йўқ; манзил ≤200', () {
      final w = TvShopRepository.pickupWrites(
        ownerPhone: '998901111111', lat: 41.8, lng: 60.3, address: 'x' * 250, showExact: false, shopExists: false,
      );
      expect(w.public['ownerPhone'], '998901111111');
      expect(w.public.containsKey('pickupLat'), isFalse);
      expect((w.private['address'] as String).length, 200);
    });
  });
}
