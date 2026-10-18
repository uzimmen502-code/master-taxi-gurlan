import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/device_binding_repository.dart';

/// Фойдаланувчи ўз ҳамёнидан пул ечиш аризаси.
class WalletWithdrawPanel extends StatelessWidget {
  const WalletWithdrawPanel({super.key, required this.phone});

  final String phone;

  String get _uid => canonicalPhoneId(phone);

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid.length < 12) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        StreamBuilder<bool>(
          stream: DeviceBindingRepository().watchDeviceTrustLimited(phone),
          builder: (context, snap) {
            if (snap.data != true) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                context.tr('wlt_wd_new_device'),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange.shade900,
                  height: 1.35,
                ),
              ),
            );
          },
        ),
        OutlinedButton.icon(
          onPressed: () => _showWithdrawDialog(context),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(context.tr('wlt_wd_btn')),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('wlt_wd_requests'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('wallet_withdraw_requests')
              .where('uid', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              // Хато матни (`snap.error`) фойдаланувчига кўрсатилмайди.
              return Text(
                context.tr('wlt_hist_failed'),
                style: const TextStyle(color: Colors.red, fontSize: 12),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text(
                context.tr('wlt_wd_none'),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              );
            }
            return Column(
              children: docs.map((d) {
                final m = d.data();
                final amount = (m['amount'] as num?)?.toInt() ?? 0;
                final status = (m['status'] ?? '').toString();
                final card = (m['payoutCardNumber'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(formatMoney(amount)),
                    subtitle: Text(
                      [
                        _statusLabel(context, status),
                        if (card.length >= 4)
                          '****${card.substring(card.length - 4)}',
                      ].join(' · '),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  static String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'pending':
        return context.tr('wlt_st_pending');
      case 'approved':
        return context.tr('wlt_st_approved');
      case 'paid':
        return context.tr('wlt_st_paid');
      case 'rejected':
        return context.tr('wlt_st_rejected');
      default:
        return status.isEmpty ? '—' : status;
    }
  }

  Future<void> _showWithdrawDialog(BuildContext context) async {
    final amountCtrl = TextEditingController();
    final cardCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(ctx.tr('wlt_wd_btn')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ctx.tr('wlt_wd_intro'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: ctx.tr('wlt_wd_amount'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cardCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: ctx.tr('wlt_wd_card'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: ctx.tr('wlt_wd_holder'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(ctx.tr('cancel')),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final amount = int.tryParse(
                              amountCtrl.text.replaceAll(RegExp(r'\D'), ''),
                            ) ??
                            0;
                        final card = cardCtrl.text.replaceAll(RegExp(r'\D'), '');
                        final holder = nameCtrl.text.trim();
                        if (amount <= 0 || card.length < 16 || holder.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(ctx.tr('wlt_wd_fill_all')),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setLocal(() => busy = true);
                        try {
                          await FirebaseFunctions.instance
                              .httpsCallable('requestWalletWithdraw')
                              .call({
                            'phone': phone,
                            'amount': amount,
                            'payoutCardNumber': card,
                            'payoutCardHolder': holder,
                          });
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.tr('wlt_wd_sent'),
                                style: const TextStyle(color: AppColors.onPrimary),
                              ),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        } on FirebaseFunctionsException catch (e) {
                          setLocal(() => busy = false);
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(e.message ?? e.code),
                            backgroundColor: Colors.red,
                          ));
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(ctx.tr('wlt_wd_send')),
              ),
            ],
          ),
        );
      },
    );
  }
}
