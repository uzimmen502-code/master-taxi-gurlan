import 'package:flutter/material.dart';

import 'ava_bottom_nav.dart';

/// Пастки менюнинг ҲАҚИҚИЙ таб навигацияси (аудит 2026-10-19, №13).
///
/// Аввал таб босилганда экран алоҳида route сифатида очиларди ва пастки
/// меню йўқолар эди (Кабинетда меню йўқ); энди «Бош» ҳамиша тирик,
/// қолган таблар (AVAGram · Хабарлар · Кабинет) унинг ўрнида кўрсатилади
/// ва меню кўриниб туради.
///
/// Қоидалар:
///  • «Бош» ИККИНЧИ таб танланганда ҲАМ ўчирилмайди ([Offstage]) — скролл
///    ҳолати, бўлимлар ва қидирув сақланади. Тикерлар тўхтатилади
///    ([TickerMode]).
///  • Қолган таблар танланганда ЯРАТИЛАДИ ва чиқиб кетилганда ЎЧИРИЛАДИ —
///    аввалги «route очиш/ёпиш»даги хатти-ҳаракатнинг айнан ўзи. Муҳими:
///    AVAGram видео лентаси ўчирилганда овоз/ижро тўхтайди (яширин тирик
///    қолмайди).
///  • Орқага (система тугмаси) — «Бош»дан бошқа табда аввал «Бош»га
///    қайтаради, «Бош»да эса иловадан чиқади.
///  • «＋» таб эмас ([AvaNavTab.create]) — у варақа очади, шу сабабли бу
///    виджетга келмайди.
class AvaTabShell extends StatelessWidget {
  const AvaTabShell({
    super.key,
    required this.current,
    required this.home,
    required this.tabBuilder,
    required this.onBackToHome,
  });

  /// Танланган таб (`create` бўлмайди).
  final AvaNavTab current;

  /// «Бош» таб мазмуни — ҳамиша тирик.
  final Widget home;

  /// «Бош»дан бошқа таб мазмуни.
  final Widget Function(BuildContext context, AvaNavTab tab) tabBuilder;

  /// «Бош»дан бошқа табда «орқага» босилганда.
  final VoidCallback onBackToHome;

  @override
  Widget build(BuildContext context) {
    final onHome = current == AvaNavTab.home;
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBackToHome();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: !onHome,
            child: TickerMode(enabled: onHome, child: home),
          ),
          if (!onHome)
            // Калит: таб алмашганда эски таб ҳолати қолмасин.
            KeyedSubtree(
              key: ValueKey(current),
              child: tabBuilder(context, current),
            ),
        ],
      ),
    );
  }
}

/// Клавиатура очиқ вақтида пастки меню яширилади: чат/қидирувда у
/// клавиатура устида туриб, жой еб қўяр эди.
bool avaNavHiddenByKeyboard(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom > 0;
