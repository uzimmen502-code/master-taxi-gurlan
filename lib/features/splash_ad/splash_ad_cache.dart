import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'splash_ad.dart';

/// Очилишда кўрсатиладиган тайёр креатив (фақат КЕШДАН — тармоқ кутилмайди).
class SplashAdLaunch {
  const SplashAdLaunch({required this.ad, this.imageBytes});

  final SplashAd ad;

  /// Расм байтлари (расмли реклама бўлса — ДОИМ бор; кешда йўқ бўлса матнли кўринишга тушади).
  final Uint8List? imageBytes;
}

/// Маҳаллий сақлаш қатлами (тестда хотирадаги сохтаси).
abstract class SplashAdStore {
  Future<String?> readString(String key);

  /// `null` — ўчириш.
  Future<void> writeString(String key, String? value);
  Future<Uint8List?> readImage();

  /// `null` — ўчириш.
  Future<void> writeImage(Uint8List? bytes);
}

/// SharedPreferences (матн/JSON) + расм: мобилда файл (app support), web'да prefs base64 (localStorage).
class PrefsSplashAdStore implements SplashAdStore {
  static const _imgPrefsKey = 'splash_ad_img_v1';
  static const _imgFileName = 'splash_ad_v1.img';

  @override
  Future<String?> readString(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writeString(String key, String? value) async {
    final p = await SharedPreferences.getInstance();
    value == null ? await p.remove(key) : await p.setString(key, value);
  }

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/$_imgFileName');

  @override
  Future<Uint8List?> readImage() async {
    if (kIsWeb) {
      final s = (await SharedPreferences.getInstance()).getString(_imgPrefsKey);
      return s == null || s.isEmpty ? null : base64Decode(s);
    }
    final f = await _file();
    return await f.exists() ? await f.readAsBytes() : null;
  }

  @override
  Future<void> writeImage(Uint8List? bytes) async {
    if (kIsWeb) {
      final p = await SharedPreferences.getInstance();
      bytes == null ? await p.remove(_imgPrefsKey) : await p.setString(_imgPrefsKey, base64Encode(bytes));
      return;
    }
    final f = await _file();
    if (bytes == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    // Аввал вақтинча файлга, кейин алмаштириш — ярим ёзилган расм кўрсатилмасин.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }
}

/// Splash реклама кеши: кейинги очилиш учун танланган креатив, қурилмадаги кунлик чегара ва
/// серверга юбориладиган кунлик кўрсатишлар (йиғма).
class SplashAdCache {
  SplashAdCache({SplashAdStore? store}) : _store = store ?? PrefsSplashAdStore();

  static final SplashAdCache instance = SplashAdCache();

  final SplashAdStore _store;

  static const metaKey = 'splash_ad_meta_v1';
  static const impKey = 'splash_ad_imp_v1';
  static const pendingKey = 'splash_ad_stats_pending_v1';

  /// Бир қурилмада кунига энг кўпи 3 марта рекламачи креативи (эга 2026-11-28); кейин — сукут матни.
  static const int maxPerDay = 3;

  /// Тошкент санаси (UTC+5) — сервер `dayKeyOf` билан бир хил.
  static String dayKey(DateTime now) =>
      now.toUtc().add(const Duration(hours: 5)).toIso8601String().substring(0, 10);

  Future<Map<String, dynamic>> _json(String key) async {
    try {
      final s = await _store.readString(key);
      final v = s == null ? null : jsonDecode(s);
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Бугун неча марта рекламачи креативи кўрсатилди (барча рекламалар бўйича).
  Future<int> shownToday(DateTime now) async {
    final m = await _json(impKey);
    return m['day'] == dayKey(now) && m['n'] is int ? m['n'] as int : 0;
  }

  /// Очилиш қарори — ФАҚАТ маҳаллий маълумот: кешдаги креатив, сана ойнаси, туман, кунлик чегара.
  /// Расмли реклама расми кешда бўлмаса — матни бўлса матн, бўлмаса `null` (сукут матни).
  Future<SplashAdLaunch?> loadForLaunch({required DateTime now, required String districtId}) async {
    try {
      final ad = SplashAd.fromCacheMap(await _json(metaKey));
      if (ad == null || !ad.isEligible(now, districtId)) return null;
      if (await shownToday(now) >= maxPerDay) return null;
      if (!ad.hasImage) return (ad.text['uz_Cyrl'] ?? '').isEmpty ? null : SplashAdLaunch(ad: ad);
      final bytes = await _store.readImage();
      if (bytes != null && bytes.isNotEmpty) return SplashAdLaunch(ad: ad, imageBytes: bytes);
      return (ad.text['uz_Cyrl'] ?? '').isEmpty ? null : SplashAdLaunch(ad: ad);
    } catch (e) {
      debugPrint('SplashAdCache.loadForLaunch: $e');
      return null;
    }
  }

  /// Креатив экранга чиқди: кунлик ҳисоб + серверга юбориладиган йиғма.
  Future<void> recordImpression(String adId, DateTime now) async {
    try {
      final day = dayKey(now);
      final imp = await _json(impKey);
      final n = imp['day'] == day && imp['n'] is int ? imp['n'] as int : 0;
      await _store.writeString(impKey, jsonEncode({'day': day, 'n': n + 1}));
      final pending = await _json(pendingKey);
      final perDay = pending[day] is Map ? Map<String, dynamic>.from(pending[day] as Map) : <String, dynamic>{};
      perDay[adId] = (perDay[adId] is int ? perDay[adId] as int : 0) + 1;
      pending[day] = perDay;
      // Сервер 7 кундан эскисини қабул қилмайди — кирмаган қурилмада йиғма чексиз ўсмасин.
      final oldest = dayKey(now.subtract(const Duration(days: 8)));
      pending.removeWhere((k, _) => k.compareTo(oldest) < 0);
      await _store.writeString(pendingKey, jsonEncode(pending));
    } catch (e) {
      debugPrint('SplashAdCache.recordImpression: $e');
    }
  }

  /// Юборишга тайёр кунлар — БУГУНДАН олдинги (кун тугагач бир марта, арзон: кунига ≤ 1 чақирув).
  Future<Map<String, Map<String, int>>> pendingBefore(DateTime now) async {
    final today = dayKey(now);
    final pending = await _json(pendingKey);
    return {
      for (final e in pending.entries)
        if (e.key.compareTo(today) < 0 && e.value is Map)
          e.key: {
            for (final x in (e.value as Map).entries)
              if (x.value is int) '${x.key}': x.value as int,
          },
    };
  }

  /// Юборилган кунларни олиб ташлайди (бугунгиси қолади).
  Future<void> clearPending(Iterable<String> days) async {
    final pending = await _json(pendingKey);
    for (final d in days) {
      pending.remove(d);
    }
    await _store.writeString(pendingKey, pending.isEmpty ? null : jsonEncode(pending));
  }

  /// Ҳозир кешдаги креатив (префетч солиштириш учун).
  Future<SplashAd?> cachedAd() async => SplashAd.fromCacheMap(await _json(metaKey));

  /// Кешда расм байтлари борми (префетч: версия бир хил, лекин расм йўқолган бўлса қайта юклаш).
  Future<bool> hasImage() async {
    try {
      final b = await _store.readImage();
      return b != null && b.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Янги креативни сақлайди. Расм ўзгармаган бўлса ([keepImage]) — қайта ёзилмайди.
  Future<void> save(SplashAd ad, {Uint8List? imageBytes, bool keepImage = false}) async {
    if (!keepImage) await _store.writeImage(ad.hasImage ? imageBytes : null);
    await _store.writeString(metaKey, jsonEncode(ad.toCacheMap()));
  }

  /// Мос реклама йўқ — кеш тозаланади (кейинги очилишда сукут матни).
  Future<void> clear() async {
    await _store.writeString(metaKey, null);
    await _store.writeImage(null);
  }
}
