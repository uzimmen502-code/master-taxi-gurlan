import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../home/screens/home_screen.dart';
import 'phone_reverify_screen.dart';

/// Restores Firebase Auth (trusted device) before Home or full reverify.
class AuthRestoreScreen extends StatefulWidget {
  const AuthRestoreScreen({super.key, required this.phoneReverified});

  final bool phoneReverified;

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

    if (widget.phoneReverified) {
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

        if (result.status == DeviceBindingStatus.trustedDevice) {
          final token = result.customToken;
          if (token != null && token.isNotEmpty) {
            await FirebaseAuth.instance.signInWithCustomToken(token);
            if (FirebaseAuth.instance.currentUser != null) {
              _goHome();
              return;
            }
          }
        }
      } catch (_) {
        // Trusted device failed — fall through to reverify.
      }
    }

    _goReverify();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
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
