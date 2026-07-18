import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// P2P: бошқа ҳамёндан пул сўраш + келган сўровларга жавоб.
class WalletP2pPanel extends StatelessWidget {
  const WalletP2pPanel({super.key, required this.phone});

  final String phone;

  String get _uid {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 9) return '998$d';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid.length < 12) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _showRequestDialog(context),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Ҳамёндан пул сўраш'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Келган сўровлар',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('wallet_transfer_requests')
              .where('fromUid', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .limit(20)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text('${snap.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12));
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text(
                'Кутилаётган сўров йўқ',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              );
            }
            return Column(
              children: docs.map((d) {
                final m = d.data();
                final amount = (m['amount'] as num?)?.toInt() ?? 0;
                final to = (m['toUid'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${formatPrice(amount)} сўм'),
                    subtitle: Text('+$to сўрамоқда'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Тасдиқ',
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          onPressed: () => _respond(context, d.id, true),
                        ),
                        IconButton(
                          tooltip: 'Рад',
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => _respond(context, d.id, false),
                        ),
                      ],
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

  Future<void> _showRequestDialog(BuildContext context) async {
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Пул сўраш'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Бошқа фойдаланувчидан пул сўрайсиз. У тасдиқлагач '
                  'унинг ҳамёнидан сизникига ўтади. Кунлик лимит: 100 000 сўм.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Кимдан (телефон)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Сумма (макс 100 000)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
                        final from = phoneCtrl.text
                            .replaceAll(RegExp(r'\D'), '');
                        final amount = int.tryParse(amountCtrl.text
                                .replaceAll(RegExp(r'\D'), '')) ??
                            0;
                        if (from.length < 9 || amount <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Телефон ва суммани текширинг'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setLocal(() => busy = true);
                        try {
                          await FirebaseFunctions.instance
                              .httpsCallable('requestWalletTransfer')
                              .call({
                            'fromPhone': from,
                            'amount': amount,
                          });
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Сўров юборилди'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        } on FirebaseFunctionsException catch (e) {
                          setLocal(() => busy = false);
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

  Future<void> _respond(
      BuildContext context, String requestId, bool accept) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('respondWalletTransfer')
          .call({
        'requestId': requestId,
        'accept': accept,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Ўтказма тасдиқланди' : 'Сўров рад этилди'),
        backgroundColor: accept ? Colors.green : Colors.orange,
      ));
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message ?? e.code),
        backgroundColor: Colors.red,
      ));
    }
  }
}
