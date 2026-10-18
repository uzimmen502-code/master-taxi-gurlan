import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/user_repository.dart';
import 'wallet_ledger_list.dart';

class WalletSection extends StatelessWidget {
  const WalletSection({
    super.key,
    required this.phone,
    this.showTitle = true,
  });

  final String phone;
  final bool showTitle;

  static const _green = AppColors.primaryText;
  static const _blue = AppColors.primaryText;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    final uid = phoneDigits(phone);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<int>(
        stream: repo.watchBonusBalance(uid),
        builder: (context, snap) {
          final bal = snap.data ?? 0;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _blue.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTitle)
                  Text(
                    '💳 ${context.tr('wlt_title')}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                if (showTitle) const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                    children: [
                      TextSpan(
                        text: formatPrice(bal),
                        style: const TextStyle(fontSize: 30.8), // 28 × 1.1
                      ),
                      TextSpan(text: ' ${context.tr('wlt_currency')}'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('wlt_intro'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                WalletLedgerList(
                  uid: uid,
                  since: DateTime.now().subtract(const Duration(days: 5)),
                  title: context.tr('wlt_hist5_title'),
                  emptyMessage: context.tr('wlt_hist5_empty'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
