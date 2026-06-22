import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';

/// Bosh ekrandagi qidiruv maydoni o'rnida — aylanuvchi savol-javob matnlari.
/// Kulrang pill (53px). Lampochka yo'q — matn chap chegaraga maksimal yaqin.
/// Savol: kursiv + kulrang. Javob: qalin (bold) + to'q yashil.
class HomeInfoTicker extends StatefulWidget {
  const HomeInfoTicker({super.key, required this.ads});

  final List<HomeTickerAd> ads;

  static const _fill     = Color(0xFFE8EAEC);
  static const _question = Color(0xFF5D6B6E); // kulrang — savol (kursiv)
  static const _answer   = Color(0xFF1B5E20); // to'q yashil — javob (bold)

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

  // Matnni "?" dan savol va javobga ajratadi.
  InlineSpan _buildSpan(String text) {
    final qi = text.indexOf('?');
    const qStyle = TextStyle(
      fontSize: 13,
      height: 1.05,
      fontStyle: FontStyle.italic,
      color: HomeInfoTicker._question,
    );
    const aStyle = TextStyle(
      fontSize: 13,
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
        const TextSpan(text: ' '),
        TextSpan(text: a, style: aStyle),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();
    final text = widget.ads[_index].text;

    return Container(
      height: 53,
      decoration: BoxDecoration(
        color: HomeInfoTicker._fill,
        borderRadius: BorderRadius.circular(27),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: Align(
          key: ValueKey(_index),
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 32,
              ),
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: _buildSpan(text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
