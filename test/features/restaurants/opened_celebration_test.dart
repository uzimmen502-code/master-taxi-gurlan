import 'dart:math' as math;

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/restaurants/merchant/opened_celebration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга, 2026-10-31: кафе/уй ошпази очилганда табрик — «Б» (конфетти).
/// Локализация делегати уланмаган: `context.tr` калитнинг ўзини қайтаради.
Future<void> _open(WidgetTester t, {required bool homeCook, bool reduceMotion = false}) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    // Тизим созламаси бутун иловага (диалог ҳам навигатор устида) — builder даражасида.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showOpenedCelebration(context, homeCook: homeCook),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('кафе: сарлавҳа, изоҳ, «Панелга ўтиш»; конфетти бор', (t) async {
    await _open(t, homeCook: false);
    expect(find.text('restaurants_m_submitted_approved'), findsOneWidget);
    expect(find.text('restaurants_m_opened_sub'), findsOneWidget);
    expect(find.text('restaurants_m_opened_go_panel'), findsOneWidget);
    expect(find.byKey(const ValueKey('opened_confetti')), findsOneWidget);
    await t.pumpAndSettle();
  });

  testWidgets('уй ошпази: «Ошхонангиз очилди!» калити', (t) async {
    await _open(t, homeCook: true);
    expect(find.text('restaurants_m_submitted_approved_home_cook'), findsOneWidget);
    await t.pumpAndSettle();
  });

  testWidgets('«Панелга ўтиш» — ойна ёпилади (кейин чақирувчи панелни очади)', (t) async {
    await _open(t, homeCook: false);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('opened_go_panel')));
    await t.pumpAndSettle();
    expect(find.text('restaurants_m_opened_go_panel'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('карта анимациядан кейин ҳам туради (ўзи ёпилмайди)', (t) async {
    await _open(t, homeCook: false);
    await t.pump(ConfettiPainter.duration + const Duration(seconds: 2));
    expect(find.text('restaurants_m_opened_go_panel'), findsOneWidget);
  });

  testWidgets('«анимацияни камайтириш» ёқиқ — конфеттисиз, фақат карта', (t) async {
    await _open(t, homeCook: false, reduceMotion: true);
    expect(find.byKey(const ValueKey('opened_confetti')), findsNothing);
    expect(find.text('restaurants_m_submitted_approved'), findsOneWidget);
  });

  group('ConfettiPainter (соф ҳисоб)', () {
    final ps = ConfettiPainter.burst(math.Random(7));
    const size = Size(400, 800);

    test('икки бурчакдан 70 тадан, тепага отилади', () {
      expect(ps.where((p) => p.fromLeft).length, 70);
      expect(ps.where((p) => !p.fromLeft).length, 70);
      expect(ps.every((p) => p.vy < 0), isTrue, reason: 'бошида юқорига');
      expect(ps.where((p) => p.fromLeft).every((p) => p.vx > 0), isTrue, reason: 'чапдан ўнгга');
      expect(ps.where((p) => !p.fromLeft).every((p) => p.vx < 0), isTrue, reason: 'ўнгдан чапга');
    });

    test('оғирлик: аввал кўтарилади, кейин тушади (чегара: 0-кадрда бурчакда)', () {
      final p = ps.first;
      expect(ConfettiPainter.positionAt(p, 0, size), const Offset(10, 780));
      final up = ConfettiPainter.positionAt(p, 20, size);
      final down = ConfettiPainter.positionAt(p, 190, size);
      expect(up.dy, lessThan(780));
      expect(down.dy, greaterThan(up.dy));
    });

    test('t=0 ва t=1 — ҳеч нарса чизилмайди; shouldRepaint вақт ўзгарса', () {
      final a = ConfettiPainter(ps, 0);
      expect(a.shouldRepaint(ConfettiPainter(ps, 0.5)), isTrue);
      expect(a.shouldRepaint(ConfettiPainter(ps, 0)), isFalse);
    });
  });
}
