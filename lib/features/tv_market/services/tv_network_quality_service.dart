import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

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
}
