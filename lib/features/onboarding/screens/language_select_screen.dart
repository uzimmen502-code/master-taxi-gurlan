import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/service_area_picker.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../utils/locale_utils.dart';
import 'onboarding_screen.dart';

/// Тил + туман — рўйхатдан олдин хабар ихчам экран.
class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});
  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  Locale? _selected;
  String _regionId = '';
  String _districtId = '';
  String _areaId = '';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_selected != null && mounted) {
        await context.read<LocaleNotifier>().setLocale(_selected!);
      }
      unawaited(DeviceBindingRepository().warmup());
    });
  }

  static const _options = [
    (label: "O'zbekcha", flag: '🇺🇿', locale: LocaleUtils.uzLatn),
    (label: 'Ўзбекча', flag: '🇺🇿', locale: LocaleUtils.uzCyrl),
    (label: 'Русский', flag: '🇷🇺', locale: LocaleUtils.ru),
  ];

  bool get _canContinue =>
      _selected != null &&
      _regionId.isNotEmpty &&
      _districtId.isNotEmpty &&
      _areaId.isNotEmpty &&
      !_saving;

  Future<void> _onLanguageTap(Locale locale) async {
    setState(() => _selected = locale);
    await context.read<LocaleNotifier>().setLocale(locale);
  }

  Future<void> _confirm() async {
    final chosen = _selected;
    if (chosen == null || !_canContinue) return;
    setState(() => _saving = true);
    try {
      await context.read<LocaleNotifier>().setLocale(chosen);
      await ServiceConfigHolder.applyGeo(
        regionId: _regionId,
        districtId: _districtId,
        serviceAreaId: _areaId,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pre_onboarding_region_id', _regionId);
      await prefs.setString('pre_onboarding_district_id', _districtId);
      await prefs.setString('pre_onboarding_service_area_id', _areaId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('ob_pre_zone_save_fail'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  BrandLabels.brand,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('ob_pre_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.tr('ob_pre_language'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._options.map((opt) {
                            final on = _selected == opt.locale;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _onLanguageTap(opt.locale),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: on
                                          ? const Color(0xFFE8F5E9)
                                          : const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: on
                                            ? AppColors.primary
                                            : Colors.transparent,
                                        width: 1.4,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(opt.flag,
                                            style:
                                                const TextStyle(fontSize: 18)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            opt.label,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: on
                                                  ? AppColors.primaryDark
                                                  : _ink,
                                            ),
                                          ),
                                        ),
                                        if (on)
                                          const Icon(Icons.check_circle,
                                              color: AppColors.primary,
                                              size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                          Divider(
                            height: 1,
                            color: _muted.withValues(alpha: 0.18),
                          ),
                          const SizedBox(height: 12),
                          ServiceAreaPicker(
                            showRegionDropdown: false,
                            showAreaDropdown: false,
                            districtLabel: context.tr('ob_pre_district'),
                            onChanged: (r, d, a) {
                              setState(() {
                                _regionId = r;
                                _districtId = d;
                                _areaId = a;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _canContinue ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primaryDark.withValues(alpha: 0.35),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
                        : Text(
                            context.tr('ob_pre_continue'),
                            style: const TextStyle(
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
