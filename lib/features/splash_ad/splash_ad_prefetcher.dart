import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'splash_ad.dart';
import 'splash_ad_cache.dart';

/// Splash реклама — орқа фонда (splash тугагач) КЕЙИНГИ очилишлар учун фойдаланувчи ҳудудидаги фаол
/// креативларни тайёрлайди ва кечаги кўрсатишларни серверга юборади.
///
/// Арзонлик (37-банд): Firestore'дан ўқиш кўпи билан ҳар [refreshEvery]да бир марта ва фақат шу ҳудуд
/// калитлари (`areaKeys`: 'all' / 'd:туман' / 'r:вилоят'); расм фақат янги/ўзгарганда юкланади, жами ҳажм
/// чегараланган ([maxCacheBytes]); статистика — кунига ≤ 1 чақирув.
class SplashAdPrefetcher {
  SplashAdPrefetcher({
    SplashAdCache? cache,
    Future<List<SplashAd>> Function(String districtId, String regionId)? fetchAds,
    Future<Uint8List?> Function(String url)? download,
    Future<void> Function(Map<String, Map<String, int>> days)? sendStats,
    DateTime Function()? now,
    int? maxCacheBytes,
  })  : _cache = cache ?? SplashAdCache.instance,
        _fetchAds = fetchAds ?? _firestoreAds,
        _download = download ?? _httpDownload,
        _sendStats = sendStats ?? _callableStats,
        _now = now ?? DateTime.now,
        maxCacheBytes = maxCacheBytes ?? (kIsWeb ? 2 * 1024 * 1024 : 8 * 1024 * 1024);

  final SplashAdCache _cache;
  final Future<List<SplashAd>> Function(String districtId, String regionId) _fetchAds;
  final Future<Uint8List?> Function(String url) _download;
  final Future<void> Function(Map<String, Map<String, int>> days) _sendStats;
  final DateTime Function() _now;

  /// Кешдаги расмлар жами ҳажми (web — localStorage кичик).
  final int maxCacheBytes;

  static const Duration refreshEvery = Duration(hours: 3);
  static const String _fetchedAtKey = 'splash_ad_fetched_at_v1';
  static const int maxImageBytes = 1500 * 1024;

  static Future<List<SplashAd>> _firestoreAds(String districtId, String regionId) async {
    final col = FirebaseFirestore.instance.collection('splash_ads');
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await col
          .where('visible', isEqualTo: true)
          .where('areaKeys', arrayContainsAny: SplashAd.areaQueryKeys(districtId, regionId))
          .limit(40)
          .get();
    } on FirebaseException catch (e) {
      // Индекс ҳали қурилмаган бўлса — эски (ҳудудсиз) сўров; мослик клиентда текширилади.
      if (e.code != 'failed-precondition') rethrow;
      snap = await col.where('visible', isEqualTo: true).limit(40).get();
    }
    return [for (final d in snap.docs) SplashAd.fromDoc(d)].whereType<SplashAd>().toList();
  }

  static Future<Uint8List?> _httpDownload(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty || r.bodyBytes.length > maxImageBytes) return null;
    return r.bodyBytes;
  }

  static Future<void> _callableStats(Map<String, Map<String, int>> days) async {
    await FirebaseFunctions.instance.httpsCallable('recordSplashImpressions').call<Object?>({'days': days});
  }

  /// Splash тугагач чақирилади (ҳеч қачон очилишни кутдирмайди). Хато — жим (кейинги сафар қайта).
  Future<void> run({required String districtId, String regionId = '', bool force = false}) async {
    await _flushStats();
    await refresh(districtId: districtId, regionId: regionId, force: force);
  }

  Future<void> refresh({required String districtId, String regionId = '', bool force = false}) async {
    try {
      final now = _now();
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_fetchedAtKey) ?? 0;
      if (!force && now.millisecondsSinceEpoch - last < refreshEvery.inMilliseconds && last <= now.millisecondsSinceEpoch) {
        return;
      }
      final chosen = SplashAd.selectForCache(
        await _fetchAds(districtId, regionId),
        now,
        districtId,
        regionId,
        max: SplashAdCache.maxAds,
      );
      final old = {for (final c in await _cache.cached()) c.ad.id: c};
      final items = <SplashAdCached>[];
      final fresh = <String, Uint8List>{};
      var bytesUsed = 0;
      var failed = false;
      for (final ad in chosen) {
        if (!ad.hasImage) {
          items.add(SplashAdCached(ad));
          continue;
        }
        final prev = old[ad.id];
        Uint8List? bytes;
        if (prev != null && prev.imageCached && prev.ad.imageUrl == ad.imageUrl) {
          bytes = await _cache.readImage(ad.id);
        }
        final reused = bytes != null;
        if (!reused && bytesUsed < maxCacheBytes) {
          bytes = await _download(ad.imageUrl);
          if (bytes == null) failed = true;
        }
        if (bytes != null && bytesUsed + bytes.length <= maxCacheBytes) {
          bytesUsed += bytes.length;
          if (!reused) fresh[ad.id] = bytes;
          items.add(SplashAdCached(ad, imageCached: true));
        } else if (ad.hasText) {
          items.add(SplashAdCached(ad)); // расм сиғмади/юкланмади — матн билан
        }
      }
      await _cache.saveAll(items, images: fresh);
      // Расм юкланмаган бўлса — вақт белгиси ёзилмайди (кейинги очилишда қайта уринади).
      if (!failed) await prefs.setInt(_fetchedAtKey, now.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('SplashAdPrefetcher.refresh: $e');
    }
  }

  Future<void> _flushStats() async {
    try {
      final days = await _cache.pendingBefore(_now());
      if (days.isEmpty) return;
      await _sendStats(days);
      await _cache.clearPending(days.keys);
    } catch (e) {
      // Кирмаган/тармоқ йўқ — йиғма сақланади, кейинги сафар (сервер 7 кундан эскисини қабул қилмайди).
      debugPrint('SplashAdPrefetcher.flushStats: $e');
    }
  }
}
