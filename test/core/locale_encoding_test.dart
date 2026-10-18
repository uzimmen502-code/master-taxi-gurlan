import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Mojibake қўриқчиси (2026-10-18). Symptom: янги калитлар қурилмада
// «ТљРёРґРёСЂРёС€…» бўлиб чиқди. Root cause: UTF-8 скрипт матни PowerShell
// `Get-Content -Raw` (cp1251) билан ўқилиб қайта ёзилган — кирилл қийматлар
// «Р…/С…» жуфтларига айланган, лотин қийматлар эса бутун қолган, шунинг учун
// калит паритети ва ҳамма тестлар ўтган эди.
//
// Кирилл UTF-8 байтлари (D0/D1 + 80–BF) cp1251 да «Р»/«С» + [Ђ-ї, “ ” … ™ № …]
// жуфтини беради. «ў/Ў» (Рў, Сў — «рўйхат», «сўров») ҳақиқий сўзларда учрайди,
// шунинг учун классдан чиқарилган; ва ҳар бир қийматда КАМИДА 2 жуфт талаб
// қилинади (ҳақиқий mojibake'да улар ўнлаб).
final _pair = RegExp(
  '[РС][Ђ-ЍЏђ-ѝџҐґ–-›'
  '€№ -¿]',
);

/// Mojibake шубҳали қийматлар калитлари.
List<String> mojibakeKeys(Map<String, dynamic> map) => [
      for (final e in map.entries)
        if (e.value is String && _pair.allMatches(e.value as String).length >= 2)
          e.key,
    ];

void main() {
  for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
    test('assets/lang/$lang.json: кодировка бузилмаган (mojibake йўқ)', () {
      final raw = File('assets/lang/$lang.json').readAsStringSync(encoding: utf8);
      final bad = mojibakeKeys(jsonDecode(raw) as Map<String, dynamic>);
      expect(bad, isEmpty, reason: 'mojibake қийматлар: ${bad.take(10)}');
    });
  }

  test('қўриқчи ҳақиқатан тутади: бузилган қиймат шубҳали, соғлом — йўқ', () {
    const healthy = 'Қидириш... (масалан: ҳайдовчи, тозалаш) — Рўйхат, Сўров';
    final broken = latin1Mojibake(healthy);
    expect(mojibakeKeys({'ok': healthy}), isEmpty);
    expect(mojibakeKeys({'bad': broken}), ['bad']);
  });
}

/// UTF-8 байтларини cp1251 сифатида ўқиганда чиқадиган матн (Dart'да cp1251
/// жадвали йўқ — фақат кирилл учун керакли ярим диапазон).
String latin1Mojibake(String s) {
  // cp1251 0x80–0xBF жадвали (Unicode).
  const hi = 'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ'
      ' ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї';
  final out = StringBuffer();
  for (final b in utf8.encode(s)) {
    if (b < 0x80) {
      out.writeCharCode(b);
    } else if (b >= 0xC0) {
      out.writeCharCode(0x0410 + (b - 0xC0)); // А..я
    } else {
      out.write(hi[b - 0x80]);
    }
  }
  return out.toString();
}
