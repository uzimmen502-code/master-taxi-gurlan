import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Golden calligraphic frame on green cards (400×130 viewBox).
class CalligraphicBorderPainter extends CustomPainter {
  CalligraphicBorderPainter({this.isCompact = false});

  final bool isCompact;

  static const _vbW = 400.0;
  static const _vbH = 130.0;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _vbW;
    final sy = size.height / _vbH;
    final avg = (sx + sy) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        const [
          Color(0xFF9A7208),
          Color(0xFFE8B400),
          Color(0xFFFFF0A0),
          Color(0xFFF5C518),
          Color(0xFFC89000),
          Color(0xFF9A7208),
        ],
        const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      );

    Offset map(double x, double y, {bool mirrorX = false, bool mirrorY = false}) {
      if (mirrorX) x = _vbW - x;
      if (mirrorY) y = _vbH - y;
      return Offset(x * sx, y * sy);
    }

    double sw(double w) => w * avg;

    void rrect(double x, double y, double w, double h, double rx, double stroke) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = sw(stroke)
        ..shader = paint.shader;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy),
          Radius.circular(rx * avg),
        ),
        p,
      );
    }

    void line(double x1, double y1, double x2, double y2, double stroke,
        {bool mirrorX = false, bool mirrorY = false}) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = sw(stroke)
        ..shader = paint.shader;
      canvas.drawLine(
        map(x1, y1, mirrorX: mirrorX, mirrorY: mirrorY),
        map(x2, y2, mirrorX: mirrorX, mirrorY: mirrorY),
        p,
      );
    }

    void circle(double cx, double cy, double r, double stroke,
        {bool mirrorX = false, bool mirrorY = false}) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw(stroke)
        ..shader = paint.shader;
      canvas.drawCircle(map(cx, cy, mirrorX: mirrorX, mirrorY: mirrorY), r * avg, p);
    }

    void path(String d, double stroke,
        {bool mirrorX = false, bool mirrorY = false}) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = sw(stroke)
        ..shader = paint.shader;
      canvas.drawPath(
        _parsePath(d, (x, y) => map(x, y, mirrorX: mirrorX, mirrorY: mirrorY)),
        p,
      );
    }

    // Borders
    rrect(6, 6, 388, 118, 2, 0.8);
    rrect(10, 10, 380, 110, 1, 0.4);

    // Top center ornament
    circle(200, 10, 3, 0.8);
    circle(200, 10, 1.5, 0.6);

    const topRightSpirals = [
      ('M203 10 C210 8 216 5 220 8 C224 11 222 16 218 17 C214 18 211 15 213 12 C215 9 218 10 217 13', 1.0),
      ('M220 8 C226 4 234 4 237 9 C240 14 236 20 231 19 C227 18 225 14 228 11 C230 9 233 10 232 13', 0.9),
      ('M237 9 C244 5 252 6 254 12 C256 17 251 22 247 20', 0.8),
      ('M217 13 C219 17 218 21 214 22 C211 23 210 19 213 17', 0.7),
      ('M232 13 C234 18 232 23 228 24 C225 25 224 21 227 19', 0.7),
    ];
    for (final (d, w) in topRightSpirals) {
      path(d, w);
    }

    const topLeftSpirals = [
      ('M197 10 C190 8 184 5 180 8 C176 11 178 16 182 17 C186 18 189 15 187 12 C185 9 182 10 183 13', 1.0),
      ('M180 8 C174 4 166 4 163 9 C160 14 164 20 169 19 C173 18 175 14 172 11 C170 9 167 10 168 13', 0.9),
      ('M163 9 C156 5 148 6 146 12 C144 17 149 22 153 20', 0.8),
      ('M183 13 C181 17 182 21 186 22 C189 23 190 19 187 17', 0.7),
      ('M168 13 C166 18 168 23 172 24 C175 25 176 21 173 19', 0.7),
    ];
    for (final (d, w) in topLeftSpirals) {
      path(d, w);
    }

    path('M190 6 C193 3 197 2 200 2 C203 2 207 3 210 6', 0.7);

    circle(120, 10, 2, 0.7);
    circle(280, 10, 2, 0.7);
    circle(50, 10, 1.5, 0.6);
    circle(350, 10, 1.5, 0.6);

    line(10, 10, 118, 10, 0.6);
    line(122, 10, 145, 10, 0.6);
    line(255, 10, 278, 10, 0.6);
    line(282, 10, 390, 10, 0.6);

    // Bottom center ornament (vertical mirror)
    for (final (d, w) in topRightSpirals) {
      path(d, w, mirrorY: true);
    }
    for (final (d, w) in topLeftSpirals) {
      path(d, w, mirrorY: true);
    }
    circle(200, 10, 3, 0.8, mirrorY: true);
    circle(200, 10, 1.5, 0.6, mirrorY: true);
    path('M190 6 C193 3 197 2 200 2 C203 2 207 3 210 6', 0.7, mirrorY: true);
    circle(120, 10, 2, 0.7, mirrorY: true);
    circle(280, 10, 2, 0.7, mirrorY: true);
    circle(50, 10, 1.5, 0.6, mirrorY: true);
    circle(350, 10, 1.5, 0.6, mirrorY: true);
    line(10, 10, 118, 10, 0.6, mirrorY: true);
    line(122, 10, 145, 10, 0.6, mirrorY: true);
    line(255, 10, 278, 10, 0.6, mirrorY: true);
    line(282, 10, 390, 10, 0.6, mirrorY: true);

    // Side ornaments (full wallet card only)
    if (!isCompact) {
      circle(6, 65, 2.5, 0.7);

      const leftUpper = [
        ('M6 62 C4 58 2 54 4 51 C6 48 9 49 10 52 C11 55 9 57 7 56 C5 55 5 52 7 51', 0.8),
        ('M7 56 C5 60 4 63 6 65', 0.6),
        ('M3 54 C2 51 4 49 6 51 C8 49 10 51 9 54 C8 57 6 58 6 58 C6 58 4 57 3 54 Z', 0.7),
      ];
      const leftLower = [
        ('M6 68 C4 72 2 76 4 79 C6 82 9 81 10 78 C11 75 9 73 7 74 C5 75 5 78 7 79', 0.8),
        ('M7 74 C5 70 4 67 6 65', 0.6),
        ('M3 76 C2 79 4 81 6 79 C8 81 10 79 9 76 C8 73 6 72 6 72 C6 72 4 73 3 76 Z', 0.7),
      ];
      for (final (d, w) in leftUpper) {
        path(d, w);
      }
      for (final (d, w) in leftLower) {
        path(d, w);
      }
      for (final (d, w) in leftUpper) {
        path(d, w, mirrorX: true);
      }
      for (final (d, w) in leftLower) {
        path(d, w, mirrorX: true);
      }
      circle(394, 65, 2.5, 0.7);

      line(6, 10, 6, 48, 0.6);
      line(6, 82, 6, 120, 0.6);
      line(394, 10, 394, 48, 0.6);
      line(394, 82, 394, 120, 0.6);
    }

    // Corner ornaments
    path('M10 10 C14 14 14 18 10 20', 0.7);
    path('M10 10 C18 10 22 14 20 18', 0.7);
    circle(15, 15, 2, 0.6);

    path('M10 10 C14 14 14 18 10 20', 0.7, mirrorX: true);
    path('M10 10 C18 10 22 14 20 18', 0.7, mirrorX: true);
    circle(15, 15, 2, 0.6, mirrorX: true);

    path('M10 10 C14 14 14 18 10 20', 0.7, mirrorY: true);
    path('M10 10 C18 10 22 14 20 18', 0.7, mirrorY: true);
    circle(15, 15, 2, 0.6, mirrorY: true);

    path('M10 10 C14 14 14 18 10 20', 0.7, mirrorX: true, mirrorY: true);
    path('M10 10 C18 10 22 14 20 18', 0.7, mirrorX: true, mirrorY: true);
    circle(15, 15, 2, 0.6, mirrorX: true, mirrorY: true);
  }

  static Path _parsePath(
    String d,
    Offset Function(double x, double y) map,
  ) {
    final path = Path();
    final tokens = RegExp(r'[MLCZ]|[-+]?(?:\d*\.)?\d+(?:e[-+]?\d+)?')
        .allMatches(d)
        .map((m) => m.group(0)!)
        .toList();

    int i = 0;
    String? cmd;

    while (i < tokens.length) {
      final t = tokens[i];
      if (t == 'M' || t == 'L' || t == 'C' || t == 'Z') {
        cmd = t;
        i++;
        continue;
      }
      if (cmd == null) {
        i++;
        continue;
      }

      switch (cmd) {
        case 'M':
        case 'L':
          final x = double.parse(tokens[i++]);
          final y = double.parse(tokens[i++]);
          final pt = map(x, y);
          if (cmd == 'M') {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
          cmd = 'L';
          break;
        case 'C':
          final x1 = double.parse(tokens[i++]);
          final y1 = double.parse(tokens[i++]);
          final x2 = double.parse(tokens[i++]);
          final y2 = double.parse(tokens[i++]);
          final x = double.parse(tokens[i++]);
          final y = double.parse(tokens[i++]);
          path.cubicTo(
            map(x1, y1).dx,
            map(x1, y1).dy,
            map(x2, y2).dx,
            map(x2, y2).dy,
            map(x, y).dx,
            map(x, y).dy,
          );
          break;
        case 'Z':
          path.close();
          break;
        default:
          i++;
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant CalligraphicBorderPainter oldDelegate) => false;
}
