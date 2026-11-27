import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'splash_ad.dart';
import 'splash_ad_cache.dart';

/// Splash реклама — орқа фонда (splash тугагач) КЕЙИНГИ очилиш учун креативни тайёрлайди ва кечаги
/// кўрсатишларни серверга юборади.
///
/// Арзонлик (37-банд): Firestore'дан ўқиш кўпи билан ҳар [refreshEvery]да бир марта (`visible == true`,
/// ≤ 20 ҳужжат); расм фақат реклама/версия ўзгарганда юкланади; статистика — кунига ≤ 1 чақирув.
class SplashAdPrefetcher {
  SplashAdPrefetcher({
    SplashAdCache? cache,
    Future<List<SplashAd>> Function()? fetchAds,
    Future<Uint8List?> Function(String url)? download,
    Future<void> Function(Map<String, Map<String, int>> days)? sendStats,
    DateTime Function()? now,
  })  : _cache = cache ?? SplashAdCache.instance,
        _fetchAds = fetchAds ?? _firestoreAds,
        _download = download ?? _httpDownload,
        _sendStats = sendStats ?? _callableStats,
        _now = now ?? DateTime.now;

  final SplashAdCache _cache;
  final Future<List<SplashAd>> Function() _fetchAds;
  final Future<Uint8List?> Function(String url) _download;
  final Future<void> Function(Map<String, Map<String, int>> days) _sendStats;
  final DateTime Function() _now;

  static const Duration refreshEvery = Duration(hours: 3);
  static const String _fetchedAtKey = 'splash_ad_fetched_at_v1';
  static const int maxImageBytes = 1500 * 1024;

  static Future<List<SplashAd>> _firestoreAds() async {
    final snap = await FirebaseFirestore.instance
        .collection('splash_ads')
        .where('visible', isEqualTo: true)
        .limit(20)
        .get();
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
  Future<void> run({required String districtId, bool force = false}) async {
    await _flushStats();
    await refresh(districtId: districtId, force: force);
  }

  Future<void> refresh({required String districtId, bool force = false}) async {
    try {
      final now = _now();
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_fetchedAtKey) ?? 0;
      if (!force && now.millisecondsSinceEpoch - last < refreshEvery.inMilliseconds && last <= now.millisecondsSinceEpoch) {
        return;
      }
      final chosen = SplashAd.pick(await _fetchAds(), now, districtId);
      if (chosen == null) {
        await _cache.clear();
      } else {
        final cur = await _cache.cachedAd();
        final sameImage = cur != null &&
            cur.id == chosen.id &&
            cur.imageUrl == chosen.imageUrl &&
            (!chosen.hasImage || await _cache.hasImage());
        if (sameImage || !chosen.hasImage) {
          await _cache.save(chosen, keepImage: sameImage);
        } else {
          final bytes = await _download(chosen.imageUrl);
          // Расм юкланмаса — матни бор бўлса матн билан, бўлмаса кеш тозаланади (сукут матни).
          if (bytes != null) {
            await _cache.save(chosen, imageBytes: bytes);
          } else if ((chosen.text['uz_Cyrl'] ?? '').isNotEmpty) {
            await _cache.save(chosen);
          } else {
            await _cache.clear();
            return; // вақт белгиси ёзилмайди — кейинги очилишда қайта уринади
          }
        }
      }
      await prefs.setInt(_fetchedAtKey, now.millisecondsSinceEpoch);
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
