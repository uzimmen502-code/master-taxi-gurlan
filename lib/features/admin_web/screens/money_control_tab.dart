import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../services/admin_auth_service.dart';

/// Finance Center — «Назорат» (телефон-first пул назорати).
class MoneyControlTab extends StatefulWidget {
  const MoneyControlTab({super.key, required this.onOpenTab});

  /// Deep-link: 1=Float, 2=Settlements, 3=Journal, 4=Closing, 5=Exceptions.
  final ValueChanged<int> onOpenTab;

  @override
  State<MoneyControlTab> createState() => _MoneyControlTabState();
}

class _MoneyControlTabState extends State<MoneyControlTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getMoneyControlSnapshot')
          .call();
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(res.data as Map);
        _loading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? e.code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getMoneyControlSnapshot')
          .call();
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(res.data as Map);
        _error = null;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _snack(e.message ?? e.code, isError: true);
    } catch (e) {
      if (!mounted) return;
      _snack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Қайта')),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final pos = _map(data['positions']);
    final queues = _map(data['queues']);
    final today = _map(data['today']);
    final recon = _map(data['reconcile']);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 700;
    final kpiCross = narrow ? 2 : 3;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 12, narrow ? 12 : 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Пул назорати',
                  style: TextStyle(
                    fontSize: narrow ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Янгилаш',
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _reconcileHint(recon),
            style: TextStyle(
              fontSize: 12,
              color: _reconcileOk(recon) ? Colors.green.shade700 : Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: kpiCross,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: narrow ? 1.55 : 1.8,
            children: [
              _KpiCard(
                label: 'Касса',
                value: formatPrice(_n(pos['adminCash'])),
                color: Colors.teal,
                icon: Icons.account_balance_wallet,
              ),
              _KpiCard(
                label: 'Ҳамёнлар Σ',
                value: formatPrice(_n(pos['passengerCreditSum'])),
                color: Colors.indigo,
                icon: Icons.account_balance_wallet,
                onTap: () => widget.onOpenTab(1),
              ),
              _KpiCard(
                label: 'Эски float Σ',
                value: formatPrice(_n(pos['driverFloatSum'])),
                color: Colors.deepPurple,
                icon: Icons.history,
                subtitle: 'миграцигача',
              ),
              _KpiCard(
                label: 'Курьерда',
                value: formatPrice(_n(pos['courierCashSum'])),
                color: Colors.orange.shade800,
                icon: Icons.delivery_dining,
              ),
              _KpiCard(
                label: 'Кутилмоқда',
                value: formatPrice(_n(pos['pendingPipelineSum'])),
                color: Colors.blueGrey,
                icon: Icons.hourglass_top,
                subtitle:
                    'S ${_n(pos['pendingSettlementSum'])} · P ${_n(pos['pendingPayoutSum'])}',
              ),
              _KpiCard(
                label: 'Истиснолар',
                value: '${_n(pos['openExceptionCount'])}',
                color: Colors.red.shade700,
                icon: Icons.warning_amber,
                onTap: () => widget.onOpenTab(5),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionTitle('Ҳаракат навбатлари'),
          const SizedBox(height: 8),
          _QueueCard(
            title: 'Критик float',
            count: _list(queues['criticalFloats']).length,
            color: Colors.red,
            onHeaderTap: () => widget.onOpenTab(1),
            child: _criticalFloatList(_list(queues['criticalFloats'])),
          ),
          const SizedBox(height: 10),
          _QueueCard(
            title: 'Pending settlements',
            count: _list(queues['pendingSettlements']).length,
            color: Colors.orange,
            onHeaderTap: () => widget.onOpenTab(2),
            child: _settlementList(_list(queues['pendingSettlements'])),
          ),
          const SizedBox(height: 10),
          _QueueCard(
            title: 'Pending payouts',
            count: _list(queues['pendingPayouts']).length,
            color: Colors.deepOrange,
            child: _payoutList(_list(queues['pendingPayouts'])),
          ),
          const SizedBox(height: 10),
          _QueueCard(
            title: 'Курьер инкассацияси',
            count: _list(queues['courierCashOutstanding']).length,
            color: Colors.brown,
            trailing: TextButton.icon(
              onPressed: () => _showInkassaDialog(
                prefill: _list(queues['courierCashOutstanding']),
              ),
              icon: const Icon(Icons.move_to_inbox, size: 18),
              label: const Text('Қабул'),
            ),
            child: _courierCashList(_list(queues['courierCashOutstanding'])),
          ),
          const SizedBox(height: 10),
          _QueueCard(
            title: 'Очиқ истиснолар',
            count: _list(queues['openExceptions']).length,
            color: Colors.red.shade400,
            onHeaderTap: () => widget.onOpenTab(5),
            child: _exceptionList(_list(queues['openExceptions'])),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Бугунги оқим (${today['periodId'] ?? '—'})'),
          const SizedBox(height: 8),
          _TodayCard(today: today, narrow: narrow, onJournal: () => widget.onOpenTab(3)),
        ],
      ),
    );
  }

  String _reconcileHint(Map<String, dynamic> recon) {
    if (_reconcileOk(recon)) return 'Sverka: мувозанат ✓';
    return 'Sverka: муаммо (balanced=${recon['balanced']}, '
        'identity=${recon['identityOk']}, projection=${recon['projectionOk']})';
  }

  bool _reconcileOk(Map<String, dynamic> recon) =>
      recon['balanced'] == true &&
      recon['identityOk'] == true &&
      recon['projectionOk'] == true;

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      );

  Widget _criticalFloatList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _emptyLine('Критик float йўқ');
    return Column(
      children: rows.take(8).map((r) {
        final bal = _n(r['balance']);
        final blocked = r['blocked'] == true;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('+${r['driverUid'] ?? ''}'),
          trailing: Text(
            formatPrice(bal),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: blocked ? Colors.red : Colors.orange.shade800,
            ),
          ),
          subtitle: blocked ? const Text('Блок') : null,
        );
      }).toList(),
    );
  }

  Widget _settlementList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _emptyLine('Кутилаётган settlement йўқ');
    return Column(
      children: rows.take(8).map((r) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(formatPrice(_n(r['amount']))),
          subtitle: Text('+${r['driverUid']} → +${r['passengerUid']}',
              style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
    );
  }

  Widget _payoutList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _emptyLine('Pending payout йўқ');
    return Column(
      children: rows.take(8).map((r) {
        final id = (r['id'] ?? '').toString();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(formatPrice(_n(r['amount']))),
          subtitle: Text(
            '${r['userName'] ?? ''} +${r['userPhone'] ?? ''}'.trim(),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Тасдиқ',
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: id.isEmpty ? null : () => _confirmPayout(id),
              ),
              IconButton(
                tooltip: 'Рад',
                icon: const Icon(Icons.cancel, color: Colors.red),
                onPressed: id.isEmpty ? null : () => _rejectPayout(id),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _courierCashList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _emptyLine('Курьерда қолдиқ йўқ');
    return Column(
      children: rows.take(10).map((r) {
        final phone = (r['courierPhone'] ?? '').toString();
        final bal = _n(r['balance']);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('+$phone'),
          trailing: Text(formatPrice(bal),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => _showInkassaDialog(
            prefill: rows,
            initialPhone: phone,
            initialAmount: bal,
          ),
        );
      }).toList(),
    );
  }

  Widget _exceptionList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _emptyLine('Очиқ истисно йўқ');
    return Column(
      children: rows.take(8).map((r) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${r['type'] ?? '—'}'),
          subtitle: Text('+${r['driverUid'] ?? ''}'),
          trailing: Text(formatPrice(_n(r['balance']))),
        );
      }).toList(),
    );
  }

  Widget _emptyLine(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: TextStyle(color: Colors.grey.shade600)),
      );

  Future<void> _confirmPayout(String requestId) async {
    final auth = context.read<AdminAuthService>();
    if (auth.phone == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payout тасдиқ'),
        content: const Text('Фойдаланувчи балансидан ёзилади. Давом?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Тасдиқ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('confirmPayout').call({
        'adminPhone': auth.phone,
        'requestId': requestId,
      });
      _snack('Payout тасдиқланди');
      await _refresh();
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? e.code, isError: true);
    }
  }

  Future<void> _rejectPayout(String requestId) async {
    final auth = context.read<AdminAuthService>();
    if (auth.phone == null) return;
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payout рад'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Сабаб (ихтиёрий)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
              child: const Text('Рад этиш')),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('rejectPayout').call({
        'adminPhone': auth.phone,
        'requestId': requestId,
        if (reason.isNotEmpty) 'reason': reason,
      });
      _snack('Payout рад этилди');
      await _refresh();
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? e.code, isError: true);
    }
  }

  Future<void> _showInkassaDialog({
    required List<Map<String, dynamic>> prefill,
    String? initialPhone,
    int? initialAmount,
  }) async {
    final phoneCtrl = TextEditingController(text: initialPhone ?? '');
    final amountCtrl = TextEditingController(
      text: initialAmount != null && initialAmount > 0
          ? '$initialAmount'
          : '',
    );
    String? selected = initialPhone;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Курьер нақдини қабул'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (prefill.isNotEmpty)
                      DropdownMenu<String>(
                        initialSelection: selected != null &&
                                prefill.any((e) =>
                                    '${e['courierPhone']}' == selected)
                            ? selected
                            : null,
                        label: const Text('Курьер (қолдиқ)'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: prefill.map((e) {
                          final p = '${e['courierPhone']}';
                          final b = _n(e['balance']);
                          return DropdownMenuEntry(
                            value: p,
                            label: '+$p — ${formatPrice(b)}',
                          );
                        }).toList(),
                        onSelected: (v) {
                          setLocal(() {
                            selected = v;
                            phoneCtrl.text = v ?? '';
                            final row = prefill.firstWhere(
                              (e) => '${e['courierPhone']}' == v,
                              orElse: () => const {},
                            );
                            final b = _n(row['balance']);
                            if (b > 0) amountCtrl.text = '$b';
                          });
                        },
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Курьер телефони',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Сумма (сўм)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Бекор'),
                ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final phone = phoneCtrl.text
                              .replaceAll(RegExp(r'\D'), '');
                          final amount = int.tryParse(amountCtrl.text
                                  .replaceAll(RegExp(r'\D'), '')) ??
                              0;
                          if (phone.length < 9 || amount <= 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Телефон ва сумма тўғри киритилсин'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setLocal(() => busy = true);
                          try {
                            final opId =
                                'ink_${DateTime.now().millisecondsSinceEpoch}_$phone';
                            final res = await FirebaseFunctions.instance
                                .httpsCallable('receiveCourierCash')
                                .call({
                              'courierPhone': phone,
                              'amount': amount,
                              'opId': opId,
                            });
                            final m =
                                Map<String, dynamic>.from(res.data as Map);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            _snack(
                              'Қабул: ${formatPrice(amount)} · қолдиқ '
                              '${formatPrice(_n(m['courierCashRemaining']))}',
                            );
                            await _refresh();
                          } on FirebaseFunctionsException catch (e) {
                            if (!ctx.mounted) return;
                            setLocal(() => busy = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(e.message ?? e.code),
                              backgroundColor: Colors.red,
                            ));
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setLocal(() => busy = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('$e'),
                              backgroundColor: Colors.red,
                            ));
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Қабул қилиш'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.title,
    required this.count,
    required this.color,
    required this.child,
    this.onHeaderTap,
    this.trailing,
  });

  final String title;
  final int count;
  final Color color;
  final Widget child;
  final VoidCallback? onHeaderTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onHeaderTap,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) trailing!,
                if (onHeaderTap != null)
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.today,
    required this.narrow,
    required this.onJournal,
  });

  final Map<String, dynamic> today;
  final bool narrow;
  final VoidCallback onJournal;

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final byKind = today['byKind'] is Map
        ? Map<String, dynamic>.from(today['byKind'] as Map)
        : <String, dynamic>{};
    final entries = byKind.entries.toList()
      ..sort((a, b) => _n(b.value).compareTo(_n(a.value)));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _chip('Оборот', formatPrice(_n(today['turnover']))),
              _chip('Field cash', formatPrice(_n(today['courierFieldCash']))),
              _chip('Инкасса', formatPrice(_n(today['courierInkassa']))),
              _chip('Ёзувлар', '${_n(today['entryCount'])}'),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text('Бугун журнал ёзуви йўқ',
                style: TextStyle(color: Colors.grey.shade600))
          else
            ...entries.take(narrow ? 8 : 12).map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      formatPrice(_n(e.value)),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onJournal,
              child: const Text('Журналга ўтиш'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$k: $v', style: const TextStyle(fontSize: 12)),
    );
  }
}
