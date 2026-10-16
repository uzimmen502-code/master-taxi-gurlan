import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// Машина маркери иконкаси — КОДДА чизилади (янги расм ресурси керак эмас).
/// Бренд ранги ([AppColors.primary]) доираси ичида шимолга қараган
/// навигация ўқи ([AppColors.onPrimary]); харита маркерни `rotation` билан
/// йўналишга буради. Бир марта чизилиб кешланади.
class EvCarMarkerIcon {
  EvCarMarkerIcon._();

  /// Харитадаги мантиқий ўлчам (dp).
  static const double logicalSize = 44;

  /// Чизиш аниқлиги (px) — ёрқин экранлар учун 3x.
  static const int _px = 132;

  static Future<BitmapDescriptor>? _cached;

  /// Чизиб бўлмаса (мас. тест муҳити) — оддий маркер ранги билан.
  static Future<BitmapDescriptor> load() {
    return _cached ??= _draw().catchError((Object e) {
      debugPrint('EvCarMarkerIcon: $e');
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    });
  }

  static Future<BitmapDescriptor> _draw() async {
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
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(c, s * 0.44, Paint()..color = Colors.white);
    canvas.drawCircle(c, s * 0.37, Paint()..color = AppColors.primary);

    // Шимолга қараган ўқ (тепаси ўткир, ичи ўйилган).
    final r = s * 0.24;
    final arrow = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * math.cos(math.pi / 5), c.dy + r * 0.85)
      ..lineTo(c.dx, c.dy + r * 0.35)
      ..lineTo(c.dx - r * math.cos(math.pi / 5), c.dy + r * 0.85)
      ..close();
    canvas.drawPath(arrow, Paint()..color = AppColors.onPrimary);

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
  static void reset() => _cached = null;
}
