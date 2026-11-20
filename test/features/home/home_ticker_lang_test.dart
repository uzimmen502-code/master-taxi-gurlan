import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бош экран баннери 3 тилда (2026-10-26, эга: «фақат (2) тузат»).
HomeTickerAd _ad({String text = 'Тошкентга такси?', String latn = '', String ru = ''}) => HomeTickerAd(
      id: 'a', text: text, textLatn: latn, textRu: ru, audience: 'all', durationSec: 6, scrollSpeed: 45,
      animationStyle: 'auto', fontSize: 13, priority: 0, active: true,
    );

Future<void> _pump(WidgetTester t, Locale locale, HomeTickerAd ad) async {
  await t.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
      Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'),
      Locale('ru'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: SizedBox(width: 360, child: HomeInfoTicker(ads: [ad]))),
  ));
  await t.pump();
}

String _shown(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('home_banner_title')).last).data!;

void main() {
  group('HomeTickerAd.textFor', () {
    test('кирилл — асосий матн; лотин/рус киритилган бўлса ўшаси', () {
      final a = _ad(latn: 'Toşkentga taksi?', ru: 'Такси в Ташкент?');
      expect(a.textFor('uz_Cyrl'), 'Тошкентга такси?');
      expect(a.textFor('uz_Latn'), 'Toşkentga taksi?');
      expect(a.textFor('ru'), 'Такси в Ташкент?');
    });

    test('лотин бўш — кирилл автоматик ўгирилади; рус бўш — кирилл қолади; нотаниш тил — кирилл', () {
      final a = _ad(text: 'Ўз ишингизни устасимисиз?');
      expect(a.textFor('uz_Latn'), 'Öz işingizni ustasimisiz?'); // янги алифбо (эга 2026-11-19)
      expect(a.textFor('ru'), 'Ўз ишингизни устасимисиз?');
      expect(a.textFor('en'), 'Ўз ишингизни устасимисиз?');
    });

    test('сақлаш: бўш тил майдони яратишда ёзилмайди, таҳрирда ўчирилади', () {
      final created = _ad().toCreateMap();
      expect(created.containsKey('textLatn'), isFalse);
      expect(created.containsKey('textRu'), isFalse);
      final upd = _ad(ru: 'Такси?').toUpdateMap();
      expect(upd['textRu'], 'Такси?');
      expect(upd['textLatn'], isA<FieldValue>(), reason: 'бўш — FieldValue.delete()');
    });
  });

  group('Баннер илова тилида (катта ҳарфсиз — эга 2026-11-20)', () {
    final ad = _ad(latn: 'Toşkentga taksi?', ru: 'Такси в Ташкент?');
    testWidgets('uz_Cyrl', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'), ad);
      expect(_shown(t), 'Тошкентга такси?');
    });
    testWidgets('uz_Latn', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'), ad);
      expect(_shown(t), 'Toşkentga taksi?');
    });
    testWidgets('ru', (t) async {
      await _pump(t, const Locale('ru'), ad);
      expect(_shown(t), 'Такси в Ташкент?');
    });
    testWidgets('жой баландлиги 86 px ўзгармайди (ҳамён билан бир жой)', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'), ad);
      expect(t.getSize(find.byType(HomeInfoTicker)).height, 86);
    });
    testWidgets('жуда узун матн — хатосиз, жойдан чиқмайди', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 320, child: HomeInfoTicker(ads: [_ad(text: 'Б' * 400)]))),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(HomeInfoTicker)).height, 86);
    });
    testWidgets('uz_Latn, лотин киритилмаган — ўгирилган кирилл', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'), _ad());
      expect(_shown(t), 'Toşkentga taksi?');
    });
  });
}