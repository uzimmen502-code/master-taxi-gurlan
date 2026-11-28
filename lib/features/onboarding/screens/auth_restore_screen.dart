import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../qr_login/services/qr_web_auth.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../shared/navigation/app_home_route.dart';
import 'guest_intro_screen.dart';
import 'phone_reverify_screen.dart';

/// Restores Firebase Auth (trusted device) before Home or full reverify.
class AuthRestoreScreen extends StatefulWidget {
  const AuthRestoreScreen({super.key});

  @override
  State<AuthRestoreScreen> createState() => _AuthRestoreScreenState();
}

class _AuthRestoreScreenState extends State<AuthRestoreScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoRestore());
  }

  Future<void> _tryAutoRestore() async {
    if (FirebaseAuth.instance.currentUser != null) {
      _goHome();
      return;
    }

    // Компьютерда QR орқали кирилган браузер қайта очилди (Firebase SESSION — кириш йўқолган):
    // жим тиклаш ЙЎҚ (эга 2026-11-28: «ҳар сафар кирганда янгидан сканерлаш») — излар тозаланади,
    // кириш экрани (QR тугмаси шу ерда).
    if (kIsWeb) {
      try {
        if (await QrWebAuth.clearAfterBrowserRestart()) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuestIntroScreen()),
          );
          return;
        }
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      if (phoneDigits(phone).length < 12) {
        _goReverify();
        return;
      }

      final snapshot = await DeviceFingerprintService().collect();
      if (!DeviceBindingRepository.isValidFingerprintHash(snapshot.hash)) {
        _goReverify();
        return;
      }

      final repo = DeviceBindingRepository();
      final result = await repo.checkDeviceBinding(
        phone: phone,
        snapshot: snapshot,
      );

      if (result.status != DeviceBindingStatus.trustedDevice) {
        _goReverify();
        return;
      }

      // checkDeviceBinding faqat bind qiladi — token createPhoneSession dan.
      var token = (result.customToken ?? '').trim();
      if (token.isEmpty) {
        token = await repo.createPhoneSession(
          phone: phone,
          snapshot: snapshot,
        );
      }
      await FirebaseAuth.instance.signInWithCustomToken(token);
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (FirebaseAuth.instance.currentUser != null) {
        await prefs.setBool('phone_reverified', true);
        _goHome();
        return;
      }
    } catch (_) {
      // Trusted device failed — full reverify wizard.
    }

    _goReverify();
  }

  void _goHome() {
    if (!mounted) return;
    pushAppHome(context);
  }

  void _goReverify() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PhoneReverifyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
