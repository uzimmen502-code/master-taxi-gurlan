import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/user_address.dart';
import '../../../repositories/user_repository.dart';
import '../../home/screens/home_screen.dart';
import '../../../services/location_service.dart';
import '../controllers/onboarding_controller.dart';

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
  static const _green1 = AppColors.primaryDark;
  static const _green2 = AppColors.primary;
  static const _green3 = AppColors.primaryMid;

  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();

  // Manzil maydonlari — onboarding'ning 4-sahifasida shu yerda to'liq
  // to'ldiriladi. Profilga keyin qaytib to'ldirish KERAK EMAS.
  final _mfyCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseCtrl = TextEditingController();
  final _districtCtrl = TextEditingController(text: 'Гурлан');
  final _noteCtrl = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = '+998 ';
    _phoneCtrl.addListener(_enforcePhonePrefix);

    // Controller'dagi maydonlarni text controller'lar bilan ikki tomonlama
    // sinxronlash.
    _mfyCtrl.addListener(
        () => context.read<OnboardingController>().setMfy(_mfyCtrl.text));
    _streetCtrl.addListener(
        () => context.read<OnboardingController>().setStreet(_streetCtrl.text));
    _houseCtrl.addListener(
        () => context.read<OnboardingController>().setHouse(_houseCtrl.text));
    _districtCtrl.addListener(() =>
        context.read<OnboardingController>().setDistrict(_districtCtrl.text));
    _noteCtrl.addListener(
        () => context.read<OnboardingController>().setNote(_noteCtrl.text));
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
    _districtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _next() async {
    final c = context.read<OnboardingController>();
    final loc = AppLocalizations.of(context)!;

    if (c.currentPage == 1) {
      final raw = _phoneCtrl.text.trim();
      if (raw.length < 9) {
        _showError(loc.translate('ob_phone_required'));
        return;
      }
      setState(() => _isLoading = true);
      try {
        final ok = await c.checkPhoneDeviceLock(raw);
        if (!ok || !mounted) return;

        final fullPhone = '+${phoneDigits(raw)}';

        if (c.otpVerified || c.skipSmsVerification) {
          c.advance();
          c.advance();
          await _pageController.animateToPage(
            3,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
          return;
        }

        final current = FirebaseAuth.instance.currentUser;
        if (current != null &&
            current.phoneNumber == fullPhone &&
            current.phoneNumber != null) {
          c.otpVerified = true;
          c.advance();
          c.advance();
          await _pageController.animateToPage(
            3,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
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
    c.advance();
    await _pageController.nextPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  void _prev() {
    final c = context.read<OnboardingController>();
    c.back();
    _pageController.previousPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
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

  String _formatBirthDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  DateTime? _parseBirthDate(String value) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return null;
    try {
      final parsed = DateTime(y, mo, d);
      if (parsed.year != y || parsed.month != mo || parsed.day != d) {
        return null;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickBirthDate() async {
    final loc = AppLocalizations.of(context)!;
    final c = context.read<OnboardingController>();
    final now = DateTime.now();
    final initial = _parseBirthDate(c.birthDate) ?? DateTime(now.year - 25);
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
    final formatted = _formatBirthDate(picked);
    _birthDateCtrl.text = formatted;
    c.setBirthDate(formatted);
  }

  Future<void> _finish() async {
    final c = context.read<OnboardingController>();
    final ok = await c.finish(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
    );
    final err = c.consumeError();
    if (err != null && mounted) {
      _showError(err);
    }
    if (!ok || !mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
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
            colors: [_green1, _green2, _green3],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            _progressBar(c.currentPage),
            const SizedBox(height: 8),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: c.goToPage,
                children: [
                  _page1(loc),
                  _page2(loc),
                  _pageOtp(loc, c),
                  _page3(loc, c),
                  _pageBirthDate(loc, c),
                  _pageAddress(loc, c),
                ],
              ),
            ),
            _footerButtons(c, loc),
          ]),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // PROGRESS + FOOTER
  // ────────────────────────────────────────────────────────────────────
  Widget _progressBar(int currentPage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        children: List.generate(
          OnboardingController.totalPages,
          (i) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              decoration: BoxDecoration(
                color: i <= currentPage
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerButtons(OnboardingController c, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(children: [
        if (c.currentPage > 0)
          GestureDetector(
            onTap: _prev,
            child: Container(
              width: 50,
              height: 50,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: c.isSubmitting || c.isCheckingDevice || _isLoading
                  ? null
                  : (c.isLastPage ? _finish : _next),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _green2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: c.isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : Text(
                      c.isLastPage
                          ? loc.translate('start')
                          : loc.translate('continue'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // PAGES
  // ────────────────────────────────────────────────────────────────────
  Widget _page1(AppLocalizations loc) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('👋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(loc.translate('onboarding_welcome'),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(loc.translate('onboarding_name'),
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
            const SizedBox(height: 28),
            _field(
              controller: _nameCtrl,
              hint: loc.translate('enter_name'),
              icon: Icons.person_outline,
              inputType: TextInputType.name,
            ),
            const SizedBox(height: 28),
            _duaBox(loc.translate('allah_protect')),
          ],
        ),
      );

  Widget _page2(AppLocalizations loc) {
    final c = context.watch<OnboardingController>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📱', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            loc.translate('onboarding_phone'),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            loc.translate('ob_phone_lock_hint'),
            style: TextStyle(
                fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 28),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.phoneStepError!,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ]),
            ),
          ],
          if (c.isCheckingDevice) ...[
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 10),
                  Text(
                    loc.translate('ob_device_checking'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pageOtp(AppLocalizations loc, OnboardingController c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔐', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            loc.translate('ob_otp_title'),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            c.isAdminCodeReady
                ? 'Админ код тайёр — киритинг ёки автоматик тўлдирилади'
                : 'Админ код яратmoqda... (${_phoneCtrl.text})',
            style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8)),
          ),
          if (c.isAdminCodeReady && c.generatedAdminCode != null) ...[
            const SizedBox(height: 12),
            Text(
              'Код: ${c.generatedAdminCode}',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 6,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofocus: true,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '------',
                counterText: '',
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
                        curve: Curves.easeInOut);
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          if (c.isSendingOtp || (!c.isAdminCodeReady && !c.otpVerified))
            Center(
              child: Column(children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  c.isSendingOtp
                      ? 'Сўров юборилмоқда...'
                      : 'Админ код кутилмоқда...',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ]),
            ),
          if (c.isVerifyingOtp)
            Center(
              child: Column(children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 8),
                Text(loc.translate('ob_otp_verifying'),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
          if (c.otpVerified)
            Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(loc.translate('ob_otp_verified'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ]),
          if (c.otpError != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.otpError!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: c.isSendingOtp
                ? null
                : () {
                    _otpCtrl.clear();
                    c.requestAdminCode(_phoneCtrl.text);
                  },
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
            label: const Text(
              'Қайта сўров юбориш',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page3(AppLocalizations loc, OnboardingController c) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🙍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(loc.translate('onboarding_gender'),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(loc.translate('onboarding_gender_sub'),
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                  child: _genderCard(
                      c, 'male', '👨', loc.translate('gender_male'))),
              const SizedBox(width: 14),
              Expanded(
                  child: _genderCard(
                      c, 'female', '👩', loc.translate('gender_female'))),
            ]),
          ],
        ),
      );

  Widget _pageBirthDate(AppLocalizations loc, OnboardingController c) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🎂', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(loc.translate('ob_birth_title'),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              loc.translate('ob_birth_hint'),
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickBirthDate,
              child: AbsorbPointer(
                child: _field(
                  controller: _birthDateCtrl,
                  hint: loc.translate('ob_birth_input_hint'),
                  icon: Icons.cake_outlined,
                  inputType: TextInputType.datetime,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickBirthDate,
              icon: const Icon(Icons.calendar_month, color: Colors.white),
              label: Text(
                loc.translate('ob_birth_calendar'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (c.birthDate.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                loc.translate('ob_birth_optional'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      );

  /// **Manzil sahifasi** — onboarding'ning ГСП + qo'lda to'lдiriladigan toliq
  /// shakli. AddressEditScreen bilan bir xil maydonlar — buyurtmalardan keyin
  /// qayta to'ldirish KERAK EMAS.
  Widget _pageAddress(AppLocalizations loc, OnboardingController c) {
    final gpsRequired = c.isGpsRequiredForPhone(_phoneCtrl.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(loc.translate('ob_address_title'),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            gpsRequired
                ? loc.translate('ob_address_hint_both')
                : loc.translate('ob_address_hint_manual'),
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 14),

          // GPS блоки.
          if (gpsRequired) ...[
            _gpsCard(c, loc),
            const SizedBox(height: 12),
          ],

          // Қўлдa тўлдириш — МФЙ, кўча, уй.
          _manualCard(loc),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // GPS CARD
  // ────────────────────────────────────────────────────────────────────
  Widget _gpsCard(OnboardingController c, AppLocalizations loc) {
    final hasGps = c.hasGps;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              hasGps ? _green2.withValues(alpha: 0.4) : Colors.orange.shade300,
          width: 1.2,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.gps_fixed, color: _green2, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(loc.translate('ob_gps_required'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          _gpsStatusBadge(c, loc),
        ]),
        const SizedBox(height: 8),
        if (hasGps) ...[
          Row(children: [
            const Icon(Icons.place, size: 14, color: _green2),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}',
                style: const TextStyle(
                    fontSize: 12, color: _green2, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          if (c.accuracy != null) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.adjust, size: 11, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Аниқлик: ±${c.accuracy!.toStringAsFixed(0)} м',
                style: TextStyle(
                  fontSize: 11,
                  color: c.hasLowAccuracyGps
                      ? Colors.orange.shade800
                      : Colors.grey.shade600,
                  fontWeight:
                      c.hasLowAccuracyGps ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ],
          if (c.gpsFromLastKnown) ...[
            const SizedBox(height: 4),
            Text(
              loc.translate('ob_gps_fast_mode'),
              style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
            ),
          ],
          if (c.hasLowAccuracyGps) ...[
            const SizedBox(height: 4),
            Text(
              'Паст аниқлик (±${c.accuracy!.toStringAsFixed(0)} м). Очиқ жойда қайта урининг.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (c.isGeoHintLoading) ...[
            const SizedBox(height: 6),
            Text(
              loc.translate('ob_gps_geocoding'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ] else if (c.geoHint != null && c.geoHint!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Атроф (маълумот): ${c.geoHint}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.translate('ob_gps_not_obtained'),
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: ElevatedButton.icon(
            onPressed: c.isGpsLoading ? null : _fetchGps,
            icon: c.isGpsLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(hasGps ? Icons.refresh : Icons.my_location, size: 16),
            label: Text(
                hasGps
                    ? loc.translate('ob_gps_update')
                    : loc.translate('ob_gps_get'),
                style: const TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green2,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _gpsStatusBadge(OnboardingController c, AppLocalizations loc) {
    final addr = UserAddress(lat: c.lat, lng: c.lng, accuracy: c.accuracy);
    final q = addr.gpsQuality;
    final (label, bg, fg) = switch (q) {
      GpsQuality.high => (
          loc.translate('gps_quality_excellent'),
          Colors.green.shade50,
          _green2
        ),
      GpsQuality.medium => (
          loc.translate('gps_quality_medium'),
          Colors.amber.shade50,
          AppColors.primary
        ),
      GpsQuality.low => (
          loc.translate('gps_quality_low'),
          Colors.red.shade50,
          Colors.red.shade700
        ),
      GpsQuality.unknown => ('OK', Colors.blue.shade50, Colors.blue.shade700),
      GpsQuality.none => (
          loc.translate('gps_quality_none'),
          Colors.grey.shade100,
          Colors.grey
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // MANUAL CARD (МФЙ, кўча, уй, туман, изоҳ)
  // ────────────────────────────────────────────────────────────────────
  Widget _manualCard(AppLocalizations loc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.edit_location_alt, color: _green2, size: 18),
          const SizedBox(width: 6),
          Text(loc.translate('ob_manual_fill'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        _manualField(
          ctrl: _mfyCtrl,
          label: '${loc.translate('ob_mfy_label')} *',
          icon: Icons.location_city,
          hint: 'Масалан: «Бахт» МФЙ',
        ),
        const SizedBox(height: 10),
        _manualField(
          ctrl: _streetCtrl,
          label: 'Кўча / гузар *',
          icon: Icons.signpost,
          hint: 'Кўча / гузар номи',
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _manualField(
              ctrl: _houseCtrl,
              label: 'Уй № *',
              icon: Icons.home,
              hint: '12',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _manualField(
              ctrl: _districtCtrl,
              label: 'Туман',
              icon: Icons.map,
              hint: 'Гурлан',
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _manualField(
          ctrl: _noteCtrl,
          label: 'Қўшимча (ихтиёрий)',
          icon: Icons.notes,
          hint: 'Подъезд, қават, ориентир...',
          maxLines: 2,
        ),
      ]),
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
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        prefixIcon: Icon(icon, size: 16, color: _green2),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _green2, width: 1.5)),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // SMALL WIDGETS
  // ────────────────────────────────────────────────────────────────────
  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType inputType,
    List<TextInputFormatter>? formatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        inputFormatters: formatters,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: _green2),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _duaBox(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Text('🤲', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontStyle: FontStyle.italic)),
          ),
        ]),
      );

  Widget _genderCard(
      OnboardingController c, String value, String emoji, String label) {
    final sel = c.gender == value;
    return GestureDetector(
      onTap: () => c.setGender(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: sel ? Colors.white : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: sel ? _green2 : Colors.white,
              )),
          if (sel) ...[
            const SizedBox(height: 4),
            const Icon(Icons.check_circle, color: _green2, size: 18),
          ],
        ]),
      ),
    );
  }
}
