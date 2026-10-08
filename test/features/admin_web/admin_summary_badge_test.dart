import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Admin рўйхатларидаги «Жами / Кутяпти / …» доираси (2026-10-08).
///
/// Нуқсон: «Яна юклаш»дан кейин сон 1000 дан ошади, 36 px доирага 4 хона
/// сиғмай «100/0», «123/4» бўлиб иккинчи қаторга ўтарди (release веб
/// кўринишида кўрилган). Аввал рўйхат 500 билан чекланган — 3 хона ҳар
/// доим сиғарди. Энди сон доирага сиғдирилади (`FittedBox`).
void main() {
  for (final path in const [
    'lib/features/admin_web/screens/jobs_moderation_screen.dart',
    'lib/features/admin_web/screens/market_moderation_screen.dart',
    'lib/features/admin_web/screens/wholesale_moderation_screen.dart',
  ]) {
    test('$path: саноқ доирага сиғдирилади', () {
      final src = File(path).readAsStringSync();
      final start = src.indexOf('Widget _summaryCard(');
      expect(start, isNonNegative);
      final card = src.substring(start, src.indexOf('Widget _', start + 10));
      final avatar = card.substring(card.indexOf('CircleAvatar('));
      final fitted = avatar.indexOf('FittedBox(');
      expect(fitted, isNonNegative, reason: 'FittedBox йўқ');
      expect(fitted, lessThan(avatar.indexOf("'\$value'")));
      expect(avatar, contains('fit: BoxFit.scaleDown'));
    });
  }
}
