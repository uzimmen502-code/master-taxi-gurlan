import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Танланган тўхташнинг харита маркери: қизил доира ичида йўл бўйича
/// тартиб рақами (1, 2, 3...). КОДДА чизилади, ҳар рақам бир марта чизилиб
/// кешланади. Қизил ранг — «асосий тўхташ» ранги (легенда билан бир хил).
class EvTripStopIcon {
  EvTripStopIcon._();

  /// «Асосий тўхташ» ранги (легенда ва тавсия белгиси билан бир хил).
  static const Color color = Color(0xFFD32F2F);

  /// Харитадаги мантиқий ўлчам (dp).
  static const double logicalSize = 38;

  /// Чизиш аниқлиги (px) — ёрқин экранлар учун 3x.
  static const int _px = 114;

  static final Map<int, Future<BitmapDescriptor>> _cache = {};

  /// Чизиб бўлмаса (мас. тест муҳити) — оддий қизил маркер.
  static Future<BitmapDescriptor> load(int number) {
    return _cache[number] ??= _draw(number).catchError((Object e) {
      debugPrint('EvTripStopIcon($number): $e');
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    });
  }

  static Future<BitmapDescriptor> _draw(int number) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const s = _px / 1.0;
    const c = Offset(s / 2, s / 2);

    // Соя + оқ ҳалқа — ёруғ ва қоронғи харитада кўриниши учун.
    canvas.drawCircle(
      c.translate(0, 3),
      s * 0.44,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, s * 0.44, Paint()..color = Colors.white);
    canvas.drawCircle(c, s * 0.37, Paint()..color = color);

    final text = '$number';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: s * (text.length > 1 ? 0.36 : 0.46),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(c.dx - painter.width / 2, c.dy - painter.height / 2),
    );

    final image = await recorder.endRecording().toImage(_px, _px);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('icon bytes null');
    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: logicalSize,
      height: logicalSize,
    );
  }

  @visibleForTesting
  static void reset() => _cache.clear();
}
