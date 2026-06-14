import 'package:flutter/material.dart';

/// Bosh ekran modul kartalari matni — zonaga sig'adi, [minScale] dan past tushmaydi.
class HomeModuleFittedBox extends StatelessWidget {
  const HomeModuleFittedBox({
    super.key,
    required this.maxWidth,
    required this.child,
    this.alignment = Alignment.center,
    this.minScale = 0.82,
  });

  /// Barcha modul kartalari uchun bir xil pastki chegara.
  static const double defaultMinScale = 0.82;

  final double maxWidth;
  final Widget child;
  final Alignment alignment;
  final double minScale;

  @override
  Widget build(BuildContext context) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return child;

    final floor = minScale.clamp(0.5, 1.0);
    return SizedBox(
      width: maxWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth / floor),
          child: child,
        ),
      ),
    );
  }
}
