import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/home_ticker_ad.dart';
import 'home_ticker_bar.dart';

/// Firestore ticker — yashil shell ichida.
class HomeTickerShell extends StatelessWidget {
  const HomeTickerShell({super.key, required this.ads});

  final List<HomeTickerAd> ads;

  @override
  Widget build(BuildContext context) {
    if (ads.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.tickerShell,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0E7A38),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: HomeTickerBar(ads: ads),
        ),
      ),
    );
  }
}
