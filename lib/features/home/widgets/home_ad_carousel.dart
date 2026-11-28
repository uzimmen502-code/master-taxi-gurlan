import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/widgets/tv_clip_poster.dart';
import 'home_info_ticker.dart' show kHomeBannerArtAsset;

/// Бош саҳифа реклама каруселлари (эга 2026-11-28): «Бозорлар», «Эълон ва хизматлар»,
/// «Транспорт ва логистика» бўлимларидан кейин.
///
/// Айланиш механикаси — эски `PromoCarousel`дан (320d6867, 2026-06-19; 6be8a0a1 да
/// олиб ташланган): виртуал чексиз `PageView`, ўнгдан чапга автоматик ўтиш, тегинилса
/// тўхтайди. Фарқи: эски баннерлар кодда қотирилган 8 та модул эди; энди манба —
/// пуллик реклама (AVAGram `tv_clips`, `category == 'ad'`, тариф «Реклама жойлашуви:
/// Home» — `adTier` `home`/`premium`/`pro_max`, [TvClip.showsOnHome]).
enum HomeAdPlacement { markets, services, transport }

/// «Реклама бериш» ўрни: мегафон расми (banner_megaphone_v1.webp 400×312) нисбати.
const double kHomeAdPlaceholderArtAspect = 400 / 312;

/// Эга 2026-11-28 (2): мегафон баннернинг ЧАП четига ёпишган, бутун баландликни тўлдиради;
/// эни = баландлик × нисбат, лекин тор экранда карта энининг шу улушидан ошмайди (матнга жой).
const double kHomeAdPlaceholderArtMaxFraction = 0.4;

/// Мегафон эни (карта ўлчамидан).
double homeAdPlaceholderArtWidth(double cardWidth, double cardHeight) {
  final natural = cardHeight * kHomeAdPlaceholderArtAspect;
  final cap = cardWidth * kHomeAdPlaceholderArtMaxFraction;
  return natural < cap ? natural : cap;
}

/// Битта слайд (UI маълумоти; манбадан мустақил — тестланади).
@immutable
class HomeAdSlide {
  const HomeAdSlide({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl = '',
  });

  factory HomeAdSlide.fromClip(TvClip c) => HomeAdSlide(
        id: c.id,
        title: c.title,
        subtitle: c.displayOwnerName(''),
        imageUrl: c.posterUrl,
      );

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
}

/// Каруселга тушадиган клиплар: фақат пуллик Home тарифидаги, ижро этиладиган реклама.
List<TvClip> homeCarouselAds(Iterable<TvClip> clips) => [
      for (final c in clips)
        if (c.isAd && c.showsOnHome && c.isPlayable) c,
    ];

/// Жойлашув калити учун маълумот модели ҳозирча йўқ (`tv_clips`да placement майдони йўқ —
/// қўшиш сервер+rules ўзгариши талаб қилади). Шу сабабли учала карусел БИТТА лентани
/// турли бошланғич слайддан кўрсатади: markets → 0, services → 1, transport → 2 (mod N).
int homeAdCarouselStart(HomeAdPlacement placement, int count) =>
    count <= 0 ? 0 : placement.index % count;

/// Учала карусел учун битта юклагич (бош саҳифа очилганда / тортиб янгилашда 1 сўров, 37-банд).
class HomeAdCarouselFeed {
  HomeAdCarouselFeed({Future<List<TvClip>> Function()? load}) : _load = load;

  final Future<List<TvClip>> Function()? _load;

  /// Энг кўпи шунча реклама айланади.
  static const limit = 10;

  final ValueNotifier<List<TvClip>> ads = ValueNotifier(const []);
  bool _loading = false;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final clips = await (_load?.call() ?? _fetch());
      ads.value = homeCarouselAds(clips);
    } catch (e) {
      // Хато — аввалги рўйхат қолади (бўш бўлса — «Реклама бериш» ўрни).
      debugPrint('[HomeAdCarousel] HOME_AD_CAROUSEL_LOAD_FAILED: $e');
    } finally {
      _loading = false;
    }
  }

  Future<List<TvClip>> _fetch() async {
    // AVAGram бош саҳифа бўлими билан бир хил ҳудуд қоидаси (D-GEO-1) ва мавжуд индекслар.
    final scope = GeoContext.homeScopeFor('tv_market');
    final page = await TvClipsRepository().fetchHomePage(
      districtId: scope.level == GeoLevel.nation ? '' : scope.area.districtId,
      limit: limit,
      categories: const ['ad'],
    );
    return page.clips;
  }

  void dispose() => ads.dispose();
}

/// Карусел: 0 реклама — «Бу ерда сизнинг рекламангиз…» + «Реклама бериш»; 1 — статик;
/// N — ўнгдан чапга автоматик айланади (тегинилганда тўхтайди).
class HomeAdCarousel extends StatefulWidget {
  const HomeAdCarousel({
    super.key,
    required this.placement,
    required this.slides,
    required this.onOpen,
    required this.onAdvertise,
    this.interval = defaultInterval,
    this.resumeDelay = defaultResumeDelay,
  });

  static const defaultInterval = Duration(seconds: 4);
  static const defaultResumeDelay = Duration(seconds: 8);
  static const height = 104.0;

  final HomeAdPlacement placement;
  final List<HomeAdSlide> slides;

  /// Слайд босилди — [slides] ичидаги индекс.
  final void Function(int index) onOpen;
  final VoidCallback onAdvertise;
  final Duration interval;

  /// Қўйиб юборилгач, автоматик айланиш шунча вақтдан кейин тикланади.
  final Duration resumeDelay;

  @override
  State<HomeAdCarousel> createState() => _HomeAdCarouselState();
}

class _HomeAdCarouselState extends State<HomeAdCarousel> {
  static const _virtualCycles = 10000;

  PageController? _controller;
  Timer? _timer;
  Timer? _resumeTimer;
  bool _touched = false;

  int get _n => widget.slides.length;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(HomeAdCarousel old) {
    super.didUpdateWidget(old);
    if (old.slides.length != _n || old.interval != widget.interval) _setup();
  }

  void _setup() {
    _timer?.cancel();
    _controller?.dispose();
    _controller = null;
    if (_n < 2) return;
    final start = homeAdCarouselStart(widget.placement, _n);
    _controller = PageController(initialPage: _virtualCycles * _n + start);
    _timer = Timer.periodic(widget.interval, (_) => _next());
  }

  void _next() {
    final c = _controller;
    if (!mounted || _touched || c == null || !c.hasClients) return;
    final page = c.page?.round();
    if (page == null) return;
    // Ўнгдан чапга: кейинги слайд ўнгдан киради.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      c.jumpToPage(page + 1);
    } else {
      c.animateToPage(page + 1, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
  }

  void _onDown(PointerDownEvent _) {
    _resumeTimer?.cancel();
    _touched = true;
  }

  void _onUp(PointerEvent _) {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(widget.resumeDelay, () => _touched = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resumeTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_n == 0) {
      body = _AdPlaceholder(onAdvertise: widget.onAdvertise);
    } else if (_n == 1) {
      body = _AdSlideCard(slide: widget.slides.first, onTap: () => widget.onOpen(0));
    } else {
      body = Listener(
        onPointerDown: _onDown,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: PageView.builder(
          key: const ValueKey('home_ad_carousel_pages'),
          controller: _controller,
          itemBuilder: (context, i) {
            final idx = i % _n;
            return _AdSlideCard(slide: widget.slides[idx], onTap: () => widget.onOpen(idx));
          },
        ),
      );
    }
    return Padding(
      key: ValueKey('home_ad_carousel_${widget.placement.name}'),
      padding: const EdgeInsets.only(top: AvaSpace.homeSection),
      child: SizedBox(height: HomeAdCarousel.height, child: body),
    );
  }
}

class _AdSlideCard extends StatelessWidget {
  const _AdSlideCard({required this.slide, required this.onTap});

  final HomeAdSlide slide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);
    return Material(
      key: ValueKey('home_ad_slide_${slide.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 120,
              child: slide.imageUrl.isEmpty
                  ? ColoredBox(color: c.surface2, child: Icon(Icons.campaign_rounded, color: c.ink2, size: 32))
                  : TvClipPoster(url: slide.imageUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _AdChip(text: context.tr('tv_ad_label')),
                    const SizedBox(height: 4),
                    Text(
                      slide.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AvaText.homeCardTitle.copyWith(color: c.ink),
                    ),
                    if (slide.subtitle.isNotEmpty)
                      Text(
                        slide.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AvaText.homeCardCaption.copyWith(color: c.ink2),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Center(child: Icon(Icons.chevron_right_rounded, size: 24, color: c.ink3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdChip extends StatelessWidget {
  const _AdChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(text, style: AvaText.homeCardCaption.copyWith(color: c.brandText, fontSize: 11)),
      ),
    );
  }
}

class _AdPlaceholder extends StatelessWidget {
  const _AdPlaceholder({required this.onAdvertise});

  final VoidCallback onAdvertise;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);
    return Material(
      key: const ValueKey('home_ad_placeholder'),
      color: c.brandSoft,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdvertise,
        child: LayoutBuilder(
          builder: (context, box) {
            // Эга 2026-11-28: юқори баннердаги мегафон расми ЧАПДА, кўзгули (ўнгга — матнга қараган).
            // Эга 2026-11-28 (2): чап четга ёпишган (ички ораликсиз), бутун баландликни тўлдиради,
            // бурчакни картанинг Clip.antiAlias и кесади. Тор экранда энни чеклаганда даста томони
            // (кўзгудан кейин — чап чет) кесилади, оғзи ва товуш чизиқлари кўринади.
            final artW = homeAdPlaceholderArtWidth(box.maxWidth, box.maxHeight);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: artW,
                  child: Transform.flip(
                    key: const ValueKey('home_ad_placeholder_art'),
                    flipX: true,
                    child: Image.asset(
                      kHomeBannerArtAsset,
                      fit: BoxFit.cover,
                      // Кўзгудан олдинги чап = кўзгудан кейинги ўнг (оғиз томони) — шу сақланади.
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => Icon(Icons.campaign_rounded, size: 36, color: c.brandText),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            context.tr('home_ad_slot_title'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AvaText.homeCardTitle.copyWith(color: c.ink),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            key: const ValueKey('home_ad_placeholder_cta'),
                            onPressed: onAdvertise,
                            style: FilledButton.styleFrom(
                              backgroundColor: c.brand,
                              foregroundColor: c.brandInk,
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(context.tr('home_ad_slot_cta'), maxLines: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
