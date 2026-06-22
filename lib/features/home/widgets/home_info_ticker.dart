import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';

/// Bosh ekrandagi qidiruv maydoni o'rnida — aylanuvchi savol-javob matnlari.
/// Pill (radius 8px, 53px balandlik). Matn chap chegaraga maksimal yaqin.
/// Savol: kursiv + to'q ko'k. Javob: qalin (bold) + to'q yashil.
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

  // Matn "qisqa" hisoblanadi — 2 qatorga sig'sa (taxminan 60 belgi)
  static const _shortThreshold = 60;

  InlineSpan _buildSpan(String text) {
    final qi = text.indexOf('?');
    const qStyle = TextStyle(
      fontSize: 43,
      height: 1.05,
      fontStyle: FontStyle.italic,
      color: HomeInfoTicker._question,
    );
    const sepStyle = TextStyle(
      fontSize: 43,
      height: 1.05,
      fontWeight: FontWeight.w500,
      color: HomeInfoTicker._question,
    );
    const aStyle = TextStyle(
      fontSize: 43,
      height: 1.05,
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
        const TextSpan(text: ' ✦ ', style: sepStyle),
        TextSpan(text: a, style: aStyle),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();
    final text = widget.ads[_index].text;
    final maxW = MediaQuery.sizeOf(context).width - 4;
    final isShort = text.length <= _shortThreshold;

    return Container(
      height: 53,
      decoration: BoxDecoration(
        color: HomeInfoTicker._fill,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: FittedBox(
          key: ValueKey(_index),
          fit: BoxFit.scaleDown,
          alignment: isShort ? Alignment.center : Alignment.centerLeft,
          child: SizedBox(
            width: maxW,
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: isShort ? TextAlign.center : TextAlign.start,
              text: _buildSpan(text),
            ),
          ),
        ),
      ),
    );
  }
}
