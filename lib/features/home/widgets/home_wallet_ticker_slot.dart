import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';
import 'home_flip_switcher.dart';
import 'home_info_ticker.dart';

/// Бош экран: ҳамён картаси ва сариқ баннер БИТТА жойда (эга, 2026-10-26: «текшир ва бажар», «Баннер 86 px
/// бўлсин»). Ҳамён кўринган пайтда баннер йўқ; ҳамён ёпилган заҳоти шу жойнинг ўзида баннер ағдарилиб чиқади.
/// Жой доим [height] баланд — пастдаги мазмун қимирламайди (аввал ҳамён йиғилганда ~92–96 px юқорига сакрарди).
///
/// Баннер матни бўлмаса (ҳаммаси нофаол) — ҳамён ёпилгач жой йиғилади.
class HomeWalletTickerSlot extends StatelessWidget {
  const HomeWalletTickerSlot({
    super.key,
    required this.showWallet,
    required this.wallet,
    required this.tickerAds,
  });

  final bool showWallet;
  final Widget wallet;
  final List<HomeTickerAd> tickerAds;

  /// Ҳамён картаси ҳақиқий Inter шрифтида 86 px (тест: home_wallet_ticker_slot_test) = баннер баландлиги.
  static const height = HomeInfoTicker.height;

  @override
  Widget build(BuildContext context) {
    final Widget? content = showWallet
        ? KeyedSubtree(key: const ValueKey('slot_wallet'), child: wallet)
        : tickerAds.isEmpty
            ? null
            : HomeInfoTicker(key: const ValueKey('slot_ticker'), ads: tickerAds);
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: content == null
          ? const SizedBox(key: ValueKey('slot_empty'), width: double.infinity)
          : SizedBox(
              key: const ValueKey('slot_box'),
              width: double.infinity,
              height: height,
              child: HomeFlipSwitcher(child: content),
            ),
    );
  }
}
