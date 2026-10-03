// УЧ ТИЛ ҚОИДАСИ — автоматик қулф.
//
//   flutter test test/core/locale_sync_test.dart
//
// НЕГА БУ ТЕСТ БОР: репода қоида бор — ҳар қандай UI матни
// `uz_Cyrl`, `uz_Latn` ва `ru` файлларига БИРГА қўшилади. Қоида қўлда
// бажарилганда биттаси эсдан чиқади ва фойдаланувчи рус ёки лотин
// тилида инглизча/калит кўриб қолади (`AppLocalizations.translate`
// калитнинг ўзини қайтаради).
//
// Тест файлларни ўқийди, шунинг учун плагин керак эмас.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const langs = ['uz_Cyrl', 'uz_Latn', 'ru'];

  Map<String, String> load(String name) {
    final file = File('assets/lang/$name.json');
    expect(file.existsSync(), isTrue, reason: 'Топилмади: ${file.path}');
    final map = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v.toString()));
  }

  test('учта локал файлда калитлар АЙНАН бир хил', () {
    final maps = {for (final l in langs) l: load(l)};
    final base = maps['uz_Cyrl']!.keys.toSet();

    for (final lang in langs.skip(1)) {
      final other = maps[lang]!.keys.toSet();

      final missing = base.difference(other).toList()..sort();
      final extra = other.difference(base).toList()..sort();

      expect(
        missing,
        isEmpty,
        reason: '`$lang` файлида ЙЎҚ калитлар (uz_Cyrl да бор): '
            '${missing.take(20).join(', ')}'
            '${missing.length > 20 ? ' … жами ${missing.length}' : ''}',
      );
      expect(
        extra,
        isEmpty,
        reason: '`$lang` файлида ҚЎШИМЧА калитлар (uz_Cyrl да йўқ): '
            '${extra.take(20).join(', ')}'
            '${extra.length > 20 ? ' … жами ${extra.length}' : ''}',
      );
    }
  });

  // МАВЖУД ҲОЛАТ — янги матнларга тегишли эмас.
  //
  // Бу калитлар учала файлда ҳам АТАЙИН бўш: «мой алмаштириш»
  // бўлимидаги изоҳлар олиб ташланган, `oil_section_types_prefix` эса
  // фақат русчада керак («Рекомендация »). Шунинг учун улар бўш
  // қолдирилади — тест янги бўш таржимани ушлаши учун.
  const intentionallyEmpty = <String>{
    'oil_section_reco_hint',
    'oil_section_types_hint',
    'oil_section_types_prefix',
    'oil_section_types_end',
  };

  // МАВЖУД КАМЧИЛИК — эга қарори кутилади (ўзим тузатмадим).
  //
  // `sum` ва `currency_sum` учала файлда ҳам «сўм» (кирилл). Яъни
  // лотин ва рус интерфейсидаги фойдаланувчи нарх ёнида кирилл кўради.
  // Тўғриси: uz_Latn -> «so'm», ru -> «сум».
  //
  // Нега ўзим тузатмадим: бу матн БУТУН иловада, ҳар бир нарх ёнида
  // ишлатилади. Нотўғри ўзгартириш ҳар бир фойдаланувчига кўринади,
  // шунинг учун бу алоҳида қарор ва алоҳида текширув талаб қилади.
  const knownCyrillicInLatn = <String>{'sum', 'currency_sum'};

  test('ҳеч бир таржима бўш эмас', () {
    for (final lang in langs) {
      final empty = load(lang).entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .where((k) => !intentionallyEmpty.contains(k))
          .toList()
        ..sort();
      expect(
        empty,
        isEmpty,
        reason: '`$lang` да бўш таржима: ${empty.take(20).join(', ')}',
      );
    }
  });

  test('uz_Latn да кирилл ҳарф қолиб кетмаган', () {
    // Энг кўп учрайдиган хато: лотин файлига кирилл матн нусхаланади.
    // Истиснолар: тўғри номлар ва бирликлар бўлиши мумкин, шунинг учун
    // чегара қўйилган — битта-иккита белги эмас, МАТН кирилл бўлса.
    final latn = load('uz_Latn');
    final cyrillic = RegExp(r'[а-яёўқғҳА-ЯЁЎҚҒҲ]');
    final suspicious = <String>[];

    for (final e in latn.entries) {
      if (knownCyrillicInLatn.contains(e.key)) continue;
      final matches = cyrillic.allMatches(e.value).length;
      if (matches == 0) continue;
      // Матннинг ярмидан кўпи кирилл бўлса — нусхаланган.
      if (matches > e.value.length / 2) suspicious.add(e.key);
    }

    expect(
      suspicious,
      isEmpty,
      reason: '`uz_Latn` да кирилл матн: ${suspicious.take(20).join(', ')}',
    );
  });

  test('ядро матнларида техник сўзлар ЙЎҚ', () {
    // Концепциянинг ўзгармайдиган қоидаси: «Фойдаланувчи "Demand",
    // "Талаб яратиш" каби техник сўзларни кўрмайди.»
    //
    // Шунинг учун ядро калитлари (`demand_*`, `activity_*`, `match_*`,
    // `offer_*`, `request_*`, `consent_*`, `capabilities_*`) матнида
    // техник атамалар бўлмаслиги керак.
    const technical = [
      'demand', 'Demand', 'matching', 'Matching',
      'provider', 'Provider', 'dispatch', 'quote',
      'callable', 'Firestore', 'push', 'Push',
    ];
    const corePrefixes = [
      'demand_', 'activity_', 'match_', 'offer_', 'offers_',
      'request_', 'consent_', 'capabilities_', 'intent_', 'confirm_', 'rate_',
    ];

    for (final lang in langs) {
      final map = load(lang);
      for (final e in map.entries) {
        if (!corePrefixes.any(e.key.startsWith)) continue;
        for (final word in technical) {
          expect(
            e.value.contains(word),
            isFalse,
            reason: '`$lang` / `${e.key}` матнида техник сўз «$word»: '
                '"${e.value}"',
          );
        }
      }
    }
  });
}
