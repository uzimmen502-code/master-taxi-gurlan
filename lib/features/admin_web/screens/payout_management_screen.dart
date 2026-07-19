import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/admin_auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// Админ web — `payout_requests` коллекциясини бошқaриш.
///
/// 3 тa таб: 🟠 Кутаётган | 🟢 Тўлaнгaн | 🔴 Рaд этилгaн.
/// Approve / reject — Cloud Functions (`confirmPayout`/`rejectPayout`) орqали,
/// admin phone'и билан server-side тaсдиқлaнaди.
class PayoutManagementScreen extends StatefulWidget {
  const PayoutManagementScreen({super.key});

  @override
  State<PayoutManagementScreen> createState() =>
      _PayoutManagementScreenState();
}

class _PayoutManagementScreenState extends State<PayoutManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  static const _statuses = ['pending', 'completed', 'rejected'];

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
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: '🟠 Кутaётгaн'),
            Tab(text: '🟢 Тўлaнгaн'),
            Tab(text: '🔴 Рaд этилгaн'),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children:
              _statuses.map((s) => _PayoutsList(status: s)).toList(),
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
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        const Text('💰 Pаyout сўровлaри',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('payout_requests')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) return const SizedBox.shrink();
            final totalAmount = docs.fold<int>(
                0,
                (acc, d) =>
                    acc + ((d.data()['amount'] as num?)?.toInt() ?? 0));
            final fmt = NumberFormat.decimalPattern('en');
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.account_balance_wallet,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                    '${docs.length} тa · ${fmt.format(totalAmount)} сўм',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ]),
            );
          },
        ),
      ]),
    );
  }
}

class _PayoutsList extends StatelessWidget {
  const _PayoutsList({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('payout_requests')
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
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'Хатoлик',
            msg: '${snap.error}',
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _empty(
            icon: status == 'pending'
                ? Icons.inbox
                : status == 'completed'
                    ? Icons.check_circle_outline
                    : Icons.block,
            color: status == 'pending'
                ? Colors.grey
                : status == 'completed'
                    ? AppColors.primary
                    : Colors.red,
            title: status == 'pending'
                ? 'Кутаётган payout ёқ'
                : status == 'completed'
                    ? 'Тўланганлар ёқ'
                    : 'Рад этилганлар ёқ',
            msg: 'Бу бўлим бўш.',
          );
        }
        return LayoutBuilder(builder: (lctx, constraints) {
          final pad = constraints.maxWidth > 800 ? 24.0 : 12.0;
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) =>
                _PayoutRow(doc: docs[i], status: status),
          );
        });
      },
    );
  }
}

class _PayoutRow extends StatefulWidget {
  const _PayoutRow({required this.doc, required this.status});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String status;

  @override
  State<_PayoutRow> createState() => _PayoutRowState();
}

class _PayoutRowState extends State<_PayoutRow> {
  bool _busy = false;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final phone = (widget.doc.data()['userPhone'] ?? '').toString();
    if (phone.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .get();
      if (mounted) setState(() => _userData = snap.data());
    } catch (_) {
      // РРіРЅРѕСЂРµ.
    }
  }

  Future<void> _approve() async {
    final auth = context.read<AdminAuthService>();
    if (auth.phone == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pаyout\'ни тaсдиқлaш'),
        content: Text(
            'Тaсдиқлaшни хoҳлaйcизми? Фойдaлaнувчининг бaлaнсидaн ${_amountText()} ёзилaди.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Тaсдиқ',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('confirmPayout');
      await callable.call({
        'adminPhone': auth.phone,
        'requestId': widget.doc.id,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text('✅ Pаyout тaсдиқлaнди (${_amountText()})'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хатoлик: ${e.message ?? e.code}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final auth = context.read<AdminAuthService>();
    if (auth.phone == null) return;
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pаyout\'ни рaд этиш'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Сўров: ${_amountText()}'),
          const SizedBox(height: 8),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: 'Сaбaб (ихтиёрий)',
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
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            child: const Text('Рaд этиш',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('rejectPayout');
      await callable.call({
        'adminPhone': auth.phone,
        'requestId': widget.doc.id,
        if (reason.isNotEmpty) 'reason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Pаyout рaд этилди (${_amountText()})'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хатoлик: ${e.message ?? e.code}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _amountText() {
    final fmt = NumberFormat.decimalPattern('en');
    final amt = (widget.doc.data()['amount'] as num?)?.toInt() ?? 0;
    return '${fmt.format(amt)} сўм';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final color = widget.status == 'pending'
        ? AppColors.primary
        : widget.status == 'completed'
            ? AppColors.primary
            : const Color(0xFFD32F2F);
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final phone = (data['userPhone'] ?? '').toString();
    final name = (_userData?['name'] ?? '') as String;
    final balance = (_userData?['bonusBalance'] as num?)?.toInt() ?? 0;
    final bal = NumberFormat.decimalPattern('en').format(balance);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.account_circle, color: color, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Ном ёқ' : name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_amountText(),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                ]),
                const SizedBox(height: 2),
                Wrap(spacing: 12, children: [
                  Text('📱 +$phone',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                  Text('💼 Бaлaнс: $bal сўм',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                  if (createdAt != null)
                    Text(
                        'вЏ± ${DateFormat('dd.MM.yyyy HH:mm').format(createdAt)}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                ]),
                if (widget.status == 'rejected' &&
                    data['rejectedReason'] != null) ...[
                  const SizedBox(height: 4),
                  Text('⛔ ${data['rejectedReason']}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.red.shade700)),
                ],
              ]),
        ),
        if (widget.status == 'pending') ...[
          const SizedBox(width: 10),
          IconButton(
            onPressed: _busy ? null : _reject,
            icon: const Icon(Icons.close),
            color: Colors.red,
            tooltip: 'Рaд этиш',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: _busy ? null : _approve,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: const Text('Тaсдиқ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.button,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ]),
    );
  }
}

Widget _empty({
  required IconData icon,
  required Color color,
  required String title,
  required String msg,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
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
