import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_labels.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p({String unit = kWholesaleDefaultUnit, int tiers = 2}) =>
    WholesaleProduct(
      id: 'p',
      sellerId: 's',
      sellerCompanyName: 'Firma',
      title: 'Tomato',
      titleLower: 'tomato',
      description: '',
      unit: unit,
      priceTiers: [
        const WholesalePriceTier(minQty: 1, price: 14000),
        if (tiers > 1) const WholesalePriceTier(minQty: 10, price: 12000),
      ],
    );

void main() {
  group('wholesaleUnitLabel / wholesalePriceLine (delegatsiz test: tr kalitni qaytaradi)', () {
    testWidgets('tarjima topilmasa xom bazaviy qiymat qaytadi (xatosiz)', (tester) async {
      late String unit;
      late String line;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          unit = wholesaleUnitLabel(context, kWholesaleDefaultUnit);
          line = wholesalePriceLine(context, _p());
          return const SizedBox();
        }),
      ));
      // `piece` / `home_price_from` tarjimasi bo'lmagan testda eski ko'rinish saqlanadi.
      expect(unit, kWholesaleDefaultUnit);
      expect(line, _p().priceLine);
    });

    testWidgets('sotuvchi o\'zi yozgan birlik o\'zgarmaydi', (tester) async {
      late String unit;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          unit = wholesaleUnitLabel(context, 'quti');
          return const SizedBox();
        }),
      ));
      expect(unit, 'quti');
    });

    testWidgets('bitta pog\'onada "dan" prefiksi yo\'q', (tester) async {
      late String line;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          line = wholesalePriceLine(context, _p(tiers: 1));
          return const SizedBox();
        }),
      ));
      expect(line, _p(tiers: 1).priceLine);
      expect(line.startsWith('home_price_from'), isFalse);
    });
  });

  group('WholesaleSeller.toFirestoreResubmit - Rules whitelist (wholesaleSellerResubmitOk)', () {
    const allowed = {
      'approvalStatus', 'companyName', 'ownerName', 'sellerType', 'updatedAt',
      'regionId', 'districtId', 'address', 'lat', 'lng',
    };
    const seller = WholesaleSeller(
      phone: '998901000011',
      companyName: '  Gurlan Savdo ',
      ownerName: ' Ali ',
      sellerType: WholesaleSeller.typeWholesaler,
      approvalStatus: WholesaleSeller.statusRejected,
      adminNote: 'sabab',
      approvedBy: 'admin',
      regionId: 'xorazm',
      districtId: 'gurlan',
      address: ' Markaz 1 ',
      lat: 41.8,
      lng: 60.4,
    );

    test('faqat ruxsat etilgan kalitlar, holat HAR DOIM pending', () {
      final m = seller.toFirestoreResubmit();
      expect(m.keys.toSet().difference(allowed), isEmpty);
      expect(m['approvalStatus'], WholesaleSeller.statusPending);
      expect(m['updatedAt'], FieldValue.serverTimestamp());
    });

    test('admin maydonlariga tegilmaydi (adminNote/approvedAt/approvedBy/phone yuborilmaydi)', () {
      final m = seller.toFirestoreResubmit();
      for (final k in ['adminNote', 'approvedAt', 'approvedBy', 'phone', 'createdAt']) {
        expect(m.containsKey(k), isFalse, reason: k);
      }
    });

    test('matn maydonlari trim qilinadi, koordinata ikkalasi birga', () {
      final m = seller.toFirestoreResubmit();
      expect(m['companyName'], 'Gurlan Savdo');
      expect(m['ownerName'], 'Ali');
      expect(m['address'], 'Markaz 1');
      expect(m['lat'], 41.8);
      expect(m['lng'], 60.4);
    });

    test('rad etilgan sotuvchi qayta yuborganda holat o\'zgartirilmaydi, "approved" hech qachon', () {
      const approvedLike = WholesaleSeller(
        phone: '998901000011',
        companyName: 'X Savdo',
        approvalStatus: WholesaleSeller.statusApproved,
      );
      // Model qaysi holatda bo'lishidan qat'i nazar, yuboriladigan holat faqat pending.
      expect(approvedLike.toFirestoreResubmit()['approvalStatus'], WholesaleSeller.statusPending);
    });
  });
}
