import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Тўлдириш ишлайдими — ботга боришдан ОЛДИН (`getWalletTopUpStatus`).
///
/// Аввал фойдаланувчи ботга бориб «Карта ҳали созланмаган» деган жавобни
/// олар эди. Карта рақами жавобда ЙЎҚ: фақат ҳолат ва лимитлар.
class WalletTopUpStatus {
  const WalletTopUpStatus({
    required this.ready,
    required this.reason,
    this.maxTopUp = 0,
    this.dailyTopUpLimit = 0,
  });

  final bool ready;

  /// `ok` | `bot_disabled` | `card_missing` | `card_invalid` (охиргиси
  /// тўлдиришни блокламайди — админга огоҳлантириш).
  final String reason;
  final int maxTopUp;
  final int dailyTopUpLimit;

  factory WalletTopUpStatus.fromMap(Map<String, dynamic> d) => WalletTopUpStatus(
        ready: d['ready'] == true,
        reason: (d['reason'] ?? '').toString(),
        maxTopUp: (d['maxTopUp'] as num?)?.toInt() ?? 0,
        dailyTopUpLimit: (d['dailyTopUpLimit'] as num?)?.toInt() ?? 0,
      );

  /// Фойдаланувчига кўрсатиладиган тушунтириш матни калити (`null` — ҳаммаси жойида).
  String? get blockedKey {
    if (ready) return null;
    return reason == 'bot_disabled' ? 'wlt_tu_bot_off' : 'wlt_tu_unavailable';
  }
}

/// Тармоқ/сервер хатосида `null` — ҳолат НОМАЪЛУМ: фойдаланувчи блокланмайди
/// (хато «тўлдириш йўқ» деб ёлғон айтмасин; ботнинг ўзи барибир текширади).
Future<WalletTopUpStatus?> loadWalletTopUpStatus() async {
  try {
    final res = await FirebaseFunctions.instance.httpsCallable('getWalletTopUpStatus').call();
    return WalletTopUpStatus.fromMap(Map<String, dynamic>.from(res.data as Map? ?? const {}));
  } catch (e) {
    debugPrint('[WalletTopUpStatus] $e');
    return null;
  }
}
