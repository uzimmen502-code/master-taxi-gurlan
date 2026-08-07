import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../shared/navigation/app_home_route.dart';

/// Mavjud foydalanuvchi — Firebase sessiyasi yo'qolganda qayta kirish.
///
/// Fingerprint + device_bindings → createPhoneSession (pending-code yo'q).
class PhoneReverifyScreen extends StatefulWidget {
  const PhoneReverifyScreen({super.key});

  @override
  State<PhoneReverifyScreen> createState() => _PhoneReverifyScreenState();
}

class _PhoneReverifyScreenState extends State<PhoneReverifyScreen> {
  final _pageController = PageController();
  final _auth = FirebaseAuth.instance;
  final _fingerprintService = DeviceFingerprintService();
  final _bindingRepo = DeviceBindingRepository();
  final _userRepo = UserRepository();

  int _step = 0;
  bool _loadingProfile = true;
  bool _signingIn = false;
  bool _signedIn = false;
  String? _error;

  String _phoneDigits = '';
  String _phoneE164 = '';
  String _userName = '';
  String _gender = 'male';
  String _birthDate = '';
  String _address = '';

  bool get _showProfileStep =>
      _birthDate.trim().isNotEmpty && _address.trim().isNotEmpty;

  int get _stepCount => _showProfileStep ? 3 : 2;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStoredProfile());
  }

  @override
  void dispose() {
    _pageController.dispose();
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
        await _bindAndSignIn();
        return;
      case 2:
        await _goHome();
        return;
    }
  }

  Future<void> _bindAndSignIn() async {
    if (_signingIn || _signedIn) return;
    final invalidDeviceMsg = context.tr('reverify_device_id_invalid');
    final bindFailedMsg = context.tr('reverify_bind_failed');
    final errorPrefix = context.tr('error');
    setState(() {
      _signingIn = true;
      _error = null;
    });

    try {
      final snapshot = await _fingerprintService.collect();
      if (!DeviceBindingRepository.isValidFingerprintHash(snapshot.hash)) {
        throw StateError(invalidDeviceMsg);
      }

      final result = await _bindingRepo.checkDeviceBinding(
        phone: _phoneDigits,
        snapshot: snapshot,
      );

      if (result.status != DeviceBindingStatus.trustedDevice) {
        if (!mounted) return;
        setState(() {
          _error = result.message ?? bindFailedMsg;
        });
        return;
      }

      final token = await _bindingRepo.createPhoneSession(
        phone: _phoneDigits,
        snapshot: snapshot,
      );
      await _auth.signInWithCustomToken(token);
      await _auth.currentUser?.getIdToken(true);

      if (!mounted) return;
      setState(() => _signedIn = true);

      if (_showProfileStep) {
        await _goToStep(2);
      } else {
        await _goHome(showProfileHint: true);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = firebaseFunctionsUserMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$errorPrefix: $e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
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
    if (_step == 0 || _signingIn) return;
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
      1 => _signingIn
          ? context.tr('ob_otp_verifying')
          : context.tr('reverify_enter_app'),
      _ => context.tr('reverify_enter_app'),
    };
  }

  bool _primaryEnabled() {
    if (_loadingProfile || _phoneDigits.length < 12 || _signingIn) {
      return false;
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
                    if (_showProfileStep) _stepProfile(context),
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
          if (_signingIn) ...[
            const SizedBox(height: 28),
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                context.tr('ob_otp_verifying'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
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
            icon: Icons.home_outlined,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
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
              onTap: _signingIn ? null : _back,
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
                child: _signingIn
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
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
