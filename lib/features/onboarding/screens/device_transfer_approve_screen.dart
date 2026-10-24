import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/user_error.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';

/// Eski qurilma: yangi telefon so‘rovini tasdiqlash / rad etish.
class DeviceTransferApproveScreen extends StatefulWidget {
  const DeviceTransferApproveScreen({
    super.key,
    required this.requestId,
    this.newDeviceLabel = '',
  });

  final String requestId;
  final String newDeviceLabel;

  @override
  State<DeviceTransferApproveScreen> createState() =>
      _DeviceTransferApproveScreenState();
}

class _DeviceTransferApproveScreenState
    extends State<DeviceTransferApproveScreen> {
  final _repo = DeviceBindingRepository();
  final _fp = DeviceFingerprintService();
  bool _busy = false;
  String? _error;

  Future<void> _respond(bool approve) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await _fp.collect();
      await _repo.respondDeviceTransfer(
        requestId: widget.requestId,
        approve: approve,
        snapshot: snapshot,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(approve
                ? 'ob_dev_approve_done'
                : 'ob_dev_approve_rejected_done'),
            style: TextStyle(color: approve ? AppColors.onPrimary : null),
          ),
          backgroundColor: approve ? AppColors.primary : Colors.red.shade700,
        ),
      );
      Navigator.pop(context, approve);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr(onboardingErrorKey(e));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(context, e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.newDeviceLabel.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ob_dev_approve_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.devices_other, size: 56, color: AppColors.primaryText),
            const SizedBox(height: 20),
            Text(
              label.isEmpty
                  ? context.tr('ob_dev_approve_req_nolabel')
                  : context.trMsg('ob_dev_approve_req_label',
                      params: {'label': label}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('ob_dev_approve_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : () => _respond(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : Text(context.tr('ob_dev_approve_allow')),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _respond(false),
              child: Text(context.tr('ob_dev_approve_reject')),
            ),
          ],
        ),
      ),
    );
  }
}
