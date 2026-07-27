import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Browser-side image normalize/compress for admin uploads (ChatGPT / large PNG).
class WebImageCompress {
  WebImageCompress._();

  /// Hard ceiling before we even try (matches market ads Storage rule spirit).
  static const int maxInputBytes = 12 * 1024 * 1024;

  /// Target after compress — keep uploads snappy.
  static const int targetBytes = 1500 * 1024;

  /// Absolute reject after compress attempts.
  static const int maxOutputBytes = 8 * 1024 * 1024;

  /// Returns JPEG bytes + mime. Falls back to original if decode fails.
  static Future<({Uint8List bytes, String mime})> prepareForUpload(
    Uint8List input, {
    String mimeHint = 'image/jpeg',
  }) async {
    if (input.isEmpty) {
      return (bytes: input, mime: mimeHint);
    }
    if (input.length > maxInputBytes) {
      throw StateError(
        'Расм жуда катта (${_mb(input.length)} MB). 12 MB дан кичик бўлсин.',
      );
    }

    // Small enough already — keep original format.
    if (input.length <= targetBytes) {
      return (
        bytes: input,
        mime: mimeHint.startsWith('image/') ? mimeHint : 'image/jpeg',
      );
    }

    try {
      final compressed = await _canvasJpeg(
        input,
        maxEdge: 1600,
        quality: 0.82,
      );
      if (compressed != null &&
          compressed.isNotEmpty &&
          compressed.length < input.length) {
        if (compressed.length <= maxOutputBytes) {
          return (bytes: compressed, mime: 'image/jpeg');
        }
      }

      // Second pass: smaller edge / lower quality.
      final tighter = await _canvasJpeg(
        input,
        maxEdge: 1280,
        quality: 0.7,
      );
      if (tighter != null &&
          tighter.isNotEmpty &&
          tighter.length <= maxOutputBytes) {
        return (bytes: tighter, mime: 'image/jpeg');
      }
    } catch (_) {
      // Fall through to original / reject.
    }

    if (input.length <= maxOutputBytes) {
      return (
        bytes: input,
        mime: mimeHint.startsWith('image/') ? mimeHint : 'image/jpeg',
      );
    }
    throw StateError(
      'Расм ${_mb(input.length)} MB — сиқилгандан кейин ҳам 8 MB дан катта. '
      'Кичикроқ расм танланг.',
    );
  }

  static Future<Uint8List?> _canvasJpeg(
    Uint8List bytes, {
    required int maxEdge,
    required double quality,
  }) async {
    final blob = html.Blob([bytes]);
    final objectUrl = html.Url.createObjectUrlFromBlob(blob);
    try {
      final img = html.ImageElement();
      final loaded = Completer<void>();
      late StreamSubscription<html.Event> ok;
      late StreamSubscription<html.Event> err;
      ok = img.onLoad.listen((_) {
        ok.cancel();
        err.cancel();
        if (!loaded.isCompleted) loaded.complete();
      });
      err = img.onError.listen((_) {
        ok.cancel();
        err.cancel();
        if (!loaded.isCompleted) {
          loaded.completeError(StateError('image decode failed'));
        }
      });
      img.src = objectUrl;
      await loaded.future.timeout(const Duration(seconds: 20));

      final w = img.naturalWidth;
      final h = img.naturalHeight;
      if (w <= 0 || h <= 0) return null;

      var tw = w;
      var th = h;
      final longEdge = w > h ? w : h;
      if (longEdge > maxEdge) {
        final scale = maxEdge / longEdge;
        tw = (w * scale).round().clamp(1, w);
        th = (h * scale).round().clamp(1, h);
      }

      final canvas = html.CanvasElement(width: tw, height: th);
      final ctx = canvas.context2D;
      ctx.drawImageScaled(img, 0, 0, tw, th);
      final dataUrl = canvas.toDataUrl('image/jpeg', quality);
      final comma = dataUrl.indexOf(',');
      if (comma < 0) return null;
      return base64Decode(dataUrl.substring(comma + 1));
    } finally {
      html.Url.revokeObjectUrl(objectUrl);
    }
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
