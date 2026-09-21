import 'package:flutter/material.dart';

/// ChatGPT мобил иловаси палитраси (light / dark) — тизим темасига қараб.
class GptColors {
  const GptColors({
    required this.bg,
    required this.drawerBg,
    required this.text,
    required this.subtle,
    required this.bubble,
    required this.inputBg,
    required this.sendBg,
    required this.sendFg,
    required this.codeBg,
    required this.border,
  });

  final Color bg;
  final Color drawerBg;
  final Color text;
  final Color subtle;
  final Color bubble;
  final Color inputBg;
  final Color sendBg;
  final Color sendFg;
  final Color codeBg;
  final Color border;

  static const light = GptColors(
    bg: Color(0xFFFFFFFF),
    drawerBg: Color(0xFFF9F9F9),
    text: Color(0xFF0D0D0D),
    subtle: Color(0xFF8E8EA0),
    bubble: Color(0xFFF4F4F4),
    inputBg: Color(0xFFF4F4F4),
    sendBg: Color(0xFF0D0D0D),
    sendFg: Color(0xFFFFFFFF),
    codeBg: Color(0xFF0D0D0D),
    border: Color(0xFFE5E5E5),
  );

  static const dark = GptColors(
    bg: Color(0xFF212121),
    drawerBg: Color(0xFF171717),
    text: Color(0xFFECECEC),
    subtle: Color(0xFFB4B4B4),
    bubble: Color(0xFF303030),
    inputBg: Color(0xFF303030),
    sendBg: Color(0xFFFFFFFF),
    sendFg: Color(0xFF0D0D0D),
    codeBg: Color(0xFF000000),
    border: Color(0xFF424242),
  );

  static GptColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
