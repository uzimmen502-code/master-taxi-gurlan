part of 'family_tree_view.dart';

class _FamilyNode {
  _FamilyNode(this.members);

  final List<RelativePerson> members;
  final List<_FamilyNode> children = [];
  _FamilyNode? parent;
  String? anchorId;
  int gen = 0;
  double centerX = 0;
  Color? familyColor;
  Rect? outerRect;

  bool get isCouple => members.length == 2;
}

/// Segment — global koordinatalarda (koridor + karta qatorlari orasida).
class _LineSeg {
  const _LineSeg(this.a, this.b, this.color, this.width);
  final Offset a;
  final Offset b;
  final Color color;
  final double width;
}

class _TreeLinesPainter extends CustomPainter {
  _TreeLinesPainter(this.segments, this.revision);

  final List<_LineSeg> segments;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in segments) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s.a, s.b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TreeLinesPainter old) =>
      old.revision != revision;
}

class _CardBorderPainter extends CustomPainter {
  _CardBorderPainter({
    required this.inheritedColor,
    required this.bottomColor,
    required this.splitBottom,
    required this.radius,
    required this.strokeWidth,
  });

  final Color inheritedColor;
  final Color bottomColor;
  final bool splitBottom;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    if (!splitBottom) {
      final paint = Paint()
        ..color = inheritedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
      return;
    }

    final topPaint = Paint()
      ..color = inheritedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final bottomPaint = Paint()
      ..color = bottomColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final tl = Offset(rect.left + radius, rect.top);
    final tr = Offset(rect.right - radius, rect.top);

    canvas.drawLine(tl, tr, topPaint);
    canvas.drawLine(Offset(rect.left, rect.top + radius),
        Offset(rect.left, rect.bottom - radius), topPaint);
    canvas.drawLine(Offset(rect.right, rect.top + radius),
        Offset(rect.right, rect.bottom - radius), topPaint);
    canvas.drawLine(
      Offset(rect.left + radius, rect.bottom),
      Offset(rect.right - radius, rect.bottom),
      bottomPaint,
    );

    canvas.drawArc(
      Rect.fromLTWH(rect.left, rect.top, radius * 2, radius * 2),
      math.pi,
      math.pi / 2,
      false,
      topPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(rect.right - radius * 2, rect.top, radius * 2, radius * 2),
      -math.pi / 2,
      math.pi / 2,
      false,
      topPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
          rect.right - radius * 2, rect.bottom - radius * 2, radius * 2, radius * 2),
      0,
      math.pi / 2,
      false,
      bottomPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
          rect.left, rect.bottom - radius * 2, radius * 2, radius * 2),
      math.pi / 2,
      math.pi / 2,
      false,
      bottomPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CardBorderPainter old) =>
      old.inheritedColor != inheritedColor ||
      old.bottomColor != bottomColor ||
      old.splitBottom != splitBottom;
}
