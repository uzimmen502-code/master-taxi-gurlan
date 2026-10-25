import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';

/// Харидор шикояти (`reports`, `type: shop_content`) — маҳсулот ёки бутун дўкон (`submitShopComplaint`).
class ShopComplaint {
  const ShopComplaint({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.ownerPhone,
    required this.title,
    required this.reason,
    required this.reporterId,
    this.createdAt,
  });

  final String id;

  /// `shop_item` | `shop`
  final String targetType;
  final String targetId;
  final String ownerPhone;
  final String title;
  final String reason;
  final String reporterId;
  final DateTime? createdAt;

  static String _s(Object? v) => v is String ? v : '';

  factory ShopComplaint.fromMap(String id, Map<String, dynamic> d) => ShopComplaint(
        id: id,
        targetType: _s(d['targetType']),
        targetId: _s(d['targetId']),
        ownerPhone: _s(d['ownerPhone']),
        title: _s(d['title']),
        reason: _s(d['reason']),
        reporterId: _s(d['reporterId']),
        createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
      );
}

/// Шикоятлар манбаи: Firestore (админ ўқийди, rules: `reports` — фақат админ) ва ёпиш — мавжуд умумий
/// `adminResolveDatingReport` callable (ҳар қандай `reports` ҳужжатини `resolved` қилади).
abstract class ShopComplaintsSource {
  Stream<List<ShopComplaint>> watchOpen();
  Future<void> resolve(BuildContext context, String reportId);
}

class FirestoreShopComplaintsSource implements ShopComplaintsSource {
  const FirestoreShopComplaintsSource();

  @override
  Stream<List<ShopComplaint>> watchOpen() => FirebaseFirestore.instance
      .collection('reports')
      .where('type', isEqualTo: 'shop_content')
      .where('status', isEqualTo: 'open')
      .limit(200)
      .snapshots()
      .map((s) {
        final list = [for (final d in s.docs) ShopComplaint.fromMap(d.id, d.data())];
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
        return list;
      });

  @override
  Future<void> resolve(BuildContext context, String reportId) {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    return context.read<AdminMarketService>().resolveComplaint(adminPhone: adminPhone, reportId: reportId);
  }
}

/// Очиқ шикоятлар рўйхати: «Дўконни очиш» — шу сотувчи админ экранида очилади (блоклаш шу ерда),
/// «Ҳал қилинди» — шикоят ёпилади.
class ShopComplaintsPanel extends StatefulWidget {
  const ShopComplaintsPanel({super.key, required this.source, required this.onOpenOwner});

  final ShopComplaintsSource source;
  final ValueChanged<String> onOpenOwner;

  @override
  State<ShopComplaintsPanel> createState() => _ShopComplaintsPanelState();
}

class _ShopComplaintsPanelState extends State<ShopComplaintsPanel> {
  static final _date = DateFormat('dd.MM HH:mm');
  late final Stream<List<ShopComplaint>> _stream = widget.source.watchOpen();
  String? _busyId;

  Future<void> _resolve(ShopComplaint c) async {
    setState(() => _busyId = c.id);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.source.resolve(context, c.id);
    } catch (e) {
      debugPrint('[ShopComplaints] resolve: $e');
      messenger?.showSnackBar(const SnackBar(content: Text('Ёпиб бўлмади. Қайта уриниб кўринг.')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopComplaint>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <ShopComplaint>[];
        if (snap.hasError || list.isEmpty) return const SizedBox.shrink();
        return Card(
          key: const ValueKey('shop_complaints_panel'),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          color: Colors.red.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Очиқ шикоятлар: ${list.length}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade800)),
              ),
              for (final c in list)
                ListTile(
                  key: ValueKey('shop_complaint_${c.id}'),
                  dense: true,
                  leading: Icon(c.targetType == 'shop' ? Icons.storefront_rounded : Icons.inventory_2_outlined),
                  title: Text(c.reason),
                  subtitle: Text([
                    c.targetType == 'shop' ? 'Дўкон' : 'Маҳсулот: ${c.title.isEmpty ? c.targetId : c.title}',
                    'эга: ${c.ownerPhone}',
                    'шикоятчи: ${c.reporterId}',
                    if (c.createdAt != null) _date.format(c.createdAt!),
                  ].join(' · ')),
                  trailing: _busyId == c.id
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Wrap(spacing: 4, children: [
                          TextButton(
                            onPressed: c.ownerPhone.isEmpty ? null : () => widget.onOpenOwner(c.ownerPhone),
                            child: const Text('Дўконни очиш'),
                          ),
                          TextButton(
                            key: ValueKey('shop_complaint_resolve_${c.id}'),
                            onPressed: () => _resolve(c),
                            child: const Text('Ҳал қилинди'),
                          ),
                        ]),
                ),
            ],
          ),
        );
      },
    );
  }
}
