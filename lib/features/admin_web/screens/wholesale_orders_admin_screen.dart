// УЛГУРЖИ БУЮРТМА ЗАНЖИРИ — админ (5-босқич, docs/ulgurji_buyurtma_zanjiri_uz.md).
// «Улгуржи бозор» бўлимидаги таб. Ички бўлимлар:
//   • Буюртмалар — `wholesale_orders` (rules: admin ҳаммасини ўқийди), янгиси биринчи,
//     ҳолат / «муаммоли» филтри (юкланган саҳифалар ичида), тафсилот, карта низоси.
//     `history` субколлекцияси rules'да ЙЎҚ → клиент ўқий олмайди (тафсилотда изоҳ).
//   • AVA улуши — `settings/wholesale_orders` + `setWholesaleOrderSettings`.
//   • Дарвоза ва тестчилар — `adminGet/SetWholesaleOrdersStage`.
//   • Вилоятлар матрицаси — логистика тарифи қораламасида 14×14 (`adminUpsertLogisticsTariff`).
// Ҳамма ёзув СЕРВЕРДА (callable); экран фақат ўқийди ва чақиради (44-банд).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_callable.dart' show adminInt;
import '../services/admin_logistics_service.dart';
import '../services/admin_wholesale_orders_service.dart';
import '../utils/admin_paged_list.dart';
import '../utils/region_zone_matrix.dart';
import '../utils/wholesale_orders_admin.dart';
import '../widgets/admin_load_more_bar.dart';
import '../widgets/region_zone_matrix_dialog.dart';
import '../widgets/wholesale_dispute_dialog.dart';
import '../widgets/wholesale_fee_card.dart';
import '../widgets/wholesale_lost_fee_dialog.dart';
import '../widgets/wholesale_stage_panel.dart';

class WholesaleOrdersAdminScreen extends StatefulWidget {
  const WholesaleOrdersAdminScreen({super.key});

  @override
  State<WholesaleOrdersAdminScreen> createState() => _WholesaleOrdersAdminScreenState();
}

class _WholesaleOrdersAdminScreenState extends State<WholesaleOrdersAdminScreen> {
  final _svc = AdminWholesaleOrdersService();
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Буюртмалар'), icon: Icon(Icons.receipt_long_outlined)),
              ButtonSegment(value: 1, label: Text('AVA улуши'), icon: Icon(Icons.percent)),
              ButtonSegment(value: 2, label: Text('Дарвоза ва тестчилар'), icon: Icon(Icons.door_front_door_outlined)),
              ButtonSegment(value: 3, label: Text('Вилоятлар матрицаси'), icon: Icon(Icons.table_chart_outlined)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
      ),
      Expanded(
        child: switch (_tab) {
          0 => _WholesaleOrdersList(svc: _svc),
          1 => ListView(padding: const EdgeInsets.all(16), children: [WholesaleFeeCard(svc: _svc)]),
          2 => WholesaleStagePanel(svc: _svc),
          _ => const _MatrixDraftsPanel(),
        },
      ),
    ]);
  }
}

// ─── Буюртмалар ─────────────────────────────────────────────────────────

class _WholesaleOrdersList extends StatefulWidget {
  const _WholesaleOrdersList({required this.svc});

  final AdminWholesaleOrdersService svc;

  @override
  State<_WholesaleOrdersList> createState() => _WholesaleOrdersListState();
}

class _WholesaleOrdersListState extends State<_WholesaleOrdersList> {
  late final AdminFirestorePagedList<WholesaleOrderAdminView> _orders;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    // Битта майдон бўйича тартиб (createdAt — сервер ҳар доим ёзади): композит индекс
    // керак эмас. Ҳолат/муаммо филтри — клиентда, юкланган саҳифалар ичида.
    final query = FirebaseFirestore.instance.collection('wholesale_orders').orderBy('createdAt', descending: true);
    _orders = AdminFirestorePagedList<WholesaleOrderAdminView>(
      watch: (window) => watchFirestoreWindow(query, window),
      map: (doc) => WholesaleOrderAdminView.fromMap(doc.id, doc.data()),
      idOf: (o) => o.id,
      pageSize: 100,
    );
  }

  @override
  void dispose() {
    _orders.dispose();
    super.dispose();
  }

  Future<void> _open(WholesaleOrderAdminView o) async {
    await showDialog<void>(
      context: context,
      builder: (_) => WholesaleOrderDetailDialog(order: o, svc: widget.svc),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _orders,
      builder: (context, _) {
        if (_orders.error != null) return Center(child: Text('Хато: ${_orders.error}'));
        if (_orders.isLoading) return const Center(child: CircularProgressIndicator());
        final all = _orders.items;
        final shown = all.where((o) => o.matchesFilter(_filter)).toList();
        final problems = all.where((o) => o.hasProblem).length;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(children: [
              const Text('Филтр:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filter,
                items: [
                  for (final e in kWholesaleOrderFilters.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _filter = v ?? ''),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Юкланган: ${all.length} · муаммоли: $problems (филтр — юкланганлар ичида)',
                  style: TextStyle(fontSize: 12, color: problems > 0 ? Colors.red.shade700 : Colors.grey.shade700),
                ),
              ),
            ]),
          ),
          Expanded(
            child: shown.isEmpty && !_orders.hasMore
                ? Center(child: Text('Буюртма йўқ', style: TextStyle(color: Colors.grey.shade600)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: shown.length + (_orders.hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == shown.length) {
                        return AdminLoadMoreBar(
                          loading: _orders.loadingMore,
                          failed: _orders.loadMoreError != null,
                          onPressed: _orders.loadMore,
                        );
                      }
                      return _orderTile(shown[i]);
                    },
                  ),
          ),
        ]);
      },
    );
  }

  Widget _orderTile(WholesaleOrderAdminView o) {
    final problems = o.problems;
    return Card(
      color: problems.isNotEmpty ? Colors.red.shade50 : null,
      child: ListTile(
        onTap: () => _open(o),
        title: Text(
          '${o.productTitle.isEmpty ? '—' : o.productTitle}${o.packLabel.isEmpty ? '' : ' (${o.packLabel})'} × ${o.qty ?? '?'}',
        ),
        subtitle: Text(
          '${o.statusLabel} · ${o.isCard ? 'карта (етказилганда)' : 'ҳамён'} · жами: '
          '${o.total == null ? '—' : '${wholesaleMoney(o.total!)} сўм'} · ${_fmt(o.createdAt)}'
          '${o.trackingNumber.isNotEmpty ? ' · ${o.trackingNumber}' : ''}'
          '${o.shipmentError != null && !o.shipmentErrorFinal ? ' · жўнатма қайта уринилмоқда' : ''}'
          '${problems.isEmpty ? '' : '\n⚠ ${problems.map((p) => p.text).join(' · ')}'}',
        ),
        isThreeLine: problems.isNotEmpty,
        trailing: o.needsDisputeDecision ? const Icon(Icons.gavel, color: Colors.red) : const Icon(Icons.chevron_right),
      ),
    );
  }
}

String _fmt(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Буюртма ҳужжатини қайта ўқиш (тўловдан кейин янгилаш). Тестда алмаштирилади.
typedef WholesaleOrderLoader = Future<WholesaleOrderAdminView?> Function(String orderId);

Future<WholesaleOrderAdminView?> _loadOrderFromFirestore(String orderId) async {
  final s = await FirebaseFirestore.instance.collection('wholesale_orders').doc(orderId).get();
  final d = s.data();
  return d == null ? null : WholesaleOrderAdminView.fromMap(s.id, d);
}

class WholesaleOrderDetailDialog extends StatefulWidget {
  const WholesaleOrderDetailDialog({super.key, required this.order, required this.svc, this.loadOrder});

  final WholesaleOrderAdminView order;
  final AdminWholesaleOrdersService svc;
  final WholesaleOrderLoader? loadOrder;

  @override
  State<WholesaleOrderDetailDialog> createState() => _WholesaleOrderDetailDialogState();
}

class _WholesaleOrderDetailDialogState extends State<WholesaleOrderDetailDialog> {
  late WholesaleOrderAdminView _order = widget.order;

  AdminWholesaleOrdersService get svc => widget.svc;

  Future<void> _dispute(BuildContext context) async {
    final res = await showWholesaleDisputeDialog(context, svc: svc, order: _order);
    if (res == null || !context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Низо ҳал қилинди${res['status'] != null ? ': ${res['status']}' : ''}'
          '${res['idempotent'] == true ? ' (аввал ҳам)' : ''}'),
    ));
  }

  /// Курьер етказиш пули қарзини тўлади → сервер ёзади → буюртма қайта ўқилади.
  Future<void> _payLostFee() async {
    final res = await showWholesaleLostFeePaymentDialog(context, svc: svc, order: _order);
    if (res == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final left = adminInt(res['outstanding']);
    messenger.showSnackBar(SnackBar(
      content: Text('Тўлов ёзилди: ${wholesaleMoney(adminInt(res['amount']) ?? 0)} сўм'
          '${left != null ? ' · қолган қарз: ${wholesaleMoney(left)} сўм' : ''}'
          '${res['idempotent'] == true ? ' (аввал ёзилган)' : ''}'),
    ));
    try {
      final fresh = await (widget.loadOrder ?? _loadOrderFromFirestore)(_order.id);
      if (fresh != null && mounted) setState(() => _order = fresh);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Буюртма янгиланмади: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    String money(int? v) => v == null ? '—' : '${wholesaleMoney(v)} сўм';
    String jsonish(Map<String, dynamic>? m) => m == null
        ? '—'
        : m.entries
            .map((e) => '${e.key}: ${e.value is Timestamp || e.value is DateTime ? _fmt(wholesaleTimeOf(e.value)) : e.value}')
            .join(', ');
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 170, child: Text(k, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))),
            Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 12.5))),
          ]),
        );
    final problems = o.problems;
    return AlertDialog(
      title: Text('Буюртма ${o.id}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (problems.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.shade50,
                  child: Text(problems.map((p) => '⚠ ${p.text}').join('\n'), style: TextStyle(color: Colors.red.shade900)),
                ),
              row('Ҳолат', '${o.statusLabel} (${o.status})'),
              row('Тўлов усули', o.isCard ? 'Карта — етказилганда (card_on_delivery)' : 'Ҳамён — олдиндан'),
              row('Товар', '${o.productTitle}${o.packLabel.isEmpty ? '' : ' (${o.packLabel})'} × ${o.qty ?? '?'}'),
              row('Дона нархи', money(o.unitPrice)),
              row('Товар суммаси', money(o.goodsTotal)),
              row('Етказиш', money(o.deliveryFee)),
              row('Жами', money(o.total)),
              row('Тўлов (payment.status)', o.paymentStatus.isEmpty ? '—' : o.paymentStatus),
              row('Қайтариш (refundStatus)', o.refundStatus.isEmpty ? '—' : o.refundStatus),
              if (o.isCard) row('Карта тўлови', jsonish(o.cardPayment)),
              if (o.returnDebt != null) row('Қайтариш қарзи', jsonish(o.returnDebt)),
              WholesaleLostFeeSection(order: o, onRecordPayment: _payLostFee),
              row('Харидор', o.buyerId),
              row('Сотувчи', o.sellerId),
              row('Тариф / зона', '${o.tariffVersion != null ? 'v${o.tariffVersion}' : '—'} · ${o.zone.isEmpty ? '—' : o.zone}'),
              row('Жўнатма', o.shipmentId.isEmpty ? 'ҳали очилмаган' : '${o.trackingNumber} (${o.shipmentId})'),
              if (o.shipmentError != null) row('Жўнатма хатоси', jsonish(o.shipmentError)),
              if (o.shipFundAnomaly != null) row('shipFundAnomaly', jsonish(o.shipFundAnomaly)),
              if (o.releaseAnomaly != null) row('releaseAnomaly', jsonish(o.releaseAnomaly)),
              row('Берилган', _fmt(o.createdAt)),
              row('Янгиланган', _fmt(o.updatedAt)),
              const SizedBox(height: 8),
              Text(
                'Ҳолатлар тарихи (history, ${o.historySeq ?? 0} та ёзув) админ панелидан ҳали ўқилмайди: '
                'Firestore rules\'да `wholesale_orders/{id}/history` учун қоида йўқ. Таклиф — admin read callable.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (o.needsDisputeDecision && o.isCard)
          FilledButton.icon(
            onPressed: () => _dispute(context),
            icon: const Icon(Icons.gavel, size: 18),
            label: const Text('Низони ҳал қилиш'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ёпиш')),
      ],
    );
  }
}

// ─── Вилоятлар матрицаси (логистика тарифи қораламаси) ─────────────────

class _MatrixDraftsPanel extends StatefulWidget {
  const _MatrixDraftsPanel();

  @override
  State<_MatrixDraftsPanel> createState() => _MatrixDraftsPanelState();
}

class _MatrixDraftsPanelState extends State<_MatrixDraftsPanel> {
  final _logistics = AdminLogisticsService();
  late final Future<List<MatrixRegion>> _regions = loadMatrixRegions();
  bool _busy = false;

  Future<void> _edit(Map<String, dynamic> t, List<MatrixRegion> regions) async {
    setState(() => _busy = true);
    try {
      await editTariffRegionMatrix(context, tariff: t, service: _logistics, loadRegions: () async => regions);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final muted = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    return FutureBuilder<List<MatrixRegion>>(
      future: _regions,
      builder: (context, regSnap) {
        final regions = regSnap.data ?? const <MatrixRegion>[];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('module_tariffs').where('module', isEqualTo: 'logistics').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
            if (!snap.hasData || regSnap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs.map((d) => d.data()).toList()
              ..sort((a, b) => ((b['version'] as num?) ?? 0).compareTo((a['version'] as num?) ?? 0));
            final ids = [for (final r in regions) r.id];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Етказиш нархи вилоятлар жуфтлиги → зона (ZONE_0..ZONE_5) бўйича. Жадвал бўш — уни эга/админ '
                  'тўлдиради; бўш жуфтликка буюртма берилмайди («етказиш нархи ҳали белгиланмаган»). '
                  'Матрица фақат ҚОРАЛАМА тарифда таҳрирланади; янги қоралама — AVA Logistics → Тариф → '
                  '«Янги версия» ёки «Нархлар → янги версия». 20 кг дан оғир (+1 кг) нархлари — «Нархлар» жадвалида.',
                  style: muted,
                ),
                const SizedBox(height: 6),
                Text(
                  regions.isEmpty
                      ? 'Вилоятлар рўйхати (geo_regions) юкланмади — матрицани очиб бўлмайди.'
                      : 'Вилоятлар: ${regions.length} (geo_regions) → ${regions.length * (regions.length + 1) ~/ 2} жуфтлик (диагонал билан).',
                  style: TextStyle(fontSize: 12.5, color: regions.isEmpty ? Colors.red.shade700 : Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                if (docs.isEmpty) Text('Логистика тарифи версиялари йўқ', style: muted),
                for (final t in docs) _tile(t, ids, regions),
              ],
            );
          },
        );
      },
    );
  }

  Widget _tile(Map<String, dynamic> t, List<String> ids, List<MatrixRegion> regions) {
    final version = (t['version'] as num?)?.toInt() ?? 0;
    final status = (t['status'] ?? '').toString();
    final isDraft = status == 'draft';
    final m = t['matrix'];
    final fill = regionMatrixFill(ids, m is Map ? m['regions'] : null);
    return Card(
      child: ListTile(
        title: Text('v$version · $status'),
        subtitle: Text('Матрица: ${fill.filled} / ${fill.total} жуфтлик тўлдирилган · бўш: ${fill.total - fill.filled}'),
        trailing: isDraft
            ? FilledButton.tonalIcon(
                onPressed: _busy || regions.isEmpty ? null : () => _edit(t, regions),
                icon: const Icon(Icons.table_chart_outlined, size: 16),
                label: const Text('Матрицани таҳрирлаш'),
              )
            : Text('ўзгармас', style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }
}
