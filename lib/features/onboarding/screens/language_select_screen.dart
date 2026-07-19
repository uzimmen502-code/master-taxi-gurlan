import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/locale_utils.dart';
import 'onboarding_screen.dart';

/// Бир марталик тил танлаш — юмшоқ (friendly) pill UI.
class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});
  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  Locale? _selected;
  bool _saving = false;

  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6741);

  @override
  void initState() {
    super.initState();
    _selected = LocaleUtils.localeResolutionCallback(
          LocaleUtils.resolveFromDevice(),
          LocaleUtils.supportedAppLocales,
        ) ??
        LocaleUtils.uzCyrl;
  }

  static const _options = [
    (label: "O'zbekcha", flag: '🇺🇿', locale: LocaleUtils.uzLatn),
    (label: 'Ўзбекча', flag: '🇺🇿', locale: LocaleUtils.uzCyrl),
    (label: 'Русский', flag: '🇷🇺', locale: LocaleUtils.ru),
  ];

  Future<void> _confirm() async {
    final chosen = _selected;
    if (chosen == null) return;
    setState(() => _saving = true);
    await context.read<LocaleNotifier>().setLocale(chosen);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  BrandLabels.brand,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(flex: 2),
                const Text('🌐',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                const Text(
                  'Тилни танланг',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Интерфейс тили — фақат бир марта.\nКейин профилда ўзгартириш мумкин.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Интерфейс тилини танланг',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._options.map((opt) {
                        final on = _selected == opt.locale;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () =>
                                  setState(() => _selected = opt.locale),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: on
                                      ? const Color(0xFFE8F5E9)
                                      : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: on
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                  boxShadow: on
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.18),
                                            blurRadius: 0,
                                            spreadRadius: 3,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(opt.flag,
                                          style: const TextStyle(fontSize: 20)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        opt.label,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: on
                                              ? AppColors.primaryDark
                                              : _ink,
                                        ),
                                      ),
                                    ),
                                    if (on)
                                      const Icon(Icons.check_circle,
                                          color: AppColors.primary, size: 22),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed:
                        (_selected == null || _saving) ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primaryDark.withValues(alpha: 0.35),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Давом этиш',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
