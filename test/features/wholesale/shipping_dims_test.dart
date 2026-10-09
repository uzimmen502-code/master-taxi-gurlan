import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShippingDims / hajmiy vazn (BTS /6000, relay tariff.js bilan bir xil)', () {
    test('30×20×15 sm → 9000 sm³ → 1500 g; yaxlitlash yuqoriga', () {
      expect(const ShippingDims(l: 30, w: 20, h: 15).volumetricWeightG(), 1500);
      // 10×10×10 = 1000 sm³ → 1000×1000/6000 = 166,67 → 167 g
      expect(const ShippingDims(l: 10, w: 10, h: 10).volumetricWeightG(), 167);
      expect(const ShippingDims(l: 10, w: 10, h: 10).volumetricWeightG(divisor: 5000), 200);
    });
    test('pulli vazn = max(haqiqiy, hajmiy); o\'lchamsiz — haqiqiy', () {
      const d = ShippingDims(l: 30, w: 20, h: 15); // 1500 g
      expect(chargeableWeightG(800, d), 1500);
      expect(chargeableWeightG(2000, d), 2000);
      expect(chargeableWeightG(800, null), 800);
    });
    test('fromMap: faqat butun 1..1000; noto\'g\'ri → null', () {
      expect(ShippingDims.fromMap({'l': 30, 'w': 20, 'h': 15}), const ShippingDims(l: 30, w: 20, h: 15));
      expect(ShippingDims.fromMap({'l': 30.0, 'w': 20, 'h': 15}), const ShippingDims(l: 30, w: 20, h: 15));
      expect(ShippingDims.fromMap({'l': 0, 'w': 20, 'h': 15}), isNull);
      expect(ShippingDims.fromMap({'l': 1001, 'w': 20, 'h': 15}), isNull);
      expect(ShippingDims.fromMap({'l': 30, 'w': 20}), isNull);
      expect(ShippingDims.fromMap({'l': '30', 'w': 20, 'h': 15}), isNull);
      expect(ShippingDims.fromMap('x'), isNull);
    });
    test('parseWeightKgToGrams: vergul/nuqta, chegaralar', () {
      expect(parseWeightKgToGrams('1,25'), 1250);
      expect(parseWeightKgToGrams('1.25'), 1250);
      expect(parseWeightKgToGrams(' 0,001 '), 1);
      expect(parseWeightKgToGrams('10000'), 10000000);
      expect(parseWeightKgToGrams('10000.001'), isNull);
      expect(parseWeightKgToGrams('0'), isNull);
      expect(parseWeightKgToGrams('-1'), isNull);
      expect(parseWeightKgToGrams('abc'), isNull);
      expect(parseWeightKgToGrams(''), isNull);
    });
    test('weightKgFieldText (forma): 1250 → «1,25», 800 → «0,8», 12000 → «12», 0 → bo\'sh', () {
      expect(weightKgFieldText(1250), '1,25');
      expect(weightKgFieldText(800), '0,8');
      expect(weightKgFieldText(12000), '12');
      expect(weightKgFieldText(1), '0,001');
      expect(weightKgFieldText(0), '');
      // Aylanma: forma matni → gramm → forma matni.
      expect(parseWeightKgToGrams(weightKgFieldText(1250)), 1250);
    });
    test('formatWeightG', () {
      expect(formatWeightG(800), '800 г');
      expect(formatWeightG(1000), '1 кг');
      expect(formatWeightG(1250), '1,25 кг');
      expect(formatWeightG(1500), '1,5 кг');
      expect(formatWeightG(12345), '12,345 кг');
    });
  });

  group('WholesaleProduct — yetkazish maydonlari', () {
    WholesaleProduct p({int? w, ShippingDims? d}) => WholesaleProduct(
          id: '',
          sellerId: '998901234567',
          sellerCompanyName: 'S',
          title: 'Traktor',
          titleLower: 'traktor',
          description: 'yangi',
          priceTiers: const [PriceTier(minQty: 1, price: 3800)],
          imageUrls: const ['https://x/a.jpg'],
          unitWeightG: w,
          unitDims: d,
        );

    test('yaratish: maydon bo\'lsa yoziladi, bo\'lmasa UMUMAN yo\'q (rules hasOnly)', () {
      final m1 = p().toFirestoreCreate();
      expect(m1.containsKey('unitWeightG'), isFalse);
      expect(m1.containsKey('unitDims'), isFalse);
      final m2 = p(w: 1200, d: const ShippingDims(l: 30, w: 20, h: 15)).toFirestoreCreate();
      expect(m2['unitWeightG'], 1200);
      expect(m2['unitDims'], {'l': 30, 'w': 20, 'h': 15});
    });
    test('tahrir: olib tashlansa FieldValue.delete() (rules kalitga ruxsat beradi)', () {
      final m = p().toFirestoreOwnerUpdate();
      expect(m['unitWeightG'], FieldValue.delete());
      expect(m['unitDims'], FieldValue.delete());
      final m2 = p(w: 500).toFirestoreOwnerUpdate();
      expect(m2['unitWeightG'], 500);
      expect(m2['unitDims'], FieldValue.delete());
    });
    test('hasShippingData / unitChargeableWeightG', () {
      expect(p().hasShippingData, isFalse);
      expect(p().unitChargeableWeightG, 0);
      expect(p(w: 800, d: const ShippingDims(l: 30, w: 20, h: 15)).unitChargeableWeightG, 1500);
      expect(p(w: 2000).unitChargeableWeightG, 2000);
    });
  });

  group('WholesaleSeller — jo\'natish manzili', () {
    test('create: manzilsiz eski shakl o\'zgarmaydi; manzil bilan maydonlar qo\'shiladi', () {
      const s0 = WholesaleSeller(phone: '998901234567', companyName: 'Savdo');
      final m0 = s0.toFirestoreCreate();
      for (final k in ['regionId', 'districtId', 'address', 'lat', 'lng']) {
        expect(m0.containsKey(k), isFalse, reason: k);
      }
      expect(s0.hasShipFrom, isFalse);
      const s1 = WholesaleSeller(
        phone: '998901234567', companyName: 'Savdo',
        regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1', lat: 41.84, lng: 60.39,
      );
      final m1 = s1.toFirestoreCreate();
      expect(m1['regionId'], 'xorazm');
      expect(m1['districtId'], 'gurlan');
      expect(m1['lat'], 41.84);
      expect(s1.hasShipFrom, isTrue);
    });
    test('koordinata faqat juft bo\'lib yoziladi; update\'da yo\'q bo\'lsa o\'chiriladi', () {
      const half = WholesaleSeller(phone: '998901234567', companyName: 'S', regionId: 'r', districtId: 'd', lat: 41.0);
      expect(half.shipFromFields().containsKey('lat'), isFalse);
      final upd = half.toFirestoreShipFromUpdate();
      expect(upd['lat'], FieldValue.delete());
      expect(upd['lng'], FieldValue.delete());
      expect(upd['updatedAt'], FieldValue.serverTimestamp());
    });
  });
}
