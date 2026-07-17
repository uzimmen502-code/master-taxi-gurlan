import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/splash_settings.dart';

/// Splash pulsatsiyasidan keyin koʻrsatiladigan soʻzlar — `settings/splash`.
class SplashTaglinesHolder {
  SplashTaglinesHolder._();

  static const _cacheKeyTaglines = 'splash_taglines';
  static const _cacheKeyEnabled = 'splash_taglines_enabled';

  static bool _enabled = SplashSettings.defaults.enabled;
  static List<String> _pool = List<String>.from(SplashSettings.defaultTaglines);
  static List<String> _sessionWords = const [];

  static bool get enabled => _enabled && _sessionWords.isNotEmpty;

  static List<String> get sessionWords => List.unmodifiable(_sessionWords);

  /// Birinchi frame / splash uchun: default pool dan session so'zlarni sync tayyorlash.
  /// Remote/kesh yangilash [load] orqali fonida ketadi.
  static void prepareSessionSync() {
    _prepareSessionWords();
  }

  static Future<void> load() async {
    await _loadFromCache();
    if (_sessionWords.isEmpty) {
      _prepareSessionWords();
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('splash')
          .get()
          .timeout(const Duration(milliseconds: 900));
      final settings = SplashSettings.fromMap(snap.data());
      _enabled = settings.enabled;
      _pool = List<String>.from(settings.taglines);
      await _saveToCache();
      // Session so'zlarni qayta aralashtirmaymiz — splash o'rtasida o'zgarib ketmasin.
      if (_sessionWords.isEmpty) {
        _prepareSessionWords();
      }
    } catch (e, st) {
      debugPrint('SplashTaglinesHolder.load: $e\n$st');
    }
  }

  static Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(_cacheKeyTaglines);
      if (cached != null && cached.isNotEmpty) {
        _pool = cached;
      }
      _enabled = prefs.getBool(_cacheKeyEnabled) ?? _enabled;
    } catch (_) {}
  }

  static Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cacheKeyTaglines, _pool);
      await prefs.setBool(_cacheKeyEnabled, _enabled);
    } catch (_) {}
  }

  static void _prepareSessionWords() {
    if (!_enabled || _pool.isEmpty) {
      _sessionWords = const [];
      return;
    }
    final shuffled = List<String>.from(_pool)..shuffle(Random());
    final picked = <String>[];
    for (final word in shuffled) {
      if (picked.length >= 3) break;
      picked.add(word);
    }
    while (picked.length < 3) {
      picked.add(_pool[picked.length % _pool.length]);
    }
    _sessionWords = picked;
  }

  @visibleForTesting
  static void setForTest({
    required bool enabled,
    required List<String> pool,
  }) {
    _enabled = enabled;
    _pool = List<String>.from(pool);
    _prepareSessionWords();
  }

  @visibleForTesting
  static void resetForTest() {
    _enabled = SplashSettings.defaults.enabled;
    _pool = List<String>.from(SplashSettings.defaultTaglines);
    _sessionWords = const [];
    _prepareSessionWords();
  }
}
