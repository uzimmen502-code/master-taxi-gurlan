import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Finance Center — Settlement Ledger boshqaruvi (admin/finance).
///   • Driver Float — top-up / return + zona
///   • Settlements — trip settlement holatlari
///   • Журнал — journal_entries (o'zgarmas)
///   • Sverka (reconcile) — invariant tekshiruvi
/// To'liq dizayn: docs/settlement_ledger_v1_uz.md
class FinanceCenterScreen extends StatefulWidget {
  const FinanceCenterScreen({super.key});

  @override
  State<FinanceCenterScreen> createState() => _FinanceCenterScreenState();
}

// settings/settlement default'lari bilan sinxron (faqat ko'rsatish uchun).
const int _floatMin = 100000;
const int _floatCritical = 20000;

class _FinanceCenterScreenState extends State<FinanceCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _reconciling = false;

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
    return Column(
      children: [
        _header(),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: AppColors.primaryDark,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Driver Float'),
              Tab(text: 'Settlements'),
              Tab(text: 'Журнал'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              _FloatTab(),
              _SettlementsTab(),
              _JournalTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          const Icon(Icons.account_balance, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finance Center',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Settlement Ledger — float, settlement, журнал',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _reconciling ? null : _runReconcile,
            icon: _reconciling
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fact_check, size: 18),
            label: const Text('Sverka'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _runReconcile() async {
    setState(() => _reconciling = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('reconcileLedger')
          .call();
      final m = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      final ok = m['balanced'] == true &&
          m['identityOk'] == true &&
          m['projectionOk'] == true;
      final mism = (m['mismatches'] as List?)?.length ?? 0;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(ok ? Icons.check_circle : Icons.warning,
                color: ok ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(ok ? 'Sverka: muvozanat ✓' : 'Sverka: muammo!'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Σ debit', formatPrice((m['totalDr'] as num?) ?? 0)),
              _kv('Σ credit', formatPrice((m['totalCr'] as num?) ?? 0)),
              _kv('Aktivlar', formatPrice((m['assets'] as num?) ?? 0)),
              _kv('Majburiyatlar', formatPrice((m['liabilities'] as num?) ?? 0)),
              _kv('balanced', '${m['balanced']}'),
              _kv('identityOk', '${m['identityOk']}'),
              _kv('projectionOk', '${m['projectionOk']}'),
              _kv('Hisoblar', '${m['accountCount']}'),
              _kv('Yozuvlar', '${m['entryCount']}'),
              if (mism > 0) _kv('Mismatch', '$mism', color: Colors.red),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Yopish')),
          ],
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      _snack('Sverka xatosi: ${e.message ?? e.code}', isError: true);
    } catch (e) {
      _snack('Sverka xatosi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Text(v,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }
}

// ════════════════════════════════════════════════════════════
// DRIVER FLOAT
// ════════════════════════════════════════════════════════════
class _FloatTab extends StatelessWidget {
  const _FloatTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _floatDialog(context, isTopUp: true),
                  icon: const Icon(Icons.add),
                  label: const Text('Float тўлдириш'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _floatDialog(context, isTopUp: false),
                  icon: const Icon(Icons.remove),
                  label: const Text('Float қайтариш'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('ledger_accounts')
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _err('${snap.error}');
              }
              final docs = (snap.data?.docs ?? [])
                  .where((d) => d.id.startsWith('driver_float:'))
                  .toList()
                ..sort((a, b) => ((b.data()['balance'] as num?) ?? 0)
                    .compareTo((a.data()['balance'] as num?) ?? 0));
              if (docs.isEmpty) {
                return _empty('Hali float yo\'q',
                    'Haydovchi depozit topshirgach paydo bo\'ladi');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final uid = docs[i].id.split(':').last;
                  final bal = ((d['balance'] as num?) ?? 0).toInt();
                  return _floatRow(context, uid, bal);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _floatRow(BuildContext context, String uid, int bal) {
    final (zoneLabel, zoneColor) = _zoneOf(bal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: zoneColor.withValues(alpha: 0.15),
            child: Icon(Icons.local_taxi, color: zoneColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('+$uid',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${formatPrice(bal)} сўм',
                    style: TextStyle(color: zoneColor, fontSize: 13)),
              ],
            ),
          ),
          if (bal < 0)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Блок (қарз)',
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: zoneColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(zoneLabel,
                style: TextStyle(
                    color: zoneColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _floatDialog(context,
                isTopUp: v == 'topup', presetPhone: uid),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'topup', child: Text('Тўлдириш')),
              PopupMenuItem(value: 'return', child: Text('Қайтариш')),
            ],
          ),
        ],
      ),
    );
  }
}

(String, Color) _zoneOf(int bal) {
  if (bal < _floatCritical) return ('Критик', Colors.red);
  if (bal < _floatMin) return ('Паст', Colors.orange);
  return ('Соғлом', Colors.green);
}

Future<void> _floatDialog(BuildContext context,
    {required bool isTopUp, String? presetPhone}) async {
  final phoneCtrl = TextEditingController(text: presetPhone ?? '');
  final amountCtrl = TextEditingController();
  final opId = '${isTopUp ? 'topup' : 'return'}_'
      '${DateTime.now().microsecondsSinceEpoch}';
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isTopUp ? 'Float тўлдириш' : 'Float қайтариш'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Ҳайдовчи телефони (998…)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Сумма (сўм)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Бекор')),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                      final amount = int.tryParse(
                              amountCtrl.text.replaceAll(RegExp(r'\D'), '')) ??
                          0;
                      if (phone.length < 9 || amount <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Телефон ва сумма тўғри киритилсин'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      setLocal(() => busy = true);
                      try {
                        final res = await FirebaseFunctions.instance
                            .httpsCallable(
                                isTopUp ? 'floatTopUp' : 'floatReturn')
                            .call({
                          'driverPhone': phone,
                          'amount': amount,
                          'opId': opId,
                        });
                        final m = Map<String, dynamic>.from(res.data as Map);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(
                              'Float: ${formatPrice((m['balance'] as num?) ?? 0)}'
                              ' сўм (${m['zone']})'),
                          backgroundColor: Colors.green,
                        ));
                      } on FirebaseFunctionsException catch (e) {
                        setLocal(() => busy = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('Хатoлик: ${e.message ?? e.code}'),
                          backgroundColor: Colors.red,
                        ));
                      } catch (e) {
                        setLocal(() => busy = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('Хатoлик: $e'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isTopUp ? 'Тўлдириш' : 'Қайтариш'),
            ),
          ],
        ),
      );
    },
  );
}

// ════════════════════════════════════════════════════════════
// SETTLEMENTS
// ════════════════════════════════════════════════════════════
class _SettlementsTab extends StatelessWidget {
  const _SettlementsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settlements')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _err('${snap.error}');
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _empty('Settlement yo\'q', 'Trip settlement\'lar shu yerda');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final state = (d['state'] ?? '').toString();
            final amount = ((d['settlementAmount'] as num?) ?? 0).toInt();
            final (label, color) = _stateOf(state);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${formatPrice(amount)} сўм',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                            '+${d['driverUid']} → +${d['passengerUid']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

(String, Color) _stateOf(String s) {
  switch (s) {
    case 'completed':
      return ('Якунланди', Colors.green);
    case 'pending':
      return ('Кутилмоқда', Colors.orange);
    case 'cancelled':
      return ('Бекор', Colors.red);
    case 'deferred':
      return ('Кечиктирилди', Colors.blue);
    default:
      return (s.isEmpty ? '—' : s, Colors.grey);
  }
}

// ════════════════════════════════════════════════════════════
// ЖУРНАЛ (journal_entries)
// ════════════════════════════════════════════════════════════
class _JournalTab extends StatelessWidget {
  const _JournalTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('journal_entries')
          .orderBy('ts', descending: true)
          .limit(200)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _err('${snap.error}');
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _empty('Журнал бўш', 'Ledger yozuvlari shu yerda');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final kind = (d['kind'] ?? '').toString();
            final amount = ((d['amount'] as num?) ?? 0).toInt();
            final legs = (d['legs'] as List?) ?? [];
            final legStr = legs.map((l) {
              final m = Map<String, dynamic>.from(l as Map);
              final acc = (m['account'] ?? '').toString();
              final dr = ((m['dr'] as num?) ?? 0).toInt();
              final cr = ((m['cr'] as num?) ?? 0).toInt();
              return dr > 0 ? 'Dr $acc ${formatPrice(dr)}'
                  : 'Cr $acc ${formatPrice(cr)}';
            }).join('  ·  ');
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(kind,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${formatPrice(amount)} сўм',
                          style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(legStr,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Umumiy yordamchilar ──
Widget _err(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text('Хатoлик: $msg', textAlign: TextAlign.center),
          ],
        ),
      ),
    );

Widget _empty(String title, String msg) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox, color: Colors.grey, size: 48),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(msg, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
