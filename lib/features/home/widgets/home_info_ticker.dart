import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/home_ticker_ad.dart';
import 'home_flip_switcher.dart';

/// Bosh ekrandagi qidiruv maydoni o'rnida — aylanuvchi savol-javob matnlari.
/// Maydon doim [height] = 86px. Matn uzunligiga qarab shrift 12–28px oralig'ida, ko'pi bilan
/// [maxLines] qatorda maydonga maksimal sig'diriladi. Matn atrofida 1px (ega, 2026-10-26:
/// «чап-ўнгда 1 px, юқори-пастда 1 px», «кўпи билан 4 қатор»; matn joyi 84px — 4 qator
/// 12px shriftda ham sig'adi: 4 × 12 × 1.1 = 52.8).
/// Savol-javob matnlari — hammasi qalin (bold) va BOSH HARFLARDA.
class HomeInfoTicker extends StatefulWidget {
  const HomeInfoTicker({super.key, required this.ads, this.random});

  final List<HomeTickerAd> ads;

  /// Тенг устуворликдаги матнларни аралаштириш учун (тестда — seed билан).
  final math.Random? random;

  /// Кўрсатиш тартиби (эга, 2026-10-26: «Устуворлик» ишласин): юқори устуворлик аввал; тенглари ўзаро аралаш.
  /// Ҳамма матн 0 бўлса — аввалгидек тўлиқ аралаш.
  static List<HomeTickerAd> displayOrder(List<HomeTickerAd> ads, math.Random random) {
    final byPriority = <int, List<HomeTickerAd>>{};
    for (final a in ads) {
      byPriority.putIfAbsent(a.priority, () => []).add(a);
    }
    final levels = byPriority.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final p in levels) ...(byPriority[p]!..shuffle(random))];
  }

  /// Maydon balandligi: 53 → 75 (эга, 2026-10-26) → 86 px (эга, 2026-10-26: «Баннер 86 px бўлсин» — ҳамён картаси
  /// билан бир хил, иккаласи битта жойда ағдарилиб алмашади, пастдаги мазмун қимирламайди).
  static const height = 86.0;

  /// Ҳар бир матн шунча туради (ағдарилиш 0.55 с шу вақт ичида): 3 → 5 с (эга, 2026-10-26: «5 сонияга ўзгартир»).
  static const textInterval = Duration(seconds: 5);

  static const _fill     = Color(0xFFFFFF00); // neon sariq
  static const _question = Color(0xFF2C2C2A);
  static const _answer   = Color(0xFF412402);

  /// Қора хошия (эга, 2026-10-31: «3 px қилиб жонлига чиқар»). Хошия баннер ичида — матн жойи
  /// ҳар томондан шунча кичраяди, шрифт [_fitFontSize] да шунга мосланади.
  static const borderColor = Color(0xFF000000);
  static const borderWidth = 3.0;

  @override
  State<HomeInfoTicker> createState() => _HomeInfoTickerState();
}

class _HomeInfoTickerState extends State<HomeInfoTicker> {
  int _index = 0;
  Timer? _timer;
  late final math.Random _random = widget.random ?? math.Random();

  /// Тартиб фақат матнлар тўплами ёки устуворлиги ўзгарганда қайта ҳисобланади — ота виджет қайта
  /// чизилганда баннер бошқа матнга сакраб кетмайди (аввал home_screen ҳар build'да аралаштирарди).
  List<HomeTickerAd> _ordered = const [];

  static String _signature(List<HomeTickerAd> ads) =>
      (ads.map((a) => '${a.id}:${a.priority}').toList()..sort()).join('|');

  @override
  void initState() {
    super.initState();
    _ordered = HomeInfoTicker.displayOrder(widget.ads, _random);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HomeInfoTicker old) {
    super.didUpdateWidget(old);
    if (identical(old.ads, widget.ads)) return;
    if (_signature(old.ads) == _signature(widget.ads)) {
      // Ўша матнлар (масалан, фақат матн таҳрирланди) — тартиб ва жорий ўрин сақланади.
      final byId = {for (final a in widget.ads) a.id: a};
      _ordered = [for (final a in _ordered) byId[a.id] ?? a];
      return;
    }
    _ordered = HomeInfoTicker.displayOrder(widget.ads, _random);
    _index = 0;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_ordered.length < 2) return;
    _timer = Timer(HomeInfoTicker.textInterval, () {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _ordered.length);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Matnlar almashganda 3D ag'darilish — [HomeFlipSwitcher] (ҳамён → баннер жойи ҳам шуни ишлатади).

  // Maydonga sig'adigan maksimal shrift (qisqa matn kattaroq).
  static const _maxFont = 28.0;
  static const _minFont = 12.0;

  static const _height = HomeInfoTicker.height;

  /// Ko'pi bilan qatorlar soni.
  static const maxLines = 4;

  /// Matn bilan maydon cheti orasidagi masofa (har tomonda).
  static const padding = EdgeInsets.all(1);

  double _fitFontSize(String text, double maxWidth, double maxHeight) {
    final upper = text.toUpperCase();
    for (var fs = _maxFont; fs >= _minFont; fs -= 0.5) {
      final painter = TextPainter(
        text: TextSpan(children: [_buildSpan(upper, fs)]),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      if (!painter.didExceedMaxLines && painter.height <= maxHeight) {
        return fs;
      }
    }
    return _minFont;
  }

  InlineSpan _buildSpan(String upper, double fs) {
    final qi = upper.indexOf('?');
    final qStyle = TextStyle(
      fontSize: fs,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: HomeInfoTicker._question,
    );
    final sepStyle = TextStyle(
      fontSize: fs,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: HomeInfoTicker._question,
    );
    final aStyle = TextStyle(
      fontSize: fs,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: HomeInfoTicker._answer,
    );

    if (qi < 0 || qi >= upper.length - 1) {
      return TextSpan(text: upper, style: qStyle);
    }

    final q = upper.substring(0, qi + 1).trimRight();
    final a = upper.substring(qi + 1).trimLeft();

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
    if (_ordered.isEmpty) return const SizedBox.shrink();
    // Илова тилидаги матн (uz_Cyrl / uz_Latn / ru; бўш тиллар учун — HomeTickerAd.textFor).
    final text = _ordered[_index].textFor(context.contentLang);
    final upper = text.toUpperCase();

    return SizedBox(
      height: _height,
      child: HomeFlipSwitcher(
        child: Container(
          key: ValueKey(_index),
          height: _height,
          decoration: BoxDecoration(
            color: HomeInfoTicker._fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: HomeInfoTicker.borderColor,
              width: HomeInfoTicker.borderWidth,
            ),
          ),
          padding: padding,
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fs = _fitFontSize(
                text,
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Align(
                alignment: Alignment.center,
                child: RichText(
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  text: TextSpan(children: [_buildSpan(upper, fs)]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
