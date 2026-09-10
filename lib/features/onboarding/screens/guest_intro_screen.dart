import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/anon_session_service.dart';
import '../../../shared/navigation/app_home_route.dart';

/// Birinchi ochilish: qisqa intro (registratsiya/ruxsat so'ralmaydi) →
/// anonim Firebase Auth sessiya → to'g'ridan-to'g'ri feed.
///
/// Telefon-orqali ro'yxatdan o'tish (`OnboardingScreen`) endi bu ekrandan
/// chaqirilmaydi — u ilova ichidan (masalan, profildan) ixtiyoriy ravishda
/// ochiladigan alohida oqim bo'lib qoladi.
class GuestIntroScreen extends StatefulWidget {
  const GuestIntroScreen({super.key});

  /// Oson o'zgartiriladigan qiymat — to'liq A/B infra bu bosqichda yo'q.
  static const int introScreenCount = 1;

  @override
  State<GuestIntroScreen> createState() => _GuestIntroScreenState();
}

class _GuestIntroScreenState extends State<GuestIntroScreen> {
  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6741);

  static const _pages = [
    (icon: Icons.auto_awesome_rounded, subtitleKey: 'guest_intro_subtitle'),
    (icon: Icons.explore_rounded, subtitleKey: 'guest_intro_subtitle_2'),
  ];

  final _pageCtrl = PageController();
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    if (GuestIntroScreen.introScreenCount <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await AnonSessionService().ensureAnonymousSession();
    } catch (_) {
      // Feed baribir ko'rsatiladi — offline/xato holatda ham davom etadi.
    }
    if (!mounted) return;
    pushAppHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final count = GuestIntroScreen.introScreenCount;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFE8F5E9),
              Color(0xFFF4FAF2),
              Color(0xFFDCEDC8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
            child: Column(
              children: [
                Text(
                  BrandLabels.brand,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.5,
                  ),
                ),
                Expanded(
                  child: _starting
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : count <= 0
                          ? const SizedBox.shrink()
                          : PageView.builder(
                              controller: _pageCtrl,
                              itemCount: count,
                              itemBuilder: (_, i) {
                                final page = _pages[i % _pages.length];
                                return _IntroPage(
                                  icon: page.icon,
                                  subtitleKey: page.subtitleKey,
                                  ink: _ink,
                                  muted: _muted,
                                );
                              },
                            ),
                ),
                if (count > 0 && !_starting) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _start,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        context.tr('ob_start'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.icon,
    required this.subtitleKey,
    required this.ink,
    required this.muted,
  });

  final IconData icon;
  final String subtitleKey;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 84, color: AppColors.primary),
        const SizedBox(height: 24),
        Text(
          context.tr(subtitleKey),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    );
  }
}
