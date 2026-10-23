import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_charging_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lang(String code) =>
    jsonDecode(File('assets/lang/$code.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  testWidgets('меҳмон экрани: хабар, сарлавҳа ва тугма калитлари (3 тилли матнга боғланган)', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const EvChargingAnonymousGate()));
    // Локализация делегати уланмаган: `context.tr` калитнинг ўзини қайтаради.
    expect(find.text('ev_guest_gate_message'), findsOneWidget);
    expect(find.text('⚡ ev_guest_gate_title'), findsOneWidget);
    expect(find.text('ev_guest_gate_register'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  test('эга матни uz_Cyrl / uz_Latn / ru да аниқ шундай (2026-10-23)', () {
    expect(_lang('uz_Cyrl')['ev_guest_gate_message'], 'EV станциялари базасини кўриш учун рўйхатдан ўтинг');
    expect(_lang('uz_Latn')['ev_guest_gate_message'], "EV stansiyalari bazasini ko'rish uchun ro'yxatdan o'ting");
    expect(_lang('ru')['ev_guest_gate_message'], 'Зарегистрируйтесь, чтобы просматривать базу EV-станций');
  });

  test('уч калит ҳам уч тилда бор ва бўш эмас', () {
    for (final code in const ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final l = _lang(code);
      for (final k in const ['ev_guest_gate_title', 'ev_guest_gate_message', 'ev_guest_gate_register']) {
        expect((l[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$code/$k');
      }
    }
  });

  test('эски қотирилган Кирилл матн экран кодида қолмаган', () {
    final src = File('lib/features/ev_charging/screens/ev_charging_map_screen.dart').readAsStringSync();
    expect(src.contains('Бу бўлим фақат рўйхатдан ўтган'), isFalse);
    expect(src.contains("Text('Рўйхатдан ўтиш')"), isFalse);
  });
}
