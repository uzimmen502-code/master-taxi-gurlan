import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Бир блокни иккинчисига 3D ағдарилиш (X ўқи атрофида) билан алмаштиради — сариқ баннер матнлари ва
/// бош экрандаги «ҳамён → баннер» жойи (эга, 2026-10-26) бир хил эффектда бўлсин деб битта жойда.
///
/// [child] нинг `key` и ўзгарганда алмашади. Иккита блок бир вақтда кўринмайди: биринчи ярмида эскиси
/// ағдарилиб йўқолади, иккинчи ярмида янгиси ағдарилиб киради. Тизимда «анимацияни камайтириш»
/// ёқилган бўлса — дарров алмашади.
class HomeFlipSwitcher extends StatelessWidget {
  const HomeFlipSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 550),
  });

  final Widget child;
  final Duration duration;

  /// Аввал `HomeInfoTicker._flipTransition` эди. У ерда кирувчи/чиқувчи иккита тармоқ бор эди, лекин
  /// AnimatedSwitcher ўтишни бола ПАЙДО бўлганда бир марта қуради (method tear-off'лар тенг — қайта
  /// қурилмайди), шунинг учун амалда доим «кирувчи» тармоғи ишларди; чиқувчиси эса шу ўтишни тескари
  /// ўйнайди. Жонлидаги кўриниш айнан шу — ўзгаришсиз сақланди, ишламайдиган тармоқ олиб ташланди.
  static Widget flipTransition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        final t = ((v - 0.5) / 0.5).clamp(0.0, 1.0);
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateX((1 - t) * (-math.pi / 2));
        return Opacity(
          opacity: v >= 0.5 ? 1 : 0,
          child: Transform(alignment: Alignment.center, transform: transform, child: child),
        );
      },
    );
  }

  static Widget _stack(Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: flipTransition,
      layoutBuilder: _stack,
      child: child,
    );
  }
}
