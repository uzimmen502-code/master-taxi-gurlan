import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/user_error.dart';
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
    this.adminReview = false,
  });

  final String phone;
  final String name;
  final DeviceFingerprintSnapshot snapshot;
  final String requestId;
  final String oldDeviceLabel;
  final int? expiresAtMs;
  final OnboardingController? controller;

  /// «Эски телефоним йўқ» — administrator ko'rigi (soatlab kutish mumkin:
  /// so'rov kamroq, matnlar boshqa). Ilova yopilsa ham so'rov saqlanadi.
  final bool adminReview;

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
    // Admin ko'rigi soatlab davom etishi mumkin — har 15 s (§37); peer — 3 s.
    _timer = Timer.periodic(
      Duration(seconds: widget.adminReview ? 15 : 3),
      (_) => _poll(),
    );
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
          _error = context.tr(st.status == 'rejected'
              ? (widget.adminReview
                  ? 'ob_dev_review_rejected'
                  : 'ob_dev_pending_rejected')
              : 'ob_dev_pending_expired');
        });
        _timer?.cancel();
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = context.tr(onboardingErrorKey(e)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userErrorMessage(context, e));
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
        title: Text(context.tr(
            widget.adminReview ? 'ob_dev_review_title' : 'ob_dev_pending_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(widget.adminReview ? Icons.support_agent : Icons.phonelink_lock,
                size: 56, color: AppColors.primaryText),
            const SizedBox(height: 20),
            Text(
              widget.adminReview
                  ? context.tr('ob_dev_review_sent')
                  : label.isEmpty
                      ? context.tr('ob_dev_pending_sent_nolabel')
                      : context.trMsg('ob_dev_pending_sent_label',
                          params: {'label': label}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(widget.adminReview
                  ? 'ob_dev_review_hint'
                  : 'ob_dev_pending_hint'),
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
                child: Text(context.tr('back')),
              ),
            ],
            const Spacer(),
            TextButton(
              onPressed: _finishing ? null : _poll,
              child: Text(context.tr('ob_dev_pending_refresh')),
            ),
          ],
        ),
      ),
    );
  }
}
