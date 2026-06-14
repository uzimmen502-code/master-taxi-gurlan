import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_ledger_labels.dart';
import '../../../models/wallet_ledger_entry.dart';
import '../../../repositories/user_repository.dart';

/// Koshelёk operatsiyalari ro‘yxati (real-time).
class WalletLedgerList extends StatelessWidget {
  const WalletLedgerList({
    super.key,
    required this.uid,
    required this.since,
    this.title,
    this.emptyMessage = 'Operatsiyalar yo‘q',
    this.maxHeight,
  });

  final String uid;
  final DateTime since;
  final String? title;
  final String emptyMessage;
  final double? maxHeight;

  static const _green = AppColors.primaryDark;
  static const _red = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    if (uid.length < 9) {
      return Text(
        'Telefon raqamini profilda kiriting',
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      );
    }

    final repo = context.read<UserRepository>();
    return StreamBuilder<List<WalletLedgerEntry>>(
      stream: repo.watchWalletLedgerSince(uid, since: since),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Text(
            'Tarix yuklanmadi',
            style: TextStyle(fontSize: 13, color: Colors.red.shade700),
          );
        }

        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              emptyMessage,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          );
        }

        final list = ListView.separated(
          shrinkWrap: true,
          physics: maxHeight == null
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (_, i) => _entryTile(items[i]),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (maxHeight != null)
              SizedBox(height: maxHeight, child: list)
            else
              list,
          ],
        );
      },
    );
  }

  Widget _entryTile(WalletLedgerEntry e) {
    final positive = e.isPositive;
    final amountColor = positive ? _green : _red;
    final sign = positive ? '+' : '−';
    final subtitle = walletLedgerSubtitle(e);
    final when = e.createdAt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              positive ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: amountColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  walletLedgerTitle(e),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.25,
                    ),
                  ),
                ],
                if (when != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd.MM.yyyy HH:mm').format(when),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$sign${formatPrice(e.amount.abs())}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
