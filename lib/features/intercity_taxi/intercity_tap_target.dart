import 'package:flutter/material.dart';

/// Шаҳарлараро такси модули учун ягона тегиш майдони: камида 48×48 dp,
/// босганда ripple, screen reader учун `label` (ва `selected` ҳолати).
///
/// Кўринадиган шакл (`child`) кичик бўлиши мумкин — босиш майдони
/// `size` га кенгаяди. `onTap == null` — ўчиқ тугма.
class IntercityTapTarget extends StatelessWidget {
  const IntercityTapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.size = minSize,
    this.radius = 12,
    this.selected,
  });

  /// Material тавсияси (Android): 48 dp.
  static const double minSize = 48;

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final double size;
  final double radius;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: size, minHeight: size),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// «Иконка + матн» қатори — эмодзи ўрнига вектор иконка.
/// Иконка декоратив: матн ўзи маънони беради, шунинг учун screen reader
/// иконкани ўқимайди.
class IntercityIconText extends StatelessWidget {
  const IntercityIconText({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor,
    this.style,
    this.iconSize = 16,
    this.maxLines,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final TextStyle? style;
  final double iconSize;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
