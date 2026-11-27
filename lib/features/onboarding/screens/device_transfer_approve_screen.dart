import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/user_error.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';

/// «Ҳа» / «Йўқ» javobini serverga yuboradi (testda almashtiriladi).
typedef DeviceTransferResponder = Future<DeviceTransferRespondResult> Function(
    bool approve);

/// «Йўқ» dan keyin shu (bog'langan) telefonning jim qayta kirishi.
typedef DeviceSessionReauth = Future<void> Function();

/// Bog'langan telefon: «Бу сизми?» — yangi qurilma shu raqam bilan kirmoqchi
/// (ega 2026-11-28). Qurilma modeli/platformasi, taxminiy shahar va vaqt
/// ko'rsatiladi. «Ҳа» → yangi qurilma kiradi (24 soat pul chiqimi yopiq).
/// «Йўқ» → o'sha qurilma 24 soat blok, hisobning barcha sessiyalari bekor,
/// shu telefon esa o'z bog'lanishi bilan jim qayta kiradi.
class DeviceTransferApproveScreen extends StatefulWidget {
  const DeviceTransferApproveScreen({
    super.key,
    required this.requestId,
    this.newDeviceLabel = '',
    this.platform = '',
    this.approxCity = '',
    this.createdAtMs,
    this.channel = 'old_device_push',
    this.responder,
    this.reauth,
  });

  final String requestId;
  final String newDeviceLabel;
  final String platform;
  final String approxCity;
  final int? createdAtMs;
  final String channel;
  final DeviceTransferResponder? responder;
  final DeviceSessionReauth? reauth;

  @override
  State<DeviceTransferApproveScreen> createState() =>
      _DeviceTransferApproveScreenState();
}

class _DeviceTransferApproveScreenState
    extends State<DeviceTransferApproveScreen> {
  bool _busy = false;
  String? _error;

  Future<DeviceTransferRespondResult> _defaultRespond(bool approve) async {
    final snapshot = await DeviceFingerprintService().collect();
    return DeviceBindingRepository().respondDeviceTransfer(
      requestId: widget.requestId,
      approve: approve,
      snapshot: snapshot,
    );
  }

  /// Server `revokeRefreshTokens` qilgach: o'z bog'lanishi bilan yangi token.
  static Future<void> defaultReauth() async {
    // revoke vaqt belgisi soniya aniqligida — yangi token undan keyin bo'lsin.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final snapshot = await DeviceFingerprintService().collect();
    final token = await DeviceBindingRepository().trustedTokenForThisDevice(
      phone: phone,
      snapshot: snapshot,
    );
    if (token == null || token.isEmpty) return;
    await FirebaseAuth.instance.signInWithCustomToken(token);
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  Future<void> _respond(bool approve) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await (widget.responder ?? _defaultRespond)(approve);
      if (!mounted) return;
      if (!approve && res.reauthRequired) {
        final reauth = widget.reauth ?? defaultReauth;
        unawaited(reauth().catchError((Object e) {
          debugPrint('device reauth after reject: $e');
        }));
      }
      final rejected = !approve;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(rejected ? 'ob_dev_isyou_no_done' : 'ob_dev_approve_done'),
            style: TextStyle(color: rejected ? null : AppColors.onPrimary),
          ),
          backgroundColor: rejected ? Colors.red.shade700 : AppColors.primary,
        ),
      );
      Navigator.pop(context, approve);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr(_errorKey(e));
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

  String _errorKey(FirebaseFunctionsException e) {
    final details = e.details;
    final code = details is Map ? (details['code'] ?? '').toString() : '';
    if (code == 'DEVICE_NOT_BOUND') return 'ob_dev_isyou_not_bound';
    return onboardingErrorKey(e);
  }

  String _platformKey(String p) => switch (p.trim().toLowerCase()) {
        'android' => 'ob_dev_platform_android',
        'ios' => 'ob_dev_platform_ios',
        'web' => 'ob_dev_platform_web',
        _ => '',
      };

  static String _two(int v) => v.toString().padLeft(2, '0');

  String _timeText(BuildContext context) {
    final ms = widget.createdAtMs;
    if (ms == null || ms <= 0) return context.tr('ob_dev_isyou_time_now');
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${_two(t.day)}.${_two(t.month)} ${_two(t.hour)}:${_two(t.minute)}';
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.newDeviceLabel.trim();
    final pKey = _platformKey(widget.platform);
    final city = widget.approxCity.trim();
    final adminReview = widget.channel == 'admin_review';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ob_dev_isyou_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.phonelink_lock,
                size: 56, color: AppColors.primaryText),
            const SizedBox(height: 16),
            Text(
              context.tr('ob_dev_isyou_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  children: [
                    _row(
                      Icons.smartphone,
                      context.tr('ob_dev_isyou_device'),
                      label.isEmpty
                          ? context.tr('ob_dev_isyou_unknown_device')
                          : label,
                    ),
                    if (pKey.isNotEmpty)
                      _row(Icons.devices, context.tr('ob_dev_isyou_platform'),
                          context.tr(pKey)),
                    if (city.isNotEmpty)
                      _row(Icons.place_outlined,
                          context.tr('ob_dev_isyou_city'), city),
                    _row(Icons.schedule, context.tr('ob_dev_isyou_time'),
                        _timeText(context)),
                  ],
                ),
              ),
            ),
            if (adminReview) ...[
              const SizedBox(height: 12),
              Text(
                context.tr('ob_dev_isyou_admin_note'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              context.tr('ob_dev_isyou_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('devApproveYes'),
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
                  : Text(context.tr('ob_dev_isyou_yes')),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('devApproveNo'),
              onPressed: _busy ? null : () => _respond(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(context.tr('ob_dev_isyou_no')),
            ),
          ],
        ),
      ),
    );
  }
}
