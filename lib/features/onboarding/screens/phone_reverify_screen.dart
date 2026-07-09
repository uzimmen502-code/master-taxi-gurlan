import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/pending_code_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../shared/navigation/app_home_route.dart';

/// Mavjud foydalanuvchi — Firebase sessiyasi yo'qolganda qayta kirish wizard.
///
/// Ma'lumot: SharedPreferences + ixtiyoriy Firestore. Har qadam foydalanuvchi
/// tasdiqlashi bilan ochiladi (avtomatik kod so'rovi / verify yo'q).
class PhoneReverifyScreen extends StatefulWidget {
  const PhoneReverifyScreen({super.key});

  @override
  State<PhoneReverifyScreen> createState() => _PhoneReverifyScreenState();
}

class _PhoneReverifyScreenState extends State<PhoneReverifyScreen> {
  static const _stepCount = 4;

  final _pageController = PageController();
  final _otpCtrl = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _fingerprintService = DeviceFingerprintService();
  final _pendingCodeRepo = PendingCodeRepository();
  final _userRepo = UserRepository();

  int _step = 0;
  bool _loadingProfile = true;

  String _phoneDigits = '';
  String _phoneE164 = '';
  String _userName = '';
  String _gender = 'male';
  String _birthDate = '';
  String _address = '';

  StreamSubscription<PendingCodeStatusUpdate>? _codeSub;
  bool _waitingCode = false;
  bool _codeReady = false;
  String? _generatedCode;
  bool _verifying = false;
  bool _otpVerified = false;
  String? _error;

  bool get _showProfileStep =>
      _birthDate.trim().isNotEmpty && _address.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStoredProfile());
  }

  @override
  void dispose() {
    _codeSub?.cancel();
    _pageController.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStoredProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final rawPhone = prefs.getString('user_phone') ?? '';
    final digits = phoneDigits(rawPhone);

    if (digits.length < 12) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _error = context.tr('reverify_no_phone');
      });
      return;
    }

    _phoneDigits = digits;
    _phoneE164 = '+$digits';
    _userName = (prefs.getString('user_name') ??
            prefs.getString('userName') ??
            '')
        .trim();
    _gender = prefs.getString('user_gender') ?? 'male';
    _birthDate = prefs.getString('user_birth_date') ?? '';
    _address = prefs.getString('user_address') ?? '';

    final uid = (prefs.getString('userId') ?? '').trim();
    final lookupId = uid.length >= 12 ? uid : digits;

    if (_userName.isEmpty ||
        _birthDate.isEmpty ||
        _address.isEmpty ||
        _gender.isEmpty) {
      try {
        final user = await _userRepo.getById(lookupId);
        if (user != null) {
          if (_userName.isEmpty && user.name.trim().isNotEmpty) {
            _userName = user.name.trim();
          }
          if (_gender.isEmpty && user.gender.isNotEmpty) {
            _gender = user.gender;
          }
          if (_birthDate.isEmpty && user.birthDate.trim().isNotEmpty) {
            _birthDate = user.birthDate.trim();
          }
          if (_address.isEmpty) {
            final display = user.addressDisplay.trim();
            if (display.isNotEmpty) _address = display;
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _loadingProfile = false);
  }

  Future<void> _goToStep(int step) async {
    setState(() {
      _step = step;
      _error = null;
    });
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _onPrimaryAction() async {
    switch (_step) {
      case 0:
        await _goToStep(1);
        return;
      case 1:
        await _requestAdminCodeAndContinue();
        return;
      case 2:
        if (_otpVerified) {
          await _advanceAfterOtp();
        } else {
          await _verifyCode(_otpCtrl.text.trim());
        }
        return;
      case 3:
        await _goHome();
        return;
    }
  }

  Future<void> _advanceAfterOtp() async {
    if (_showProfileStep) {
      await _goToStep(3);
    } else {
      await _goHome(showProfileHint: true);
    }
  }

  void _resetCodeState() {
    _codeSub?.cancel();
    _codeSub = null;
    _waitingCode = false;
    _codeReady = false;
    _generatedCode = null;
    _otpVerified = false;
    _verifying = false;
    _otpCtrl.clear();
  }

  Future<void> _requestAdminCodeAndContinue() async {
    _resetCodeState();
    setState(() {
      _waitingCode = true;
      _error = null;
    });

    try {
      final snapshot = await _fingerprintService.collect();
      await _pendingCodeRepo.requestPendingCode(
        phone: _phoneDigits,
        snapshot: snapshot,
      );

      _codeSub = _pendingCodeRepo
          .watchStatus(
            phone: _phoneDigits,
            deviceFingerprintHash: snapshot.hash,
          )
          .listen((update) {
        if (!mounted) return;

        if (update.status == 'expired') {
          setState(() {
            _error = context.tr('reverify_code_expired');
            _waitingCode = false;
            _codeReady = false;
          });
          return;
        }

        if (update.isApproved) {
          final code = update.code!;
          setState(() {
            _generatedCode = code;
            _codeReady = true;
            _waitingCode = false;
            _error = null;
          });
          if (_otpCtrl.text != code) {
            _otpCtrl.text = code;
            _otpCtrl.selection = TextSelection.collapsed(offset: code.length);
          }
        }
      }, onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = '${context.tr('error')}: $e');
      });

      await _goToStep(2);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${context.tr('error')}: $e');
    }
  }

  Future<void> _verifyCode(String code) async {
    if (code.trim().length != 6 || _verifying || _otpVerified) return;
    if (!_codeReady) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final snapshot = await _fingerprintService.collect();
      final callable = FirebaseFunctions.instance
          .httpsCallable('verifyPendingCodeAndRegister');
      final result = await callable.call<Map<String, dynamic>>({
        'phone': _phoneDigits,
        'code': code.trim(),
        'deviceFingerprintHash': snapshot.hash,
        'fingerprint': Map<String, String>.from(snapshot.components),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final token = data['customToken'] as String?;
      if (token != null && token.isNotEmpty) {
        await _auth.signInWithCustomToken(token);
      }
      _codeSub?.cancel();
      if (!mounted) return;
      setState(() => _otpVerified = true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = firebaseFunctionsUserMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${context.tr('error')}: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _goHome({bool showProfileHint = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('phone_reverified', true);
    if (_userName.isNotEmpty) {
      await prefs.setString('user_name', _userName);
    }
    if (_birthDate.isNotEmpty) {
      await prefs.setString('user_birth_date', _birthDate);
    }
    if (_address.isNotEmpty) {
      await prefs.setString('user_address', _address);
    }
    if (_gender.isNotEmpty) {
      await prefs.setString('user_gender', _gender);
    }

    if (!mounted) return;

    if (showProfileHint) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('reverify_profile_incomplete_hint')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    Navigator.pushAndRemoveUntil(
      context,
      appHomeRoute(),
      (_) => false,
    );
  }

  Future<void> _back() async {
    if (_step == 0) return;
    if (_step == 2) _resetCodeState();
    await _goToStep(_step - 1);
  }

  String _genderLabel(BuildContext context) {
    return _gender == 'female'
        ? context.tr('gender_female')
        : context.tr('gender_male');
  }

  String _primaryLabel(BuildContext context) {
    return switch (_step) {
      0 => context.tr('reverify_confirm_yes'),
      1 => context.tr('reverify_request_code'),
      2 => _otpVerified
          ? context.tr('continue')
          : context.tr('reverify_confirm_code'),
      _ => context.tr('reverify_enter_app'),
    };
  }

  bool _primaryEnabled() {
    if (_loadingProfile || _phoneDigits.length < 12) return false;
    if (_step == 2) {
      if (_verifying) return false;
      if (_otpVerified) return true;
      return _codeReady && _otpCtrl.text.trim().length == 6;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
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
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  context.tr('loading'),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_phoneDigits.length < 12) {
      return _errorScaffold(context, _error ?? context.tr('reverify_no_phone'));
    }

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
          child: Column(
            children: [
              _progressBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _stepIdentity(context),
                    _stepPhone(context),
                    _stepCode(context),
                    _stepProfile(context),
                  ],
                ),
              ),
              if (_error != null) _errorBox(_error!),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorScaffold(BuildContext context, String message) {
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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        children: List.generate(
          _stepCount,
          (i) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              decoration: BoxDecoration(
                color: i <= _step
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

  Widget _stepIdentity(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👋', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            context.tr('reverify_step_identity_title'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('reverify_wizard_intro'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 24),
          _readOnlyCard(
            icon: Icons.person_outline,
            label: context.tr('enter_name'),
            value: _userName.isNotEmpty ? _userName : '—',
          ),
        ],
      ),
    );
  }

  Widget _stepPhone(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📱', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            context.tr('reverify_step_phone_title'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('reverify_phone_binding_hint'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 24),
          _readOnlyCard(
            icon: Icons.phone_outlined,
            label: context.tr('reverify_phone_label'),
            value: _phoneE164,
          ),
        ],
      ),
    );
  }

  Widget _stepCode(BuildContext context) {
    final statusText = _codeReady
        ? context.tr('reverify_code_ready').replaceAll('{phone}', _phoneE164)
        : context.tr('reverify_code_waiting').replaceAll('{phone}', _phoneE164);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔐', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            context.tr('reverify_title'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('reverify_code_confirm_hint'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          if (_codeReady && _generatedCode != null) ...[
            const SizedBox(height: 12),
            Text(
              'Код: $_generatedCode',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 6,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              enabled: _codeReady && !_verifying && !_otpVerified,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                hintText: '------',
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_waitingCode && !_codeReady) ...[
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('reverify_code_pending'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
          if (_verifying) ...[
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('ob_otp_verifying'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
          if (_otpVerified) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  context.tr('ob_otp_verified'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
          if (!_waitingCode && !_codeReady && !_otpVerified) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _requestAdminCodeAndContinue,
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
              label: Text(
                context.tr('reverify_resend'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepProfile(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🙍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            context.tr('reverify_step_profile_title'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('reverify_step_profile_sub'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 24),
          _readOnlyCard(
            icon: Icons.wc_outlined,
            label: context.tr('reverify_profile_gender'),
            value: _genderLabel(context),
          ),
          const SizedBox(height: 12),
          _readOnlyCard(
            icon: Icons.cake_outlined,
            label: context.tr('reverify_profile_birth'),
            value: _birthDate.isNotEmpty ? _birthDate : '—',
          ),
          const SizedBox(height: 12),
          _readOnlyCard(
            icon: Icons.location_on_outlined,
            label: context.tr('reverify_profile_address'),
            value: _address.isNotEmpty ? _address : '—',
          ),
        ],
      ),
    );
  }

  Widget _readOnlyCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          if (_step > 0)
            GestureDetector(
              onTap: _verifying ? null : _back,
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
                onPressed: _primaryEnabled() ? _onPrimaryAction : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _primaryLabel(context),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
