import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/home_label_animator.dart';

/// Modul kartasi ostidagi matn — faol kartada harflar ketma-ket yorug'lanadi.
class WaveLabelText extends StatelessWidget {
  const WaveLabelText({
    super.key,
    required this.moduleId,
    required this.plainText,
    required this.baseStyle,
    this.highlightStyle,
    this.highlightFromIndex,
    this.maxLines = 4,
    this.maxWidth,
    this.wrapAlignment = WrapAlignment.center,
  });

  final String moduleId;
  final String plainText;
  final TextStyle baseStyle;
  final TextStyle? highlightStyle;
  final int? highlightFromIndex;
  final int maxLines;
  final double? maxWidth;
  final WrapAlignment wrapAlignment;

  TextAlign get _textAlign => switch (wrapAlignment) {
        WrapAlignment.end => TextAlign.right,
        WrapAlignment.start => TextAlign.left,
        _ => TextAlign.center,
      };

  Alignment get _fitAlignment => switch (wrapAlignment) {
        WrapAlignment.end => Alignment.centerRight,
        WrapAlignment.start => Alignment.centerLeft,
        _ => Alignment.center,
      };

  List<String> get _lines =>
      plainText.split('\n').take(maxLines).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animator = context.watch<HomeLabelAnimator>();

    if (reduceMotion || plainText.isEmpty) {
      return _fitChild(
        _staticText(plainText, baseStyle, highlightStyle, highlightFromIndex),
      );
    }

    final active = animator.isActive(moduleId);
    final wave = animator.waveIndex;
    var charGlobal = 0;

    return _fitChild(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: switch (wrapAlignment) {
          WrapAlignment.end => CrossAxisAlignment.end,
          WrapAlignment.start => CrossAxisAlignment.start,
          _ => CrossAxisAlignment.center,
        },
        children: [
          for (final line in _lines) ...[
            SizedBox(
              width: maxWidth,
              child: Wrap(
                alignment: wrapAlignment,
                spacing: 0,
                runSpacing: 0,
                children: [
                  for (final ch in line.characters) ...[
                    _waveChar(
                      ch,
                      index: charGlobal++,
                      active: active,
                      wave: wave,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fitChild(Widget child) {
    if (maxWidth == null || maxWidth! <= 0) return child;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: _fitAlignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: child,
      ),
    );
  }

  Widget _waveChar(
    String ch, {
    required int index,
    required bool active,
    required int wave,
  }) {
    final useHighlight = highlightStyle != null &&
        highlightFromIndex != null &&
        index >= highlightFromIndex!;
    final style = useHighlight ? highlightStyle! : baseStyle;
    double opacity = 1;
    FontWeight weight = style.fontWeight ?? FontWeight.w900;

    if (active) {
      if (index < wave) {
        opacity = 1;
      } else if (index == wave) {
        opacity = 1;
        weight = FontWeight.w900;
      } else {
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

  Widget _staticText(
    String text,
    TextStyle style,
    TextStyle? hi,
    int? hiFrom,
  ) {
    final lines = text.split('\n').take(maxLines).toList(growable: false);
    if (lines.length > 1 || text.contains('\n')) {
      if (hi == null || hiFrom == null) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: switch (wrapAlignment) {
            WrapAlignment.end => CrossAxisAlignment.end,
            WrapAlignment.start => CrossAxisAlignment.start,
            _ => CrossAxisAlignment.center,
          },
          children: [
            for (final line in lines)
              Text(
                line,
                textAlign: _textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
          ],
        );
      }
      var offset = 0;
      final children = <Widget>[];
      for (final line in lines) {
        final lineStart = offset;
        final lineEnd = offset + line.length;
        offset = lineEnd;
        if (hiFrom >= lineEnd) {
          children.add(
            Text(
              line,
              textAlign: _textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          );
        } else if (hiFrom <= lineStart) {
          children.add(
            Text(
              line,
              textAlign: _textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hi,
            ),
          );
        } else {
          final local = hiFrom - lineStart;
          children.add(
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: line.substring(0, local), style: style),
                  TextSpan(text: line.substring(local), style: hi),
                ],
              ),
              textAlign: _textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: switch (wrapAlignment) {
          WrapAlignment.end => CrossAxisAlignment.end,
          WrapAlignment.start => CrossAxisAlignment.start,
          _ => CrossAxisAlignment.center,
        },
        children: children,
      );
    }
    if (hi == null || hiFrom == null) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: _textAlign,
        style: style,
      );
    }
    final flat = text.replaceAll('\n', '');
    final hiText = flat.length > hiFrom ? flat.substring(hiFrom) : '';
    final pre = flat.length > hiFrom ? flat.substring(0, hiFrom) : flat;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: pre, style: style),
          if (hiText.isNotEmpty) TextSpan(text: hiText, style: hi),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: _textAlign,
    );
  }
}
