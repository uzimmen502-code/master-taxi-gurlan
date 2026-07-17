// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'money_control_tab.dart';

/// Finance Center — Settlement Ledger (finance/auditor/superadmin, SoD).
///   • Назорат — пул оқими KPI + навбат + инкасса / payout
///   • Driver Float — top-up / return + zona
///   • Settlements — holatlar + CSV export
///   • Журнал — journal_entries + CSV export
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

void _downloadCsv(String filename, String content) {
  final blob = html.Blob([content], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

String _csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

class _FinanceCenterScreenState extends State<FinanceCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _reconciling = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _goTab(int index) {
    if (index < 0 || index >= _tabCtrl.length) return;
    _tabCtrl.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Column(
      children: [
        _header(narrow: narrow),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: AppColors.primaryDark,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            labelPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 16),
            tabs: const [
              Tab(text: 'Назорат'),
              Tab(text: 'Driver Float'),
              Tab(text: 'Settlements'),
              Tab(text: 'Аудит журнали'),
              Tab(text: 'Давр қулфи'),
              Tab(text: 'Истиснолар'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              MoneyControlTab(onOpenTab: _goTab),
              const _FloatTab(),
              const _SettlementsTab(),
              const _JournalTab(),
              const _ClosingTab(),
              const _ExceptionsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header({required bool narrow}) {
    final sverkaBtn = ElevatedButton.icon(
      onPressed: _reconciling ? null : _runReconcile,
      icon: _reconciling
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.fact_check, size: 18),
      label: Text(narrow ? 'Sverka' : 'Sverka'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        visualDensity: narrow ? VisualDensity.compact : VisualDensity.standard,
      ),
    );

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, narrow ? 12 : 18,
          narrow ? 12 : 20, narrow ? 10 : 14),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance, color: AppColors.primaryDark),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Finance Center',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Пул назорати · float · settlement · журнал',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: sverkaBtn),
              ],
            )
          : Row(
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
                      Text(
                          'Пул назорати · Settlement Ledger — float, settlement, журнал',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                sverkaBtn,
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
class _SettlementsTab extends StatefulWidget {
  const _SettlementsTab();

  @override
  State<_SettlementsTab> createState() => _SettlementsTabState();
}

class _SettlementsTabState extends State<_SettlementsTab> {
  bool _exporting = false;

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('settlements')
          .orderBy('createdAt', descending: true)
          .limit(2000)
          .get();
      final rows = <String>[
        'id,tripId,driverUid,passengerUid,state,settlementAmount,totalChange,cashGiven,createdAt',
      ];
      for (final doc in snap.docs) {
        final d = doc.data();
        rows.add([
          _csvEscape(doc.id),
          _csvEscape('${d['tripId'] ?? ''}'),
          _csvEscape('${d['driverUid'] ?? ''}'),
          _csvEscape('${d['passengerUid'] ?? ''}'),
          _csvEscape('${d['state'] ?? ''}'),
          '${(d['settlementAmount'] as num?) ?? 0}',
          '${(d['totalChange'] as num?) ?? 0}',
          '${(d['cashGiven'] as num?) ?? 0}',
          _csvEscape(_fmtTs(d['createdAt'])),
        ].join(','));
      }
      _downloadCsv(
        'settlements_${DateTime.now().toIso8601String().substring(0, 10)}.csv',
        rows.join('\n'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export xato: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextButton.icon(
              onPressed: _exporting ? null : _exportCsv,
              icon: _exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download, size: 18),
              label: const Text('CSV export'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
          ),
        ),
      ],
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
class _JournalTab extends StatefulWidget {
  const _JournalTab();

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  bool _exporting = false;

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('journal_entries')
          .orderBy('ts', descending: true)
          .limit(2000)
          .get();
      final rows = <String>[
        'id,kind,amount,postedBy,postedRole,refType,refId,ts,legs',
      ];
      for (final doc in snap.docs) {
        final d = doc.data();
        final legs = ((d['legs'] as List?) ?? [])
            .map((l) {
              final m = Map<String, dynamic>.from(l as Map);
              final acc = m['account'] ?? '';
              final dr = (m['dr'] as num?) ?? 0;
              final cr = (m['cr'] as num?) ?? 0;
              return dr > 0 ? 'Dr $acc $dr' : 'Cr $acc $cr';
            })
            .join(' | ');
        rows.add([
          _csvEscape(doc.id),
          _csvEscape('${d['kind'] ?? ''}'),
          '${(d['amount'] as num?) ?? 0}',
          _csvEscape('${d['postedBy'] ?? ''}'),
          _csvEscape('${d['postedRole'] ?? ''}'),
          _csvEscape('${d['refType'] ?? ''}'),
          _csvEscape('${d['refId'] ?? ''}'),
          _csvEscape(_fmtTs(d['ts'])),
          _csvEscape(legs),
        ].join(','));
      }
      _downloadCsv(
        'journal_${DateTime.now().toIso8601String().substring(0, 10)}.csv',
        rows.join('\n'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export xato: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextButton.icon(
              onPressed: _exporting ? null : _exportCsv,
              icon: _exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download, size: 18),
              label: const Text('CSV export'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
            final role = (d['postedRole'] ?? '').toString();
            final by = (d['postedBy'] ?? '').toString();
            final refType = (d['refType'] ?? '').toString();
            final ts = _fmtTs(d['ts']);
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
                      Expanded(
                        child: Text(kind,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Text('${formatPrice(amount)} сўм',
                          style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(legStr,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (ts.isNotEmpty) _auditChip(Icons.schedule, ts),
                      if (role.isNotEmpty)
                        _auditChip(Icons.badge_outlined, role),
                      if (by.isNotEmpty)
                        _auditChip(Icons.person_outline, by),
                      if (refType.isNotEmpty)
                        _auditChip(Icons.link, refType),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// ДАВР ҚУЛФИ (Daily Closing — period_closings)
// ════════════════════════════════════════════════════════════
class _ClosingTab extends StatefulWidget {
  const _ClosingTab();

  @override
  State<_ClosingTab> createState() => _ClosingTabState();
}

class _ClosingTabState extends State<_ClosingTab> {
  bool _busy = false;

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
                  onPressed: _busy ? null : _closeDialog,
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_clock),
                  label: const Text('Давр қулфлаш'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('period_closings')
                .orderBy('periodId', descending: true)
                .limit(120)
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _err('${snap.error}');
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return _empty('Қулфланган давр йўқ',
                    'Кунлик ҳисоб-китобни қулфлаш учун юқоридаги тугмани босинг');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _closingRow(docs[i].data()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _closingRow(Map<String, dynamic> d) {
    final periodId = (d['periodId'] ?? '').toString();
    final t = Map<String, dynamic>.from((d['totals'] as Map?) ?? {});
    final ok = t['balanced'] == true &&
        t['identityOk'] == true &&
        t['projectionOk'] == true;
    final entries = ((t['periodEntryCount'] as num?) ?? 0).toInt();
    final periodDr = ((t['periodDr'] as num?) ?? 0).toInt();
    final closedAt = _fmtTs(d['closedAt']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified : Icons.warning,
                  color: ok ? Colors.green : Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(periodId,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              const Icon(Icons.lock, size: 14, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _auditChip(Icons.receipt_long, '$entries ёзув'),
              _auditChip(Icons.swap_vert, '${formatPrice(periodDr)} оборот'),
              _auditChip(ok ? Icons.check : Icons.error_outline,
                  ok ? 'мувозанат ✓' : 'муаммо!'),
              if (closedAt.isNotEmpty) _auditChip(Icons.schedule, closedAt),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _closeDialog() async {
    final today = DateTime.now().toUtc();
    final dateCtrl = TextEditingController(
        text: '${today.year.toString().padLeft(4, '0')}-'
            '${today.month.toString().padLeft(2, '0')}-'
            '${today.day.toString().padLeft(2, '0')}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Давр қулфлаш'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Кун (UTC) қулфланади ва ушбу давр учун снапшот сақланади. '
                'Журнал ўзгармас — қулф фақат аудит/ҳисобот учун.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(
                  labelText: 'Сана (YYYY-MM-DD)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Қулфлаш')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final periodId = dateCtrl.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(periodId)) {
      _snack('Сана YYYY-MM-DD форматида бўлсин', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('closePeriod')
          .call({'periodId': periodId});
      final m = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      if (m['alreadyClosed'] == true) {
        _snack('$periodId аллақачон қулфланган');
      } else {
        _snack('$periodId қулфланди ✓');
      }
    } on FirebaseFunctionsException catch (e) {
      _snack('Хатoлик: ${e.message ?? e.code}', isError: true);
    } catch (e) {
      _snack('Хатoлик: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
// ИСТИСНОЛАР (ledger_exceptions)
// ════════════════════════════════════════════════════════════
class _ExceptionsTab extends StatelessWidget {
  const _ExceptionsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ledger_exceptions')
          .orderBy('detectedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _err('${snap.error}');
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _empty('Истисно йўқ', 'Камомад/низо/сверка хатолари шу ерда');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final type = (d['type'] ?? '').toString();
            final driverUid = (d['driverUid'] ?? '').toString();
            final bal = ((d['balance'] as num?) ?? 0).toInt();
            final resolved = d['resolved'] == true;
            final detectedAt = _fmtTs(d['detectedAt']);
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
                  CircleAvatar(
                    backgroundColor:
                        (resolved ? Colors.green : Colors.red).withValues(alpha: 0.15),
                    child: Icon(
                        resolved ? Icons.check : Icons.report_problem_outlined,
                        color: resolved ? Colors.green : Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_exceptionLabel(type),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        if (driverUid.isNotEmpty)
                          Text('+$driverUid  ·  ${formatPrice(bal)} сўм',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        if (detectedAt.isNotEmpty)
                          Text(detectedAt,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: (resolved ? Colors.green : Colors.orange)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(resolved ? 'Ҳал қилинган' : 'Очиқ',
                        style: TextStyle(
                            color: resolved ? Colors.green : Colors.orange,
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

String _exceptionLabel(String type) {
  switch (type) {
    case 'deferred_timeout':
      return 'Кечиктирилган қарз муддати ўтди';
    default:
      return type.isEmpty ? 'Истисно' : type;
  }
}

// ── Umumiy yordamchilar ──
String _fmtTs(dynamic v) {
  if (v is Timestamp) {
    final dt = v.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
  return '';
}

Widget _auditChip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );

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
