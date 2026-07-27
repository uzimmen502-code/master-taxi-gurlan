import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Clipboard / paste image extraction for admin web dialogs.
class ClipboardPasteImage {
  ClipboardPasteImage._();

  /// True when paste payload likely contains an image (safe to preventDefault).
  static bool looksLikeImagePaste(html.ClipboardEvent event) {
    final data = event.clipboardData;
    if (data == null) return false;

    final items = data.items;
    if (items != null) {
      final itemCount = items.length ?? 0;
      for (var i = 0; i < itemCount; i++) {
        final item = items[i];
        final type = (item.type ?? '').toLowerCase();
        if (type.startsWith('image/')) return true;
        if (item.kind == 'file' &&
            (type.isEmpty || type == 'application/octet-stream')) {
          return true;
        }
      }
    }

    final files = data.files;
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        if (f.type.toLowerCase().startsWith('image/') ||
            _nameLooksImage(f.name)) {
          return true;
        }
      }
    }

    final htmlText = data.getData('text/html');
    if (htmlText.toLowerCase().contains('<img')) return true;

    final plain = data.getData('text/plain').trim();
    if (_looksLikeImageUrl(plain)) return true;

    return false;
  }

  /// Reads image bytes from a paste [ClipboardEvent].
  ///
  /// Blob/File handles are captured synchronously during the event, then
  /// decoded asynchronously (Chrome invalidates clipboard files after the turn).
  static Future<({Uint8List bytes, String mime})?> fromPasteEvent(
    html.ClipboardEvent event,
  ) async {
    final data = event.clipboardData;
    if (data == null) return null;

    final pending = <({html.Blob blob, String mimeHint})>[];

    // 1) DataTransferItemList — capture File handles NOW
    final items = data.items;
    if (items != null) {
      final itemCount = items.length ?? 0;
      for (var i = 0; i < itemCount; i++) {
        final item = items[i];
        final type = (item.type ?? '').toLowerCase();
        final kind = item.kind;
        final looksImage = type.startsWith('image/') ||
            (kind == 'file' &&
                (type.isEmpty || type == 'application/octet-stream'));
        if (!looksImage) continue;
        final file = item.getAsFile();
        if (file == null) continue;
        pending.add((
          blob: file,
          mimeHint: type.startsWith('image/') ? type : '',
        ));
      }
    }

    // 2) clipboardData.files
    final files = data.files;
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final type = file.type.toLowerCase();
        if (!(type.startsWith('image/') || _nameLooksImage(file.name))) {
          continue;
        }
        pending.add((
          blob: file,
          mimeHint: type.startsWith('image/')
              ? type
              : (_mimeFromName(file.name) ?? ''),
        ));
      }
    }

    final htmlFallback = data.getData('text/html');
    final urlFallback = data.getData('text/plain').trim();

    for (final entry in pending) {
      final bytes = await blobToBytes(entry.blob);
      if (bytes == null || bytes.isEmpty) continue;
      final mime = entry.mimeHint.isNotEmpty
          ? entry.mimeHint
          : (_sniffMime(bytes) ?? 'image/png');
      return (bytes: bytes, mime: mime);
    }

    // 3) HTML <img src>
    if (htmlFallback.isNotEmpty) {
      final src = _firstImgSrc(htmlFallback);
      if (src != null) {
        final loaded = await loadFromSrc(src);
        if (loaded != null) return loaded;
      }
    }

    // 4) Plain image URL
    if (_looksLikeImageUrl(urlFallback)) {
      final loaded = await loadFromSrc(urlFallback);
      if (loaded != null) return loaded;
    }

    return null;
  }

  static Future<({Uint8List bytes, String mime})?> loadFromSrc(String src) async {
    final s = src.trim();
    if (s.startsWith('data:image/')) {
      final bytes = _decodeDataUrl(s);
      if (bytes == null || bytes.isEmpty) return null;
      final mime = _mimeFromDataUrl(s) ?? _sniffMime(bytes) ?? 'image/png';
      return (bytes: bytes, mime: mime);
    }
    if (s.startsWith('blob:') ||
        s.startsWith('http://') ||
        s.startsWith('https://')) {
      try {
        final req = await html.HttpRequest.request(
          s,
          method: 'GET',
          responseType: 'arraybuffer',
        );
        final bytes = _coerceToBytes(req.response);
        if (bytes == null || bytes.isEmpty) return null;
        final header =
            req.getResponseHeader('content-type')?.split(';').first.trim();
        return (
          bytes: bytes,
          mime: (header != null && header.startsWith('image/'))
              ? header
              : (_sniffMime(bytes) ?? 'image/png'),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Robust Blob → bytes (Data URL avoids Flutter web ArrayBuffer typing bugs).
  static Future<Uint8List?> blobToBytes(html.Blob blob) async {
    final viaDataUrl = await _readBlob(blob, asDataUrl: true);
    if (viaDataUrl is String) {
      final decoded = _decodeDataUrl(viaDataUrl);
      if (decoded != null && decoded.isNotEmpty) return decoded;
    }

    final viaBuffer = await _readBlob(blob, asDataUrl: false);
    final coerced = _coerceToBytes(viaBuffer);
    if (coerced != null && coerced.isNotEmpty) return coerced;
    return null;
  }

  static Future<Object?> _readBlob(html.Blob blob, {required bool asDataUrl}) {
    final reader = html.FileReader();
    final done = Completer<Object?>();
    late StreamSubscription<html.ProgressEvent> loadSub;
    late StreamSubscription<html.ProgressEvent> errSub;
    void finish(Object? value) {
      if (done.isCompleted) return;
      loadSub.cancel();
      errSub.cancel();
      done.complete(value);
    }

    loadSub = reader.onLoad.listen((_) => finish(reader.result));
    errSub = reader.onError.listen((_) => finish(null));
    if (asDataUrl) {
      reader.readAsDataUrl(blob);
    } else {
      reader.readAsArrayBuffer(blob);
    }
    return done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
  }

  static Uint8List? _coerceToBytes(Object? result) {
    if (result == null) return null;
    if (result is Uint8List) return result;
    if (result is ByteBuffer) return Uint8List.view(result);
    if (result is TypedData) {
      return Uint8List.view(
        result.buffer,
        result.offsetInBytes,
        result.lengthInBytes,
      );
    }
    if (result is List<int>) return Uint8List.fromList(result);
    try {
      // ignore: avoid_dynamic_calls
      final dynamic dyn = result;
      if (dyn is ByteBuffer) return Uint8List.view(dyn);
      final length = dyn.length as int?;
      if (length != null && length > 0) {
        final out = Uint8List(length);
        for (var i = 0; i < length; i++) {
          out[i] = dyn[i] as int;
        }
        return out;
      }
    } catch (_) {}
    return null;
  }

  static Uint8List? _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static String? _mimeFromDataUrl(String dataUrl) {
    final m = RegExp(r'data:(image/[a-zA-Z0-9.+-]+)').firstMatch(dataUrl);
    return m?.group(1)?.toLowerCase();
  }

  static String? _firstImgSrc(String htmlText) {
    final m = RegExp(
      r'''<img[^>]+src\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(htmlText);
    return m?.group(1);
  }

  static bool _looksLikeImageUrl(String s) {
    if (!(s.startsWith('http://') || s.startsWith('https://'))) return false;
    final lower = s.toLowerCase();
    return lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('.gif') ||
        lower.contains('image') ||
        lower.contains('oaidalle') ||
        lower.contains('chatgpt');
  }

  static bool _nameLooksImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif');
  }

  static String? _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }

  static String? _sniffMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    return null;
  }
}
