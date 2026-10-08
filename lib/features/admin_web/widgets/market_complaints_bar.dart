import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';

/// Онлайн бозор шикоятлари (`reports`, `type: market_ad`, `status: open`).
///
/// Фойдаланувчи эълон тафсилотидан шикоят юборади (`submitMarketComplaint`),
/// лекин аввал ҳеч қайси админ экрани уларни кўрсатмасди — шикоятлар ҳеч
/// кимга етмасди (админ аудити O-6, 2026-10-08).
class MarketComplaintsBar extends StatelessWidget {
  const MarketComplaintsBar({super.key});

  static Query<Map<String, dynamic>> openQuery() => FirebaseFirestore.instance
      .collection('reports')
      .where('type', isEqualTo: 'market_ad')
      .where('status', isEqualTo: 'open')
      .limit(200);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: openQuery().snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        if (snap.hasError || n == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(children: [
            Icon(Icons.report_outlined, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Очиқ шикоятлар: $n',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _MarketComplaintsDialog(),
              ),
              child: const Text('Кўриш'),
            ),
          ]),
        );
      },
    );
  }
}

class _MarketComplaintsDialog extends StatefulWidget {
  const _MarketComplaintsDialog();

  @override
  State<_MarketComplaintsDialog> createState() => _MarketComplaintsDialogState();
}

class _MarketComplaintsDialogState extends State<_MarketComplaintsDialog> {
  static final _date = DateFormat('dd.MM HH:mm');
  String? _busyId;

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('Хатолик: $e'),
      ));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    final svc = context.read<AdminMarketService>();
    return AlertDialog(
      title: const Text('Бозор шикоятлари'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: MarketComplaintsBar.openQuery().snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Text('Хатолик: ${snap.error}');
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('Очиқ шикоят йўқ.'));
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = docs[i].data();
                final id = docs[i].id;
                final adId = (d['targetId'] ?? '') as String;
                final created = d['createdAt'] is Timestamp
                    ? _date.format((d['createdAt'] as Timestamp).toDate())
                    : '';
                final busy = _busyId == id;
                return ListTile(
                  title: Text((d['reason'] ?? '') as String),
                  subtitle: Text(
                    'Эълон: $adId · шикоятчи: ${d['reporterId'] ?? ''}'
                    '${created.isNotEmpty ? ' · $created' : ''}',
                  ),
                  trailing: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Wrap(spacing: 4, children: [
                          // Эълонни яшириш (админ рад этиши — эга қайта
                          // жойлай олмайди) ва шикоятни ёпиш.
                          TextButton(
                            onPressed: adId.isEmpty
                                ? null
                                : () => _run(id, () async {
                                      await svc.updateAdStatus(
                                        adminPhone: adminPhone,
                                        adId: adId,
                                        status: 'inactive',
                                      );
                                      await svc.resolveComplaint(
                                        adminPhone: adminPhone,
                                        reportId: id,
                                      );
                                    }),
                            child: const Text('Яшириш'),
                          ),
                          TextButton(
                            onPressed: () => _run(
                              id,
                              () => svc.resolveComplaint(
                                adminPhone: adminPhone,
                                reportId: id,
                              ),
                            ),
                            child: const Text('Ҳал қилинди'),
                          ),
                        ]),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Ёпиш'),
        ),
      ],
    );
  }
}
