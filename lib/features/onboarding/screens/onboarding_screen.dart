import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/service_area_picker.dart';
import '../../../l10n/app_localizations.dart';
import '../../../repositories/user_repository.dart';
import '../../../shared/navigation/app_home_route.dart';
import '../../../services/location_service.dart';
import '../../../services/mfy_service.dart';
import '../../oil_change/data/oil_car_options.dart';
import '../controllers/onboarding_controller.dart';

/// Ихчам soft онбординг: танишув → админ код → ҳудуд → Home.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnboardingController>(
      create: (ctx) => OnboardingController(
        userRepo: ctx.read<UserRepository>(),
        locationService: ctx.read<LocationService>(),
      ),
      child: const _OnboardingView(),
    );
  }
}

class _OnboardingView extends StatefulWidget {
  const _OnboardingView();

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6741);
  static const _green = AppColors.primary;
  static const _greenDark = AppColors.primaryDark;

  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _mfyCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseCtrl = TextEditingController();
  final _carPlateCtrl = TextEditingController();

  bool _isLoading = false;
  bool _carExpanded = false;

  @override
  void initState() {
    super.initState();
    unawaited(MfyService.loadMfyData());
    _phoneCtrl.text = '+998 ';
    _phoneCtrl.addListener(_enforcePhonePrefix);
    _mfyCtrl.addListener(
        () => context.read<OnboardingController>().setMfy(_mfyCtrl.text));
    _streetCtrl.addListener(
        () => context.read<OnboardingController>().setStreet(_streetCtrl.text));
    _houseCtrl.addListener(
        () => context.read<OnboardingController>().setHouse(_houseCtrl.text));
    _birthDateCtrl.addListener(() => context
        .read<OnboardingController>()
        .setBirthDate(_birthDateCtrl.text));
    _carPlateCtrl.addListener(() =>
        context.read<OnboardingController>().setCarPlate(_carPlateCtrl.text));
  }

  void _enforcePhonePrefix() {
    if (!_phoneCtrl.text.startsWith('+998 ')) {
      _phoneCtrl.text = '+998 ';
      _phoneCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _phoneCtrl.text.length));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _birthDateCtrl.dispose();
    _mfyCtrl.dispose();
    _streetCtrl.dispose();
    _houseCtrl.dispose();
    _carPlateCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _goPage(int page) async {
    context.read<OnboardingController>().goToPage(page);
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _next() async {
    final c = context.read<OnboardingController>();

    if (c.currentPage == 0) {
      final err = c.validate(name: _nameCtrl.text, phone: _phoneCtrl.text);
      if (err != null) {
        _showError(err);
        return;
      }
      final raw = _phoneCtrl.text.trim();
      setState(() => _isLoading = true);
      try {
        final ok = await c.checkPhoneDeviceLock(raw);
        if (!ok || !mounted) return;

        final fullPhone = '+${phoneDigits(raw)}';

        if (c.otpVerified || c.skipSmsVerification) {
          await _goPage(2);
          return;
        }

        final current = FirebaseAuth.instance.currentUser;
        if (current != null &&
            current.phoneNumber == fullPhone &&
            current.phoneNumber != null) {
          c.otpVerified = true;
          await _goPage(2);
          return;
        }

        final sent = await c.requestAdminCode(raw);
        if (!mounted) return;
        if (!sent) {
          _showError(c.otpError ?? 'Код сўрови юборилмади');
          return;
        }
        c.advance();
        await _pageController.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    final err = c.validate(name: _nameCtrl.text, phone: _phoneCtrl.text);
    if (err != null) {
      _showError(err);
      return;
    }
    if (c.isLastPage) {
      await _finish();
      return;
    }
    c.advance();
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _prev() {
    final c = context.read<OnboardingController>();
    c.back();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _fetchGps() async {
    final c = context.read<OnboardingController>();
    final ok = await c.fetchGps();
    if (!mounted) return;
    if (!ok) {
      final err = c.consumeError();
      if (err != null) _showError(err);
    }
  }

  Future<void> _pickBirthDate() async {
    final loc = AppLocalizations.of(context)!;
    final c = context.read<OnboardingController>();
    final now = DateTime.now();
    final initial = OnboardingController.parseBirthDate(c.birthDate) ??
        DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: loc.translate('ob_birth_picker'),
      cancelText: loc.translate('ob_date_picker_cancel'),
      confirmText: loc.translate('ob_date_picker_confirm'),
    );
    if (picked == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final formatted =
        '${two(picked.day)}.${two(picked.month)}.${picked.year}';
    _birthDateCtrl.text = formatted;
    c.setBirthDate(formatted);
  }

  void _prepareCarBeforeFinish(OnboardingController c) {
    final plate = _carPlateCtrl.text.trim();
    final wantsCar = _carExpanded &&
        (plate.isNotEmpty ||
            c.carBrand.trim().isNotEmpty && c.carModel.trim().isNotEmpty);
    if (wantsCar) {
      c.setSkipCarStep(false);
      c.setCarSetupStep(1);
      if (c.carUsageTags.isEmpty) {
        c.setCarUsageTags(const ['taxi']);
      }
    } else {
      c.clearCarDraft();
    }
  }

  Future<void> _finish() async {
    final c = context.read<OnboardingController>();
    final err = c.validate(name: _nameCtrl.text, phone: _phoneCtrl.text);
    if (err != null) {
      _showError(err);
      return;
    }
    _prepareCarBeforeFinish(c);
    final ok = await c.finish(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
    );
    final finishErr = c.consumeError();
    if (finishErr != null && mounted) _showError(finishErr);
    if (!ok || !mounted) return;
    pushAppHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<OnboardingController>();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFFF4FAF2), Color(0xFFDCEDC8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  children: [
                    Text(
                      BrandLabels.brand,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _greenDark,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _progressBar(c.currentPage),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Қадам ${c.currentPage + 1} / ${OnboardingController.totalPages}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: c.goToPage,
                  children: [
                    _pageIdentity(loc, c),
                    _pageOtp(loc, c),
                    _pageZone(loc, c),
                  ],
                ),
              ),
              _footer(c, loc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressBar(int currentPage) {
    return Row(
      children: List.generate(
        OnboardingController.totalPages,
        (i) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            decoration: BoxDecoration(
              color: i <= currentPage
                  ? _green
                  : _green.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(OnboardingController c, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        children: [
          if (c.currentPage > 0)
            TextButton(
              onPressed: _isLoading ? null : _prev,
              child: const Text(
                'Ортга',
                style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (c.currentPage > 0) const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: c.isSubmitting || c.isCheckingDevice || _isLoading
                    ? null
                    : _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _greenDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: c.isSubmitting || _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        c.isLastPage
                            ? 'Бошлаш'
                            : loc.translate('continue'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 0 ───────────────────────────────────────────────────────────
  Widget _pageIdentity(AppLocalizations loc, OnboardingController c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👋', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          const Text(
            'Танишайлик',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Исм, телефон ва жинс — битта экранда.',
            style: TextStyle(fontSize: 14, color: _muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(
              children: [
                _field(
                  controller: _nameCtrl,
                  hint: loc.translate('enter_name'),
                  icon: Icons.person_outline,
                  inputType: TextInputType.name,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _phoneCtrl,
                  hint: loc.translate('enter_phone'),
                  icon: Icons.phone_outlined,
                  inputType: TextInputType.phone,
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s]')),
                  ],
                ),
                if (c.phoneStepError != null) ...[
                  const SizedBox(height: 10),
                  Text(c.phoneStepError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                ],
                if (c.isCheckingDevice) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: _green),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _genderPill(
                          c, 'male', '👨', loc.translate('gender_male')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _genderPill(
                          c, 'female', '👩', loc.translate('gender_female')),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _birthDateCtrl,
                  hint: loc.translate('ob_birth_input_hint'),
                  icon: Icons.cake_outlined,
                  inputType: TextInputType.number,
                  formatters: [_BirthDateInputFormatter()],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickBirthDate,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: Text(loc.translate('ob_birth_calendar')),
                    style: TextButton.styleFrom(foregroundColor: _greenDark),
                  ),
                ),
                _benefit(
                  icon: '🎂',
                  text:
                      'Киритсангиз — AVA Zona туғилган кунда табрик ва бонус беради.',
                  warm: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 1 ───────────────────────────────────────────────────────────
  Widget _pageOtp(AppLocalizations loc, OnboardingController c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔐', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            loc.translate('ob_otp_title'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.isAdminCodeReady
                ? 'Админ код тайёр — киритинг ёки автоматик тўлдирилади'
                : 'Админ код яратилмоқда... (${_phoneCtrl.text})',
            style: const TextStyle(
              fontSize: 14,
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(
              children: [
                if (c.isAdminCodeReady && c.generatedAdminCode != null) ...[
                  Text(
                    'Код: ${c.generatedAdminCode}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _greenDark,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: _ink,
                  ),
                  decoration: InputDecoration(
                    hintText: '------',
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                  onChanged: (val) async {
                    if (c.isAdminCodeReady &&
                        c.generatedAdminCode != null &&
                        val.trim().isEmpty) {
                      _otpCtrl.text = c.generatedAdminCode!;
                      _otpCtrl.selection = TextSelection.collapsed(
                        offset: c.generatedAdminCode!.length,
                      );
                    }
                    if (val.trim().length == 6) {
                      final ok = await c.verifyAdminCode(
                        _phoneCtrl.text,
                        val.trim(),
                      );
                      if (ok && mounted) {
                        c.advance();
                        await _pageController.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                        );
                      } else if (mounted && c.otpError != null) {
                        _showError(c.otpError!);
                      }
                    }
                  },
                ),
                if (c.isSendingOtp ||
                    (!c.isAdminCodeReady && !c.otpVerified)) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: _green),
                  const SizedBox(height: 8),
                  Text(
                    c.isSendingOtp
                        ? 'Сўров юборилмоқда...'
                        : 'Админ код кутилмоқда...',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
                if (c.otpVerified) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: _green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        loc.translate('ob_otp_verified'),
                        style: const TextStyle(
                          color: _greenDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 2 ───────────────────────────────────────────────────────────
  Widget _pageZone(AppLocalizations loc, OnboardingController c) {
    final gpsRequired = c.isGpsRequiredForPhone(_phoneCtrl.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          const Text(
            'Ҳудудингиз',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Вилоят, туман ва GPS — хизматлар учун. Аниқ манзил — ихтиёрий.',
            style: TextStyle(
              fontSize: 14,
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Хизмат зонаси *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                ServiceAreaPicker(
                  initialRegionId: c.geoRegionId,
                  initialDistrictId: c.geoDistrictId,
                  initialServiceAreaId: c.geoServiceAreaId,
                  showAreaDropdown: false,
                  onChanged: (region, district, area) {
                    c.setGeoArea(region, district, area);
                  },
                ),
                if (gpsRequired) ...[
                  const SizedBox(height: 14),
                  _gpsCard(c, loc),
                ],
                const SizedBox(height: 10),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    title: const Text(
                      'Яшаш манзилингизни киритинг',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _greenDark,
                        fontSize: 14,
                      ),
                    ),
                    children: [
                      _benefit(
                        icon: '🍞',
                        text:
                            'Аниқ манзил бўлса — нон ва бошқа буюртмалар тўғри эшигингизга етиб боради.',
                      ),
                      const SizedBox(height: 10),
                      _mfyAutocomplete(c, loc),
                      const SizedBox(height: 8),
                      _manualField(
                        ctrl: _streetCtrl,
                        label: 'Кўча / гузар',
                        icon: Icons.signpost,
                        hint: 'Кўча номи',
                      ),
                      const SizedBox(height: 8),
                      _manualField(
                        ctrl: _houseCtrl,
                        label: 'Уй №',
                        icon: Icons.home,
                        hint: '12',
                      ),
                    ],
                  ),
                ),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    onExpansionChanged: (v) =>
                        setState(() => _carExpanded = v),
                    title: const Text(
                      'Автомобил маълумоти',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _greenDark,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'ихтиёрий',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                    children: [
                      _benefit(
                        icon: '🚗',
                        text:
                            'Киритсангиз — AVA service хизматларини 5%–20% арзонроқ таклиф қиламиз.',
                        warm: true,
                      ),
                      const SizedBox(height: 10),
                      _dropdownStr(
                        label: context.tr('oil_brand'),
                        value: OilCarOptions.brands.contains(c.carBrand)
                            ? c.carBrand
                            : OilCarOptions.brands.first,
                        items: OilCarOptions.brands,
                        onChanged: c.setCarBrand,
                      ),
                      _dropdownStr(
                        label: context.tr('oil_model'),
                        value: OilCarOptions.models.contains(c.carModel)
                            ? c.carModel
                            : OilCarOptions.models.first,
                        items: OilCarOptions.models,
                        onChanged: c.setCarModel,
                      ),
                      _dropdownInt(
                        label: context.tr('oil_year'),
                        value: OilCarOptions.years.contains(c.carYear)
                            ? c.carYear
                            : OilCarOptions.years.first,
                        items: OilCarOptions.years,
                        onChanged: c.setCarYear,
                      ),
                      _manualField(
                        ctrl: _carPlateCtrl,
                        label: context.tr('onb_car_plate_hint'),
                        icon: Icons.pin_outlined,
                        hint: '01 A 123 BC',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gpsCard(OnboardingController c, AppLocalizations loc) {
    final hasGps = c.hasGps;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasGps ? _green.withValues(alpha: 0.45) : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, color: _green, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  loc.translate('ob_gps_required'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasGps)
            Text(
              '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}'
              '${c.accuracy != null ? ' · ±${c.accuracy!.toStringAsFixed(0)} м' : ''}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _greenDark,
              ),
            )
          else
            Text(
              loc.translate('ob_gps_not_obtained'),
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: c.isGpsLoading ? null : _fetchGps,
              icon: c.isGpsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(hasGps ? Icons.refresh : Icons.my_location, size: 18),
              label: Text(
                hasGps
                    ? loc.translate('ob_gps_update')
                    : 'Жойлашувни олиш (GPS)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _benefit({
    required String icon,
    required String text,
    bool warm = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: warm
              ? const [Color(0xFFFFF8E1), Color(0xFFE8F5E9)]
              : const [Color(0xFFE3F2FD), Color(0xFFE8F5E9)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: warm
              ? const Color(0x338D6E00)
              : const Color(0x331565C0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: warm ? const Color(0xFF5D4037) : const Color(0xFF1A3A5C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genderPill(
    OnboardingController c,
    String value,
    String emoji,
    String label,
  ) {
    final on = c.gender == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => c.setGender(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFE8F5E9) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: on ? _green : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: on ? _greenDark : _ink,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType inputType,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      inputFormatters: formatters,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: Icon(icon, color: _green),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _mfyAutocomplete(OnboardingController c, AppLocalizations loc) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _mfyCtrl.text),
      optionsBuilder: (TextEditingValue tev) async {
        await MfyService.loadMfyData();
        final q = tev.text.trim();
        final districtId = c.geoDistrictId.trim();
        if (q.isEmpty) {
          final list = districtId.isNotEmpty
              ? MfyService.getMfyByDistrict(districtId)
              : MfyService.getAllMfy();
          if (list.isEmpty) return MfyService.getAllMfy().take(12);
          return list.take(12);
        }
        var hits = MfyService.searchMfy(
          q,
          district: districtId.isEmpty ? null : districtId,
        );
        if (hits.isEmpty) hits = MfyService.searchMfy(q);
        return hits.take(12);
      },
      onSelected: (value) {
        _mfyCtrl.text = value;
        c.setMfy(value);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          onChanged: (v) {
            _mfyCtrl.text = v;
            c.setMfy(v);
          },
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: loc.translate('ob_mfy_label'),
            hintText: 'МФЙ номини ёзинг — рўйхатдан танланг',
            prefixIcon:
                const Icon(Icons.location_city, size: 18, color: _green),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF7FBF7),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _green, width: 1.5),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      option,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _manualField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String hint = '',
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: _green),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7FBF7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
      ),
    );
  }

  Widget _dropdownStr({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF7FBF7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: items.contains(value) ? value : items.first,
            isExpanded: true,
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  Widget _dropdownInt({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF7FBF7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: items.contains(value) ? value : items.first,
            isExpanded: true,
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

class _BirthDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 2 || i == 4) buf.write('.');
      buf.write(capped[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
