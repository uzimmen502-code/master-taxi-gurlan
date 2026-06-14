import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/locale_utils.dart';

/// Ilova tili — qurilma + qo‘lda tanlov.
class LocaleNotifier extends ChangeNotifier with WidgetsBindingObserver {
  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('saved_language')) {
      // Foydalanuvchi o'zi tanlagan — saqlanganidan o'qiymiz
      _locale = await LocaleUtils.getInitialLocale();
    } else {
      // Hali tanlanmagan — qurilma tilini ishlatamiz, lekin SAQLAMAYMIZ
      _locale = LocaleUtils.resolveFromDevice();
    }
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _applyDeviceLocaleIfNoManualOverride();
  }

  Future<void> _applyDeviceLocaleIfNoManualOverride() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('saved_language')) return;
    final device = LocaleUtils.resolveFromDevice();
    if (device != _locale) {
      _locale = device;
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    final normalized = LocaleUtils.localeResolutionCallback(
          locale,
          LocaleUtils.supportedAppLocales,
        ) ??
        LocaleUtils.uzCyrl;
    _locale = normalized;
    await LocaleUtils.saveLocale(normalized);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
