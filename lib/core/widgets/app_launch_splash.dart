import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/splash_ad/splash_ad.dart';
import '../../features/splash_ad/splash_ad_cache.dart';
import '../brand_labels.dart';
import '../theme/ava_tokens.dart';

/// Илова очилишидаги РЕКЛАМА ЎРНИ (эга 2026-11-28; аввалги ~1.8 с лого анимацияси ўрнига).
///
///  * Аниқ [displayDuration] (3 с; эга 2026-11-28: 2 с → 3 с) кўринади, «Ўтказиб юбориш» тугмаси ЙЎҚ.
///  * Пастки «Реклама бериш» тугмаси ЙЎҚ (эга 2026-11-28). [onAdvertise] — намуна реклама ёки сукут матни (креатив
///    йўқ) майдонининг исталган жойи босилганда (splash дарров ёпилади, кейин пуллик харид оқими).
///  * Креатив ФАҚАТ кешдан ([launch], `main()` да олдиндан ўқилган) — тармоқ кутилмайди; йўқ бўлса
///    сукут матни «Бу ерда сизнинг рекламангиз бўлиши мумкин».
///  * Намуна (уй) реклама ([SplashAd.house]): босилса — «Реклама бериш» оқими; «Реклама» белгиси кўрсатилмайди.
///  * OS native launch screen ўзгармайди.
///
/// Тил/биринчи кадр: [child] (`MaterialApp`) оверлей остида шаффоф ҳолда қурилади — таржималар шу 3 с
/// ичида юкланади, қурилма тили «лип» этиб кўринмайди. Оверлей матнлари [lang] бўйича (main()да
/// prefs'дан синхрон олинган тил), чунки бу ерда `AppLocalizations` ҳали йўқ.
class AppLaunchSplash extends StatefulWidget {
  const AppLaunchSplash({
    super.key,
    required this.child,
    this.onFinished,
    this.launch,
    this.lang = 'uz_Cyrl',
    this.onAdvertise,
    this.onOpenAd,
    this.onShown,
  });

  final Widget child;

  /// Splash overlay yopilganda (bir marta) — FCM/notification shu paytda.
  final VoidCallback? onFinished;

  /// Кешдаги рекламачи креативи (`null` — сукут матни).
  final SplashAdLaunch? launch;

  /// `uz_Cyrl` | `uz_Latn` | `ru`.
  final String lang;

  /// Намуна/сукут банери босилди — «Реклама бериш» оқими (splash аллақачон ёпилган).
  final VoidCallback? onAdvertise;

  /// Креатив босилди ва унда ҳавола бор (splash аллақачон ёпилган).
  final ValueChanged<SplashAd>? onOpenAd;

  /// Рекламачи креативи экранга чиқди (кўрсатишлар йиғмаси учун) — бир марта.
  final ValueChanged<SplashAd>? onShown;

  /// Эга 2026-11-28: аниқ 3 сония (аввал 2 с).
  static const Duration displayDuration = Duration(seconds: 3);

  static const Key overlayKey = ValueKey('splash-ad-overlay');
  /// Креатив майдони босиладиган бўлса — шу калит (намуна/сукут: «Реклама бериш»; ҳаволали креатив: ҳавола).
  static const Key tapAreaKey = ValueKey('splash-ad-tap-area');
  static const Key tapHintKey = ValueKey('splash-ad-tap-hint');
  static const Key imageKey = ValueKey('splash-ad-image');
  static const Key textKey = ValueKey('splash-ad-text');
  static const Key placeholderKey = ValueKey('splash-ad-placeholder');

  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash> {
  bool _overlayVisible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Таймер биринчи кадр чизилгач — реклама экранда ТЎЛИҚ 3 с туради.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_overlayVisible) return;
      _timer = Timer(AppLaunchSplash.displayDuration, _finish);
      final ad = widget.launch?.ad;
      if (ad != null) widget.onShown?.call(ad);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish() {
    if (!mounted || !_overlayVisible) return;
    _timer?.cancel();
    setState(() => _overlayVisible = false);
    widget.onFinished?.call();
  }

  void _advertise() {
    _finish();
    widget.onAdvertise?.call();
  }

  void _openAd(SplashAd ad) {
    _finish();
    widget.onOpenAd?.call(ad);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: _overlayVisible ? 0 : 1, child: widget.child),
          if (_overlayVisible)
            _SplashAdOverlay(
              key: AppLaunchSplash.overlayKey,
              launch: widget.launch,
              lang: widget.lang,
              onAdvertise: _advertise,
              onOpenAd: _openAd,
            ),
        ],
      ),
    );
  }
}

class _SplashAdOverlay extends StatelessWidget {
  const _SplashAdOverlay({
    super.key,
    required this.launch,
    required this.lang,
    required this.onAdvertise,
    required this.onOpenAd,
  });

  final SplashAdLaunch? launch;
  final String lang;
  final VoidCallback onAdvertise;
  final ValueChanged<SplashAd> onOpenAd;

  @override
  Widget build(BuildContext context) {
    final l = launch;
    final ad = l?.ad;
    final text = ad?.textFor(lang) ?? '';
    final bytes = l?.imageBytes;
    final Widget content;
    if (ad != null && bytes != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          bytes,
          key: AppLaunchSplash.imageKey,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _Message(text: text.isNotEmpty ? text : SplashAdTexts.placeholder(lang)),
        ),
      );
    } else if (ad != null && text.isNotEmpty) {
      content = _Message(key: AppLaunchSplash.textKey, text: text, large: true);
    } else {
      // Кешда креатив йўқ — сукут матни + босиш ишораси (пастки тугма олиб ташланди, эга 2026-11-28).
      content = Column(
        key: AppLaunchSplash.placeholderKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Message(text: SplashAdTexts.placeholder(lang)),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.touch_app_rounded, color: AvaLight.brandInk, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  SplashAdTexts.tapHint(lang),
                  key: AppLaunchSplash.tapHintKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AvaLight.brandInk, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      );
    }
    // Эга 2026-11-28: пастдаги «Реклама бериш» тугмаси ОЛИБ ТАШЛАНДИ. Пуллик харид экрани энди банернинг ўзидан:
    //  * намуна (уй) реклама ёки сукут матни (креатив йўқ) — исталган жойи босилса «Реклама бериш» оқими;
    //  * рекламачи креативи — аввалгидек: `https://` ҳаволаси бўлса ҳавола, бўлмаса босилмайди.
    final house = ad != null && ad.house;
    final advertises = ad == null || house;
    final tappable = advertises || ad.linkUrl.startsWith('https://');

    return Material(
      color: AvaLight.brand,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    BrandLabels.brand,
                    style: TextStyle(
                      color: AvaLight.brandInk,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const Spacer(),
                  if (ad != null && !house)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AvaLight.brandInk.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        SplashAdTexts.adLabel(lang),
                        style: const TextStyle(color: AvaLight.brandInk, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Босиладиган креатив — бутун креатив майдони босилади (расм ҳали чизилмаган бўлса ҳам).
              Expanded(
                child: tappable
                    ? Semantics(
                        button: true,
                        label: advertises ? SplashAdTexts.advertise(lang) : null,
                        child: GestureDetector(
                          key: AppLaunchSplash.tapAreaKey,
                          behavior: HitTestBehavior.opaque,
                          onTap: advertises ? onAdvertise : () => onOpenAd(ad),
                          child: Center(child: content),
                        ),
                      )
                    : Center(child: content),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, this.large = false});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AvaLight.brandInk,
          fontSize: large ? 28 : 24,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }
}
