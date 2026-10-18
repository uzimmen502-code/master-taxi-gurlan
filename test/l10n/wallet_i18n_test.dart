import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ҳамён экрани 3 тилли (2026-10-18): калитлар учала тилда бор, параметрлар
/// ({module}, {amount}…) бир хил, ва ҳамён файлларида қаттиқ ёзилган
/// кирилл/лотин матн ҚОЛМАГАН (лойиҳанинг 3 тил қоидаси).
Map<String, dynamic> _load(String lang) =>
    jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;

final _param = RegExp(r'\{[a-z]+\}');

void main() {
  final cyr = _load('uz_Cyrl');
  final lat = _load('uz_Latn');
  final ru = _load('ru');
  final keys = cyr.keys.where((k) => k.startsWith('wlt_')).toList();

  test('ҳамён калитлари бор (70+)', () => expect(keys.length, greaterThan(70)));

  test('ҳар wlt_ калити учала тилда бор ва бўш эмас', () {
    for (final k in keys) {
      for (final m in {'uz_Cyrl': cyr, 'uz_Latn': lat, 'ru': ru}.entries) {
        final v = m.value[k];
        expect(v is String && v.trim().isNotEmpty, isTrue, reason: '$k / ${m.key}');
      }
    }
  });

  test('параметрлар учала тилда бир хил', () {
    for (final k in keys) {
      Set<String> p(Map<String, dynamic> m) => _param.allMatches(m[k] as String).map((x) => x[0]!).toSet();
      expect(p(lat), p(cyr), reason: '$k lat');
      expect(p(ru), p(cyr), reason: '$k ru');
    }
  });

  test('лотин матнда кирилл ҳарф ва кирилл/русда лотин сўз аралашмаган (ботдаги /команда ва бренд истисно)', () {
    final cyrillic = RegExp(r'[Ѐ-ӿ]');
    for (final k in keys) {
      final v = lat[k] as String;
      // `→`, `—`, `№` ва бренд/команда рухсат; кирилл ҳарф — йўқ.
      expect(cyrillic.hasMatch(v), isFalse, reason: '$k (uz_Latn): $v');
    }
  });

  test('рус матнда ўзбекча махсус ҳарфлар (ў қ ғ ҳ) йўқ', () {
    final uzOnly = RegExp('[ўқғҳЎҚҒҲ]');
    for (final k in keys) {
      expect(uzOnly.hasMatch(ru[k] as String), isFalse, reason: '$k (ru): ${ru[k]}');
    }
  });

  test('ҳамён виджетлари/экранларида қаттиқ ёзилган кирилл ёки лотин ўзбекча матн йўқ', () {
    final files = [
      'lib/features/profile/screens/wallet_screen.dart',
      'lib/features/profile/screens/wallet_operations_tab.dart',
      'lib/features/profile/widgets/wallet_section.dart',
      'lib/features/profile/widgets/wallet_telegram_link_panel.dart',
      'lib/features/profile/widgets/wallet_withdraw_panel.dart',
      'lib/features/profile/widgets/wallet_ledger_list.dart',
      'lib/features/profile/widgets/wallet_topup_requests.dart',
      'lib/features/profile/widgets/wallet_topup_notice.dart',
      'lib/core/utils/wallet_ledger_labels.dart',
    ];
    final cyrillic = RegExp(r'[Ѐ-ӿ]');
    for (final f in files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//')) continue; // изоҳлар кирилда бўлиши мумкин
        expect(cyrillic.hasMatch(lines[i]), isFalse, reason: '$f:${i + 1} қаттиқ матн: ${lines[i].trim()}');
      }
    }
  });
}
