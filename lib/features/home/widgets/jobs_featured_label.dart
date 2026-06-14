import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/home_label_animator.dart';
import 'home_module_fitted_box.dart';

/// Ish top kartasi — 1-qator yuqorida, 2-qator pastda, bir xil shrift, to‘lqin animatsiyasi.
class JobsFeaturedLabel extends StatelessWidget {
  const JobsFeaturedLabel({
    super.key,
    required this.moduleId,
    required this.plainText,
    required this.firstLineStyle,
    required this.urgentLineStyle,
    required this.highlightFromIndex,
    this.spreadVertically = false,
    this.cellHeight,
    this.lineMaxWidth,
    this.lineMinScale = HomeModuleFittedBox.defaultMinScale,
  });

  final String moduleId;
  final String plainText;
  final TextStyle firstLineStyle;
  final TextStyle urgentLineStyle;
  final int highlightFromIndex;
  final bool spreadVertically;
  final double? cellHeight;

  /// Har qator — [HomeModuleFittedBox] bilan sig'adi (min 82%).
  final double? lineMaxWidth;
  final double lineMinScale;

  List<String> get _lines => plainText.split('\n');

  TextStyle _styleForLine(int charIndex) {
    if (charIndex >= highlightFromIndex) {
      return urgentLineStyle;
    }
    return firstLineStyle;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animator = context.watch<HomeLabelAnimator>();
    final lines = _lines;

    if (reduceMotion || plainText.isEmpty) {
      return _wrapLayout(_staticColumn());
    }

    final active = animator.isActive(moduleId);
    final wave = animator.waveIndex;
    var charGlobal = 0;

    return _wrapLayout(
      Column(
        mainAxisSize:
            spreadVertically ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: spreadVertically
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
            _wrapLine(
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  for (final ch in lines[lineIndex].characters)
                    _animatedChar(
                      ch,
                      index: charGlobal++,
                      active: active,
                      wave: wave,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrapLayout(Widget child) {
    if (!spreadVertically || cellHeight == null) return child;
    return SizedBox(
      height: cellHeight,
      width: double.infinity,
      child: child,
    );
  }

  Widget _wrapLine(Widget line) {
    if (lineMaxWidth == null || lineMaxWidth! <= 0) {
      return line;
    }
    return HomeModuleFittedBox(
      maxWidth: lineMaxWidth!,
      alignment: Alignment.centerRight,
      minScale: lineMinScale,
      child: line,
    );
  }

  Widget _animatedChar(
    String ch, {
    required int index,
    required bool active,
    required int wave,
  }) {
    final style = _styleForLine(index);
    var opacity = 1.0;
    var weight = style.fontWeight ?? FontWeight.w900;

    if (active) {
      if (index > wave) {
        opacity = 0.32;
        weight = FontWeight.w600;
      }
    }

    return Text(
      ch,
      style: style.copyWith(
        color: style.color?.withValues(alpha: opacity),
        fontWeight: weight,
      ),
    );
  }

  Widget _staticColumn() {
    var offset = 0;
    return Column(
      mainAxisSize:
          spreadVertically ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: spreadVertically
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < _lines.length; i++)
          Builder(
            builder: (context) {
              final line = _lines[i];
              final lineStart = offset;
              final lineEnd = offset + line.length;
              offset = lineEnd;
              late final Widget lineWidget;
              if (highlightFromIndex >= lineEnd) {
                lineWidget = Text(
                  line,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: firstLineStyle,
                );
              } else if (highlightFromIndex <= lineStart) {
                lineWidget = Text(
                  line,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: urgentLineStyle,
                );
              } else {
                final local = highlightFromIndex - lineStart;
                lineWidget = Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: line.substring(0, local),
                        style: firstLineStyle,
                      ),
                      TextSpan(
                        text: line.substring(local),
                        style: urgentLineStyle,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.right,
                );
              }
              return _wrapLine(lineWidget);
            },
          ),
      ],
    );
  }
}
