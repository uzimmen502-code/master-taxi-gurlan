// Улгуржи — «2% ҳисоботи» (10 кунлик давр) ва «Ойлик ҳисобот» (эга, 2026-11-14).
//
//   • 2% ҳисоботи — `adminGetWholesaleFeeStatement({periodStart})`: давр ичида ЕТКАЗИЛГАН ва AVA
//     улуши буюртма пайтида олинмаган (ҳозир — банк ўтказмаси) буюртмалар, сотувчи бўйича.
//     «Йиғилди деб белгилаш» — `adminMarkWholesaleFeeCollected` (фақат ёпилган давр, idempotent,
//     сумма серверда қайта ҳисобланади, audit). Пул ҳаракати ЙЎҚ — тўлов иловадан ташқарида.
//   • Ойлик ҳисобот — `adminGetWholesaleOrdersReport({month})`: сотувчи × тўлов усули.
//
// Сотувчи номи — `wholesale_sellers/{тел}.companyName` (админ ўқийди); жадвалда телефон охири.
// Экран фақат ўқийди ва чақиради (44-банд).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_callable.dart';
import '../services/admin_wholesale_orders_service.dart';
import '../utils/wholesale_fee_statement.dart';
import 'admin_reason_dialog.dart';

/// Сотувчи ID'лари → компания номи (тестда алмаштирилади). Ўқилмаса — бўш харита.
typedef WholesaleSellerNamesLoader = Future<Map<String, String>> Function(List<String> sellerIds);

Future<Map<String, String>> _loadSellerNames(List<String> ids) async {
  final db = FirebaseFirestore.instance;
  final out = <String, String>{};
  // Ҳар сотувчига 1 ўқиш (даврдаги сотувчилар — оз; 37-банд).
  final snaps = await Future.wait(ids.map((id) => db.collection('wholesale_sellers').doc(id).get()));
  for (final s in snaps) {
    final n = s.data()?['companyName'];
    if (n is String && n.trim().isNotEmpty) out[s.id] = n.trim();
  }
  return out;
}

String _sellerText(String id, Map<String, String> names) {
  final n = names[id];
  return n == null ? wholesalePhoneTail(id) : '$n · ${wholesalePhoneTail(id)}';
}

Future<void> _copyCsv(BuildContext context, String csv) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: csv));
  messenger.showSnackBar(const SnackBar(content: Text('CSV нусхаланди — Excel/Sheets га қўйинг')));
}

Widget _cell(String t, {bool bold = false, TextAlign align = TextAlign.start}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(t, textAlign: align, style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w700 : null)),
    );

Widget _notes(List<String> anomalies, bool truncated) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (truncated)
          Text('⚠ Буюртмалар жуда кўп — ҳисобот тўлиқ эмас (сервер чегараси).',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
        if (anomalies.isNotEmpty)
          Text(
            '⚠ Муҳри бузилган буюртмалар (суммага қўшилмаган, қўлда текширинг): ${anomalies.join(', ')}',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
      ],
    );

// ─── 2% ҳисоботи (10 кунлик) ─────────────────────────────────────────────

class WholesaleFeeStatementPanel extends StatefulWidget {
  const WholesaleFeeStatementPanel({super.key, required this.svc, this.now, this.sellerNames});

  final AdminWholesaleOrdersService svc;

  /// Тест учун соат.
  final DateTime Function()? now;
  final WholesaleSellerNamesLoader? sellerNames;

  @override
  State<WholesaleFeeStatementPanel> createState() => _WholesaleFeeStatementPanelState();
}

class _WholesaleFeeStatementPanelState extends State<WholesaleFeeStatementPanel> {
  late final DateTime _now = (widget.now ?? DateTime.now)();
  late final List<WholesaleFeePeriod> _periods = WholesaleFeePeriod.recent(_now);
  late WholesaleFeePeriod _period = WholesaleFeePeriod.lastClosed(_now);
  WholesaleFeeStatement? _st;
  Map<String, String> _names = const {};
  bool _loading = false;
  String? _error;
  String? _busySeller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = _period;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await widget.svc.feeStatement(p);
      var names = const <String, String>{};
      try {
        final ids = [for (final r in st.sellers) r.sellerId];
        if (ids.isNotEmpty) names = await (widget.sellerNames ?? _loadSellerNames)(ids);
      } catch (_) {
        // Ном ўқилмади — телефон охири кўрсатилади (ҳисоботга таъсир қилмайди).
      }
      if (!mounted || p != _period) return;
      setState(() {
        _st = st;
        _names = names;
      });
    } catch (e) {
      if (mounted && p == _period) setState(() => _error = adminErrorText(e));
    } finally {
      if (mounted && p == _period) setState(() => _loading = false);
    }
  }

  Future<void> _mark(WholesaleFeeStatementRow r) async {
    final note = await showAdminReasonDialog(
      context,
      title: 'Йиғилди деб белгилаш',
      message: '${_sellerText(r.sellerId, _names)} · ${_period.label}\n'
          'AVA улуши: ${wholesaleSum(r.avaFeeDue)} (${r.count} та буюртма).\n'
          'Пул ҳаракати йўқ — фақат «сотувчидан олинди» белгиси (audit). Ортга қайтарилмайди.',
      required: false,
    );
    if (note == null || !mounted) return;
    setState(() => _busySeller = r.sellerId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await widget.svc.markFeeCollected(sellerId: r.sellerId, period: _period, note: note);
      final amount = adminInt(res['avaFeeDue']);
      messenger.showSnackBar(SnackBar(
        content: Text('Белгиланди${amount != null ? ': ${wholesaleSum(amount)}' : ''}'
            '${res['idempotent'] == true ? ' (аввал белгиланган)' : ''}'),
      ));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(adminErrorText(e)), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _busySeller = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final muted = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Давр ичида етказилган, AVA улуши буюртма пайтида олинмаган буюртмалар (ҳозир — банк ўтказмаси). '
          'Даврлар: 1–10, 11–20, 21–ой охири (Тошкент вақти). «Йиғилди» — фақат ёпилган даврга.',
          style: muted,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Давр:'),
          DropdownButton<WholesaleFeePeriod>(
            key: const ValueKey('fee-period'),
            value: _period,
            items: [
              for (final p in _periods)
                DropdownMenuItem(value: p, child: Text('${p.label}${p.isClosedAt(_now) ? '' : ' (очиқ)'}')),
            ],
            onChanged: _loading
                ? null
                : (p) {
                    if (p == null || p == _period) return;
                    setState(() {
                      _period = p;
                      _st = null;
                    });
                    _load();
                  },
          ),
          IconButton(tooltip: 'Янгилаш', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          OutlinedButton.icon(
            key: const ValueKey('fee-csv'),
            onPressed: st == null ? null : () => _copyCsv(context, wholesaleFeeStatementCsv(st, names: _names)),
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('CSV нусхалаш'),
          ),
        ]),
        const SizedBox(height: 8),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Text('Хато: $_error', key: const ValueKey('fee-error'), style: TextStyle(color: Colors.red.shade700)),
        if (!_loading && st != null) ...[
          if (!st.closed)
            Text('Давр ҳали тугамаган — рақамлар ўзгариши мумкин, «Йиғилди» ўчиқ.',
                key: const ValueKey('fee-open-period'), style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800)),
          _notes(st.anomalies, st.truncated),
          const SizedBox(height: 6),
          if (st.sellers.isEmpty)
            Text('Бу даврда ҳисоботга тушадиган буюртма йўқ', style: muted)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(color: Colors.grey.shade300),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    children: [
                      _cell('Сотувчи', bold: true),
                      _cell('Буюртма', bold: true),
                      _cell('Товар суммаси', bold: true),
                      _cell('AVA улуши', bold: true),
                      _cell('Ҳолат', bold: true),
                    ],
                  ),
                  for (final r in st.sellers)
                    TableRow(children: [
                      _cell(_sellerText(r.sellerId, _names)),
                      _cell('${r.count}', align: TextAlign.end),
                      _cell(wholesaleSum(r.goodsTotal), align: TextAlign.end),
                      _cell(wholesaleSum(r.avaFeeDue), align: TextAlign.end, bold: true),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: r.isCollected
                            ? Text('✓ йиғилган', style: TextStyle(fontSize: 12.5, color: Colors.green.shade800))
                            : FilledButton.tonal(
                                key: ValueKey('fee-mark-${r.sellerId}'),
                                onPressed: !st.closed || r.avaFeeDue <= 0 || _busySeller != null ? null : () => _mark(r),
                                child: _busySeller == r.sellerId
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Йиғилди деб белгилаш'),
                              ),
                      ),
                    ]),
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    children: [
                      _cell('Жами', bold: true),
                      _cell('${st.totalCount}', bold: true, align: TextAlign.end),
                      _cell(wholesaleSum(st.totalGoods), bold: true, align: TextAlign.end),
                      _cell(wholesaleSum(st.totalDue), bold: true, align: TextAlign.end),
                      _cell(''),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// ─── Ойлик ҳисобот ───────────────────────────────────────────────────────

class WholesaleMonthlyReportPanel extends StatefulWidget {
  const WholesaleMonthlyReportPanel({super.key, required this.svc, this.now, this.sellerNames});

  final AdminWholesaleOrdersService svc;
  final DateTime Function()? now;
  final WholesaleSellerNamesLoader? sellerNames;

  @override
  State<WholesaleMonthlyReportPanel> createState() => _WholesaleMonthlyReportPanelState();
}

class _WholesaleMonthlyReportPanelState extends State<WholesaleMonthlyReportPanel> {
  late final List<String> _months = wholesaleRecentMonths((widget.now ?? DateTime.now)());

  /// Стандарт — ўтган (тугаган) ой.
  late String _month = _months.length > 1 ? _months[1] : _months.first;
  WholesaleMonthlyReport? _r;
  Map<String, String> _names = const {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = _month;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.svc.monthlyReport(m);
      var names = const <String, String>{};
      try {
        final ids = {for (final x in r.rows) x.sellerId}.toList();
        if (ids.isNotEmpty) names = await (widget.sellerNames ?? _loadSellerNames)(ids);
      } catch (_) {}
      if (!mounted || m != _month) return;
      setState(() {
        _r = r;
        _names = names;
      });
    } catch (e) {
      if (mounted && m == _month) setState(() => _error = adminErrorText(e));
    } finally {
      if (mounted && m == _month) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final muted = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Ой ичида етказилган барча буюртмалар — сотувчи × тўлов усули. AVA улуши: «ledger» — етказилганда '
          'автоматик; «ҳисобот» — 10 кунлик 2% ҳисоботи орқали сотувчидан йиғилади.',
          style: muted,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Ой:'),
          DropdownButton<String>(
            key: const ValueKey('report-month'),
            value: _month,
            items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: _loading
                ? null
                : (m) {
                    if (m == null || m == _month) return;
                    setState(() {
                      _month = m;
                      _r = null;
                    });
                    _load();
                  },
          ),
          IconButton(tooltip: 'Янгилаш', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          OutlinedButton.icon(
            key: const ValueKey('report-csv'),
            onPressed: r == null ? null : () => _copyCsv(context, wholesaleMonthlyReportCsv(r, names: _names)),
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('CSV нусхалаш'),
          ),
        ]),
        const SizedBox(height: 8),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Text('Хато: $_error', key: const ValueKey('report-error'), style: TextStyle(color: Colors.red.shade700)),
        if (!_loading && r != null) ...[
          _notes(r.anomalies, r.truncated),
          const SizedBox(height: 6),
          if (r.rows.isEmpty)
            Text('Бу ойда етказилган буюртма йўқ', style: muted)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(color: Colors.grey.shade300),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    children: [
                      _cell('Сотувчи', bold: true),
                      _cell('Тўлов усули', bold: true),
                      _cell('Буюртма', bold: true),
                      _cell('Товар суммаси', bold: true),
                      _cell('Етказиш', bold: true),
                      _cell('AVA улуши', bold: true),
                      _cell('Улуш қандай', bold: true),
                    ],
                  ),
                  for (final x in r.rows)
                    TableRow(children: [
                      _cell(_sellerText(x.sellerId, _names)),
                      _cell(wholesaleMethodLabel(x.paymentMethod)),
                      _cell('${x.count}', align: TextAlign.end),
                      _cell(wholesaleSum(x.goodsTotal), align: TextAlign.end),
                      _cell(wholesaleSum(x.deliveryFee), align: TextAlign.end),
                      _cell(wholesaleSum(x.avaFee), align: TextAlign.end),
                      _cell(x.avaFeeVia == 'statement' ? 'ҳисобот' : 'ledger'),
                    ]),
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    children: [
                      _cell('Жами', bold: true),
                      _cell(''),
                      _cell('${r.totalCount}', bold: true, align: TextAlign.end),
                      _cell(wholesaleSum(r.totalGoods), bold: true, align: TextAlign.end),
                      _cell(wholesaleSum(r.totalDelivery), bold: true, align: TextAlign.end),
                      _cell(wholesaleSum(r.totalAvaFee), bold: true, align: TextAlign.end),
                      _cell(''),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
