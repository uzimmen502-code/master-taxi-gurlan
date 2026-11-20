import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';
import 'home_flip_switcher.dart';
import 'home_info_ticker.dart';

/// Бош экран: ҳамён картаси ва баннер БИТТА жойда (эга, 2026-10-26: «Баннер 86 px бўлсин»).
/// Ҳамён кўринган пайтда баннер йўқ; ҳамён ёпилган заҳоти шу жойнинг ўзида баннер ағдарилиб чиқади.
/// Жой доим [height] баланд — пастдаги мазмун қимирламайди.
///
/// Ҳамён ↔ баннер алмашиш қоидаси ЎЗГАРМАГАН (эга 2026-11-20: «ҳамён — эски қоида бўйича»).
/// Админ матни бўлмаса — баннер эга берган сукут матн билан чиқади (эга 2026-11-20; аввал жой йиғиларди).
class HomeWalletTickerSlot extends StatelessWidget {
  const HomeWalletTickerSlot({
    super.key,
    required this.showWallet,
    required this.wallet,
    required this.tickerAds,
    this.onBannerCta,
  });

  final bool showWallet;
  final Widget wallet;
  final List<HomeTickerAd> tickerAds;

  /// Баннердаги «Эълон бериш →».
  final VoidCallback? onBannerCta;

  /// Ҳамён картаси ҳақиқий Inter шрифтида 86 px (тест: home_wallet_ticker_slot_test) = баннер баландлиги.
  static const height = HomeInfoTicker.height;

  @override
  Widget build(BuildContext context) {
    final Widget content = showWallet
        ? KeyedSubtree(key: const ValueKey('slot_wallet'), child: wallet)
        : HomeInfoTicker(key: const ValueKey('slot_ticker'), ads: tickerAds, onCta: onBannerCta);
    return SizedBox(
      key: const ValueKey('slot_box'),
      width: double.infinity,
      height: height,
      child: HomeFlipSwitcher(child: content),
    );
  }
}
