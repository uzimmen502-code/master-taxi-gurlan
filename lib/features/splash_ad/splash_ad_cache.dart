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

/// Маҳаллий сақлаш қатлами (тестда хотирадаги сохтаси). Расмлар реклама ID си бўйича.
abstract class SplashAdStore {
  Future<String?> readString(String key);

  /// `null` — ўчириш.
  Future<void> writeString(String key, String? value);
  Future<Uint8List?> readImage(String adId);

  /// `null` — ўчириш.
  Future<void> writeImage(String adId, Uint8List? bytes);

  /// Эски (v1, битта креатив) кешни тозалаш.
  Future<void> deleteLegacy();
}

/// SharedPreferences (матн/JSON) + расм: мобилда файл (app support), web'да prefs base64 (localStorage).
class PrefsSplashAdStore implements SplashAdStore {
  static const _imgPrefsPrefix = 'splash_ad_img_v2_';
  static const _imgFilePrefix = 'splash_ad_v2_';

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<String?> readString(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writeString(String key, String? value) async {
    final p = await SharedPreferences.getInstance();
    value == null ? await p.remove(key) : await p.setString(key, value);
  }

  Future<File> _file(String name) async => File('${(await getApplicationSupportDirectory()).path}/$name');

  @override
  Future<Uint8List?> readImage(String adId) async {
    if (kIsWeb) {
      final s = (await SharedPreferences.getInstance()).getString('$_imgPrefsPrefix${_safe(adId)}');
      return s == null || s.isEmpty ? null : base64Decode(s);
    }
    final f = await _file('$_imgFilePrefix${_safe(adId)}.img');
    return await f.exists() ? await f.readAsBytes() : null;
  }

  @override
  Future<void> writeImage(String adId, Uint8List? bytes) async {
    if (kIsWeb) {
      final p = await SharedPreferences.getInstance();
      final k = '$_imgPrefsPrefix${_safe(adId)}';
      bytes == null ? await p.remove(k) : await p.setString(k, base64Encode(bytes));
      return;
    }
    final f = await _file('$_imgFilePrefix${_safe(adId)}.img');
    if (bytes == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    // Аввал вақтинча файлга, кейин алмаштириш — ярим ёзилган расм кўрсатилмасин.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> deleteLegacy() async {
    final p = await SharedPreferences.getInstance();
    for (final k in ['splash_ad_meta_v1', 'splash_ad_imp_v1', 'splash_ad_img_v1']) {
      if (p.containsKey(k)) await p.remove(k);
    }
    if (!kIsWeb) {
      final f = await _file('splash_ad_v1.img');
      if (await f.exists()) await f.delete();
    }
  }
}

/// Кешдаги битта креатив: реклама + расми кешдами.
class SplashAdCached {
  const SplashAdCached(this.ad, {this.imageCached = false});

  final SplashAd ad;
  final bool imageCached;

  /// Очилишда кўрсатиш мумкинми (расм кешда ёки кирилл матн бор).
  bool get showable => imageCached || ad.hasText;
}

/// Splash реклама кеши: кейинги очилишлар учун БИР НЕЧТА креатив (ҳудудга мос, оғирлиги бўйича),
/// айланиш ҳолати ва серверга юбориладиган кунлик кўрсатишлар (йиғма).
///
/// Эга 2026-11-28: ҲАР очилишда реклама (аввалги 3/кун чегараси йўқ), навбатдагиси оғирлик бўйича.
class SplashAdCache {
  SplashAdCache({SplashAdStore? store}) : _store = store ?? PrefsSplashAdStore();

  static final SplashAdCache instance = SplashAdCache();

  final SplashAdStore _store;

  static const listKey = 'splash_ad_list_v2';
  static const rotationKey = 'splash_ad_rot_v2';
  static const pendingKey = 'splash_ad_stats_pending_v1';

  /// Кешдаги креативлар чегараси (жой ва трафик).
  static const int maxAds = 8;

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

  /// Кешдаги рўйхат.
  Future<List<SplashAdCached>> cached() async {
    try {
      final s = await _store.readString(listKey);
      final v = s == null ? null : jsonDecode(s);
      if (v is! List) return const [];
      return [
        for (final e in v)
          if (e is Map && SplashAd.fromCacheMap(e['ad']) != null)
            SplashAdCached(SplashAd.fromCacheMap(e['ad'])!, imageCached: e['img'] == true),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Очилиш қарори — ФАҚАТ маҳаллий маълумот: кешдаги креативлар, сана ойнаси, ҳудуд ва айланиш ҳолати.
  /// Танланган расм ўқилмаса — матни бўлса матн, бўлмаса `null` (сукут матни). Ҳолат шу ерда сақланади
  /// (кейинги очилиш — кейинги реклама).
  Future<SplashAdLaunch?> loadForLaunch({
    required DateTime now,
    required String districtId,
    String regionId = '',
  }) async {
    try {
      final candidates = [
        for (final c in await cached())
          if (c.showable && c.ad.isEligible(now, districtId, regionId)) c,
      ];
      if (candidates.isEmpty) return null;
      final state = {
        for (final e in (await _json(rotationKey)).entries)
          if (e.value is int) e.key: e.value as int,
      };
      final (ad, next) = SplashAdRotation.next([for (final c in candidates) c.ad], state);
      await _store.writeString(rotationKey, jsonEncode(next));
      if (ad == null) return null;
      final c = candidates.firstWhere((x) => x.ad.id == ad.id);
      if (c.imageCached) {
        final bytes = await _store.readImage(ad.id);
        if (bytes != null && bytes.isNotEmpty) return SplashAdLaunch(ad: ad, imageBytes: bytes);
      }
      return ad.hasText ? SplashAdLaunch(ad: ad) : null;
    } catch (e) {
      debugPrint('SplashAdCache.loadForLaunch: $e');
      return null;
    }
  }

  /// Креатив экранга чиқди: серверга юбориладиган кунлик йиғма (чегара йўқ — ҳар очилиш).
  Future<void> recordImpression(String adId, DateTime now) async {
    try {
      final day = dayKey(now);
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

  Future<Uint8List?> readImage(String adId) async {
    try {
      final b = await _store.readImage(adId);
      return b == null || b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  /// Янги рўйхатни сақлайди. [images] — янги юкланган расмлар (ID → байт); [keepImages] — ўзгармаганлари.
  /// Рўйхатдан чиққан рекламаларнинг расмлари ўчирилади.
  Future<void> saveAll(List<SplashAdCached> items, {Map<String, Uint8List> images = const {}}) async {
    final old = await cached();
    final keep = {for (final i in items) i.ad.id};
    for (final o in old) {
      if (!keep.contains(o.ad.id)) await _store.writeImage(o.ad.id, null);
    }
    for (final e in images.entries) {
      await _store.writeImage(e.key, e.value);
    }
    await _store.writeString(
      listKey,
      items.isEmpty ? null : jsonEncode([for (final i in items) {'ad': i.ad.toCacheMap(), 'img': i.imageCached}]),
    );
    try {
      await _store.deleteLegacy();
    } catch (_) {}
  }

  /// Мос реклама йўқ — кеш тозаланади (кейинги очилишда сукут матни).
  Future<void> clear() => saveAll(const []);
}
