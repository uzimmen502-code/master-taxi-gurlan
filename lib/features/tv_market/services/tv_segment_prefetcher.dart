import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tv_clip_cache_service.dart';
import 'tv_network_quality_service.dart';

/// HLS сегмент prefetch — ExoPlayer instance'сиз, native Media3 `SimpleCache`
/// (`AvaMediaCache`, vendored `video_player_android`) орқали. Player ўқиганда
/// шу кешдан олади. MP4 (HLS бўлмаган) URL'лар учун мавжуд
/// [TvClipCacheService] қолади — бу ерда no-op.
///
/// Нима учун: TECNO/4G ўлчови — свайп→play 2.9 с, NEXT player ҳеч қачон
/// тайёр эмас (current "соғлом" бўлгунча prefetch бошланмайди). Сегмент
/// prefetch арзон (RAM ≈ 0), шунинг учун соғломликни кутмасдан бошланади.
class TvSegmentPrefetcher {
  TvSegmentPrefetcher._();

  static const _channel = MethodChannel('uz.ava.gurlan/tv_media_cache');

  /// Тест учун алмаштирилади.
  @visibleForTesting
  static Future<dynamic> Function(String method, Map<String, dynamic> args)?
      invokeOverride;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// [seconds] сония сегмент (0 — фақат playlist'лар). HLS бўлмаса — no-op.
  static Future<void> prefetch(String url, {required int seconds}) async {
    if (url.isEmpty || !TvClipCacheService.isHlsUrl(url)) return;
    if (seconds < 0) return;
    await _invoke('prefetch', {'url': url, 'seconds': seconds});
  }

  static Future<void> cancelAll() => _invoke('cancelAll', const {});

  /// Фақат [urls] керак — рўйхатда йўқ prefetch'лар бекор қилинади. Forward
  /// свайпда олдинги NEXT/NEXT+1 (= янги CURRENT/NEXT) давом этаверади.
  static Future<void> markWanted(List<String> urls) => _invoke('markWanted', {
        'urls': urls.where(TvClipCacheService.isHlsUrl).toList(growable: false),
      });

  static Future<void> _invoke(String method, Map<String, dynamic> args) async {
    final override = invokeOverride;
    if (override != null) {
      await override(method, args);
      return;
    }
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>(method, args);
    } catch (e) {
      debugPrint('[TvSegmentPrefetcher] $method: $e');
    }
  }

  /// Тармоққа қараб қанча сония олдиндан ёзиш. `null` — умуман prefetch йўқ.
  ///
  /// [quality] — [TvNetworkQualityService.preferredQuality] ('720p' Wi-Fi,
  /// '480p' мобил, '360p' номаълум/йўқ). [slowHistory] — сўнгги клиплар
  /// кўпи timeout'га тушган ([TvNetworkQualityService.adaptivePrefetchTimeout]
  /// 4 с бўлса).
  ///
  /// Сониялар сегмент чегарасига яхлитланади (production 4 с, В-4 деплойидан
  /// кейин 3 с): NEXT учун мақсад — **биринчи сегмент** (биринчи frame учун
  /// етарли; `_waitUntilHealthy` 3 с буфер сўрайди). Кўпроқ = секин тармоқда
  /// (~180 KB/s ўлчанди) 2 сегмент ≈ 4 с, свайп темпидан узун.
  static int? secondsFor(
    String quality, {
    required bool nextPlusOne,
    bool slowHistory = false,
  }) {
    switch (quality) {
      case '720p':
        return nextPlusOne ? 0 : 3;
      case '480p':
        if (slowHistory) return nextPlusOne ? null : 2;
        return nextPlusOne ? 0 : 2;
      default:
        return nextPlusOne ? null : 2;
    }
  }

  static bool get slowHistory =>
      TvNetworkQualityService.adaptivePrefetchTimeout() >=
      const Duration(milliseconds: 4000);
}
