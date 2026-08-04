import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase_functions_client.dart';
import '../core/utils/formatters.dart';
import '../services/device_fingerprint_service.dart';

/// Admin kod so'rovi holati (`getPendingCodeStatus` / polling).
class PendingCodeStatusUpdate {
  const PendingCodeStatusUpdate({
    required this.status,
    this.code,
  });

  /// `none` | `pending` | `approved` | `expired`
  final String status;
  final String? code;

  bool get isApproved =>
      status == 'approved' && code != null && code!.length == 6;

  bool get isTerminal =>
      status == 'expired' || status == 'none' || isApproved;
}

/// `pending_codes` — yozuv faqat Cloud Functions orqali.
class PendingCodeRepository {
  PendingCodeRepository({FirebaseFunctions? functions})
      : _functions = functions ?? AvaFunctions.auth;

  final FirebaseFunctions _functions;

  Future<void> requestPendingCode({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final digits = phoneDigits(phone);
    final hash = snapshot.hash.trim().toLowerCase();
    final callable = _functions.httpsCallable('requestPendingCode');
    await callable.call<Map<String, dynamic>>({
      'phone': digits,
      'deviceFingerprintHash': hash,
      'fingerprint': Map<String, String>.from(snapshot.components),
    });
  }

  Future<PendingCodeStatusUpdate> fetchStatus({
    required String phone,
    required String deviceFingerprintHash,
  }) async {
    final digits = phoneDigits(phone);
    final hash = deviceFingerprintHash.trim().toLowerCase();
    final callable = _functions.httpsCallable('getPendingCodeStatus');
    final result = await callable.call<Map<String, dynamic>>({
      'phone': digits,
      'deviceFingerprintHash': hash,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return PendingCodeStatusUpdate(
      status: (data['status'] ?? 'none').toString(),
      code: (data['code'] as String?)?.trim(),
    );
  }

  /// Firestore o'rniga CF polling — auth talab qilinmaydi.
  Stream<PendingCodeStatusUpdate> watchStatus({
    required String phone,
    required String deviceFingerprintHash,
    Duration interval = const Duration(milliseconds: 1500),
  }) {
    final controller = StreamController<PendingCodeStatusUpdate>();
    Timer? timer;
    var closed = false;

    Future<void> poll() async {
      if (closed) return;
      try {
        final update = await fetchStatus(
          phone: phone,
          deviceFingerprintHash: deviceFingerprintHash,
        );
        if (closed || controller.isClosed) return;
        controller.add(update);
        if (update.isTerminal) {
          closed = true;
          timer?.cancel();
          await controller.close();
        }
      } catch (e, st) {
        if (!closed && !controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    timer = Timer.periodic(interval, (_) => unawaited(poll()));
    unawaited(poll());

    controller.onCancel = () {
      closed = true;
      timer?.cancel();
    };
    return controller.stream;
  }
}
