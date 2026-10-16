import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart' show AvaFont;
import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;

// EV testlari uchun umumiy yordamchilar: ilovaning HAQIQIY matnlari
// (assets/lang/*.json) sinxron o'qiladi va ilovaning haqiqiy shrifti (Inter)
// yuklanadi - testning standart Ahem shrifti har harfni kvadrat qilib matnni
// ~2 baravar keng ko'rsatadi, "1.3 shriftda sig'adimi" degan tekshiruv
// ma'nosiz bo'lib qoladi.

const Locale evUzCyrl = Locale('uz'); // AppLocalizations uni uz_Cyrl deb oladi
const Locale evUzLatn =
    Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn');
const Locale evRu = Locale('ru');

/// `setUpAll` ichida chaqiriladi.
Future<void> loadInterFont() async {
  final loader = FontLoader(AvaFont.family);
  for (final f in const [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final bytes = File('assets/fonts/Inter-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// `AppLocalizations`ning sinxron, fayldan o'qiydigan nusxasi
/// (`AppLocalizations.delegate` rootBundle orqali async va bir necha testda
/// ketma-ket ishonchsiz).
class _FileL10n extends AppLocalizations {
  _FileL10n(super.locale) : _strings = _load(locale);

  final Map<String, String> _strings;

  static Map<String, String> _load(Locale locale) {
    final code = switch (locale.languageCode) {
      'ru' => 'ru',
      'uz' => locale.scriptCode == 'Latn' ? 'uz_Latn' : 'uz_Cyrl',
      _ => 'uz_Cyrl',
    };
    final raw = json.decode(File('assets/lang/$code.json').readAsStringSync())
        as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, v.toString()));
  }

  @override
  String translate(String key) => _strings[key] ?? key;
}

class _FileL10nDelegate extends LocalizationsDelegate<AppLocalizations> {
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_FileL10n(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

class _AnyLocale<T> extends LocalizationsDelegate<T> {
  const _AnyLocale(this.value);
  final T value;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => SynchronousFuture<T>(value);

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;
}

/// Haqiqiy matnlar + Inter + [textScale] bilan ilova.
Widget evL10nApp({
  required Widget home,
  Locale locale = evUzLatn,
  double textScale = 1.0,
}) {
  return MaterialApp(
    locale: locale,
    theme: ThemeData(fontFamily: AvaFont.family),
    supportedLocales: [locale],
    localizationsDelegates: [
      _FileL10nDelegate(),
      const _AnyLocale<MaterialLocalizations>(DefaultMaterialLocalizations()),
      const _AnyLocale<WidgetsLocalizations>(DefaultWidgetsLocalizations()),
      const _AnyLocale<CupertinoLocalizations>(DefaultCupertinoLocalizations()),
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
}

/// Faylda ko'rsatilgan matn (tarjimasi bo'yicha) - kutilgan qiymatlar uchun.
String evTr(Locale locale, String key) =>
    _FileL10n(locale).translate(key);
