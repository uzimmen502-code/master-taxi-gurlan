import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

/// ТВ ролик юклаш: 720p / 24fps, катта файл бўлса 540p.
class TvClipCompress {
  TvClipCompress._();

  static const maxHeight = 720;
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

  /// Сиқилган йўл ёки асл файл (web / хато / аллақачон кичик).
  static Future<String> forUpload(String path) async {
    if (kIsWeb || path.isEmpty) return path;
    try {
      final info = await VideoCompress.getMediaInfo(path);
      var bytes = info.filesize ?? 0;
      if (bytes <= 0) {
        final f = File(path);
        if (f.existsSync()) bytes = f.lengthSync();
      }
      final height = info.height;
      if (shouldSkip(height: height, bytes: bytes)) return path;

      final first = await VideoCompress.compressVideo(
        path,
        quality: qualityFor(height: height, bytes: bytes),
        frameRate: 24,
        includeAudio: true,
        deleteOrigin: false,
      );
      var out = first?.file?.path;
      var outBytes = first?.filesize ?? 0;
      if (out != null && outBytes <= 0) {
        final f = File(out);
        if (f.existsSync()) outBytes = f.lengthSync();
      }

      if (out != null && outBytes > recompressIfOverBytes) {
        final second = await VideoCompress.compressVideo(
          path,
          quality: VideoQuality.Res960x540Quality,
          frameRate: 24,
          includeAudio: true,
          deleteOrigin: false,
        );
        final secondPath = second?.file?.path;
        var secondBytes = second?.filesize ?? 0;
        if (secondPath != null && secondBytes <= 0) {
          final f = File(secondPath);
          if (f.existsSync()) secondBytes = f.lengthSync();
        }
        if (secondPath != null &&
            secondBytes > 0 &&
            (outBytes <= 0 || secondBytes < outBytes)) {
          out = secondPath;
          outBytes = secondBytes;
        }
      }

      if (out != null && outBytes > 0 && (bytes <= 0 || outBytes < bytes)) {
        return out;
      }
    } catch (e) {
      debugPrint('[TvClipCompress] $e');
    }
    return path;
  }

  static Future<Uint8List?> thumbnailBytes(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    try {
      final file = await VideoCompress.getFileThumbnail(
        path,
        quality: 55,
        position: -1,
      );
      if (file.existsSync()) return file.readAsBytes();
    } catch (e) {
      debugPrint('[TvClipCompress] thumb $e');
    }
    return null;
  }
}
