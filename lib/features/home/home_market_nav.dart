import 'package:flutter/material.dart';

/// Асосий экрандаги бозор бўлимидан (Аҳоли / Улгуржи / Хитой) маҳсулот
/// очиш: тафсилот остида ТЕГИШЛИ БОЗОР экрани туради, шунинг учун орқага
/// стрелка бозорга қайтаради, асосий экранга эмас (эга талаби, 2026-10-31).
///
/// Стек: `Асосий → Бозор → Тафсилот`. Бозор экрани анимациясиз қўйилади
/// (фойдаланувчи уни кўрмайди), тафсилот [openDetail] орқали одатдагидек
/// очилади. Қайтиш: бозор ёпилгунча кутади.
Future<void> pushDetailOverMarket(
  BuildContext context, {
  required Widget market,
  required Future<void> Function() openDetail,
  Duration reverse = const Duration(milliseconds: 280),
}) async {
  final marketClosed = Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => market,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: reverse,
    ),
  );
  await openDetail();
  await marketClosed;
}
