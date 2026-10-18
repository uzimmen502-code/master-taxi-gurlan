import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/wallet_topup_status.dart';

/// Тўлдиришнинг ҳолати: ишламаса — сабаби (ботга боришдан олдин), ишласа —
/// лимитлар. [status] `null` (юкланмоқда ёки номаълум) — ҳеч нарса.
class WalletTopUpNotice extends StatelessWidget {
  const WalletTopUpNotice({super.key, required this.status});

  final WalletTopUpStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();

    final blocked = s.blockedKey;
    if (blocked != null) {
      return Container(
        key: const ValueKey('wallet-topup-blocked'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.orange.shade900),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr(blocked),
                style: TextStyle(fontSize: 13, color: Colors.orange.shade900, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    if (s.maxTopUp > 0 && s.dailyTopUpLimit > 0) {
      return Padding(
        key: const ValueKey('wallet-topup-limits'),
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          context.trMsg('wlt_tu_limits', params: {
            'max': formatMoney(s.maxTopUp),
            'daily': formatMoney(s.dailyTopUpLimit),
          }),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
