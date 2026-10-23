import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/business_category.dart';

/// Харитадаги маркерлар: тур рангидаги томчи (пин) + оқ иконка (эга, 2026-10-23: чип ва маркер бир хил ранг).
/// Иконка PNG'га бир марта чизилади ва тур бўйича кешланади (14 тадан ортиқ эмас).
abstract final class BusinessMarkerIcons {
  static const double _logical = 44; // харитадаги ўлчам (dp)
  static const double _scale = 3; // чизиш аниқлиги

  static final Map<BusinessCategory, Future<BitmapDescriptor>> _cache = {};

  static Future<BitmapDescriptor> of(BusinessCategory c) => _cache.putIfAbsent(c, () => _render(c));

  /// Тур бўйича тайёр иконка (синхрон; ҳали чизилмаган бўлса `null` — чақирувчи стандарт маркер қўяди).
  static final Map<BusinessCategory, BitmapDescriptor> ready = {};

  /// Барча 14 тур иконкасини олдиндан чизиб қўяди (экран очилганда бир марта).
  static Future<void> warmUp() async {
    for (final c in BusinessCategory.values) {
      ready[c] = await of(c);
    }
  }

  static Future<BitmapDescriptor> _render(BusinessCategory c) async {
    final size = _logical * _scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final center = Offset(size / 2, size / 2);
    final r = size / 2 - 3 * _scale;
    canvas.drawCircle(center + Offset(0, 1.5 * _scale), r, Paint()..color = const Color(0x33000000));
    canvas.drawCircle(center, r, Paint()..color = c.color);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * _scale,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(c.icon.codePoint),
        style: TextStyle(
          fontSize: r * 1.15,
          fontFamily: c.icon.fontFamily,
          package: c.icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes, width: _logical, height: _logical);
  }
}
