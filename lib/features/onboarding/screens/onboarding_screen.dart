import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../repositories/user_repository.dart';
import '../../../shared/navigation/app_home_route.dart';
import '../../../services/location_service.dart';
import '../controllers/onboarding_controller.dart';
import 'onboarding_bootstrap_screen.dart';

/// Ихчам онбординг: исм + телефон → Home (тил/туман олдинда).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnboardingController>(
      create: (ctx) {
        final c = OnboardingController(
          userRepo: ctx.read<UserRepository>(),
          locationService: ctx.read<LocationService>(),
        );
        unawaited(c.loadPreselectedGeo());
        return c;
      },
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

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = '+998 ';
    _phoneCtrl.addListener(_enforcePhonePrefix);
    _birthDateCtrl.addListener(() => context
        .read<OnboardingController>()
        .setBirthDate(_birthDateCtrl.text));
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

  Future<void> _next() async {
    final c = context.read<OnboardingController>();
    final loc = AppLocalizations.of(context)!;

    if (c.currentPage == 0) {
      final err = c.validate(name: _nameCtrl.text, phone: _phoneCtrl.text);
      if (err != null) {
        _showError(loc.translate(err));
        return;
      }
      final raw = _phoneCtrl.text.trim();
      setState(() => _isLoading = true);
      try {
        final ok = await c.checkPhoneDeviceLock(raw);
        if (!ok || !mounted) return;

        final fullPhone = '+${phoneDigits(raw)}';

        if (c.otpVerified || c.skipSmsVerification) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChangeNotifierProvider<OnboardingController>.value(
                value: c,
                child: OnboardingBootstrapScreen(
                  name: _nameCtrl.text,
                  phone: raw,
                ),
              ),
            ),
          );
          return;
        }

        final current = FirebaseAuth.instance.currentUser;
        if (current != null &&
            current.phoneNumber == fullPhone &&
            current.phoneNumber != null) {
          c.otpVerified = true;
          await _finish();
          return;
        }

        // Fallback: needsVerification — админ код оқими.
        final sent = await c.requestAdminCode(raw);
        if (!mounted) return;
        if (!sent) {
          _showError(
              c.otpError ?? loc.translate('ob_code_request_failed'));
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
      _showError(loc.translate(err));
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

  Future<void> _finish() async {
    final c = context.read<OnboardingController>();
    final loc = AppLocalizations.of(context)!;
    final err = c.validate(name: _nameCtrl.text, phone: _phoneCtrl.text);
    if (err != null) {
      _showError(loc.translate(err));
      return;
    }
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
                    if (c.currentPage > 0) ...[
                      const SizedBox(height: 10),
                      _progressBar(c.currentPage),
                    ],
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
              child: Text(
                loc.translate('ob_back'),
                style: const TextStyle(
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
                            ? loc.translate('ob_start')
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
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/ava_logo_mark.png',
                  height: 42,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 1,
                  height: 26,
                  color: _green.withValues(alpha: 0.35),
                ),
                Text(
                  loc.translate('ob_platform_for_you'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _greenDark.withValues(alpha: 0.9),
                    letterSpacing: 0.2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            loc.translate('ob_meet_title'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 10),
                Text(
                  loc.translate('ob_phone_bind_warning'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
                if (c.phoneStepError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    c.phoneStepError!.startsWith('ob_')
                        ? loc.translate(c.phoneStepError!)
                        : c.phoneStepError!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ],
                if (c.isCheckingDevice || _isLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: _green),
                  const SizedBox(height: 8),
                  Text(
                    loc.translate('ob_device_linking'),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
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
                Text(
                  loc.translate('ob_birth_enter'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 8),
                _field(
                  controller: _birthDateCtrl,
                  hint: loc.translate('ob_birth_input_hint'),
                  icon: Icons.cake_outlined,
                  inputType: TextInputType.number,
                  formatters: [_BirthDateInputFormatter()],
                ),
                const SizedBox(height: 10),
                _benefit(
                  icon: '🎂',
                  text: loc.translate('ob_birth_benefit'),
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
                ? loc.translate('ob_admin_code_ready')
                : loc
                    .translate('ob_admin_code_creating')
                    .replaceAll('{phone}', _phoneCtrl.text),
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
                    loc
                        .translate('ob_admin_code_label')
                        .replaceAll('{code}', c.generatedAdminCode!),
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
                        await _finish();
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
                        ? loc.translate('ob_admin_code_sending')
                        : loc.translate('ob_admin_code_waiting'),
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
