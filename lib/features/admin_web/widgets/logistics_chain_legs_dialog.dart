// Админ: жўнатманинг йўл бўлаклари (LEG) — йиғиш ҳолати, ким қайси бўлакни
// олган, ҳақи; «Бўлакни қайта эълон қилиш» ва бўлак ҳақини қўлда бериш
// (эга 2026-11-07).
//
// ЎҚИШ: `demands/{legId}` (админга очиқ қоида) — битта `whereIn` сўрови,
// диалог очилганда БИР МАРТА (тинглаш йўқ, 36-банд). Курьер — ID (ҳужжатдаги
// `legAssignments`/`assignment.providerId`); исм сервер callable'исиз
// олинмайди, шунинг учун ID кўрсатилади.
// ЁЗИШ: фақат callable — `adminReopenChainLeg`, `adminPlanShipmentRoute`
// (`payoutOverrides`). Сервер ҳал қилувчи; бу ерда фақат эрта текширув.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../logistics/domain/logistics_models.dart' show ChainState, ShipmentChain, logisticsMoney;
import '../services/admin_callable.dart';
import '../services/admin_logistics_service.dart';
import '../utils/chain_payout_overrides.dart';

/// Админ учун йиғиш ҳолати номи.
String chainStateLabel(ChainState s) => switch (s) {
      ChainState.assembling => 'йиғилмоқда',
      ChainState.locked => 'қулфланган (ҳамма бўлак олинган)',
      ChainState.expired => 'муддати ўтган',
      ChainState.cancelled => 'бекор',
      ChainState.unknown => 'номаълум',
    };

/// «Бўлаклар: йиғилмоқда 2/3 · муддат …» — жўнатма қаторидаги қисқа матн.
String chainSummaryLine(ShipmentChain ch, {int legCountFallback = 0, String Function(DateTime)? fmt}) {
  final total = ch.legCount > 0 ? ch.legCount : legCountFallback;
  final f = fmt ?? _fmtDate;
  return 'Бўлаклар: ${chainStateLabel(ch.state)} ${ch.claimed}/$total'
      '${ch.isAssembling && ch.deadlineAt != null ? ' · муддат ${f(ch.deadlineAt!)}' : ''}'
      '${ch.lockedAt != null ? ' · қулф: ${f(ch.lockedAt!)}' : ''}';
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Битта бўлак (LEG) — `demands/{id}` ҳужжатидан.
class ChainLegRow {
  const ChainLegRow({
    required this.legId,
    required this.legIndex,
    required this.status,
    required this.from,
    required this.to,
    this.providerId,
    this.payout,
  });

  final String legId;
  final int legIndex;
  final String status;
  final String? providerId;

  /// `attributes.payout` — бутун сўм; ўқилмаса `null`.
  final int? payout;
  final Map<String, String> from;
  final Map<String, String> to;

  static Map<String, String> _pt(Object? p) {
    final m = p is Map ? p : const {};
    return {
      'regionId': (m['regionId'] ?? '').toString(),
      'districtId': (m['districtId'] ?? '').toString(),
    };
  }

  static ChainLegRow fromDemand(
    String id,
    Map<String, dynamic> d, {
    Map<String, String> legAssignments = const {},
    int fallbackIndex = 0,
  }) {
    final a = d['attributes'] is Map ? d['attributes'] as Map : const {};
    final asg = d['assignment'] is Map ? d['assignment'] as Map : const {};
    final holder = legAssignments[id] ?? asg['providerId']?.toString();
    final idx = a['legIndex'];
    final pay = a['payout'];
    return ChainLegRow(
      legId: id,
      legIndex: idx is num ? idx.toInt() : fallbackIndex,
      status: (d['status'] ?? '').toString(),
      providerId: holder == null || holder.isEmpty ? null : holder,
      payout: pay is num ? pay.toInt() : null,
      from: _pt(d['location']),
      to: _pt(d['destination']),
    );
  }

  String get routeLabel {
    String p(Map<String, String> m) => m['districtId']!.isNotEmpty ? m['districtId']! : m['regionId']!;
    return '${p(from)} → ${p(to)}';
  }
}

/// Ижрочилар пули = жорий бўлак ҳақлари йиғиндиси (биттаси ўқилмаса `null`).
/// INFERRED: сервер `legPayouts` йиғиндиси = `providerPool` (tariff.test.js).
int? chainProviderPool(List<ChainLegRow> legs) {
  if (legs.isEmpty) return null;
  var sum = 0;
  for (final l in legs) {
    final p = l.payout;
    if (p == null) return null;
    sum += p;
  }
  return sum;
}

Future<void> showChainLegsDialog(
  BuildContext context, {
  required String shipmentId,
  required Map<String, dynamic> shipment,
  required AdminLogisticsService service,
  FirebaseFirestore? db,
}) async {
  final legIds = (shipment['legIds'] is List ? shipment['legIds'] as List : const [])
      .map((e) => e.toString())
      .where((e) => e.isNotEmpty)
      .toList();
  final raw = shipment['legAssignments'] is Map ? shipment['legAssignments'] as Map : const {};
  final assignments = <String, String>{
    for (final e in raw.entries)
      if (e.value != null) e.key.toString(): e.value.toString(),
  };
  List<ChainLegRow> rows = const [];
  String? loadError;
  try {
    if (legIds.isNotEmpty) {
      // LEG сони ≤ 6 (сервер) — битта `whereIn` (чегара 10/30).
      final snap = await (db ?? FirebaseFirestore.instance)
          .collection('demands')
          .where(FieldPath.documentId, whereIn: legIds)
          .get();
      final byId = {for (final d in snap.docs) d.id: d.data()};
      rows = [
        for (var i = 0; i < legIds.length; i += 1)
          if (byId[legIds[i]] != null)
            ChainLegRow.fromDemand(legIds[i], byId[legIds[i]]!, legAssignments: assignments, fallbackIndex: i),
      ]..sort((a, b) => a.legIndex.compareTo(b.legIndex));
    }
  } catch (e) {
    loadError = '$e';
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => ChainLegsDialog(
      shipmentId: shipmentId,
      shipment: shipment,
      legs: rows,
      loadError: loadError,
      service: service,
    ),
  );
}

class ChainLegsDialog extends StatefulWidget {
  const ChainLegsDialog({
    super.key,
    required this.shipmentId,
    required this.shipment,
    required this.legs,
    required this.service,
    this.loadError,
  });

  final String shipmentId;
  final Map<String, dynamic> shipment;
  final List<ChainLegRow> legs;
  final AdminLogisticsService service;
  final String? loadError;

  @override
  State<ChainLegsDialog> createState() => _ChainLegsDialogState();
}

class _ChainLegsDialogState extends State<ChainLegsDialog> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  ShipmentChain? get _chain {
    final c = widget.shipment['chain'];
    return ShipmentChain.fromMap(c is Map ? c.map((k, v) => MapEntry(k.toString(), v)) : null);
  }

  String get _status => (widget.shipment['status'] ?? '').toString();

  bool get _replannable => _status == 'awaiting_payment' || _status == 'ready';

  void _show(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _reopen(ChainLegRow leg) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(title: 'Бўлакни қайта эълон қилиш — сабаб (audit)'),
    );
    if (reason == null || reason.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.service.reopenChainLeg(shipmentId: widget.shipmentId, legId: leg.legId, reason: reason);
      _show('${leg.legIndex + 1}-бўлак қайта эълон қилинди');
    } catch (e) {
      _show('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPayouts() async {
    final res = await showDialog<(List<Map<String, int>>, String)>(
      context: context,
      builder: (_) => PayoutOverrideDialog(legs: widget.legs),
    );
    if (res == null) return;
    setState(() => _busy = true);
    try {
      final out = await widget.service.planRouteWithPayouts(
        shipmentId: widget.shipmentId,
        legs: [for (final l in widget.legs) {'from': l.from, 'to': l.to}],
        payoutOverrides: res.$1,
        reason: res.$2,
      );
      _show('Ҳақ сақланди: маршрут v${out['version'] ?? '?'} (бўлаклар қайта яратилди)');
    } catch (e) {
      _show('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = _chain;
    final pool = chainProviderPool(widget.legs);
    return AlertDialog(
      title: Text('Бўлаклар — ${widget.shipment['trackingNumber'] ?? widget.shipmentId}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ch == null || !ch.isAssembleAll
                    ? 'Режим: кетма-кет (эски) · ҳолат: $_status'
                    : '${chainSummaryLine(ch, legCountFallback: widget.legs.length)} · ҳолат: $_status',
                key: const ValueKey('chain-admin-summary'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Ижрочилар пули: ${pool == null ? 'номаълум' : '${logisticsMoney(pool)} сўм'} · '
                'курьер — ID (исм кўрсатилмайди)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              if (widget.loadError != null) ...[
                const SizedBox(height: 8),
                Text('Бўлаклар ўқилмади: ${widget.loadError}', style: TextStyle(color: Colors.red.shade700)),
              ],
              const SizedBox(height: 8),
              if (widget.legs.isEmpty && widget.loadError == null) const Text('Бўлак йўқ'),
              for (final l in widget.legs)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 14, child: Text('${l.legIndex + 1}')),
                    title: Text('${l.routeLabel} · ${l.status}'),
                    subtitle: Text(
                      'курьер: ${l.providerId ?? '— йўқ'} · ҳақ: '
                      '${l.payout == null ? '?' : '${logisticsMoney(l.payout!)} сўм'} · ${l.legId}',
                    ),
                    // Қулфлангандан кейин курьер тушиб қолса (эга 2026-11-07).
                    trailing: ch != null && ch.isLocked && l.status != 'completed'
                        ? OutlinedButton.icon(
                            key: ValueKey('chain-reopen-${l.legIndex}'),
                            onPressed: _busy ? null : () => _reopen(l),
                            icon: const Icon(Icons.campaign_outlined, size: 16),
                            label: const Text('Бўлакни қайта эълон қилиш'),
                          )
                        : null,
                  ),
                ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, style: TextStyle(color: _messageIsError ? Colors.red.shade700 : Colors.green.shade800)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_replannable && widget.legs.isNotEmpty)
          FilledButton.tonalIcon(
            key: const ValueKey('chain-edit-payouts'),
            onPressed: _busy ? null : _editPayouts,
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: const Text('Бўлак ҳақини ўзгартириш'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ёпиш')),
      ],
    );
  }
}

/// Ҳар бўлак ҳақи: бутун сўм, йиғинди = ижрочилар пули. Натижа:
/// (`payoutOverrides`, сабаб) ёки `null`.
class PayoutOverrideDialog extends StatefulWidget {
  const PayoutOverrideDialog({super.key, required this.legs});

  final List<ChainLegRow> legs;

  @override
  State<PayoutOverrideDialog> createState() => _PayoutOverrideDialogState();
}

class _PayoutOverrideDialogState extends State<PayoutOverrideDialog> {
  late final List<TextEditingController> _ctrls = [
    for (final l in widget.legs) TextEditingController(text: l.payout?.toString() ?? ''),
  ];
  final _reason = TextEditingController();
  late final int? _pool = chainProviderPool(widget.legs);

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  PayoutOverrideCheck get _check => validatePayoutOverrides([for (final c in _ctrls) c.text], pool: _pool);

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final reasonOk = _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Бўлак ҳақини ўзгартириш'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Бутун сўм. Йиғинди ижрочилар пулига тенг бўлиши шарт: '
                '${_pool == null ? 'номаълум' : '${logisticsMoney(_pool)} сўм'}. '
                'Маршрут ўша нуқталар билан қайта режаланади (ҳеч бир бўлак олинмаган '
                'бўлиши керак — сервер текширади).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < widget.legs.length; i += 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: ValueKey('chain-payout-$i'),
                    controller: _ctrls[i],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${i + 1}-бўлак: ${widget.legs[i].routeLabel}',
                      suffixText: 'сўм',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              TextField(
                key: const ValueKey('chain-payout-reason'),
                controller: _reason,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Сабаб (audit)', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              Text(
                check.error ?? 'Йиғинди: ${logisticsMoney(check.sum)} сўм — тўғри',
                key: const ValueKey('chain-payout-check'),
                style: TextStyle(fontSize: 12, color: check.error != null ? Colors.red.shade700 : Colors.green.shade800),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          key: const ValueKey('chain-payout-save'),
          onPressed: check.isValid && reasonOk
              ? () => Navigator.pop(context, (check.overrides!, _reason.text.trim()))
              : null,
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ctrl.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        maxLength: 300,
        decoration: const InputDecoration(hintText: 'Қисқа сабаб (камида 3 белги)'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: const Text('Тасдиқлаш'),
        ),
      ],
    );
  }
}
