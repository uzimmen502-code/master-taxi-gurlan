import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/features/home/widgets/home_wallet_ticker_slot.dart';
import 'package:ava_gurlan/features/home/widgets/wallet_card.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бош экран: ҳамён ва сариқ баннер битта 86 px жойда, алмашганда пастдаги мазмун қимирламайди
/// (эга, 2026-10-26: «текшир ва бажар», «Баннер 86 px бўлсин»).
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

const _wallet = WalletCard(
  key: ValueKey('wallet'),
  balanceAmount: '19 562', balanceCurrency: 'сўм', lastTxAmount: '—',
  displayName: 'Азиз Каримов', dateText: 'Бугун: 26.10.2026', locationText: 'Гурлан',
);

HomeTickerAd _ad(String id) => HomeTickerAd(
      id: id, text: 'Такси керакми? Илова орқали чақиринг.', audience: 'all', durationSec: 6, scrollSpeed: 45,
      animationStyle: 'auto', fontSize: 13, priority: 0, active: true,
    );

Widget _screen({required bool showWallet, List<HomeTickerAd>? ads, bool reduceMotion = false}) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(375, 812), disableAnimations: reduceMotion),
        child: Scaffold(
          body: SizedBox(
            width: 343,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeWalletTickerSlot(showWallet: showWallet, wallet: _wallet, tickerAds: ads ?? [_ad('a'), _ad('b')]),
                const SizedBox(height: 2),
                const Text('Барча хизматлар', key: ValueKey('below')),
              ],
            ),
          ),
        ),
      ),
    );

double _belowY(WidgetTester t) => t.getTopLeft(find.byKey(const ValueKey('below'))).dy;

void main() {
  testWidgets('ҳамён картаси ҳақиқий Inter шрифтида жойга сиғади (86 px) ва баннер ҳам 86 px', (t) async {
    await _loadInter();
    for (final w in [288.0, 343.0, 380.0]) {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: SizedBox(width: w, child: const Column(mainAxisSize: MainAxisSize.min, children: [_wallet])))),
      ));
      final h = t.getSize(find.byKey(const ValueKey('wallet'))).height;
      expect(h, lessThanOrEqualTo(HomeWalletTickerSlot.height), reason: 'эни $w: ҳамён $h px — жойдан баланд бўлса пасти қирқилади');
      expect(h, greaterThan(HomeWalletTickerSlot.height - 2), reason: 'ҳамён ва баннер баландлиги бир хил бўлсин');
    }
    expect(HomeInfoTicker.height, 86);
    expect(HomeWalletTickerSlot.height, HomeInfoTicker.height);
  });

  testWidgets('ҳамён → баннер: жой 86 px қолади, пастдаги мазмун қимирламайди; ағдарилишдан кейин фақат баннер', (t) async {
    await t.pumpWidget(_screen(showWallet: true));
    expect(t.getSize(find.byType(HomeWalletTickerSlot)).height, 86);
    expect(find.byType(HomeInfoTicker), findsNothing, reason: 'ҳамён кўринганда баннер йўқ');
    final y0 = _belowY(t);

    await t.pumpWidget(_screen(showWallet: false));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
      expect(_belowY(t), y0, reason: 'ағдарилиш пайтида ҳам пастдаги мазмун ўрнида');
      expect(t.getSize(find.byType(HomeWalletTickerSlot)).height, 86);
    }
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('wallet')), findsNothing);
    expect(find.byType(HomeInfoTicker), findsOneWidget);
    expect(_belowY(t), y0);

    // Кабинетдан қайтганда ҳамён яна шу жойда.
    await t.pumpWidget(_screen(showWallet: true));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('wallet')), findsOneWidget);
    expect(find.byType(HomeInfoTicker), findsNothing);
    expect(_belowY(t), y0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('баннер матни йўқ — ҳамён ёпилгач жой йиғилади', (t) async {
    await t.pumpWidget(_screen(showWallet: true, ads: const []));
    await t.pumpWidget(_screen(showWallet: false, ads: const []));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.getSize(find.byType(HomeWalletTickerSlot)).height, 0);
  });

  testWidgets('«анимацияни камайтириш» ёқилган — дарров алмашади', (t) async {
    await t.pumpWidget(_screen(showWallet: true, reduceMotion: true));
    await t.pumpWidget(_screen(showWallet: false, reduceMotion: true));
    await t.pump();
    expect(find.byKey(const ValueKey('wallet')), findsNothing);
    expect(find.byType(HomeInfoTicker), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
