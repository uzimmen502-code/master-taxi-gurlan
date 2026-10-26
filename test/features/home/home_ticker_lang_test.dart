import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    t.widget<RichText>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(RichText))).text.toPlainText();

void main() {
  group('HomeTickerAd.textFor', () {
    test('кирилл — асосий матн; лотин/рус киритилган бўлса ўшаси', () {
      final a = _ad(latn: 'Toshkentga taksi?', ru: 'Такси в Ташкент?');
      expect(a.textFor('uz_Cyrl'), 'Тошкентга такси?');
      expect(a.textFor('uz_Latn'), 'Toshkentga taksi?');
      expect(a.textFor('ru'), 'Такси в Ташкент?');
    });

    test('лотин бўш — кирилл автоматик ўгирилади; рус бўш — кирилл қолади; нотаниш тил — кирилл', () {
      final a = _ad(text: 'Ўз ишингизни устасимисиз?');
      expect(a.textFor('uz_Latn'), "o'z ishingizni ustasimisiz?");
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

  group('Баннер илова тилида', () {
    final ad = _ad(latn: 'Toshkentga taksi?', ru: 'Такси в Ташкент?');
    testWidgets('uz_Cyrl', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'), ad);
      expect(_shown(t), contains('ТОШКЕНТГА ТАКСИ?'));
    });
    testWidgets('uz_Latn', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'), ad);
      expect(_shown(t), contains('TOSHKENTGA TAKSI?'));
    });
    testWidgets('ru', (t) async {
      await _pump(t, const Locale('ru'), ad);
      expect(_shown(t), contains('ТАКСИ В ТАШКЕНТ?'));
    });
    testWidgets('матн атрофида ҳамма томонда 1 px, кўпи билан 4 қатор (эга, 2026-10-26)', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'), ad);
      final box = t.widget<Container>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(Container)).first);
      expect(box.padding, const EdgeInsets.all(1));
      expect(t.getSize(find.byType(HomeInfoTicker)).height, 86, reason: 'эга, 2026-10-26: 53 → 75 → 86 px (ҳамён билан бир жой)');
      final rt = t.widget<RichText>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(RichText)));
      expect(rt.maxLines, 4);
    });

    // Тест шрифтида ҳар ҳарф шрифт ўлчамидек кенг (ҳақиқий шрифтдан ~1.7 баробар) — пиксел сиғими телефонда
    // кўз билан текширилади; бу ерда шрифтга боғлиқ бўлмаган хоссалар.
    RenderParagraph paragraph(WidgetTester t) => t.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(RichText)));

    /// Қатор сони = баландлик / (шрифт × 1.1) — виджетдаги `height: 1.1` билан.
    int lines(WidgetTester t) {
      final rt = t.widget<RichText>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(RichText)));
      double? fs;
      rt.text.visitChildren((s) {
        fs ??= s.style?.fontSize;
        return fs == null;
      });
      return (paragraph(t).size.height / (fs! * 1.1)).round();
    }

    testWidgets('ўртача матн 2 қатордан кўп ишлатади (аввал кўпи билан 2 эди), баландлик ≤ 84 px', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 320, child: HomeInfoTicker(ads: [_ad(text: 'А' * 60)]))),
      ));
      await t.pump();
      final p = paragraph(t);
      expect(lines(t), greaterThan(2));
      expect(lines(t), lessThanOrEqualTo(4));
      expect(p.size.height, lessThanOrEqualTo(84.0));
      expect(t.takeException(), isNull);
    });

    testWidgets('жуда узун матн — хатосиз, 4 қатордан ошмайди, майдондан чиқмайди', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 320, child: HomeInfoTicker(ads: [_ad(text: 'Б' * 400)]))),
      ));
      await t.pump();
      expect(lines(t), lessThanOrEqualTo(4));
      expect(paragraph(t).size.height, lessThanOrEqualTo(84.0));
      expect(t.takeException(), isNull);
    });

    testWidgets('uz_Latn, лотин киритилмаган — ўгирилган кирилл', (t) async {
      await _pump(t, const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'), _ad());
      expect(_shown(t), contains('TOSHKENTGA TAKSI?'));
    });
  });
}
