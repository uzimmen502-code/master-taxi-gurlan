import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Экранларда қаттиқ ёзилган (локаллашмаган) кирилл матн қайта пайдо
/// бўлмаслиги учун қулф (аудит F-06, 2026-10-24).
///
/// Текширувга тушадиган жойлар: `Text('…')`, `hintText:`, `labelText:`,
/// `tooltip:`, `title: Text('…')`, `label: Text('…')`, `SnackBar(content:
/// Text('…'))`. Маълумот/қидирув жадваллари (`data/`, `utils/`, `models/`),
/// админ ва ишлатилмайдиган (dead) файллар бундан истисно.
final _literal = RegExp(
  "(?:Text\\(\\s*(?:const\\s+)?|hintText:\\s*|labelText:\\s*|tooltip:\\s*|"
  "helperText:\\s*|errorText:\\s*)"
  "'[^'\$\\n]*[Ѐ-ӿ][^'\\n]*'",
);

/// Қасддан қолдирилган файллар (сабаби билан). Рўйхатга ЯНГИ файл қўшишдан
/// олдин матнни JSON га кўчиринг.
const _allowedFiles = <String, String>{
  // Ишлатилмайдиган (чақирувчиси йўқ) виджетлар — ўчириш/сақлаш эга қарори.
  'lib/features/driver_home/widgets/trip_request_card.dart': 'dead code',
  'lib/features/driver_home/widgets/trip_request_dialog.dart': 'dead code',
  'lib/features/driver_home/widgets/online_pulse_toggle.dart': 'dead code',
  'lib/features/driver_home/widgets/seats_card.dart': 'dead code',
  'lib/features/driver_home/widgets/queue_card.dart': 'dead code',
  'lib/features/driver_home/widgets/driver_hero_card.dart': 'dead code',
  'lib/features/sell/screens/sell_hub_screen.dart': 'dead code',
  'lib/widgets/wallet_cash_split_panel.dart': 'dead code',
};

bool _skipPath(String p) =>
    p.contains('/admin_web/') ||
    p.contains('/analytics/') ||
    p.contains('/data/') ||
    p.contains('/sell/') ||
    p.contains('/oil_change/');

void main() {
  test('экран файлларида қаттиқ ёзилган кирилл UI матн йўқ', () {
    final offenders = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final path = e.path.replaceAll('\\', '/');
      if (_skipPath(path) || _allowedFiles.containsKey(path)) continue;
      var n = 0;
      for (final line in e.readAsLinesSync()) {
        n++;
        if (line.trimLeft().startsWith('//')) continue;
        if (_literal.hasMatch(line)) {
          offenders.add('$path:$n  ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Қуйидаги матнлар assets/lang/*.json (3 тил) га кўчирилсин:\n'
            '${offenders.join('\n')}');
  });
}
