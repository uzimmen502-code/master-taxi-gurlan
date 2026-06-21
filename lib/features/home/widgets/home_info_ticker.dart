import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';

/// Bosh ekrandagi qidiruv maydoni o'rnida — aylanuvchi savol-javob/ma'lumot
/// matnlari. Kulrang pill ko'rinishi saqlanadi (balandlik 53px o'zgarmaydi),
/// chap tomonda 💡 lampochka, matn to'q ko'k rangda, auto-fit (matn uzun
/// bo'lsa shrift kichrayadi, 3 qatorgacha o'raladi).
class HomeInfoTicker extends StatefulWidget {
  const HomeInfoTicker({super.key, required this.ads});

  /// Tasodifiy aralashtirilgan holatda uzatiladi (parent shuffle qiladi).
  final List<HomeTickerAd> ads;

  static const _fill = Color(0xFFE8EAEC);
  static const _accent = Color(0xFF1B5E20); // to'q yashil — brendga mos, o'qilishi yaxshi

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
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline,
            color: HomeInfoTicker._accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
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
                      maxWidth: MediaQuery.sizeOf(context).width - 90,
                    ),
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.05,
                        fontWeight: FontWeight.w500,
                        color: HomeInfoTicker._accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
