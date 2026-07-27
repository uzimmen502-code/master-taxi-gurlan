import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

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
        OutlinedButton.icon(
          onPressed: () => _showWithdrawDialog(context),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Ҳамёндан пул ечиш'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Ечиш аризалари',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
              return Text(
                '${snap.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text(
                'Ариза йўқ',
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
                    title: Text('${formatMoney(amount)}'),
                    subtitle: Text(
                      [
                        _statusLabel(status),
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

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Кутилмоқда';
      case 'approved':
        return 'Тасдиқланди';
      case 'paid':
        return 'Тўланди';
      case 'rejected':
        return 'Рад этилди';
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
            title: const Text('Ҳамёндан пул ечиш'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ўз ҳамёнингиздан пул ечиш аризаси. '
                    'Админ тасдиқлагач картангизга ўтказилади '
                    'ва баланс камаяди.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Сумма (сўм)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cardCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Карта рақами',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Карта эгаси (ФИО)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Бекор'),
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
                            const SnackBar(
                              content: Text(
                                'Сумма, карта (16 рақам) ва ФИОни киритинг',
                              ),
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
                            const SnackBar(
                              content: Text('Ечиш аризаси юборилди'),
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
                    : const Text('Юбориш'),
              ),
            ],
          ),
        );
      },
    );
  }
}
