// Меню қаторининг ЎЛЧАМЛАРИ — соф ҳисоб (2026-10-24, UI/UX қайта лойиҳа).
//
// Ўнг рўйхат `SliverFixedExtentList` (қатъий баландлик): [MenuScrollSync] ҳар бўлим offset'ини олдиндан
// ҳисоблайди. Шунинг учун қатор баландлиги бутун меню учун БИТТА, лекин «сунъий» эмас: ном 1 қаторга
// сиғса қатор ихчам, ҳеч бир таом номи 2 қаторга чиқмаса ортиқча жой ажратилмайди.
//
// Қатор тузилиши (қаранг: `restaurant_screen.dart`):
//   [расм 72]? [ном (≤2 қатор)]
//              [тавсиф (1 қатор)]
//              [нарх ........ −  n  +]
//              [миқдорга чегирма ҳинти]?  (нархнинг тагида)
// Нарх ва степпер ЯНГИ қаторда: матн кенглиги степпер ҳолатига боғлиқ эмас («сакрамайди»).

import 'package:flutter/painting.dart';

/// Баландликни ҳисоблаш учун битта таомнинг керакли қисми.
class MenuRowSample {
  const MenuRowSample({required this.name, required this.priceText, required this.hasTile});

  final String name;

  /// Тайёр нарх матни («120 000 сўм»).
  final String priceText;

  /// Қаторда расм плиткаси бор (расм ёки видео белгиси).
  final bool hasTile;
}

class MenuRowMetrics {
  const MenuRowMetrics({required this.itemHeight, required this.nameLines, required this.stackedWithTile});

  /// Бутун менюдаги битта қатор баландлиги (dp).
  final double itemHeight;

  /// Энг узун таом номи нечта қатор (1 ёки 2).
  final int nameLines;

  /// Расмли қаторда нарх ва степпер сиғмайди — степпер нархнинг ОСТИГА ўтади.
  final bool stackedWithTile;

  // ── Қатор ичидаги ўлчамлар (қатор ва ҳисоб БИР ХИЛ сонлардан фойдаланади) ──
  static const double padLeft = 12;
  static const double padRight = 8;
  static const double padTop = 10;
  static const double padBottom = 8;
  static const double tileSize = 72;
  static const double tileGap = 10;

  /// Степпер тугмасининг босиш майдони (AvaTap.minSize) ва сон ўрни.
  static const double hit = 44;
  static const double qtySlot = 24;
  static const double stepperWidth = hit + qtySlot + hit;

  static const double nameFont = 15;
  static const double nameLineHeight = 1.25;
  static const double descFont = 12;
  static const double descLineHeight = 1.3;
  static const double priceFont = 15;
  static const double tierFont = 12;

  /// Матн устуни кенглиги: [listWidth] — рўйхатнинг ўзи (рейл ҳисобга олинган).
  static double textWidth(double listWidth, {required bool hasTile}) =>
      listWidth - padLeft - padRight - (hasTile ? tileSize + tileGap : 0);

  static MenuRowMetrics compute({
    required List<MenuRowSample> items,
    required double listWidth,
    required TextScaler scaler,
    required TextDirection direction,
    required bool hasTiers,
    required bool showStepper,

    /// Амалда чизиладиган шрифт (Theme.textTheme): ўлчаш чизиш билан бир хил бўлиши шарт (қаранг: itCategoryFontSize).
    TextStyle? baseStyle,
  }) {
    final base = baseStyle ?? const TextStyle();
    double line(double size, double h) => scaler.scale(size) * h;

    // 1) Ном нечта қатор: ҳар таом ўз устун кенглигида ўлчанади.
    var nameLines = 1;
    var needStack = false;
    for (final it in items) {
      final w = textWidth(listWidth, hasTile: it.hasTile);
      if (w <= 0) continue;
      final p = TextPainter(
        text: TextSpan(
          text: it.name,
          style: base.copyWith(fontSize: nameFont, fontWeight: FontWeight.w700, height: nameLineHeight),
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: w);
      final lines = p.didExceedMaxLines ? 2 : p.computeLineMetrics().length;
      p.dispose();
      if (lines > nameLines) nameLines = lines > 2 ? 2 : lines;

      // 2) Расмли қаторда нарх + степпер бир қаторга сиғадими.
      if (showStepper && it.hasTile) {
        final pp = TextPainter(
          text: TextSpan(
            text: it.priceText,
            style: base.copyWith(fontSize: priceFont, fontWeight: FontWeight.w800),
          ),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final need = pp.width + 8 + stepperWidth;
        pp.dispose();
        if (need > w) needStack = true;
      }
    }

    final name = line(nameFont, nameLineHeight) * nameLines;
    final desc = line(descFont, descLineHeight);
    // Миқдорга чегирма ҳинти (D-REST-25) НАРХНИНГ ТАГИДА, степпердан чапда (қаторда биргаси бўлса ҳам жой ажратилади).
    final tier = hasTiers ? line(tierFont, descLineHeight) + 2 : 0.0;
    final priceLine = line(priceFont, 1.3);
    final priceBlock = priceLine + tier;
    final double bottom;
    if (!showStepper) {
      bottom = priceBlock + 6;
    } else if (needStack) {
      bottom = priceBlock + hit;
    } else {
      bottom = priceBlock > hit ? priceBlock : hit;
    }
    // +2: қирқилишдан ҳимоя (ярим пиксел яхлитлаш).
    final h = padTop + name + 2 + desc + bottom + padBottom + 2;
    return MenuRowMetrics(itemHeight: h, nameLines: nameLines, stackedWithTile: needStack);
  }
}
