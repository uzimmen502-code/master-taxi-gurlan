import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/utils/crash_report.dart';

class TvClipCompressResult {
  const TvClipCompressResult({
    required this.path,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.trimmed = false,
    this.skipped = false,
  });

  final String path;
  final int bytesIn;
  final int bytesOut;
  final bool trimmed;
  final bool skipped;
}

/// ТВ ролик: 720p / 24fps, макс. 60 с, катта файл → 540p.
class TvClipCompress {
  TvClipCompress._();

  static const maxHeight = 720;
  static const maxSeconds = 60;
  static const skipIfAtMostBytes = 3500000;
  static const recompressIfOverBytes = 5000000;

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
        final first = await VideoCompress.compressVideo(
          path,
          quality: qualityFor(height: height, bytes: bytesIn),
          frameRate: 24,
          includeAudio: true,
          deleteOrigin: false,
          duration: trimTo,
        );
        var out = first?.file?.path;
        var outBytes = _fileBytes(out, first?.filesize);
        if (out != null && outBytes > recompressIfOverBytes) {
          final second = await VideoCompress.compressVideo(
            path,
            quality: VideoQuality.Res960x540Quality,
            frameRate: 24,
            includeAudio: true,
            deleteOrigin: false,
            duration: trimTo,
          );
          final secondPath = second?.file?.path;
          final secondBytes = _fileBytes(secondPath, second?.filesize);
          if (secondPath != null &&
              secondBytes > 0 &&
              (outBytes <= 0 || secondBytes < outBytes)) {
            out = secondPath;
            outBytes = secondBytes;
          }
        }
        if (out != null &&
            outBytes > 0 &&
            (bytesIn <= 0 || outBytes < bytesIn)) {
          return TvClipCompressResult(
            path: out,
            bytesIn: bytesIn,
            bytesOut: outBytes,
            trimmed: trimTo != null,
          );
        }
        if (out != null && trimTo != null) {
          return TvClipCompressResult(
            path: out,
            bytesIn: bytesIn,
            bytesOut: outBytes > 0 ? outBytes : bytesIn,
            trimmed: true,
          );
        }
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
