import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/home_ticker_ad.dart';

/// Баннер ўнг томонидаги расм (карнай) — эга чизган (2026-11-20), шаффоф фонли.
/// ЯГОНА алмаштириш нуқтаси: янги версияни `assets/images/home/` га қўйиб, шу йўлни
/// ўзгартириш кифоя (номдаги `_vN` — кешни янгилаш учун; `.svg` ҳам бўлади). Файл топилмаса — иконка.
const String kHomeBannerArtAsset = 'assets/images/home/banner_megaphone_v1.webp';

/// Баннердаги битта матн жуфти: сарлавҳа + изоҳ.
@immutable
class HomeBannerText {
  const HomeBannerText(this.title, this.caption);

  final String title;
  final String caption;

  /// Админ матни (`home_ticker_ads`): «Савол? Жавоб» шаклида бўлса — савол сарлавҳа,
  /// жавоб изоҳ (аввалги «савол ✦ жавоб» анъанаси); акс ҳолда бутун матн сарлавҳа.
  /// Матн КАТТА ҲАРФГА ўгирилмайди (эга 2026-11-20: ALL CAPS йўқ).
  factory HomeBannerText.fromAdText(String text) {
    final t = text.trim();
    final qi = t.indexOf('?');
    if (qi <= 0 || qi >= t.length - 1) return HomeBannerText(t, '');
    return HomeBannerText(t.substring(0, qi + 1).trim(), t.substring(qi + 1).trim());
  }

  @override
  bool operator ==(Object other) =>
      other is HomeBannerText && other.title == title && other.caption == caption;

  @override
  int get hashCode => Object.hash(title, caption);
}

/// Бош экран баннери (ҳамён билан битта 86 px жойда — [HomeWalletTickerSlot]).
///
/// Эга 2026-11-20 «енгил дизайн»: қора хошия ва КАТТА ҲАРФ йўқ; фон `brandSoft`
/// (#FFF3DF), сарлавҳа тўқ semi-bold, изоҳ кичикроқ кулранг, битта тўқ сариқ
/// «Эълон бериш →» тугмаси, ўнгда ~18% кенгликда карнай расми. Фақат МАТН
/// алмашади (юқорига сурилиб сўнади, янгиси пастдан, ~350 мс, ҳар 5 с); расм ва
/// тугма қимирламайди; баннерга тегилганда авто-алмашиш тўхтайди.
///
/// Админ матнлари бўлмаса — эга берган сукут матн ([defaultTexts]).
class HomeInfoTicker extends StatefulWidget {
  const HomeInfoTicker({super.key, required this.ads, this.random, this.onCta});

  final List<HomeTickerAd> ads;

  /// Тенг устуворликдаги матнларни аралаштириш учун (тестда — seed билан).
  final math.Random? random;

  /// «Эълон бериш →» тугмаси.
  final VoidCallback? onCta;

  /// Кўрсатиш тартиби (эга, 2026-10-26: «Устуворлик» ишласин): юқори устуворлик аввал; тенглари ўзаро аралаш.
  static List<HomeTickerAd> displayOrder(List<HomeTickerAd> ads, math.Random random) {
    final byPriority = <int, List<HomeTickerAd>>{};
    for (final a in ads) {
      byPriority.putIfAbsent(a.priority, () => []).add(a);
    }
    final levels = byPriority.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final p in levels) ...(byPriority[p]!..shuffle(random))];
  }

  /// Сукут матн (эга 2026-11-20), 3 тилда — lang калитлари.
  static List<HomeBannerText> defaultTexts(BuildContext context) => [
        HomeBannerText(
          context.tr('home_banner_default_title'),
          context.tr('home_banner_default_caption'),
        ),
      ];

  /// Жой баландлиги — ҳамён картаси билан бир хил (эга, 2026-10-26), ўзгармайди.
  static const height = 86.0;

  /// Ҳар бир матн шунча туради (эга, 2026-10-26: 5 с).
  static const textInterval = Duration(seconds: 5);

  /// Матн алмашиш анимацияси (эга 2026-11-20: 300–400 мс).
  static const textAnimation = Duration(milliseconds: 350);

  /// Расм устуни кенглиги — баннер энининг улуши (эга 2026-11-20, 3-тур: 25%; аввал 18%).
  static const artWidthFactor = 0.25;

  @override
  State<HomeInfoTicker> createState() => _HomeInfoTickerState();
}

class _HomeInfoTickerState extends State<HomeInfoTicker> {
  int _index = 0;
  Timer? _timer;
  bool _touching = false;
  late final math.Random _random = widget.random ?? math.Random();

  /// Тартиб фақат матнлар тўплами ёки устуворлиги ўзгарганда қайта ҳисобланади — ота виджет қайта
  /// чизилганда баннер бошқа матнга сакраб кетмайди.
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
    _timer = null;
    if (_ordered.length < 2 || _touching) return;
    _timer = Timer(HomeInfoTicker.textInterval, () {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _ordered.length);
      _schedule();
    });
  }

  void _setTouching(bool v) {
    if (_touching == v) return;
    _touching = v;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  HomeBannerText _current(BuildContext context) {
    if (_ordered.isEmpty) return HomeInfoTicker.defaultTexts(context).first;
    final i = _index % _ordered.length;
    return HomeBannerText.fromAdText(_ordered[i].textFor(context.contentLang));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final text = _current(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final textKey = ValueKey('banner_text_${_ordered.isEmpty ? 'default' : _index}');

    return Listener(
      // Тегилганда авто-алмашиш тўхтайди; қўйиб юборилгач қайта 5 с санайди.
      onPointerDown: (_) => _setTouching(true),
      onPointerUp: (_) => _setTouching(false),
      onPointerCancel: (_) => _setTouching(false),
      child: Container(
        key: const ValueKey('home_banner_box'),
        height: HomeInfoTicker.height,
        decoration: BoxDecoration(
          color: c.brandSoft,
          borderRadius: BorderRadius.circular(AvaRadius.banner),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: MediaQuery.withClampedTextScaling(
          // 86 px жой қатъий (ҳамён билан алмашади) — катта шрифтда матн блоки
          // ўзи кичраяди ([FittedBox]), тугма эса 1.3 гача катталашади.
          maxScaleFactor: 1.3,
          child: LayoutBuilder(
            builder: (context, box) {
              final artW = (box.maxWidth * HomeInfoTicker.artWidthFactor).clamp(40.0, 120.0);
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRect(
                            child: AnimatedSwitcher(
                              duration: reduceMotion ? Duration.zero : HomeInfoTicker.textAnimation,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previous, if (current != null) current],
                              ),
                              transitionBuilder: (child, animation) {
                                // Кирувчи — пастдан; чиқувчи — юқорига (анимация 1 → 0).
                                final incoming = child.key == textKey;
                                final slide = Tween<Offset>(
                                  begin: incoming ? const Offset(0, 0.6) : const Offset(0, -0.6),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(position: slide, child: child),
                                );
                              },
                              child: _BannerTextBlock(key: textKey, text: text),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _CtaButton(onTap: widget.onCta),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    key: const ValueKey('home_banner_art'),
                    width: artW,
                    height: double.infinity,
                    child: const _BannerArt(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BannerTextBlock extends StatelessWidget {
  const _BannerTextBlock({super.key, required this.text});

  final HomeBannerText text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        // Сиғмаса — бутун блок бир хилда кичраяди (матн кесилмайди).
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: box.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.title,
                key: const ValueKey('home_banner_title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AvaText.homeCardTitle.copyWith(color: c.ink, height: 1.2),
              ),
              if (text.caption.isNotEmpty)
                Text(
                  text.caption,
                  key: const ValueKey('home_banner_caption'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AvaText.caption.copyWith(fontSize: 13, color: c.ink2, height: 1.2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      key: const ValueKey('home_banner_cta'),
      color: c.brand,
      borderRadius: BorderRadius.circular(AvaRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            context.tr('home_banner_cta'),
            maxLines: 1,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25, color: c.brandInk),
          ),
        ),
      ),
    );
  }
}

class _BannerArt extends StatelessWidget {
  const _BannerArt();

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.campaign_rounded, size: 44, color: context.ava.brand);
    if (kHomeBannerArtAsset.isEmpty) return Center(child: fallback);
    return kHomeBannerArtAsset.toLowerCase().endsWith('.svg')
        ? SvgPicture.asset(
            kHomeBannerArtAsset,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => Center(child: fallback),
          )
        : Image.asset(
            kHomeBannerArtAsset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(child: fallback),
          );
  }
}
