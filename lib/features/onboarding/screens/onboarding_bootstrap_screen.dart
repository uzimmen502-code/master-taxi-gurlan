import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/navigation/app_home_route.dart';
import '../controllers/onboarding_controller.dart';

/// Device binding OK → шу экран дарҳол очилади.
/// Фонда: Auth session → prefs → Home; profile ‖ zone ‖ FCM.
class OnboardingBootstrapScreen extends StatefulWidget {
  const OnboardingBootstrapScreen({
    super.key,
    required this.name,
    required this.phone,
  });

  final String name;
  final String phone;

  @override
  State<OnboardingBootstrapScreen> createState() =>
      _OnboardingBootstrapScreenState();
}

class _OnboardingBootstrapScreenState extends State<OnboardingBootstrapScreen> {
  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6741);

  String? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    final c = context.read<OnboardingController>();
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _error = null;
      _retrying = true;
    });

    // Онбординг экранида аллақачон sign-in бўлган бўлиши мумкин — лекин
    // сессия айнан шу телефонга тегишли бўлса.
    final signedInPhone =
        FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ?? '';
    final alreadySignedIn = signedInPhone.isNotEmpty &&
        canonicalPhoneId(signedInPhone) == canonicalPhoneId(widget.phone);
    final sessionOk = alreadySignedIn ||
        await c.establishPhoneSession(widget.phone);
    if (!mounted) return;
    if (!sessionOk) {
      setState(() {
        _retrying = false;
        _error = c.consumeError() ?? loc.translate('ob_device_linking');
      });
      return;
    }

    final prefsOk = await c.persistLocalOnboardingPrefs(
      name: widget.name,
      phone: widget.phone,
    );
    if (!mounted) return;
    if (!prefsOk) {
      setState(() {
        _retrying = false;
        _error = c.consumeError() ?? loc.translate('ob_err_zone');
      });
      return;
    }

    // Home дарҳол — profile/zone/FCM фонда.
    unawaited(
      c.syncProfileZoneFcmInBackground(
        name: widget.name,
        phone: widget.phone,
      ),
    );
    pushAppHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
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
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
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
                const Spacer(),
                if (_error == null) ...[
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    loc.translate('ob_device_linking'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.translate('ob_bootstrap_wait_hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: _muted,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.wifi_off_rounded,
                      size: 40, color: Colors.orange.shade800),
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _retrying ? null : _run,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        loc.translate('ob_retry'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
