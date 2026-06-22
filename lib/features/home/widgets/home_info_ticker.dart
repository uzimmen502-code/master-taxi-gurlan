import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';

/// Bosh ekrandagi qidiruv maydoni o'rnida — aylanuvchi savol-javob matnlari.
/// Maydon doim 53px. Matn maydonni (kenglik + balandlik) to'ldiradi:
/// uzunligiga qarab boshlang'ich shrift tanlanadi, so'ng BoxFit.contain bilan
/// bo'sh joyga sig'dirib kattalashtiriladi — lekin maksimal 22px, minimal 12px.
/// Savol: kursiv (#2C2C2A). Javob: qalin bold (#412402). Fon: Amber Orange.
class HomeInfoTicker extends StatefulWidget {
  const HomeInfoTicker({super.key, required this.ads});

  final List<HomeTickerAd> ads;

  static const _fill     = Color(0xFFFFB000);
  static const _question = Color(0xFF2C2C2A);
  static const _answer   = Color(0xFF412402);

  @override
  State<HomeInfoTicker> createState() => _HomeInfoTickerState();
}

class _HomeInfoTickerState extends State<HomeInfoTicker> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HomeInfoTicker old) {
    super.didUpdateWidget(old);
    if (old.ads.length != widget.ads.length) {
      _index = 0;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.ads.length < 2) return;
    final secs = widget.ads[_index].durationSec.clamp(3, 12);
    _timer = Timer(Duration(seconds: secs), () {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.ads.length);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Matn uzunligiga qarab boshlang'ich shrift (max 22, min 12).
  // BoxFit.contain bu o'lchamdan kattalashtirib bo'sh joyni to'ldiradi,
  // lekin RichText o'zi shu o'lchamda yozadi — natijada uzun matn kichik,
  // qisqa matn katta bo'ladi, ikkalasi ham maydonni to'ldiradi.
  double _baseFont(String text) {
    final n = text.length;
    if (n <= 25) return 22;
    if (n <= 45) return 18;
    if (n <= 70) return 15;
    if (n <= 95) return 13;
    return 12;
  }

  InlineSpan _buildSpan(String text, double fs) {
    final qi = text.indexOf('?');
    final qStyle = TextStyle(
      fontSize: fs,
      height: 1.1,
      fontStyle: FontStyle.italic,
      color: HomeInfoTicker._question,
    );
    final sepStyle = TextStyle(
      fontSize: fs,
      height: 1.1,
      fontWeight: FontWeight.w500,
      color: HomeInfoTicker._question,
    );
    final aStyle = TextStyle(
      fontSize: fs,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: HomeInfoTicker._answer,
    );

    if (qi < 0 || qi >= text.length - 1) {
      return TextSpan(text: text, style: qStyle);
    }

    final q = text.substring(0, qi + 1).trimRight();
    final a = text.substring(qi + 1).trimLeft();

    return TextSpan(children: [
      TextSpan(text: q, style: qStyle),
      if (a.isNotEmpty) ...[
        TextSpan(text: ' ✦ ', style: sepStyle),
        TextSpan(text: a, style: aStyle),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();
    final text = widget.ads[_index].text;
    final fs = _baseFont(text);
    final isShort = text.length <= 25;

    return Container(
      height: 53,
      decoration: BoxDecoration(
        color: HomeInfoTicker._fill,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: LayoutBuilder(
          key: ValueKey(_index),
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.contain,
              alignment: isShort ? Alignment.center : Alignment.centerLeft,
              child: SizedBox(
                width: constraints.maxWidth,
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isShort ? TextAlign.center : TextAlign.start,
                  text: _buildSpan(text, fs),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
