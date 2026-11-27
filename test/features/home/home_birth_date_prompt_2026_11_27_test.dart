// Эга 2026-11-27: туғилган санаси йўқ фойдаланувчига бош саҳифа «Эълон ва хизматлар» бўлими бошида
// «Туғилган кунингизни киритинг» карточкаси; босилса — профилдаги мавжуд таҳрир экрани (UserInfoScreen).
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lang(String l) =>
    jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;

bool _all(String _) => true;

void main() {
  group('birthDatePromptVisibleFor', () {
    test('сана йўқ/бўш — кўринади', () {
      expect(birthDatePromptVisibleFor(hasUser: true, phoneDigits: '998901234567', birthDate: ''), isTrue);
      expect(birthDatePromptVisibleFor(hasUser: true, phoneDigits: '998901234567', birthDate: '   '), isTrue);
      expect(birthDatePromptVisibleFor(hasUser: true, phoneDigits: '901234567', birthDate: null), isTrue);
    });
    test('сана бор — йўқ', () {
      expect(birthDatePromptVisibleFor(hasUser: true, phoneDigits: '998901234567', birthDate: '1990-05-01'), isFalse);
    });
    test('ҳужжат юкланмаган ёки телефонсиз (меҳмон) — йўқ', () {
      expect(birthDatePromptVisibleFor(hasUser: false, phoneDigits: '998901234567', birthDate: ''), isFalse);
      expect(birthDatePromptVisibleFor(hasUser: true, phoneDigits: '', birthDate: ''), isFalse);
      expect(birthDatePromptVisibleFor(hasUser: true, phoneDigits: '12345678', birthDate: ''), isFalse);
    });
  });

  group('«Эълон ва хизматлар» тартиби', () {
    // Эга 2026-11-28: «Пул ўтказмалари»дан кейин, «Яқинларингиз…»дан олдин (аввал бўлим бошида эди).
    test('кўринса — Пул ўтказмаларидан кейин, Яқинлар карточкасидан олдин', () {
      final ids = homeAdsServicesCardIds(
        isVisible: _all,
        viewerBirthDate: '',
        restaurantsAllowed: false,
        holidayVisible: true,
        relativesPromptVisible: true,
        birthDatePromptVisible: true,
      );
      expect(ids.indexOf('birth_date'), ids.indexOf('pay') + 1);
      expect(ids.last, 'relatives_bday');
      expect(ids.where((e) => e == 'birth_date').length, 1);
      expect(ids.contains('holiday'), isFalse);
    });
    test('кўринмаса — карточка йўқ (сукут ҳам)', () {
      expect(
        homeAdsServicesCardIds(isVisible: _all, viewerBirthDate: '1990-01-01', restaurantsAllowed: false)
            .contains('birth_date'),
        isFalse,
      );
      expect(
        homeAdsServicesCardIds(
          isVisible: _all,
          viewerBirthDate: '1990-01-01',
          restaurantsAllowed: false,
          birthDatePromptVisible: false,
        ).contains('birth_date'),
        isFalse,
      );
    });
  });

  test('home_screen: карточка мавжуд таҳрир экранини очади, ягона қоида ишлатилади', () {
    final src = File('lib/features/home/home_screen.dart').readAsStringSync();
    final i = src.indexOf("'birth_date' => HomeLiteCardData(");
    expect(i, greaterThan(0));
    final card = src.substring(i, src.indexOf("'relatives_bday' =>", i));
    expect(card.contains("context.tr('home_lite_birth_title')"), isTrue);
    expect(card.contains("context.tr('home_lite_birth_caption')"), isTrue);
    expect(card.contains('onTap: () => openUserInfoScreen(context)'), isTrue);
    expect(src.contains('birthDatePromptVisible: birthDatePromptVisibleFor('), isTrue);
    final ui = File('lib/features/profile/screens/user_info_screen.dart').readAsStringSync();
    expect(ui.contains('Future<void> openUserInfoScreen(BuildContext context)'), isTrue);
    expect(ui.contains('saveBirthDateOrRequest'), isTrue);
  });

  testWidgets('карточка чизилади ва босилади', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeLiteSection(
          title: 'x',
          cards: [
            HomeLiteCardData(
              id: 'birth_date',
              title: 'Туғилган кунингизни киритинг',
              caption: 'Танишув, туғилган кун саватчаси, совға ва бонуслар очилади',
              icon: Icons.cake_rounded,
              fit: HomeLiteImageFit.contain,
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('home_lite_card_birth_date')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('home_lite_card_birth_date')));
    expect(taps, 1);
  });

  test('матн 3 тилда (uz_Latn — янги алифбо)', () {
    expect(_lang('uz_Cyrl')['home_lite_birth_title'], 'Туғилган кунингизни киритинг');
    expect(_lang('uz_Cyrl')['home_lite_birth_caption'], 'Танишув, туғилган кун саватчаси, совға ва бонуслар очилади');
    expect(_lang('uz_Latn')['home_lite_birth_title'], 'Tuğilgan kuningizni kiriting');
    expect(_lang('uz_Latn')['home_lite_birth_caption'], 'Tanişuv, tuğilgan kun savatçasi, sovğa va bonuslar oçiladi');
    expect(_lang('ru')['home_lite_birth_title'], 'Укажите дату рождения');
    expect(_lang('ru')['home_lite_birth_caption'], 'Откроются знакомства, корзина ко дню рождения, подарки и бонусы');
  });
}
