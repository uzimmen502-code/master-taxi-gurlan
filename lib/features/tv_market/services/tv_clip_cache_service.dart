import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// TV Market video'lari uchun bounded lokal disk cache (video-core audit,
/// T7). `entertainment_cache_service.dart` bilan bir xil bounded-LRU
/// pattern.
///
/// Faqat butun-fayl MP4 uchun. HLS (`.m3u8`) manzillar bu kesh'dan
/// ATAYIN chetlab o'tiladi — qarang: [isHlsUrl]. Ya'ni HLS kliplar
/// qayta ko'rilganda lokal nusxadan emas, tarmoqdan oqadi; segment
/// darajasidagi kesh `video_player` paketi orqali boshqarilmaydi
/// (ExoPlayer'ning `SimpleCache`'iga yo'l yo'q).
///
/// Playback'ni bloklamaydi: [ensureCached] fon'da yuklaydi, joriy
/// controller network orqali streaming davom etadi — cache faqat
/// KEYINGI ko'rishlar uchun.
class TvClipCacheService {
  TvClipCacheService._();
  static final instance = TvClipCacheService._();

  /// Audit'dagi boshlang'ich benchmark parametri (~300MB) — qat'iy son
  /// emas, real qurilmalarda sinab ko'rish kerak.
  static const int maxCacheBytes = 300 * 1024 * 1024;

  final _inflight = <String, Future<File?>>{};

  Future<Directory> _cacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'tv_clip_cache'));
    if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);
    return cacheDir;
  }

  /// [url]dan barqaror fayl nomi — faqat path asosida (query'dagi
  /// download token o'zgarsa ham bir xil kalit qoladi).
  String _keyFor(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    return '${md5.convert(utf8.encode(path))}.mp4';
  }

  /// HLS манзилими? Бу кэш бутун-файл учун: `.m3u8` — бу видео эмас,
  /// сегментларга ишора қилувчи бир неча юз байтлик матн. Уни юклаб
  /// «кэшландим» деб ҳисоблаш ЗАРАРЛИ бўларди: кейинги кўришда
  /// [localFile] ўша матн файлини қайтариб, плеер видео ўрнига
  /// playlist'ни файлдан ўқишга уринарди.
  ///
  /// Шунинг учун HLS клиплар бу кэшдан фойдаланмайди — улар ҳар
  /// кўришда тармоқдан оқади (ExoPlayer'нинг ўз буфери ишлайди).
  /// MP4 клиплар (эскилари ва HLS йиқилганлари) аввалгидек кэшланади.
  static bool isHlsUrl(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return path.endsWith('.m3u8');
  }

  Future<File?> localFile(String url) async {
    if (kIsWeb || url.isEmpty || isHlsUrl(url)) return null;
    final dir = await _cacheDir();
    final file = File(p.join(dir.path, _keyFor(url)));
    return file.existsSync() ? file : null;
  }

  /// Bir url uchun bir vaqtda bitta yuklash (dedup) — natijani kutish
  /// shart emas, chaqiruvchi odatda `unawaited()` bilan ishlatadi.
  Future<void> ensureCached(String url) {
    if (kIsWeb || url.isEmpty || isHlsUrl(url)) return Future.value();
    if (_inflight.containsKey(url)) return _inflight[url]!.then((_) {});
    return _inflight.putIfAbsent(url, () => _download(url)).then((_) {});
  }

  Future<File?> _download(String url) async {
    try {
      final existing = await localFile(url);
      if (existing != null) return existing;

      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      final dir = await _cacheDir();
      final key = _keyFor(url);
      final dest = File(p.join(dir.path, key));
      final tmp = File(p.join(dir.path, '$key.part'));
      await tmp.writeAsBytes(res.bodyBytes);
      if (!tmp.existsSync()) return null;
      await tmp.rename(dest.path);

      await _prune();
      return dest;
    } catch (e) {
      debugPrint('[TvClipCache] download $e');
      return null;
    } finally {
      _inflight.remove(url);
    }
  }

  /// Limitdan oshsa — eng eski (oxirgi yozilgan) fayllardan boshlab
  /// o'chiramiz.
  Future<void> _prune() async {
    final dir = await _cacheDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp4'))
        .toList();
    var total = 0;
    for (final f in files) {
      total += f.statSync().size;
    }
    if (total <= maxCacheBytes) return;
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    for (final f in files) {
      if (total <= maxCacheBytes) break;
      final sz = f.statSync().size;
      try {
        f.deleteSync();
        total -= sz;
      } catch (_) {}
    }
  }

  Future<int> cacheSizeBytes() async {
    if (kIsWeb) return 0;
    final dir = await _cacheDir();
    var total = 0;
    for (final f in dir.listSync().whereType<File>()) {
      total += f.statSync().size;
    }
    return total;
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    final dir = await _cacheDir();
    for (final f in dir.listSync().whereType<File>()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}
