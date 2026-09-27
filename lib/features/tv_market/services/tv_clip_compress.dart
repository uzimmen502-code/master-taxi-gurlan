import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/utils/crash_report.dart';
import '../models/tv_clip.dart' show tvClipMaxUploadSeconds;

class TvClipCompressResult {
  const TvClipCompressResult({
    required this.path,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.skipped = false,
  });

  final String path;
  final int bytesIn;
  final int bytesOut;
  final bool skipped;
}

/// ТВ ролик: 720p / 24fps, катта файл → 540p → 480p.
class TvClipCompress {
  TvClipCompress._();

  static const maxHeight = 720;
  static const skipIfAtMostBytes = 3500000;

  static const _qualityLadder = [
    VideoQuality.Res1280x720Quality,
    VideoQuality.Res960x540Quality,
    VideoQuality.Res640x480Quality,
  ];

  /// Қарор ҚИСҚА ҚИРРА (short edge) бўйича қабул қилинади.
  ///
  /// Аввал фақат `height` қаралар эди. AVAGram — вертикал лента: портрет
  /// клипда баландлик УЗУН қирра (720×1280 да h=1280). Шунинг учун
  /// «баландлиги 720 дан катта» шарти портрет видеода ДОИМО тўғри чиқар
  /// ва аллақачон 720×1280 бўлган, кичик (≤3.5MB) файл ҳам бекорга
  /// қайта кодланарди — яъни ҳар юкланган клип иловада бир марта, кейин
  /// серверда яна бир марта йўқотишли кодлашдан ўтарди (икки авлод
  /// сифат йўқотиш). Қисқа қирра билан бундай файл умуман тегилмайди.
  ///
  /// [width] берилмаса — эски хулқ (`height` қисқа қирра деб қаралади),
  /// шунинг учун эскирган чақирувлар ўзгармайди.
  static int _shortEdge(int? width, int? height) {
    final w = width ?? 0;
    final h = height ?? 0;
    if (w > 0 && h > 0) return w < h ? w : h;
    return h;
  }

  static VideoQuality qualityFor({int? height, int? width, int? bytes}) {
    final s = _shortEdge(width, height);
    final b = bytes ?? 0;
    if (s > 0 && s <= 540 && b > skipIfAtMostBytes) {
      return VideoQuality.Res960x540Quality;
    }
    return VideoQuality.Res1280x720Quality;
  }

  static bool shouldSkip({int? height, int? width, int? bytes}) {
    final s = _shortEdge(width, height);
    final b = bytes ?? 0;
    return b > 0 && b <= skipIfAtMostBytes && s > 0 && s <= maxHeight;
  }

  /// Сиқишдан олдин кесиш керакми — керак бўлмаса `null`.
  ///
  /// Бу маҳаллий кесиш серверникини ТАКРОРЛАЙДИ, алмаштирмайди: ҳақиқий,
  /// авторитетли чегара барибир серверда (`TV_CLIP_MAX_SECONDS`). Бу ерда
  /// у фақат исрофни олдини олади — акс ҳолда телефон бутун видеони
  /// сиқиб, бутунини юклайди, сервер эса ортиқчасини барибир ташлайди.
  /// (Ўлчанган ҳолат: 4 дақиқалик ролик 720p да 121MB чиққан, ундан
  /// ярмидан кўпи бекорга кетарди.)
  ///
  /// [durationMs] — `MediaInfo.duration`; баъзи қурилмалар сония беради.
  static int? trimToSeconds(double? durationMs) {
    if (durationMs == null || durationMs <= 0) return null;
    final seconds = durationMs >= 1000 ? durationMs / 1000.0 : durationMs;
    if (seconds <= tvClipMaxUploadSeconds) return null;
    return tvClipMaxUploadSeconds;
  }

  static Future<TvClipCompressResult> forUpload(
    String path, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb || path.isEmpty) {
      return TvClipCompressResult(path: path, skipped: true);
    }
    var bytesIn = 0;
    try {
      final info = await VideoCompress.getMediaInfo(path);
      bytesIn = info.filesize ?? 0;
      if (bytesIn <= 0) {
        final f = File(path);
        if (f.existsSync()) bytesIn = f.lengthSync();
      }
      final trimTo = trimToSeconds(info.duration);
      final height = info.height;
      final width = info.width;
      // Кесиш керак бўлса сиқишни ўтказиб юбориб бўлмайди — кесиш
      // айнан сиқиш давомида бажарилади.
      if (trimTo == null &&
          shouldSkip(height: height, width: width, bytes: bytesIn)) {
        return TvClipCompressResult(
          path: path,
          bytesIn: bytesIn,
          bytesOut: bytesIn,
          skipped: true,
        );
      }

      final sub = VideoCompress.compressProgress$.subscribe((p) {
        final n = p <= 1.0 ? p : p / 100.0;
        onProgress?.call(n.clamp(0.0, 1.0));
      });
      try {
        final startQuality =
            qualityFor(height: height, width: width, bytes: bytesIn);
        var startIndex = _qualityLadder.indexOf(startQuality);
        if (startIndex < 0) startIndex = 0;

        for (var i = startIndex; i < _qualityLadder.length; i++) {
          final quality = _qualityLadder[i];
          final result = await VideoCompress.compressVideo(
            path,
            quality: quality,
            frameRate: 24,
            includeAudio: true,
            deleteOrigin: false,
            duration: trimTo,
          );
          final outPath = result?.file?.path;
          final outBytes = _fileBytes(outPath, result?.filesize);
          if (outPath == null || outBytes <= 0) {
            // `video_compress` native kanal xato TASHLAMAYDI — muvaffaqiyatsiz
            // bo'lganda shunchaki `null` qaytaradi. Shu holat oldin butunlay
            // ko'rinmas edi (na debugPrint, na Crashlytics) — endi aniq
            // qayd etiladi va zinapoyaning keyingi (pastroq) tieriga o'tiladi.
            unawaited(CrashReport.nonFatal(
              Exception('video_compress null at $quality'),
              StackTrace.current,
              reason: 'tv_clip_compress_null_result',
              keys: {'quality': quality.toString(), 'bytesIn': bytesIn},
            ));
            continue;
          }
          return TvClipCompressResult(
            path: outPath,
            bytesIn: bytesIn,
            bytesOut: outBytes,
          );
        }
        // Zinapoyaning barcha bosqichlari muvaffaqiyatsiz tugadi — xom,
        // siqilmagan faylni qaytaramiz.
      } finally {
        sub.unsubscribe();
      }
    } catch (e, st) {
      debugPrint('[TvClipCompress] $e');
      unawaited(CrashReport.nonFatal(e, st, reason: 'tv_clip_compress'));
    }
    return TvClipCompressResult(
      path: path,
      bytesIn: bytesIn,
      bytesOut: bytesIn,
    );
  }

  static int _fileBytes(String? path, int? reported) {
    if (reported != null && reported > 0) return reported;
    if (path == null || path.isEmpty) return 0;
    final f = File(path);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  static Future<Uint8List?> thumbnailBytes(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    try {
      final raw = await VideoCompress.getByteThumbnail(
        path,
        quality: 55,
        position: -1,
      );
      if (raw == null || raw.isEmpty) return null;
      final jpeg = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: 720,
        minHeight: 720,
        quality: 62,
        format: CompressFormat.jpeg,
      );
      if (jpeg.isNotEmpty) return Uint8List.fromList(jpeg);
      return raw;
    } catch (e) {
      debugPrint('[TvClipCompress] thumb $e');
      return null;
    }
  }
}
