// Ресторан виджет тестлари учун ЯГОНА таржима ёрдамчиси: ҳақиқий `assets/lang/*.json`
// СИНХРОН ўқилади (калит унутилса — хом калит чиқади ва тест йиқилади; тестлар
// тартибдан мустақил ва тез). Тил — `uz_Latn`: ёзув ҳақиқий матн билан текширилади.
//
// ЭСЛАТМА: `Locale('uz', 'Latn')` — бу ДАВЛАТ коди; ёзув коди учун
// [uzLatnLocale] (`Locale.fromSubtags`) ишлатилади, акс ҳолда `contentLang` кирилл бўлиб қолади.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const uzLatnLocale = Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn');

Map<String, String> loadLang(String lang) => {
      for (final e in (jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>).entries)
        e.key: e.value.toString(),
    };

class _JsonL10n extends AppLocalizations {
  _JsonL10n(super.locale, this._s);

  final Map<String, String> _s;

  @override
  String translate(String key) => _s[key] ?? key;
}

class JsonL10nDelegate extends LocalizationsDelegate<AppLocalizations> {
  JsonL10nDelegate([String lang = 'uz_Latn']) : _s = loadLang(lang);

  final Map<String, String> _s;

  /// Калит бўйича матн (тест ичида кутилаётган ёзувни ҳақиқий файлдан олиш учун).
  String tr(String key) => _s[key] ?? key;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(_JsonL10n(locale, _s));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

/// `MaterialApp`: ҳақиқий матнлар, `uz_Latn`, ихтиёрий матн масштаби.
MaterialApp l10nApp({required Widget home, JsonL10nDelegate? delegate, double textScale = 1.0}) {
  final d = delegate ?? JsonL10nDelegate();
  return MaterialApp(
    locale: uzLatnLocale,
    supportedLocales: const [uzLatnLocale],
    localizationsDelegates: [
      d,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
}
