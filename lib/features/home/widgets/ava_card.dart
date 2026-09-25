import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

/// Бир хил карточка — оқ усти, ингичка контур, радиус 12, соясиз.
///
/// Янги дизайн тизимида барча карточка бир хил: градиент, рангли соя ва
/// ҳар модулга алоҳида безак йўқ.
class AvaCard extends StatelessWidget {
  const AvaCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.width,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double? width;

  /// Танланган ҳолат — контур бренд рангида.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);

    final body = Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        border: Border.all(
          color: selected ? c.brand : c.line,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: child,
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: body,
      ),
    );
  }
}
