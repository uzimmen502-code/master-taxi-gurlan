import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../controllers/onboarding_controller.dart';
import '../screens/device_transfer_pending_screen.dart';

/// phone_bound_other_device / device_bound_other_phone / blocked uchun tanlov.
Future<bool> showDeviceBindingConflictSheet({
  required BuildContext context,
  required DeviceBindingCheckResult result,
  required String phone,
  required String name,
  required DeviceFingerprintSnapshot snapshot,
  OnboardingController? controller,
}) async {
  final outcome = await showModalBottomSheet<_ConflictAction>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ConflictSheetBody(result: result),
  );

  if (!context.mounted || outcome == null || outcome == _ConflictAction.dismiss) {
    return false;
  }

  if (outcome == _ConflictAction.requestTransfer) {
    try {
      final repo = DeviceBindingRepository();
      final transfer = await repo.requestDeviceTransfer(
        phone: phone,
        snapshot: snapshot,
      );
      if (!context.mounted) return false;
      if (transfer.requestId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(transfer.message ?? 'So‘rov yaratilmadi'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return false;
      }
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DeviceTransferPendingScreen(
            phone: phone,
            name: name,
            snapshot: snapshot,
            requestId: transfer.requestId,
            oldDeviceLabel: transfer.oldDeviceLabel.isNotEmpty
                ? transfer.oldDeviceLabel
                : result.oldDeviceLabel,
            expiresAtMs: transfer.expiresAtMs,
            controller: controller,
          ),
        ),
      );
      return ok == true;
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(firebaseFunctionsUserMessage(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return false;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return false;
    }
  }

  return false;
}

enum _ConflictAction { requestTransfer, dismiss }

class _ConflictSheetBody extends StatelessWidget {
  const _ConflictSheetBody({required this.result});

  final DeviceBindingCheckResult result;

  @override
  Widget build(BuildContext context) {
    final isPhoneOther = result.status == DeviceBindingStatus.phoneBoundOtherDevice;
    final isDeviceOther = result.status == DeviceBindingStatus.deviceBoundOtherPhone;
    final isBlocked = result.status == DeviceBindingStatus.blocked;
    final label = result.oldDeviceLabel.trim();

    String title;
    String body;
    if (isPhoneOther) {
      title = 'Raqam boshqa qurilmada';
      body = label.isEmpty
          ? 'Bu raqam allaqachon boshqa telefonga bog‘langan. '
              'Eski qurilmangizdan «Ruxsat berish» orqali yangi telefonga ko‘chirishingiz mumkin.'
          : 'Bu raqam ($label) qurilmasiga bog‘langan. '
              'Eski qurilmadan tasdiqlasangiz, yangi telefonga o‘tadi.';
    } else if (isBlocked) {
      title = 'Vaqtincha cheklangan';
      body = result.message ??
          'Bir necha marta noto‘g‘ri urinish bo‘ldi. '
              'To‘g‘ri raqam bilan kiring yoki birozdan keyin qayta urinib ko‘ring.';
    } else if (isDeviceOther) {
      title = 'Qurilma boshqa raqamga bog‘liq';
      body = result.message ??
          'Bu telefonda boshqa raqam bilan kirilgan. '
              'Shu qurilmaga biriktirilgan raqamni kiriting.';
    } else {
      title = 'Kirish cheklangan';
      body = result.message ?? 'Qayta urinib ko‘ring.';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.4),
            ),
            const SizedBox(height: 20),
            if (isPhoneOther && result.selfServeAvailable) ...[
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _ConflictAction.requestTransfer),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.phonelink_setup),
                label: const Text('Eski qurilmadan tasdiqlash'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              onPressed: () => Navigator.pop(context, _ConflictAction.dismiss),
              child: Text(
                isDeviceOther || isBlocked
                    ? 'Tushundim'
                    : 'Bekor qilish',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agar eski telefon yo‘qolgan bo‘lsa — operatorga murojaat qiling.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
