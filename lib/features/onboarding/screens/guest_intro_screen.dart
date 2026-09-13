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

  @override
  State<GuestIntroScreen> createState() => _GuestIntroScreenState();
}

class _IntroPageData {
  const _IntroPageData({
    required this.icon,
    required this.headKey,
    required this.subKey,
    this.tagsKey,
    this.isFunnel = false,
  });

  final IconData icon;
  final String headKey;
  final String subKey;
  final String? tagsKey;
  final bool isFunnel;
}

const _pages = [
  _IntroPageData(icon: Icons.people_alt_rounded, headKey: 'guest_intro2_p1_head', subKey: 'guest_intro2_p1_sub', tagsKey: 'guest_intro2_p1_tags'),
  _IntroPageData(icon: Icons.storefront_rounded, headKey: 'guest_intro2_p2_head', subKey: 'guest_intro2_p2_sub', tagsKey: 'guest_intro2_p2_tags'),
  _IntroPageData(icon: Icons.videocam_rounded, headKey: 'guest_intro2_p3_head', subKey: 'guest_intro2_p3_sub', tagsKey: 'guest_intro2_p3_tags'),
  _IntroPageData(icon: Icons.live_tv_rounded, headKey: 'guest_intro2_p4_head', subKey: 'guest_intro2_p4_sub', tagsKey: 'guest_intro2_p4_tags'),
  _IntroPageData(icon: Icons.local_shipping_rounded, headKey: 'guest_intro2_p5_head', subKey: 'guest_intro2_p5_sub', tagsKey: 'guest_intro2_p5_tags'),
  _IntroPageData(icon: Icons.storefront_outlined, headKey: 'guest_intro2_p6_head', subKey: 'guest_intro2_p6_sub', tagsKey: 'guest_intro2_p6_tags'),
  _IntroPageData(icon: Icons.park_rounded, headKey: 'guest_intro2_p7_head', subKey: 'guest_intro2_p7_sub', tagsKey: 'guest_intro2_p7_tags'),
  _IntroPageData(icon: Icons.auto_awesome_rounded, headKey: 'guest_intro2_p8_head', subKey: 'guest_intro2_p8_sub', tagsKey: 'guest_intro2_p8_tags', isFunnel: true),
];

class _GuestIntroScreenState extends State<GuestIntroScreen> {
  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6741);

  final _pageCtrl = PageController();
  int _page = 0;
  bool _starting = false;

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
    final isLast = _page == _pages.length - 1;
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
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
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
                          child: CircularProgressIndicator(color: AppColors.primary),
                        )
                      : PageView.builder(
                          controller: _pageCtrl,
                          itemCount: _pages.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, i) => _IntroPage(
                            data: _pages[i],
                            ink: _ink,
                            muted: _muted,
                          ),
                        ),
                ),
                if (!_starting) ...[
                  _Dots(count: _pages.length, index: _page),
                  const SizedBox(height: 16),
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
                        context.tr('guest_intro2_go_app'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                  ),
                  if (isLast) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _start,
                      child: Text(
                        context.tr('guest_intro2_read_later'),
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryDark : AppColors.primaryDark.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.data,
    required this.ink,
    required this.muted,
  });

  final _IntroPageData data;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final tagsRaw = data.tagsKey == null ? '' : context.tr(data.tagsKey!);
    final tags = tagsRaw.isEmpty ? const <String>[] : tagsRaw.split('|');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(data.icon, size: 72, color: AppColors.primary),
        const SizedBox(height: 22),
        Text(
          context.tr(data.headKey),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr(data.subKey),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          data.isFunnel ? _FunnelChips(tags: tags) : _TagChips(tags: tags),
        ],
      ],
    );
  }
}

class _TagChips extends StatelessWidget {
  const _TagChips({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: tags.map((t) => _Chip(t)).toList(),
    );
  }
}

class _FunnelChips extends StatelessWidget {
  const _FunnelChips({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < tags.length; i++) {
      children.add(_Chip(tags[i]));
      if (i < tags.length - 1) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text('→', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
        ));
      }
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 8,
      children: children,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primaryDark.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}
