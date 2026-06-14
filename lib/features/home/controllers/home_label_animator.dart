import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Bosh ekran modul kartalari ostidagi yozuvlar — ketma-ket to'lqin animatsiyasi.
class HomeLabelAnimator extends ChangeNotifier {
  HomeLabelAnimator();

  /// Barcha 6 ta modul — bitta ketma-ket to'lqin tsikli.
  static const order = [
    'bread',
    'jobs',
    'cheap_products_home',
    'marshrut',
    'local_taxi',
    'intercity',
  ];

  /// Yuqori katta kartalar (kengroq) — l10n kalitlari.
  static const labelPlainTextFeatured = <String, String>{
    'bread': 'home_module_bread',
    'jobs': 'home_module_jobs',
    'cheap_products_home': 'home_module_cheap_products',
    'marshrut': 'home_module_marshrut',
    'local_taxi': 'home_module_local',
    'intercity': 'home_module_intercity',
  };

  /// Tor qator (taksi / bozor) — l10n kalitlari.
  static const labelPlainTextCompact = <String, String>{
    'bread': 'home_module_bread',
    'jobs': 'home_module_jobs',
    'cheap_products_home': 'home_module_cheap_products',
    'marshrut': 'home_module_marshrut',
    'local_taxi': 'home_module_local',
    'intercity': 'home_module_intercity',
  };

  static const _letterMs = 95;
  static const _pauseAfterMs = 400;

  int _moduleIndex = 0;
  int _waveIndex = 0;
  bool _pausing = false;
  Timer? _timer;
  final Map<String, int> _plainCharCounts = {};

  String get activeModuleId => order[_moduleIndex % order.length];
  int get waveIndex => _waveIndex;

  bool isActive(String moduleId) => activeModuleId == moduleId;

  static bool isFeaturedLayout(String moduleId) =>
      moduleId == 'bread' || moduleId == 'jobs';

  static String labelKeyFor(String moduleId, {required bool featured}) {
    final map = featured ? labelPlainTextFeatured : labelPlainTextCompact;
    return map[moduleId] ?? labelPlainTextFeatured[moduleId] ?? moduleId;
  }

  static String plainTextFor(
    BuildContext context,
    String moduleId, {
    required bool featured,
  }) {
    final key = labelKeyFor(moduleId, featured: featured);
    return AppLocalizations.of(context)!.translate(key);
  }

  /// Kartalar build qilganda chaqiriladi — to'lqin uzunligi tarjima matniga mos.
  void syncPlainCharCount(String moduleId, String resolvedPlain) {
    final n = resolvedPlain.replaceAll('\n', '').length;
    _plainCharCounts[moduleId] = n;
  }

  int charCount(String moduleId, {required bool featured}) {
    final cached = _plainCharCounts[moduleId];
    if (cached != null && cached > 0) return cached;
    return labelKeyFor(moduleId, featured: featured).length;
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: _letterMs), _tick);
  }

  void _tick(Timer t) {
    if (_pausing) return;
    final id = activeModuleId;
    final total = charCount(id, featured: isFeaturedLayout(id));
    if (total == 0) {
      _advanceModule();
      return;
    }
    if (_waveIndex < total) {
      _waveIndex++;
      notifyListeners();
      return;
    }
    _pausing = true;
    Timer(const Duration(milliseconds: _pauseAfterMs), () {
      _pausing = false;
      _advanceModule();
    });
  }

  void _advanceModule() {
    _waveIndex = 0;
    _moduleIndex = (_moduleIndex + 1) % order.length;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
