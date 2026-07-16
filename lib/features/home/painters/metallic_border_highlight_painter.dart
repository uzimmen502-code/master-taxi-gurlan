import 'package:flutter/material.dart';

/// Karta konturi **butun bo'ylab bir vaqtda (yaxlit)** to'q ranglarga ketma-ket
/// almashadi: ramka har lahzada bitta rang bo'lib, [progress] bilan navbatma-navbat
/// barcha to'q ranglardan yumshoq o'tadi.
class MetallicBorderHighlightPainter extends CustomPainter {
  MetallicBorderHighlightPainter({
    required this.progress,
    required this.borderRadius,
    this.strokeWidth = 3.0,
  });

  /// 0..1 — ranglar halqasi bo'ylab to'liq bir aylanish.
  final double progress;
  final double borderRadius;
  final double strokeWidth;

  /// To'q, to'yingan ranglar (7 ta) — halqa bo'ylab uzluksiz aylanadi.
  static const _deepColors = <Color>[
    Color(0xFF8E0000), // to'q qizil
    Color(0xFFB8860B), // to'q oltin
    Color(0xFF1B5E20), // to'q yashil
    Color(0xFF006064), // to'q feruza
    Color(0xFF0D47A1), // to'q ko'k
    Color(0xFF4A148C), // to'q binafsha
    Color(0xFF880E4F), // to'q malina
  ];

  /// [progress] bo'yicha butun konturning yaxlit rangi (qo'shni ranglar orasida lerp).
  Color _colorAt(double p) {
    final n = _deepColors.length;
    final scaled = (p % 1.0) * n;
    final i = scaled.floor() % n;
    final t = scaled - scaled.floorToDouble();
    return Color.lerp(_deepColors[i], _deepColors[(i + 1) % n], t)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final inset = strokeWidth / 2 + 0.5;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    if (rect.isEmpty) return;

    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular((borderRadius - inset).clamp(0.0, borderRadius)),
    );

    // Butun kontur — bitta yaxlit rang (xira glow'siz, aniq chiziq).
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = _colorAt(progress),
    );
  }

  @override
  bool shouldRepaint(covariant MetallicBorderHighlightPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
