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
/// `isReminder: true` — ro'yxatdan yangi o'tgan foydalanuvchiga xuddi shu
/// tur eslatma sifatida qayta ko'rsatiladi (`OnboardingBootstrapScreen`dan
/// chaqiriladi); bu holda anonim sessiya ochilmaydi — foydalanuvchi
/// allaqachon telefon orqali autentifikatsiyadan o'tgan.
class GuestIntroScreen extends StatefulWidget {
  const GuestIntroScreen({super.key, this.isReminder = false});

  final bool isReminder;

  @override
  State<GuestIntroScreen> createState() => _GuestIntroScreenState();
}

class _IntroPageData {
  const _IntroPageData({
    required this.icon,
    required this.headKey,
    required this.bodyKey,
    this.tagsKey,
    this.isFunnel = false,
  });

  final IconData icon;
  final String headKey;
  final String bodyKey;
  final String? tagsKey;
  final bool isFunnel;
}

const _pages = [
  _IntroPageData(icon: Icons.people_alt_rounded, headKey: 'guest_intro2_p1_head', bodyKey: 'guest_intro2_p1_body'),
  _IntroPageData(icon: Icons.storefront_rounded, headKey: 'guest_intro2_p2_head', bodyKey: 'guest_intro2_p2_body'),
  _IntroPageData(icon: Icons.videocam_rounded, headKey: 'guest_intro2_p3_head', bodyKey: 'guest_intro2_p3_body'),
  _IntroPageData(icon: Icons.live_tv_rounded, headKey: 'guest_intro2_p4_head', bodyKey: 'guest_intro2_p4_body'),
  _IntroPageData(icon: Icons.local_shipping_rounded, headKey: 'guest_intro2_p5_head', bodyKey: 'guest_intro2_p5_body'),
  _IntroPageData(icon: Icons.storefront_outlined, headKey: 'guest_intro2_p6_head', bodyKey: 'guest_intro2_p6_body'),
  _IntroPageData(icon: Icons.park_rounded, headKey: 'guest_intro2_p7_head', bodyKey: 'guest_intro2_p7_body'),
  _IntroPageData(
    icon: Icons.auto_awesome_rounded,
    headKey: 'guest_intro2_p8_head',
    bodyKey: 'guest_intro2_p8_body',
    tagsKey: 'guest_intro2_p8_tags',
    isFunnel: true,
  ),
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
    if (!widget.isReminder) {
      try {
        await AnonSessionService().ensureAnonymousSession();
      } catch (_) {
        // Feed baribir ko'rsatiladi — offline/xato holatda ham davom etadi.
      }
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
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
            child: Column(
              children: [
                Text(
                  BrandLabels.brand,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
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
                  const SizedBox(height: 14),
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
                    const SizedBox(height: 6),
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

/// Саҳифа — "китоб варағи": иконка + сарлавҳа (марказда), сўнг эркин
/// сурилувчи мазмун. Мазмун ичидаги мини-белги: `## ` — кичик сарлавҳа,
/// `* ` — ажратилган хулоса (қалин/курсив), бўш қатор — абзац оралиғи.
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
    final body = context.tr(data.bodyKey);
    final tagsRaw = data.tagsKey == null ? '' : context.tr(data.tagsKey!);
    final tags = tagsRaw.isEmpty ? const <String>[] : tagsRaw.split('|');

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 6),
          Icon(data.icon, size: 52, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(
            context.tr(data.headKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              height: 1.28,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: _RichBody(text: body, ink: ink, muted: muted),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            _FunnelChips(tags: tags),
          ],
        ],
      ),
    );
  }
}

class _RichBody extends StatelessWidget {
  const _RichBody({required this.text, required this.ink, required this.muted});
  final String text;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 12));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            line.substring(3),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: ink),
          ),
        ));
      } else if (line.startsWith('* ')) {
        widgets.add(Container(
          margin: const EdgeInsets.only(top: 2, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryDark.withValues(alpha: 0.18)),
          ),
          child: Text(
            line.substring(2),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              fontSize: 13.5,
              height: 1.45,
              color: ink,
            ),
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: TextStyle(fontSize: 14, height: 1.55, fontWeight: FontWeight.w500, color: muted),
          ),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
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
