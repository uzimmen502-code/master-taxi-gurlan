// «AVA Супермаркет» 3-босқич — «Харид режаси» ва «Аналитика» (эга 2026-11-21). Матнлар — Кирилл (админ конвенцияси).
// Тизим ҳеч нарса сотиб олмайди ва таъминотчига мурожаат қилмайди — фақат ҳисоблайди. Барча рақамлар серверда
// (`adminSupermarketProcurementReport`, `adminSupermarketStats`); захира % ва CSV — фақат шу экранда.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../services/admin_supermarket_service.dart';

typedef SmSaveFile = Future<void> Function(String fileName, Uint8List bytes);

Future<void> _shareCsv(String name, Uint8List bytes) =>
    Share.shareXFiles([XFile.fromData(bytes, name: name, mimeType: 'text/csv')], fileNameOverrides: [name]);

// ─── Харид режаси ─────────────────────────────────────────────────────────

class SmProcurementAdminTab extends StatefulWidget {
  const SmProcurementAdminTab({super.key, required this.service, this.saveFile, this.today});

  final AdminSupermarketService service;

  /// Тест учун; бўлмаса — [Share.shareXFiles] (вебда юклаб олиш).
  final SmSaveFile? saveFile;

  /// Тест учун (Тошкент бўйича бугун).
  final DateTime? today;

  @override
  State<SmProcurementAdminTab> createState() => _SmProcurementAdminTabState();
}

class _SmProcurementAdminTabState extends State<SmProcurementAdminTab> {
  late final DateTime _today = widget.today ?? smTashkentToday();
  late DateTime _date = _today.add(const Duration(days: 1)); // сукут — эртага (харид кечқурун режалаштирилади)
  final _reserve = TextEditingController(text: '10');
  SmProcurementReport? _report;
  String? _error;
  bool _loading = false;

  int get _reservePct => (int.tryParse(_reserve.text.trim()) ?? 0).clamp(0, 500);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reserve.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.service.procurementReport(smDateKey(_date));
      if (mounted) setState(() => _report = r);
    } catch (e) {
      debugPrint('[SmProcurement] load failed: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setDate(DateTime d) {
    if (d == _date) return;
    setState(() => _date = d);
    _load();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today.subtract(const Duration(days: 30)),
      lastDate: _today.add(const Duration(days: 30)),
    );
    if (d != null) _setDate(DateTime.utc(d.year, d.month, d.day));
  }

  Future<void> _export() async {
    final r = _report;
    if (r == null) return;
    final bytes = Uint8List.fromList(utf8.encode(smProcurementCsv(r, _reservePct)));
    try {
      await (widget.saveFile ?? _shareCsv)('ava_supermarket_harid_${r.date}.csv', bytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'CSV сақлаб бўлмади: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tomorrow = _today.add(const Duration(days: 1));
    final r = _report;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Card(
          key: ValueKey('sm_proc_note'),
          color: Color(0xFFFFF3E0),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Тизим харид қилмайди, фақат ҳисоблайди. Таъминотчиларга ҳеч нарса юборилмайди.',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChoiceChip(
            key: const ValueKey('sm_proc_today'),
            label: const Text('Бугун'),
            selected: _date == _today,
            onSelected: (_) => _setDate(_today),
          ),
          ChoiceChip(
            key: const ValueKey('sm_proc_tomorrow'),
            label: const Text('Эртага'),
            selected: _date == tomorrow,
            onSelected: (_) => _setDate(tomorrow),
          ),
          OutlinedButton.icon(
            key: const ValueKey('sm_proc_date'),
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(smDateKey(_date)),
          ),
          SizedBox(
            width: 170,
            child: TextField(
              key: const ValueKey('sm_proc_reserve'),
              controller: _reserve,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Хавфсизлик захираси %', border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(tooltip: 'Янгилаш', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          FilledButton.icon(
            key: const ValueKey('sm_proc_csv'),
            onPressed: r == null || r.offers.isEmpty ? null : _export,
            icon: const Icon(Icons.download),
            label: const Text('CSV'),
          ),
        ]),
        const SizedBox(height: 8),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Text(_error!, key: const ValueKey('sm_proc_error'), style: const TextStyle(color: Colors.red)),
        if (!_loading && r != null) ..._body(r),
      ],
    );
  }

  List<Widget> _body(SmProcurementReport r) {
    final pct = _reservePct;
    return [
      Text(
        'Сана: ${r.date} · тўланган буюртмалар (янги/қабул қилинган): ${r.orderCount} · таклифлар: ${r.offers.length}',
        key: const ValueKey('sm_proc_summary'),
      ),
      if (r.stockIsNetOfReservations)
        const Text(
          '«Қолдиқ» — сотилмаган қолдиқ (буюртма берилганда сервер уни камайтиради).',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      if (r.truncated)
        const Text('Диққат: буюртмалар жуда кўп — рўйхат тўлиқ эмас (3000 гача).', style: TextStyle(color: Colors.red)),
      if (r.offers.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Бу сана учун харид керак эмас'))),
      for (final e in r.byCategory().entries) ...[
        const SizedBox(height: 12),
        Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            columns: const [
              DataColumn(label: Text('Гуруҳ')),
              DataColumn(label: Text('Таклиф')),
              DataColumn(label: Text('Бирлик')),
              DataColumn(label: Text('Талаб'), numeric: true),
              DataColumn(label: Text('Қолдиқ'), numeric: true),
              DataColumn(label: Text('Етишмайди'), numeric: true),
              DataColumn(label: Text('Тавсия харид'), numeric: true),
              DataColumn(label: Text('Буюртмалар'), numeric: true),
            ],
            rows: [
              for (final o in e.value)
                DataRow(key: ValueKey('sm_proc_row_${o.productId}'), cells: [
                  DataCell(Text(o.groupName)),
                  DataCell(Text([o.name, if (o.varietyName.isNotEmpty) '(${o.varietyName})', if (o.packLabel != null) o.packLabel!]
                      .join(' '))),
                  DataCell(Text('${smUnitTextRu[o.unit] ?? o.unit}${o.weighed ? ' ⚖' : ''}')),
                  DataCell(Text(smReportQty(o.demandQty))),
                  DataCell(Text(o.stock == null ? '—' : smReportQty(o.stock!))),
                  DataCell(Text(smReportQty(o.shortfall),
                      style: TextStyle(color: o.shortfall > 0 ? Colors.red : null, fontWeight: o.shortfall > 0 ? FontWeight.w600 : null))),
                  DataCell(Text(
                    '${smSuggestedPurchase(shortfall: o.shortfall, demand: o.demandQty, reservePercent: pct)}',
                    key: ValueKey('sm_proc_suggest_${o.productId}'),
                  )),
                  DataCell(Text('${o.orderCount}')),
                ]),
            ],
          ),
        ),
      ],
    ];
  }
}

// ─── Аналитика ────────────────────────────────────────────────────────────

const _originText = <String, String>{
  'catalog': 'Каталог',
  'quick': 'Тезкор харид',
  'weekly': 'Ҳафталик сават',
  'reorder': 'Қайта буюртма',
  'unknown': 'Номаълум (эски)',
};

class SmAnalyticsAdminTab extends StatefulWidget {
  const SmAnalyticsAdminTab({super.key, required this.service, this.today});

  final AdminSupermarketService service;
  final DateTime? today;

  @override
  State<SmAnalyticsAdminTab> createState() => _SmAnalyticsAdminTabState();
}

class _SmAnalyticsAdminTabState extends State<SmAnalyticsAdminTab> {
  late final DateTime _today = widget.today ?? smTashkentToday();
  late DateTime _to = _today.subtract(const Duration(days: 1));
  late DateTime _from = _to.subtract(const Duration(days: 6));
  SmStatsReport? _report;
  Map<String, String> _groupNames = const {};
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool backfill = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.service.stats(from: smDateKey(_from), to: smDateKey(_to), backfill: backfill);
      Map<String, String> names = _groupNames;
      if (names.isEmpty) {
        try {
          final tx = await widget.service.loadTaxonomyRaw();
          names = {
            for (final c in (tx?['categories'] as List? ?? const []))
              if (c is Map)
                for (final g in (c['groups'] as List? ?? const []))
                  if (g is Map && g['names'] is Map) '${g['id']}': '${(g['names'] as Map)['uz_Cyrl'] ?? g['id']}',
          };
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _report = r;
          _groupNames = names;
        });
      }
    } catch (e) {
      debugPrint('[SmAnalytics] load failed: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: _today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null) return;
    final from = DateTime.utc(r.start.year, r.start.month, r.start.day);
    final to = DateTime.utc(r.end.year, r.end.month, r.end.day);
    if (to.difference(from).inDays + 1 > 92) {
      setState(() => _error = 'Оралиқ 92 кундан ошмасин');
      return;
    }
    setState(() {
      _from = from;
      _to = to;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            key: const ValueKey('sm_stats_range'),
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            label: Text('${smDateKey(_from)} — ${smDateKey(_to)}'),
          ),
          IconButton(tooltip: 'Янгилаш', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          if (r != null && r.missing.isNotEmpty)
            TextButton.icon(
              key: const ValueKey('sm_stats_backfill'),
              onPressed: _loading ? null : () => _load(backfill: true),
              icon: const Icon(Icons.calculate_outlined),
              label: Text('Етишмаган кунларни ҳисоблаш (${r.missing.length}, бир марта 7 тагача)'),
            ),
        ]),
        const SizedBox(height: 8),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Text(_error!, key: const ValueKey('sm_stats_error'), style: const TextStyle(color: Colors.red)),
        if (!_loading && r != null) ..._body(r),
      ],
    );
  }

  Widget _tile(String key, String label, String value, {Color? color, String? hint}) => SizedBox(
        width: 190,
        child: Card(
          key: ValueKey('sm_kpi_$key'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              if (hint != null) Text(hint, style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ]),
          ),
        ),
      );

  static String _money(int? v) => v == null ? 'маълум эмас' : formatMoney(v);
  static Color? _netColor(int? v) => v != null && v < 0 ? Colors.red : null;

  List<Widget> _body(SmStatsReport r) {
    final net = r.netLogistics;
    final origin = r.byOrigin;
    return [
      if (r.missing.isNotEmpty)
        Text('Ҳисобланмаган кунлар: ${r.missing.join(', ')}',
            key: const ValueKey('sm_stats_missing'), style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 8),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _tile('orders', 'Буюртмалар', '${r.sumOf('orders')}'),
        _tile('delivered', 'Етказилди', '${r.sumOf('delivered')}'),
        _tile('cancelled', 'Бекор / рад', '${r.sumOf('cancelled')}'),
        _tile('gmv', 'Товар айланмаси (GMV)', formatMoney(r.sumOf('gmv'))),
        _tile('fee', 'Етказиш ҳақи (тушум)', formatMoney(r.sumOf('deliveryFeeRevenue'))),
        _tile('payout', 'Курьерга тўлов', _money(r.courierPayout),
            hint: r.courierPayout == null ? 'Платформа буюртмаси учун курьер тўлови майдони йўқ' : null),
        _tile('net', 'Соф логистика (ҳақ − курьер)', _money(net),
            color: _netColor(net), hint: net != null && net < 0 ? 'Етказиш зарар қилмоқда' : null),
        _tile('refunds', 'Қайтимлар', formatMoney(r.sumOf('refundsTotal'))),
        _tile('avg', 'Ўртача сават', formatMoney(r.sumOf('avgBasket'))),
        _tile('reminders', 'Эслатмали ҳафталик рўйхатлар', r.listsWithReminders == null ? '—' : '${r.listsWithReminders}'),
        _tile('weekly', 'Ҳафталик сават орқали буюртма', '${r.sumOf('weeklyOrders')}'),
      ]),
      const SizedBox(height: 12),
      const Text('Кунлар бўйича', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Сана')),
            DataColumn(label: Text('Буюртма'), numeric: true),
            DataColumn(label: Text('Етказилди'), numeric: true),
            DataColumn(label: Text('Бекор'), numeric: true),
            DataColumn(label: Text('GMV'), numeric: true),
            DataColumn(label: Text('Етказиш ҳақи'), numeric: true),
            DataColumn(label: Text('Курьер'), numeric: true),
            DataColumn(label: Text('Соф логистика'), numeric: true),
            DataColumn(label: Text('Қайтим'), numeric: true),
            DataColumn(label: Text('Ўрт. сават'), numeric: true),
            DataColumn(label: Text('Мижоз'), numeric: true),
            DataColumn(label: Text('Такрорий'), numeric: true),
          ],
          rows: [
            for (final d in r.days)
              DataRow(cells: [
                DataCell(Text(d.partial ? '${d.date} (тугамаган)' : d.date, key: ValueKey('sm_stats_day_${d.date}'))),
                DataCell(Text('${d.orders}')),
                DataCell(Text('${d.delivered}')),
                DataCell(Text('${d.cancelled}')),
                DataCell(Text(formatMoney(d.gmv))),
                DataCell(Text(formatMoney(d.deliveryFeeRevenue))),
                DataCell(Text(d.courierPayout == null ? '—' : formatMoney(d.courierPayout!))),
                DataCell(Text(d.netLogistics == null ? '—' : formatMoney(d.netLogistics!),
                    key: ValueKey('sm_stats_net_${d.date}'), style: TextStyle(color: _netColor(d.netLogistics)))),
                DataCell(Text(formatMoney(d.refundsTotal))),
                DataCell(Text(formatMoney(d.avgBasket))),
                DataCell(Text('${d.uniqueCustomers}')),
                DataCell(Text('${d.repeatCustomers}')),
              ]),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text('Буюртма манбаи', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Wrap(spacing: 8, children: [
        for (final k in _originText.keys)
          Chip(key: ValueKey('sm_origin_$k'), label: Text('${_originText[k]}: ${origin[k] ?? 0}')),
      ]),
      const SizedBox(height: 12),
      const Text('Энг кўп сотилган гуруҳлар', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      for (final g in r.topGroups())
        ListTile(
          key: ValueKey('sm_top_${g.groupId}'),
          dense: true,
          title: Text(_groupNames[g.groupId] ?? g.groupId),
          subtitle: Text([
            for (final e in g.qty.entries) '${smReportQty(e.value)} ${smUnitTextRu[e.key] ?? e.key}',
            '${g.lines} қатор',
          ].join(' · ')),
          trailing: Text(formatMoney(g.sum)),
        ),
    ];
  }
}
