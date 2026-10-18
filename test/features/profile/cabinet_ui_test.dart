import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/profile/widgets/cabinet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кабинет UI бўлаклари (2026-10-18 қайта лойиҳа): Firebase'сиз, фақат кўриниш.
Widget _host(Widget child, {double width = 360, double textScale = 1}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('CabinetWalletCard', () {
    testWidgets('баланс маълум — сумма чиқади ва босилади', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(CabinetWalletCard(
        title: 'Ҳамён',
        balanceText: '150 000 сўм',
        hint: 'Баланс ва тўлдириш',
        actionLabel: 'Тўлдириш',
        onTap: () => taps++,
      )));
      expect(find.text('150 000 сўм'), findsOneWidget);
      expect(find.text('Баланс ва тўлдириш'), findsNothing);
      await tester.tap(find.text('Тўлдириш'));
      await tester.tap(find.text('150 000 сўм'));
      expect(taps, 2, reason: 'тугма ҲАМ, карточка ҲАМ ҳамённи очади');
    });

    testWidgets('баланс номаълум — ёлғон «0» йўқ, изоҳ чиқади', (tester) async {
      await tester.pumpWidget(_host(CabinetWalletCard(
        title: 'Ҳамён',
        balanceText: null,
        hint: 'Баланс ва тўлдириш',
        actionLabel: 'Тўлдириш',
        onTap: () {},
      )));
      expect(find.text('Баланс ва тўлдириш'), findsOneWidget);
      expect(find.textContaining('0'), findsNothing);
    });

    // REGRESSION (қурилмада, 2026-10-19): катта шрифтда баланс «19 562 …»
    // бўлиб қирқилган эди. Энди сумма тўлиқ ва карточка ичида қолади.
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('баланс тўлиқ кўринади (320 px, шрифт ×$scale): қирқилмайди, чиқиб кетмайди',
          (tester) async {
        await tester.pumpWidget(_host(
          CabinetWalletCard(
            title: 'Кошелёк',
            balanceText: '19 562 000 сўм',
            hint: 'x',
            actionLabel: 'Пополнить',
            onTap: () {},
          ),
          width: 320,
          textScale: scale,
        ));
        expect(tester.takeException(), isNull);
        final text = find.text('19 562 000 сўм');
        expect(text, findsOneWidget);
        // «…» ишлатилмайди: Text'да ellipsis йўқ.
        expect(tester.widget<Text>(text).overflow, isNot(TextOverflow.ellipsis));
        // FittedBox ичида ва ўнг чегарадан ошмайди (масштаб ҳисобга олинган).
        expect(find.ancestor(of: text, matching: find.byType(FittedBox)), findsOneWidget);
        final card = tester.getRect(find.byType(CabinetWalletCard));
        expect(tester.getRect(text).right, lessThanOrEqualTo(card.right));
      });
    }

    testWidgets('«Тўлдириш» тугмаси ихчам, катта шрифтда ҳам ўсмайди; сумма кўп жой олади',
        (tester) async {
      Future<Size> pillSize(double scale) async {
        await tester.pumpWidget(_host(
          CabinetWalletCard(
            title: 'Кошелёк',
            balanceText: '19 562 000 сўм',
            hint: 'x',
            actionLabel: 'Пополнить',
            onTap: () {},
          ),
          width: 360,
          textScale: scale,
        ));
        return tester.getSize(find
            .ancestor(of: find.text('Пополнить'), matching: find.byType(Container))
            .first);
      }

      final normal = await pillSize(1.0);
      final big = await pillSize(2.0);
      expect(normal.height, lessThanOrEqualTo(36), reason: 'ихчам (аввал 44+)');
      expect(big, normal, reason: 'шрифт ×2 да ҳам тугма ўсмайди');
    });

    testWidgets('семантика: битта тугма, баланс ёрлиқда', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(CabinetWalletCard(
        title: 'Ҳамён',
        balanceText: '5 000 сўм',
        hint: 'x',
        actionLabel: 'Тўлдириш',
        onTap: () {},
      )));
      expect(find.bySemanticsLabel('Ҳамён 5 000 сўм'), findsOneWidget);
      handle.dispose();
    });
  });

  group('CabinetSection / CabinetRow', () {
    testWidgets('сарлавҳа, қаторлар ва улар орасида ажратгич (n-1)', (tester) async {
      await tester.pumpWidget(_host(CabinetSection(title: 'Фаолият', children: [
        CabinetRow(icon: Icons.person, title: 'Бир', onTap: () {}),
        CabinetRow(icon: Icons.person, title: 'Икки', subtitle: 'изоҳ', onTap: () {}),
        CabinetRow(icon: Icons.logout, title: 'Уч', danger: true, showChevron: false, onTap: () {}),
      ])));
      expect(find.text('Фаолият'), findsOneWidget);
      expect(find.byType(CabinetRow), findsNWidgets(3));
      expect(find.byType(Divider), findsNWidgets(2));
      expect(find.text('изоҳ'), findsOneWidget);
      // Фақат биринчи ва иккинчи қаторда `›` бор.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    });

    testWidgets('қатор босилади; хавфли қатор хато рангида', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(CabinetSection(title: 'Илова', children: [
        CabinetRow(icon: Icons.logout, title: 'Чиқиш', danger: true, showChevron: false, onTap: () => taps++),
      ])));
      await tester.tap(find.text('Чиқиш'));
      expect(taps, 1);
      final text = tester.widget<Text>(find.text('Чиқиш'));
      expect(text.style!.color, AvaLight.danger);
    });

    testWidgets('минимал баландлик 44дан катта (босиш қулайлиги)', (tester) async {
      await tester.pumpWidget(_host(CabinetSection(title: 'x', children: [
        CabinetRow(icon: Icons.person, title: 'Бир', onTap: () {}),
      ])));
      expect(tester.getSize(find.byType(CabinetRow)).height, greaterThanOrEqualTo(AvaTap.minSize));
    });
  });

  group('CabinetHeader', () {
    testWidgets('аватар ва роль чипи босилади; телефон бўш бўлса қатор йўқ', (tester) async {
      var avatar = 0, role = 0;
      await tester.pumpWidget(_host(CabinetHeader(
        avatar: const Center(child: Text('А')),
        title: 'жаноб Али',
        roleLabel: 'Фойдаланувчи',
        changePhotoLabel: 'Расм',
        onAvatarTap: () => avatar++,
        onRoleTap: () => role++,
      )));
      await tester.tap(find.text('А'));
      await tester.tap(find.text('Фойдаланувчи'));
      expect(avatar, 1);
      expect(role, 1);
      expect(find.text('+998901234567'), findsNothing);
    });

    testWidgets('жуда узун исм 2 қаторга қирқилади', (tester) async {
      await tester.pumpWidget(_host(CabinetHeader(
        avatar: const SizedBox(),
        title: 'жаноб ${'Узунисм' * 30}',
        phone: '+998901234567',
        roleLabel: 'Фойдаланувчи',
        changePhotoLabel: 'Расм',
        onAvatarTap: () {},
      )));
      expect(tester.takeException(), isNull);
      expect(find.text('+998901234567'), findsOneWidget);
    });
  });

  group('чекка ҳолатлар', () {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('320 px кенглик, матн ×$scale — overflow йўқ', (tester) async {
        await tester.pumpWidget(_host(
          Column(children: [
            CabinetHeader(
              avatar: const SizedBox(),
              title: 'жаноб Муҳаммаджонов Абдурахмонбек',
              phone: '+998901234567',
              roleLabel: '🛵 Курьер',
              changePhotoLabel: 'Расм',
              onAvatarTap: () {},
            ),
            CabinetWalletCard(
              title: 'Ҳамён',
              balanceText: '12 345 678 сўм',
              hint: 'Баланс ва тўлдириш',
              actionLabel: 'Тўлдириш',
              onTap: () {},
            ),
            CabinetNotice(
              text: 'Курьер буюртмангизни етказиб беришин учун яшаш манзилингизни киритинг',
              actionLabel: 'Тўлдириш',
              onAction: () {},
            ),
            CabinetSection(title: 'Ҳисоб', children: [
              CabinetRow(
                icon: Icons.person,
                title: 'Фойдаланувчи маълумотлари',
                subtitle: 'Хоразм вилояти, Гурлан тумани, Бирлашган маҳалласи, 12-уй, 3-хонадон',
                onTap: () {},
              ),
            ]),
          ]),
          width: 320,
          textScale: scale,
        ));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('баннер: тугма босилади', (tester) async {
      var n = 0;
      await tester.pumpWidget(_host(CabinetNotice(text: 'Манзил', actionLabel: 'Тўлдириш', onAction: () => n++)));
      await tester.tap(find.text('Тўлдириш'));
      expect(n, 1);
    });
  });

  group('l10n', () {
    // Кабинет янги калитлари учала тилда бўлиши шарт (уч тил қоидаси).
    const keys = [
      'cab_topup',
      'cab_sec_account',
      'cab_sec_activity',
      'cab_sec_app',
      'cab_seller_panel',
      'home_nav_cabinet',
      'profile_demand_offer_hint',
    ];
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      test('$lang — барча калит бор ва бўш эмас', () {
        final map = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final k in keys) {
          expect((map[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$k yo\'q: $lang');
        }
      });
    }
  });
}
