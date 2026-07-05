import 'package:flutter/material.dart';

import '../../utils/locale_utils.dart';
import 'offline_l10n.dart';

/// Ilova tili — qurilma + qo‘lda tanlov.
class LocaleNotifier extends ChangeNotifier with WidgetsBindingObserver {
  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    _locale = await LocaleUtils.effectiveLocale();
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _applyDeviceLocaleIfNoManualOverride();
  }

  Future<void> _applyDeviceLocaleIfNoManualOverride() async {
    if (await LocaleUtils.hasManualLocale()) return;
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
    OfflineL10n.invalidate();
    notifyListeners();
  }

  /// Saqlangan tilni o'chirib, qurilma tiliga qaytish.
  Future<void> setFollowDeviceLocale() async {
    await LocaleUtils.saveFollowDeviceChoice();
    _locale = LocaleUtils.resolveFromDevice();
    OfflineL10n.invalidate();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
