import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/splash_ad/splash_ad.dart';
import '../../features/splash_ad/splash_ad_cache.dart';
import '../brand_labels.dart';
import '../theme/ava_tokens.dart';

/// Илова очилишидаги РЕКЛАМА ЎРНИ (эга 2026-11-28; аввалги ~1.8 с лого анимацияси ўрнига).
///
///  * Аниқ [displayDuration] (3 с; эга 2026-11-28: 2 с → 3 с) кўринади, «Ўтказиб юбориш» тугмаси ЙЎҚ.
///  * «Реклама бериш» тугмаси — [onAdvertise] (splash дарров ёпилади, кейин мавжуд йўл очилади).
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

  /// «Реклама бериш» босилди (splash аллақачон ёпилган).
  final VoidCallback? onAdvertise;

  /// Креатив босилди ва унда ҳавола бор (splash аллақачон ёпилган).
  final ValueChanged<SplashAd>? onOpenAd;

  /// Рекламачи креативи экранга чиқди (кўрсатишлар йиғмаси учун) — бир марта.
  final ValueChanged<SplashAd>? onShown;

  /// Эга 2026-11-28: аниқ 3 сония (аввал 2 с).
  static const Duration displayDuration = Duration(seconds: 3);

  static const Key overlayKey = ValueKey('splash-ad-overlay');
  static const Key advertiseKey = ValueKey('splash-ad-advertise');
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
      content = _Message(key: AppLaunchSplash.placeholderKey, text: SplashAdTexts.placeholder(lang));
    }
    // Намуна (уй) реклама — AVA'нинг ўз чорлови: босилса «Реклама бериш» (ҳавола эмас), «Реклама» белгиси йўқ.
    final house = ad != null && ad.house;
    final tappable = ad != null && (house || ad.linkUrl.startsWith('https://'));

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
              // Ҳаволали креатив — бутун креатив майдони босилади (расм ҳали чизилмаган бўлса ҳам).
              Expanded(
                child: tappable
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: house ? onAdvertise : () => onOpenAd(ad),
                        child: Center(child: content),
                      )
                    : Center(child: content),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  key: AppLaunchSplash.advertiseKey,
                  onPressed: onAdvertise,
                  style: FilledButton.styleFrom(
                    backgroundColor: AvaLight.brandInk,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text(SplashAdTexts.advertise(lang)),
                ),
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
