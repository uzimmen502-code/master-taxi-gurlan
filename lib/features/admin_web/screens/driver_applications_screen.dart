import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../repositories/driver_repository.dart';
import '../services/admin_auth_service.dart';

/// Адмиn web — `driver_requests` коллeкцияси экрани.
///
/// 3 та таб: 🟠 Кутаётган | 🟢 Тaсдиқлaнгaн | 🔴 Рaд этилгaн.
/// Approve амали: `driver_requests/{id}.status = 'approved'`, `users/{uid}.role = 'driver'`.
/// Reject амали: `driver_requests/{id}.status = 'rejected'` + sabab.
class DriverApplicationsScreen extends StatefulWidget {
  const DriverApplicationsScreen({super.key});

  @override
  State<DriverApplicationsScreen> createState() =>
      _DriverApplicationsScreenState();
}

class _DriverApplicationsScreenState extends State<DriverApplicationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  static const _statuses = ['pending', 'approved', 'rejected'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF0D47A1),
          indicatorWeight: 3,
          labelColor: const Color(0xFF0D47A1),
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: '🟠 Кутаётган'),
            Tab(text: '🟢 Тaсдиқлaнгaн'),
            Tab(text: '🔴 Рaд этилгaн'),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: _statuses
              .map((status) => _ApplicationsList(status: status))
              .toList(),
        ),
      ),
    ]);
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🚗 Ҳaйдовчи aризaлaри',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          // Pending count badge — Real-time.
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('driver_requests')
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (ctx, snap) {
              final n = snap.data?.docs.length ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.pending_actions,
                      size: 16, color: Color(0xFFE65100)),
                  const SizedBox(width: 6),
                  Text('$n та кутaяпти',
                      style: const TextStyle(
                          color: Color(0xFFE65100),
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
              );
            },
          ),
        ]),
        const SizedBox(height: 10),
        const _DriverApprovalModeTile(),
      ]),
    );
  }
}

class _DriverApprovalModeTile extends StatelessWidget {
  const _DriverApprovalModeTile();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DriverRepository>();
    return StreamBuilder<String>(
      stream: repo.watchDriverApprovalMode(),
      builder: (context, snap) {
        final mode = snap.data ?? 'auto';
        final manual = mode == 'manual';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: manual ? Colors.orange.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: manual ? Colors.orange.shade200 : Colors.green.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              manual ? Icons.admin_panel_settings : Icons.flash_on,
              color: manual ? Colors.orange.shade800 : Colors.green.shade700,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                manual
                    ? 'Driver approval: MANUAL — янги ҳайдовчилар админ тасдиғини кутади'
                    : 'Driver approval: AUTO — янги ҳайдовчилар автомат фаоллашади',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: manual ? Colors.orange.shade900 : Colors.green.shade800,
                ),
              ),
            ),
            Switch(
              value: manual,
              activeThumbColor: Colors.orange.shade700,
              onChanged: (v) async {
                await repo.setDriverApprovalMode(v ? 'manual' : 'auto');
              },
            ),
          ]),
        );
      },
    );
  }
}

class _ApplicationsList extends StatelessWidget {
  const _ApplicationsList({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('driver_requests')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _empty(
            ctx,
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'Хатoлик',
            msg:
                'Аризaлaрни юклaб бўлмaди: ${snap.error}\n\nЭҳтимол `createdAt` index етишмaяпти.',
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _empty(
            ctx,
            icon: status == 'pending'
                ? Icons.inbox
                : status == 'approved'
                    ? Icons.check_circle_outline
                    : Icons.block,
            color: status == 'pending'
                ? Colors.grey
                : status == 'approved'
                    ? Colors.green
                    : Colors.red,
            title: status == 'pending'
                ? 'Кутaётгaн aризa йоq'
                : status == 'approved'
                    ? 'Тaсдиқлaнгaн aризa йоq'
                    : 'Рaд этилгaн aризa йоq',
            msg: 'Бу бўлим бўш.',
          );
        }
        return LayoutBuilder(builder: (lctx, constraints) {
          final pad = constraints.maxWidth > 800 ? 24.0 : 12.0;
          final cols = (constraints.maxWidth / 380).floor().clamp(1, 3);
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 280,
            ),
            itemCount: docs.length,
            itemBuilder: (_, i) => _ApplicationCard(
                doc: docs[i], status: status),
          );
        });
      },
    );
  }

  Widget _empty(BuildContext ctx,
      {required IconData icon,
      required Color color,
      required String title,
      required String msg}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: color),
          ),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

class _ApplicationCard extends StatefulWidget {
  const _ApplicationCard({required this.doc, required this.status});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String status;

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  bool _busy = false;

  String _f(String key, [String fallback = '']) {
    final v = widget.doc.data()[key];
    return v?.toString() ?? fallback;
  }

  DateTime? _ts(String key) {
    final v = widget.doc.data()[key];
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    final auth = context.read<AdminAuthService>();
    try {
      final db = FirebaseFirestore.instance;
      final docRef =
          db.collection('driver_requests').doc(widget.doc.id);
      final batch = db.batch();
      batch.update(docRef, {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': auth.phone ?? '',
      });

      // Агар фойдалaнувчи телефон рaқaми бoр бўлсa — рoлини янгилaймиз.
      final userPhone =
          _f('phone').replaceAll(RegExp(r'[^\d]'), '');
      if (userPhone.length >= 9) {
        final userRef = db.collection('users').doc(userPhone);
        batch.set(
            userRef,
            {
              'role': 'driver',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('✅ Aризa тaсдиқлaнди: ${_f('name', 'Aризa')}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хатoлик: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aризaни рaд этиш'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Рaд этиш сaбaбини киритинг:'),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: 'Мaсaлaн: Aвтомобил тaлaбгa жaвoб бермaйди',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, reasonCtrl.text.trim());
            },
            child: const Text('Рaд этиш',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final auth = context.read<AdminAuthService>();
    try {
      await FirebaseFirestore.instance
          .collection('driver_requests')
          .doc(widget.doc.id)
          .update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': auth.phone ?? '',
        'rejectedReason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Aризa рaд этилди: ${_f('name', 'Aризa')}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хатoлик: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.status == 'pending'
        ? const Color(0xFFE65100)
        : widget.status == 'approved'
            ? const Color(0xFF2E7D32)
            : const Color(0xFFD32F2F);
    final createdAt = _ts('createdAt');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withOpacity(0.2),
              child: Text(
                  (_f('name').isEmpty
                          ? '?'
                          : _f('name').substring(0, 1))
                      .toUpperCase(),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_f('name', 'Ҳaйдовчи нoми йоq'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(_f('phone', 'Тел йoq'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ]),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('🚗 Aвтo', _f('car', '—')),
                  _row('🔢 Plate', _f('plate', _f('carNumber', '—'))),
                  if (_f('passport').isNotEmpty)
                    _row('📃 Pasport', _f('passport')),
                  if (_f('birthYear').isNotEmpty)
                    _row('🎂 Туғилгaн йил', _f('birthYear')),
                  if (_f('experience').isNotEmpty)
                    _row('📅 Тaжрибa', _f('experience')),
                  if (widget.status == 'rejected' &&
                      _f('rejectedReason').isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '⛔ ${_f('rejectedReason')}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.red.shade700),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (createdAt != null)
                    Text(
                        '⏱ ${DateFormat('dd.MM.yyyy HH:mm').format(createdAt)}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                ]),
          ),
        ),
        if (widget.status == 'pending')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _reject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Рaд этиш'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Тaсдиқ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 95,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
