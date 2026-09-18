import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// TV Market video variant tanlash uchun oddiy tarmoq-sifat signali.
///
/// Bandwidth estimation qilmaydi — faqat ulanish turiga (Wi-Fi/mobil)
/// qarab qaysi resolution talab qilinishini aytadi. Bu to'liq adaptive
/// bitrate emas (video_engine loyihasining keyingi bosqichi), lekin
/// respublika miqyosidagi tarmoq farqining katta qismini arzon yechadi.
///
/// T4: endi [watch] orqali ulanish turi o'zgarishiga ham reaksiya
/// beradi — avval faqat screen ochilganda bir marta o'qilardi (Wi-Fi'dan
/// mobilga o'tish sessiya davomida hisobga olinmasdi). Reaktsiya faqat
/// KEYINGI prepare qilinadigan URL'ga taalluqli — allaqachon ijro
/// etilayotgan controller qayta yaratilmaydi (playback uzilmaydi).
class TvNetworkQualityService {
  /// `videoVariants` kalitlaridan biri: `'720p'` | `'480p'` | `'360p'`.
  static Future<String> preferredQuality() async {
    final results = await Connectivity().checkConnectivity();
    return _qualityFor(results);
  }

  /// Ulanish turi o'zgarganda [onChange]ni yangi quality bilan chaqiradi.
  /// Chaqiruvchi natijadagi subscription'ni `dispose()`da cancel qilishi
  /// shart.
  static StreamSubscription<String> watch(void Function(String quality) onChange) {
    return Connectivity().onConnectivityChanged.map(_qualityFor).listen(onChange);
  }

  static String _qualityFor(List<ConnectivityResult> results) {
    if (results.any((r) => r == ConnectivityResult.none) &&
        results.length == 1) {
      return '360p';
    }
    if (results.any((r) =>
        r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet)) {
      return '720p';
    }
    if (results.any((r) => r == ConnectivityResult.mobile)) {
      return '480p';
    }
    return '360p';
  }

  // ── T-В4-1: adaptive/predictive prefetch (В-4 1-босқич) ──────────────
  //
  // Юқоридаги [preferredQuality] фақат улаgish ТУРИНИ билади (Wi-Fi/мобил).
  // Қуйидаги қисм эса реал буферлаш натижасига (TvMarketFeedScreen'нинг
  // `_waitUntilHealthy`си орқали) қараб ҳисобланадиган, ҳақиқий тармоқ
  // ҳолатини акс эттирувчи сигнал — "сўнгги N клип соғлом (timeout'гача)
  // буферланди ёки йўқ". b40bb65'даги фиксланган 2.5s timeout ўрнига
  // шу тарихга қараб мослашади.
  static const _healthWindow = 5;
  static final List<bool> _recentHealthy = [];

  /// `TvMarketFeedScreen._waitUntilHealthy()` ҳар клип учун натижани шу
  /// ерга ёзади — фақат ҳақиқий "соғлом тугади" / "timeout" ҳолатларида
  /// (генерация эскириши/хато каби ҳолатлар сигнал сифатида ҳисобланмайди).
  static void recordBufferHealth(bool healthyBeforeTimeout) {
    _recentHealthy.add(healthyBeforeTimeout);
    if (_recentHealthy.length > _healthWindow) {
      _recentHealthy.removeAt(0);
    }
  }

  /// Кейинги клипни prefetch қилишдан олдин жорий клипнинг "соғлом"
  /// бўлишини кутиш вақти — тарих йўқ бўлса нейтрал 2.5s (b40bb65'даги
  /// баҳоланган қиймат); сўнгги клиплар кўпи соғлом бўлса қисқароқ (тезроқ
  /// prefetch), кўпи timeout бўлса узунроқ (заиф тармоқда кейинги клип
  /// жорийнинг тармоғини тортиб олмасин).
  static Duration adaptivePrefetchTimeout() {
    if (_recentHealthy.isEmpty) return const Duration(milliseconds: 2500);
    final healthyRatio =
        _recentHealthy.where((h) => h).length / _recentHealthy.length;
    if (healthyRatio >= 0.8) return const Duration(milliseconds: 1500);
    if (healthyRatio <= 0.3) return const Duration(milliseconds: 4000);
    return const Duration(milliseconds: 2500);
  }

  /// Фақат тест учун — сессиялар ўртасида тарих сизиб қолмаслиги учун.
  @visibleForTesting
  static void resetHealthHistoryForTest() => _recentHealthy.clear();
}
