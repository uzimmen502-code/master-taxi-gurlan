import 'package:flutter/material.dart';

/// Barcha modul kartalari — yuqori va pastki barg dekorlari.
class HomeModuleCardLeaves {
  HomeModuleCardLeaves._();

  static const double defaultSize = 52;

  static List<Widget> positioned({
    double size = defaultSize,
    double top = -6,
    double bottom = -6,
  }) =>
      [
        Positioned(
          top: top,
          right: 0,
          child: _leaf('assets/images/leaf_top.png', size),
        ),
        Positioned(
          bottom: bottom,
          right: 0,
          child: _leaf('assets/images/leaf_buttom.png', size),
        ),
      ];

  static Widget _leaf(String asset, double width) {
    return Image.asset(
      asset,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
