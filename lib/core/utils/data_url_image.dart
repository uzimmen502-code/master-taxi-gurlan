import 'dart:convert';
import 'dart:typed_data';

/// `data:image/png;base64,...` / `data:image/jpeg;base64,...` дан байтлар.
Uint8List? decodeDataUrlImageBytes(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (!s.startsWith('data:image/')) return null;
  final comma = s.indexOf(',');
  if (comma < 0 || comma >= s.length - 1) return null;
  final payload = s.substring(comma + 1).trim();
  if (payload.isEmpty) return null;
  try {
    return Uint8List.fromList(base64Decode(payload));
  } catch (_) {
    return null;
  }
}

bool isHttpImageUrl(String s) {
  final t = s.trim();
  return t.startsWith('http://') || t.startsWith('https://');
}

bool isDataImageUrl(String s) => s.trim().startsWith('data:image/');
