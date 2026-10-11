import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_index_entry.dart';
import '../services/admin_all_orders_service.dart';

/// «Барча буюртмалар» (D-ALL-1…11): барча модул буюртмалари бир жойда,
/// ФАҚАТ КЎРИШ (D-ALL-3). Маълумот — сервер ёзадиган `order_index`;
/// «тиқилиб қолган» вақти серверда ҳисобланган (`stuckAt`).
class AdminAllOrdersScreen extends StatefulWidget {
  const AdminAllOrdersScreen({super.key, this.source, this.clock});

  final AllOrdersSource? source;

  /// Тест учун вақт манбаи.
  final DateTime Function()? clock;

  @override
  State<AdminAllOrdersScreen> createState() => _AdminAllOrdersScreenState();
}

class _AdminAllOrdersScreenState extends State<AdminAllOrdersScreen> {
  static const _page = 50;

  late final AllOrdersSource _source = widget.source ?? FirestoreAllOrdersSource();
  final _searchCtrl = TextEditingController();

  AllOrdersFilter _filter = const AllOrdersFilter();
  int _limit = _page;

  // Оқим state'да кешланади — rebuild янги listener очмасин.
  late Stream<List<OrderIndexEntry>> _stream = _source.watch(_filter, _limit);
  Future<AllOrdersCounts>? _counts;
  Future<List<OrderIndexEntry>>? _searchResults;
  Timer? _tick;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _reloadCounts();
    // Ёш ва «кечикди» ёзуви янгилансин; ҳисоблагичлар — дақиқасига бир.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        _reloadCounts();
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reloadCounts() => _counts = _source.counts(_filter, _now);

  void _apply(AllOrdersFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _limit = _page;
      _stream = _source.watch(_filter, _limit);
      _reloadCounts();
    });
  }

  void _loadMore() {
    setState(() {
      _limit += _page;
      _stream = _source.watch(_filter, _limit);
    });
  }

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    final results = q.isEmpty ? null : _source.search(q);
    setState(() {
      _searchResults = results;
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _searchResults = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _countersBar(),
        _filtersBar(),
        const Divider(height: 1),
        Expanded(child: _searchResults != null ? _searchList() : _streamList()),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Барча буюртмалар — фақат кўриш',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Янгилаш',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _stream = _source.watch(_filter, _limit);
              _reloadCounts();
            }),
          ),
        ],
      ),
    );
  }

  Widget _countersBar() {
    return FutureBuilder<AllOrdersCounts>(
      future: _counts,
      builder: (context, snap) {
        final c = snap.data;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in OrderIndexEntry.statusOrder)
                FilterChip(
                  key: ValueKey('count_$s'),
                  selected: !_filter.stuckOnly && _filter.status == s,
                  label: Text(
                    '${OrderIndexEntry.statusLabels[s]}: ${c == null ? '…' : c.byStatus[s] ?? 0}',
                  ),
                  onSelected: (sel) => _apply(_filter.copyWith(
                    status: sel ? s : null,
                    stuckOnly: false,
                  )),
                ),
              FilterChip(
                key: const ValueKey('count_stuck'),
                selected: _filter.stuckOnly,
                avatar: const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red),
                label: Text(
                  'Тиқилиб қолган: ${c == null ? '…' : c.stuck}',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                ),
                onSelected: (sel) => _apply(_filter.copyWith(stuckOnly: sel, status: null)),
              ),
              if (snap.hasError)
                const Text('Сонлар юкланмади', style: TextStyle(color: Colors.red)),
            ],
          ),
        );
      },
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            key: const ValueKey('module_filter'),
            value: _filter.module,
            hint: const Text('Барча модуллар'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Барча модуллар')),
              for (final e in OrderIndexEntry.moduleLabels.entries)
                DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => _apply(_filter.copyWith(module: v)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                key: const ValueKey('stuck_switch'),
                value: _filter.stuckOnly,
                onChanged: (v) => _apply(_filter.copyWith(stuckOnly: v, status: null)),
              ),
              const Text('Фақат тиқилиб қолганлар'),
            ],
          ),
          SizedBox(
            width: 280,
            child: TextField(
              key: const ValueKey('search_field'),
              controller: _searchCtrl,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: 'Буюртма ID ёки телефон охирги 4 рақами',
                suffixIcon: _searchResults == null
                    ? IconButton(icon: const Icon(Icons.search), onPressed: _runSearch)
                    : IconButton(icon: const Icon(Icons.close), onPressed: _clearSearch),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streamList() {
    return StreamBuilder<List<OrderIndexEntry>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return _errorView(snap.error);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return _empty();
        final more = items.length >= _limit;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: items.length + (more ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == items.length) {
              return Center(
                child: TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Яна юклаш'),
                ),
              );
            }
            return _row(items[i]);
          },
        );
      },
    );
  }

  Widget _searchList() {
    return FutureBuilder<List<OrderIndexEntry>>(
      future: _searchResults,
      builder: (context, snap) {
        if (snap.hasError) return _errorView(snap.error);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('Ҳеч нарса топилмади'));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: items.map(_row).toList(),
        );
      },
    );
  }

  Widget _empty() => Center(
        child: Text(
          _filter.stuckOnly ? 'Тиқилиб қолган буюртма йўқ' : 'Буюртма йўқ',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );

  Widget _errorView(Object? e) {
    final text = '$e';
    final denied = text.contains('permission-denied') || text.contains('PERMISSION_DENIED');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          denied
              ? 'Бу бўлимга рухсатингиз йўқ. Админдан «Барча буюртмалар» рухсатини сўранг.'
              : 'Буюртмаларни юклаб бўлмади. Қайта уриниб кўринг.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  }

  static const _moduleIcons = <String, IconData>{
    'bread': Icons.bakery_dining,
    'wholesale': Icons.warehouse_outlined,
    'restaurant': Icons.restaurant_outlined,
    'carpet': Icons.local_laundry_service_outlined,
    'milk': Icons.water_drop_outlined,
    'logistics': Icons.local_post_office_outlined,
    'courier': Icons.delivery_dining,
  };

  static Color statusColor(String s) => switch (s) {
        'NEW' => Colors.blue.shade700,
        'ACCEPTED' => Colors.teal.shade700,
        'WAITING_COURIER' => Colors.orange.shade800,
        'WITH_COURIER' => Colors.indigo.shade600,
        'DELIVERED' => Colors.green.shade700,
        'CANCELLED' => Colors.grey.shade600,
        _ => Colors.brown,
      };

  Widget _row(OrderIndexEntry e) {
    final now = _now;
    final stuck = e.isStuck(now);
    final inStage = e.inStageFor(now);
    final overdue = e.overdueBy(now);
    final shortId = e.sourceId.length > 8 ? e.sourceId.substring(0, 8) : e.sourceId;
    final created = e.createdAt == null ? '' : DateFormat('dd.MM HH:mm').format(e.createdAt!);
    return Card(
      key: ValueKey('row_${e.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: stuck ? Colors.red.shade300 : Colors.grey.shade200),
      ),
      color: stuck ? Colors.red.shade50 : Colors.white,
      child: ListTile(
        onTap: () => _showDetail(e),
        leading: Icon(_moduleIcons[e.module] ?? Icons.receipt_long, color: AppColors.primaryText),
        title: Text(
          [
            e.moduleLabel,
            '#$shortId',
            if (e.title.isNotEmpty) e.title,
          ].join(' · '),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              e.statusLabel,
              style: TextStyle(color: statusColor(e.normStatus), fontWeight: FontWeight.w600),
            ),
            if (inStage != null && !e.final_)
              Text('${formatAge(inStage)}${e.sinceApprox ? ' (тахм.)' : ''}'),
            if (overdue != null)
              Text(
                '⚠ ${formatAge(overdue)} кечикди',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
              ),
            if (e.hasCourier) const Icon(Icons.delivery_dining, size: 16),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (e.amount != null && e.amount! > 0)
              Text(formatMoney(e.amount!), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(created, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(OrderIndexEntry e) {
    final now = _now;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    String t(DateTime? d) => d == null ? '—' : fmt.format(d);
    final inStage = e.inStageFor(now);
    final rows = <(String, String)>[
      ('Модул', e.moduleLabel),
      ('Буюртма ID', e.sourceId),
      ('Ҳолат', e.statusLabel),
      ('Босқич', e.stageLabel),
      ('Асл статус', e.rawStatus.isEmpty ? '—' : e.rawStatus),
      (
        'Шу ҳолатда',
        inStage == null || e.final_
            ? '—'
            : '${formatAge(inStage)}${e.sinceApprox ? ' (тахминий — эски буюртма)' : ''}',
      ),
      (
        e.isStuck(now) ? 'Тиқилиб қолди' : 'Тиқилиб қолади',
        e.stuckAt == null
            ? 'чегара йўқ'
            : '${t(e.stuckAt)}${e.stuckRule == 'cycle' ? ' (бутун жараён чегараси)' : ''}',
      ),
      ('Курьер', e.courierId ?? (e.hasCourier ? 'бор' : 'йўқ')),
      ('Сумма', e.amount == null || e.amount == 0 ? '—' : formatMoney(e.amount!)),
      ('Мижоз', e.customerTail.isEmpty ? '—' : '…${e.customerTail}'),
      ('Ҳудуд', [e.regionId, e.districtId].whereType<String>().join(' / ').ifEmpty('—')),
      ('Яратилган', t(e.createdAt)),
      ('Бошқарув', e.managedInSection),
    ];
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${e.moduleLabel} буюртмаси'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(r.$1, style: TextStyle(color: Colors.grey.shade700)),
                        ),
                        Expanded(child: SelectableText(r.$2)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Бу ерда фақат кўриш. Ҳолатни ўзгартириш — «${e.managedInSection}» бўлимида.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ёпиш')),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
