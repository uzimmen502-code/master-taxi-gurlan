import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/utils/crash_report.dart';

/// To'liq sig'im zinapoyasi sinab ko'rilgandan keyin ham natija
/// [TvClipCompress.recompressIfOverBytes]dan katta bo'lsa (yoki barcha
/// urinishlar muvaffaqiyatsiz tugasa) — `TvClipCompress.forUpload()` bu
/// xatoni EMAS, `TvClipCompressResult.oversized == true`ni qaytaradi;
/// bu tur faqat chaqiruvchi ekranda (`tv_publish_screen.dart`) yuklashni
/// bloklash uchun `throw` qilinadi.
class TvClipTooLargeException implements Exception {
  const TvClipTooLargeException();

  @override
  String toString() => 'TvClipTooLargeException';
}

/// `TvClipCompress.checkPostCompressDuration()` siqilgan natijaning
/// haqiqiy ijro davomiyligi [TvClipCompress.maxPostCompressSeconds]dan
/// oshganini aniqlasa — chaqiruvchi ekranda (`tv_publish_screen.dart`)
/// yuklashni bloklash uchun `throw` qilinadi. `forUpload()`ning o'zi
/// buni bilmaydi/qaytarmaydi — bu mustaqil, post-compression tekshiruv.
class TvClipTooLongException implements Exception {
  const TvClipTooLongException();

  @override
  String toString() => 'TvClipTooLongException';
}

class TvClipCompressResult {
  const TvClipCompressResult({
    required this.path,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.trimmed = false,
    this.skipped = false,
    this.oversized = false,
  });

  final String path;
  final int bytesIn;
  final int bytesOut;
  final bool trimmed;
  final bool skipped;

  /// To'liq zinapoya sinalgandan keyin ham natija ≤5MB emas (yoki
  /// barcha urinishlar muvaffaqiyatsiz) — [path] bu holatda siqilmagan
  /// (yoki eng yaxshi urinishning) fayliga ishora qiladi va
  /// YUKLANMASLIGI kerak.
  final bool oversized;
}

/// ТВ ролик: 720p / 24fps, макс. 60 с, катта файл → 540p → 480p.
class TvClipCompress {
  TvClipCompress._();

  static const maxHeight = 720;
  static const maxSeconds = 60;
  static const skipIfAtMostBytes = 3500000;
  static const recompressIfOverBytes = 5000000;

  /// Post-compression xavfsizlik-tekshiruvi: `forUpload()` natijasining
  /// haqiqiy ijro davomiyligi shundan oshsa — yuklash bloklanadi (native
  /// `duration: trimTo` kesishiga to'liq ishonmay, natijani qayta
  /// tekshirish uchun). Qarang: [checkPostCompressDuration].
  static const maxPostCompressSeconds = 200;

  static const _qualityLadder = [
    VideoQuality.Res1280x720Quality,
    VideoQuality.Res960x540Quality,
    VideoQuality.Res640x480Quality,
  ];

  static VideoQuality qualityFor({int? height, int? bytes}) {
    final h = height ?? 0;
    final b = bytes ?? 0;
    if (h > 0 && h <= 540 && b > skipIfAtMostBytes) {
      return VideoQuality.Res960x540Quality;
    }
    return VideoQuality.Res1280x720Quality;
  }

  static bool shouldSkip({int? height, int? bytes}) {
    final h = height ?? 0;
    final b = bytes ?? 0;
    return b > 0 && b <= skipIfAtMostBytes && h > 0 && h <= maxHeight;
  }

  /// [MediaInfo.duration] миллисекунд (баъзи қурилмалар сония беради).
  static int? clipDurationSeconds(double? durationMs) {
    if (durationMs == null || durationMs <= 0) return null;
    final seconds = durationMs >= 1000 ? durationMs / 1000.0 : durationMs;
    if (seconds <= maxSeconds) return null;
    return maxSeconds;
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
      final trimTo = clipDurationSeconds(info.duration);
      final height = info.height;
      if (trimTo == null && shouldSkip(height: height, bytes: bytesIn)) {
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
        final startQuality = qualityFor(height: height, bytes: bytesIn);
        var startIndex = _qualityLadder.indexOf(startQuality);
        if (startIndex < 0) startIndex = 0;

        final attemptBytes = <int?>[];
        final attemptPaths = <String?>[];
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
            attemptBytes.add(null);
            attemptPaths.add(null);
            continue;
          }
          attemptBytes.add(outBytes);
          attemptPaths.add(outPath);
          if (outBytes <= recompressIfOverBytes) break;
        }

        final outcome = resolveLadderOutcome(
          attemptBytes,
          targetBytes: recompressIfOverBytes,
        );
        final chosen = outcome.chosenIndex;
        if (chosen != null) {
          return TvClipCompressResult(
            path: attemptPaths[chosen]!,
            bytesIn: bytesIn,
            bytesOut: attemptBytes[chosen]!,
            trimmed: trimTo != null,
            oversized: outcome.oversized,
          );
        }
        // Zinapoyaning barcha bosqichlari muvaffaqiyatsiz tugadi — xom,
        // siqilmagan faylni qaytaramiz, lekin `oversized: true` bilan:
        // chaqiruvchi ekran buni HECH QACHON yuklamaydi.
        return TvClipCompressResult(
          path: path,
          bytesIn: bytesIn,
          bytesOut: bytesIn,
          oversized: true,
        );
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

  /// `forUpload()`dan KEYIN, alohida qadam sifatida chaqiriladi
  /// (`forUpload()`ning o'zi bunga tegmaydi/bilmaydi). Natija faylining
  /// haqiqiy davomiyligini `getMediaInfo()` orqali QAYTA o'qiydi —
  /// so'ralgan `trimTo` qiymatiga emas, native chiqishning o'ziga
  /// ishonib (audit: native trim kadr-aniqligi tasdiqlanmagan).
  static Future<bool> checkPostCompressDuration(String path) async {
    if (kIsWeb || path.isEmpty) return false;
    try {
      final info = await VideoCompress.getMediaInfo(path);
      final ms = info.duration;
      final seconds = (ms != null && ms >= 1000) ? ms / 1000.0 : ms;
      return exceedsMaxPostCompressDuration(seconds);
    } catch (e, st) {
      debugPrint('[TvClipCompress] post-compress duration check $e');
      unawaited(CrashReport.nonFatal(
        e,
        st,
        reason: 'tv_clip_compress_post_duration_check',
      ));
      return false;
    }
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

/// `TvClipCompress.forUpload()` zinapoyasidagi har bir urinish natijasini
/// (muvaffaqiyatsiz bo'lsa `null`, aks holda hajmi baytlarda) ketma-ket
/// oladi; qaysi urinish tanlanishini va yakuniy natija [targetBytes]dan
/// oshiq-oshmasligini hisoblaydi. `VideoCompress`'siz — sof, testlanadigan.
class LadderOutcome {
  const LadderOutcome({required this.chosenIndex, required this.oversized});

  /// Eng kichik muvaffaqiyatli urinishning indeksi — hammasi
  /// muvaffaqiyatsiz bo'lsa `null`.
  final int? chosenIndex;

  /// Tanlangan (yoki hech biri muvaffaqiyatli bo'lmasa — fallback) natija
  /// hali ham [targetBytes]dan katta.
  final bool oversized;
}

LadderOutcome resolveLadderOutcome(
  List<int?> attemptBytes, {
  required int targetBytes,
}) {
  int? bestIndex;
  for (var i = 0; i < attemptBytes.length; i++) {
    final bytes = attemptBytes[i];
    if (bytes == null || bytes <= 0) continue;
    if (bestIndex == null || bytes < attemptBytes[bestIndex]!) {
      bestIndex = i;
    }
    if (bytes <= targetBytes) {
      return LadderOutcome(chosenIndex: i, oversized: false);
    }
  }
  if (bestIndex == null) {
    return const LadderOutcome(chosenIndex: null, oversized: true);
  }
  return LadderOutcome(chosenIndex: bestIndex, oversized: true);
}

/// Sof qaror: [seconds] [TvClipCompress.maxPostCompressSeconds]dan
/// OSHGANMI (`>200` — `true`, rad etilishi kerak; `<=200` — `false`).
/// Noma'lum/o'qib bo'lmagan qiymat (`null` yoki `<=0`) — xavfsiz tomonga:
/// `false` (bloklanmaydi) — bu tekshiruv "native trim ishladimi" degan
/// noaniqlikni yopish uchun, metadata o'qish xatosi uchun emas.
bool exceedsMaxPostCompressDuration(num? seconds) {
  if (seconds == null || seconds <= 0) return false;
  return seconds > TvClipCompress.maxPostCompressSeconds;
}
