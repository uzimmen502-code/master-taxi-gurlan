import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/locale_utils.dart';
import 'onboarding_screen.dart';

class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});
  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  Locale? _selected;
  bool _saving = false;

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
    (label: "O'zbek", sub: 'Lotin yozuvi', locale: LocaleUtils.uzLatn),
    (label: 'Ўзбек', sub: 'Кирилл ёзуви', locale: LocaleUtils.uzCyrl),
    (label: 'Русский', sub: 'Кириллица', locale: LocaleUtils.ru),
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
              AppColors.primaryDark,
              AppColors.primary,
              AppColors.primaryMid,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Text(
                  '🌐',
                  style: TextStyle(fontSize: 56),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Tilni tanlang\nВыберите язык\nТилни танланг",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 36),
                ...(_options.map((opt) {
                  final isSelected = _selected == opt.locale;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = opt.locale),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    opt.label,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white,
                                    ),
                                  ),
                                  Text(
                                    opt.sub,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected
                                          ? AppColors.primaryDark
                                          : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                                size: 26,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                })),
                const Spacer(),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed:
                        (_selected == null || _saving) ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Davom etish  /  Продолжить  /  Давом этиш',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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
