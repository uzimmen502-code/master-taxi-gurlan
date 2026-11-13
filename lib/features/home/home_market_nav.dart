import 'dart:async';

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

/// Аралаш бозор рўйхатидан БОШҚА бозор маҳсулоти (Улгуржи / Хитой) очилганда
/// (эга, 2026-11-13): Аралаш экрани стекдан олинади, ўрнига ўша бозор экрани
/// қўйилади, тафсилот унинг устида очилади.
///
/// Стек: `Асосий → Бозор → Тафсилот`. Орқага: тафсилот → бозор → асосий экран
/// (эга: «Улгуржи бозорда яна орқага — асосий экранга»). [nav] — олдиндан
/// олинган навигатор: Аралаш экрани ёпилгач унинг `context`и ишламайди.
Future<void> openDetailOverOtherMarket(
  NavigatorState nav, {
  required Widget market,
  required Route<void> detail,
}) async {
  unawaited(nav.pushAndRemoveUntil<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => market,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 280),
    ),
    (r) => r.isFirst,
  ));
  await nav.push<void>(detail);
}
