import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// Сафар харитасида режага КИРМАГАН ва танланмаган «бошқа» станциялар учун
/// ЙИРИК бўлмаган хира нуқта (эга қарори, 2026-10-16): тавсия этилган
/// тўхташлар кўриниш марказида қолсин, қолганлари фон бўлиб турсин. Ёрқин
/// яшил игна ўрнига тема токенидаги нейтрал кулранг ([AvaLight.ink3]) доира.
///
/// КОДДА чизилади ва рақамли иконкалар каби ([EvTripStopIcon]) бир марта
/// чизилиб кешланади. Кўринадиган нуқта кичик, лекин иконка полотноси
/// каттароқ (шаффоф чекка) — босиш майдони бармоқ учун етарли.
class EvTripDotIcon {
  EvTripDotIcon._();

  /// Нуқта ранги — тема токенидаги нейтрал кулранг (легенда билан бир хил).
  static const Color color = AvaLight.ink3;

  /// Иконка полотноси (dp): босиладиган майдон.
  static const double logicalSize = 28;

  /// Кўринадиган нуқта диаметри (dp): оқ ҳалқа билан.
  static const double visibleDiameter = 16;

  static const int _px = 84; // 3x

  static Future<BitmapDescriptor>? _cache;

  /// Чизиб бўлмаса (мас. тест муҳити) — оддий маркер.
  static Future<BitmapDescriptor> load() {
    return _cache ??= _draw().catchError((Object e) {
      debugPrint('EvTripDotIcon: $e');
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    });
  }

  static Future<BitmapDescriptor> _draw() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const s = _px / 1.0;
    const c = Offset(s / 2, s / 2);
    const outer = s * (visibleDiameter / logicalSize) / 2;

    // Оқ ҳалқа — ёруғ ва қоронғи харитада нуқта йўқолмаслиги учун.
    canvas.drawCircle(c, outer, Paint()..color = Colors.white);
    canvas.drawCircle(c, outer * 0.74, Paint()..color = color);

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
  static void reset() => _cache = null;
}
