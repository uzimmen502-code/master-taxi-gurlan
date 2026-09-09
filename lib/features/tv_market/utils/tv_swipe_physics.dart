import 'package:flutter/widgets.dart';

/// Instagram Reels'дагидек — тезликсиз (секин) drag экран баландлигининг
/// [commitFraction] (default 20%) қисмидан ошса, кейинги/олдинги видеога
/// ўтади. Стандарт Flutter `PageScrollPhysics`да бу чегара ~50% (nearest
/// page rounding). Тез flick — одатдагидек, масофадан қатъи назар
/// тезлик йўналиши бўйича ишлайди (Flutter'нинг ўз ±0.5 pre-shift'и).
///
/// Чекланиш: [commitFraction] < 0.5 бўлгани учун бир pixel-based
/// формула икки йўналишни ҳам аниқ ажрата олмайди — шунинг учун
/// «қайси саҳифадан бошланган» деб eng yaqin butun sahifa (`round()`)
/// olinadi. Bitta uzluksiz drag ~50% dan ошса (жуда узун свайп, кам
/// учрайди), noto'g'ri tomonga snap qilishi mumkin — past ehtimol,
/// past ta'sir (faqat qayta svayp talab qiladi, crash emas).
class TvSwipePhysics extends ScrollPhysics {
  const TvSwipePhysics({super.parent, this.commitFraction = 0.20});

  final double commitFraction;

  @override
  TvSwipePhysics applyTo(ScrollPhysics? ancestor) {
    return TvSwipePhysics(
      parent: buildParent(ancestor),
      commitFraction: commitFraction,
    );
  }

  double _page(ScrollMetrics position) =>
      position.pixels / position.viewportDimension;

  double _pixelsForPage(ScrollMetrics position, double page) =>
      page * position.viewportDimension;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = _page(position);

    if (velocity.abs() > tolerance.velocity) {
      // Тез flick — масофадан қатъи назар, йўналиш бўйича туташ саҳифа.
      page += velocity < 0 ? -0.5 : 0.5;
      page = page.roundToDouble();
    } else {
      final nearest = page.roundToDouble();
      final displacement = page - nearest;
      page = displacement.abs() > commitFraction
          ? nearest + displacement.sign
          : nearest;
    }

    final target = _pixelsForPage(position, page)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
