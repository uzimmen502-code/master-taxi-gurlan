import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../controllers/onboarding_controller.dart';
import 'onboarding_bootstrap_screen.dart';

/// Yangi qurilma: eski qurilmadan tasdiq kutish.
class DeviceTransferPendingScreen extends StatefulWidget {
  const DeviceTransferPendingScreen({
    super.key,
    required this.phone,
    required this.name,
    required this.snapshot,
    required this.requestId,
    this.oldDeviceLabel = '',
    this.expiresAtMs,
    this.controller,
  });

  final String phone;
  final String name;
  final DeviceFingerprintSnapshot snapshot;
  final String requestId;
  final String oldDeviceLabel;
  final int? expiresAtMs;
  final OnboardingController? controller;

  @override
  State<DeviceTransferPendingScreen> createState() =>
      _DeviceTransferPendingScreenState();
}

class _DeviceTransferPendingScreenState
    extends State<DeviceTransferPendingScreen> {
  final _repo = DeviceBindingRepository();
  Timer? _timer;
  String? _error;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    unawaited(_poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted || _finishing) return;
    try {
      final st = await _repo.getDeviceTransferStatus(
        phone: widget.phone,
        snapshot: widget.snapshot,
        requestId: widget.requestId,
      );
      if (!mounted) return;
      if (st.status == 'approved') {
        await _finishApproved();
        return;
      }
      if (st.status == 'rejected' ||
          st.status == 'expired' ||
          st.status == 'cancelled') {
        setState(() {
          _error = st.status == 'rejected'
              ? 'Eski qurilmada so‘rov rad etildi.'
              : 'Tasdiq muddati tugadi. Qayta urinib ko‘ring.';
        });
        _timer?.cancel();
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = firebaseFunctionsUserMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _finishApproved() async {
    if (_finishing) return;
    _finishing = true;
    _timer?.cancel();
    final c = widget.controller;
    if (c != null) {
      c.otpVerified = true;
      c.markBindingRegistered(widget.phone);
    }
    if (!mounted) return;
    if (c != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider<OnboardingController>.value(
            value: c,
            child: OnboardingBootstrapScreen(
              name: widget.name,
              phone: widget.phone,
            ),
          ),
        ),
      );
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.oldDeviceLabel.trim();
    final expired = widget.expiresAtMs != null &&
        widget.expiresAtMs! > 0 &&
        widget.expiresAtMs! <= DateTime.now().millisecondsSinceEpoch;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasdiq kutilmoqda'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.phonelink_lock, size: 56, color: AppColors.primary),
            const SizedBox(height: 20),
            Text(
              label.isEmpty
                  ? 'Eski qurilmangizga so‘rov yuborildi.'
                  : 'Eski qurilmaga ($label) so‘rov yuborildi.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Eski telefonda AVA ilovasini oching va «Ruxsat berish» tugmasini bosing. '
              'So‘rov taxminan 30 daqiqa amal qiladi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 28),
            if (_error == null && !expired)
              const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 14),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Orqaga'),
              ),
            ],
            const Spacer(),
            TextButton(
              onPressed: _finishing ? null : _poll,
              child: const Text('Holatni yangilash'),
            ),
          ],
        ),
      ),
    );
  }
}
