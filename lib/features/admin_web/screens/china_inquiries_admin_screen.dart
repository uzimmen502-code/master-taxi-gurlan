import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Хитой бозори — «Сўров қолдириш» админ қисми (ega qarori 2026-10-20, variant A).
///
/// Оператор: сўровни кўради → хитойча матн тайёрлайди → ҳар таъминотчига АВАнинг
/// WeChat'идан ҚЎЛДА юборади ва «Юборилди» деб белгилайди → жавобни киритади.
/// Бутун ёзув серверда (`functions/china_inquiries.js`: `admin*China*`); бу экран
/// фақат чақиради ва ўқийди (`firestore.rules`да ёзув ёпиқ). Босқич — `china_inquiry_config/main`.
class ChinaInquiriesAdminScreen extends StatefulWidget {
  const ChinaInquiriesAdminScreen({super.key});

  @override
  State<ChinaInquiriesAdminScreen> createState() =>
      _ChinaInquiriesAdminScreenState();
}

class _ChinaInquiriesAdminScreenState extends State<ChinaInquiriesAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Сўровлар'),
              Tab(text: 'Таъминотчилар'),
              Tab(text: 'Созлама'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _InquiriesTab(),
              _SuppliersTab(),
              _ConfigTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Умумий ёрдамчилар ─────────────────────────

/// Сервер callable'ини чақиради; хатони фойдаланувчига матн + диагностик код билан кўрсатади (25-қоида).
Future<Map<String, dynamic>?> _callChina(
  BuildContext context,
  String name,
  Map<String, Object?> data,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final res = await FirebaseFunctions.instance.httpsCallable(name).call<Object?>(data);
    final out = res.data;
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  } on FirebaseFunctionsException catch (e) {
    final details = e.details;
    final code = details is Map && details['code'] != null ? '${details['code']}' : e.code;
    messenger?.showSnackBar(SnackBar(
      backgroundColor: Colors.red.shade700,
      content: Text('${_errorText(code)} ($code)'),
    ));
  } catch (e) {
    debugPrint('[ChinaInquiriesAdmin] $name $e');
    messenger?.showSnackBar(SnackBar(
      backgroundColor: Colors.red.shade700,
      content: const Text('Амални бажариб бўлмади. Қайта уриниб кўринг.'),
    ));
  }
  return null;
}

String _errorText(String code) {
  switch (code) {
    case 'TEXT_ZH_REQUIRED':
      return 'Аввал хитойча матнни сақланг';
    case 'SUPPLIER_INACTIVE':
      return 'Таъминотчи фаол эмас';
    case 'NOT_DISPATCHED':
      return 'Бу таъминотчига ҳали «Юборилди» белгиланмаган';
    case 'INVALID_TRANSITION':
      return 'Сўров бу ҳолатда бу амални қабул қилмайди';
    case 'PRICE_INVALID':
      return 'Нарх нотўғри';
    case 'CURRENCY_INVALID':
      return 'Валюта нотўғри';
    case 'MOQ_INVALID':
      return 'Минимал миқдор нотўғри';
    case 'LEAD_TIME_INVALID':
      return 'Етказиш муддати нотўғри';
    case 'REASON_REQUIRED':
      return 'Сабабни ёзинг';
    case 'TESTERS_INVALID':
      return 'Тестер рақамлари нотўғри (12 хонали, 998…)';
    case 'TOO_MANY_QUOTES':
      return 'Бу сўровга таклифлар чегараси тўлди';
    case 'permission-denied':
      return 'Бу амал фақат админ учун';
    default:
      return 'Амални бажариб бўлмади';
  }
}

/// Пулни `double`сиз бутун минор бирликка ўгиради (8-қоида): «38» → 3800, «38.5» → 3850,
/// «38.50» → 3850. Нотўғри (3+ хона, ҳарф, манфий, бўш) → null.
int? parsePriceMinor(String input) {
  final s = input.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,10})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final minor = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return minor >= 1 ? minor : null;
}

String formatPriceMinor(int minor) {
  final whole = minor ~/ 100;
  final frac = (minor % 100).toString().padLeft(2, '0');
  return '$whole.$frac';
}

String _fmtTime(Object? v) {
  if (v is! Timestamp) return '—';
  final d = v.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

const _statusLabels = <String, String>{
  'new': 'Янги',
  'sent': 'Юборилган',
  'quoted': 'Таклиф келган',
  'closed': 'Ёпилган',
  'cancelled': 'Бекор қилинган',
};

Color _statusColor(String s) {
  switch (s) {
    case 'new':
      return Colors.orange.shade800;
    case 'sent':
      return Colors.blue.shade700;
    case 'quoted':
      return Colors.green.shade700;
    default:
      return Colors.grey.shade600;
  }
}

Future<String?> _askReason(BuildContext context, String title) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 300,
        decoration: const InputDecoration(labelText: 'Сабаби'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Тасдиқлаш'),
        ),
      ],
    ),
  );
}

// ───────────────────────── Сўровлар ─────────────────────────

class _InquiriesTab extends StatefulWidget {
  const _InquiriesTab();

  @override
  State<_InquiriesTab> createState() => _InquiriesTabState();
}

class _InquiriesTabState extends State<_InquiriesTab> {
  String _filter = 'open';

  // Бир марта очилади (setState филтрда listener қайта очилмасин); чекланган сўров (36-қоида).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = FirebaseFirestore
      .instance
      .collection('china_inquiries')
      .orderBy('updatedAt', descending: true)
      .limit(100)
      .snapshots();

  bool _matches(String status) {
    switch (_filter) {
      case 'open':
        return status == 'new' || status == 'sent' || status == 'quoted';
      case 'all':
        return true;
      default:
        return status == _filter;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in const {
                'open': 'Очиқ',
                'new': 'Янги',
                'sent': 'Юборилган',
                'quoted': 'Таклиф келган',
                'closed': 'Ёпилган',
                'all': 'Ҳаммаси',
              }.entries)
                ChoiceChip(
                  label: Text(f.value),
                  selected: _filter == f.key,
                  onSelected: (_) => setState(() => _filter = f.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('Рўйхатни юклаб бўлмади. Қайта уриниб кўринг.'));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs
                  .where((d) => _matches('${d.data()['status']}'))
                  .toList();
              if (docs.isEmpty) return const Center(child: Text('Сўровлар йўқ'));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final status = '${d['status']}';
                  return Card(
                    child: ListTile(
                      title: Text('${d['refNo']}  ·  ${d['text']}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_statusLabels[status] ?? status}'
                        '${(d['quoteCount'] ?? 0) > 0 ? ' · таклиф: ${d['quoteCount']}' : ''}'
                        ' · ${_fmtTime(d['createdAt'])}',
                        style: TextStyle(color: _statusColor(status)),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => _InquiryDialog(inquiryId: docs[i].id),
                      ),
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

class _InquiryDialog extends StatefulWidget {
  const _InquiryDialog({required this.inquiryId});

  final String inquiryId;

  @override
  State<_InquiryDialog> createState() => _InquiryDialogState();
}

class _InquiryDialogState extends State<_InquiryDialog> {
  final _textZh = TextEditingController();
  bool _textZhLoaded = false;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('china_inquiries').doc(widget.inquiryId);

  @override
  void dispose() {
    _textZh.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>?> Function() action, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null && ok != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(ok)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _ref.snapshots(),
          builder: (context, snap) {
            final d = snap.data?.data();
            if (d == null) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            if (!_textZhLoaded) {
              _textZh.text = '${d['textZh'] ?? ''}';
              _textZhLoaded = true;
            }
            final status = '${d['status']}';
            final open = status == 'new' || status == 'sent' || status == 'quoted';
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('${d['refNo']} · ${_statusLabels[status] ?? status}',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 8),
                SelectableText('${d['text']}'),
                if ('${d['quantity'] ?? ''}'.isNotEmpty) Text('Миқдор: ${d['quantity']}'),
                if ('${d['productId'] ?? ''}'.isNotEmpty) Text('Маҳсулот ID: ${d['productId']}'),
                Text('Мижоз: ${d['ownerId']}', style: const TextStyle(color: Colors.black54)),
                const Divider(height: 28),
                Text('Хитойча матн (таъминотчига юбориладиган)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                TextField(
                  controller: _textZh,
                  enabled: open && !_busy,
                  maxLines: 5,
                  maxLength: 1500,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: open && !_busy
                        ? () => _run(
                              () => _callChina(context, 'adminSetChinaInquiryTextZh',
                                  {'inquiryId': widget.inquiryId, 'textZh': _textZh.text}),
                              ok: 'Матн сақланди',
                            )
                        : null,
                    child: const Text('Матнни сақлаш'),
                  ),
                ),
                const Divider(height: 28),
                _DispatchSection(
                  inquiryId: widget.inquiryId,
                  inquiry: d,
                  open: open,
                  busy: _busy,
                  run: _run,
                ),
                const Divider(height: 28),
                _QuotesSection(
                  inquiryId: widget.inquiryId,
                  open: open,
                  busy: _busy,
                  run: _run,
                ),
                const Divider(height: 28),
                if (open)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final reason = await _askReason(context, 'Сўровни ёпиш');
                              if (reason == null || !context.mounted) return;
                              await _run(
                                () => _callChina(context, 'adminCloseChinaInquiry',
                                    {'inquiryId': widget.inquiryId, 'reason': reason}),
                                ok: 'Сўров ёпилди',
                              );
                            },
                      child: const Text('Сўровни ёпиш'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

typedef _Runner = Future<void> Function(
  Future<Map<String, dynamic>?> Function() action, {
  String? ok,
});

/// Таъминотчилар: нусхалаш (матн) ва ҳақиқий юборилгандан кейин «Юборилди» белгиси —
/// икки алоҳида тугма: оператор юбормасдан белгилаб қўймасин.
class _DispatchSection extends StatelessWidget {
  const _DispatchSection({
    required this.inquiryId,
    required this.inquiry,
    required this.open,
    required this.busy,
    required this.run,
  });

  final String inquiryId;
  final Map<String, dynamic> inquiry;
  final bool open;
  final bool busy;
  final _Runner run;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('china_inquiries').doc(inquiryId);
    final textZh = '${inquiry['textZh'] ?? ''}';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('china_suppliers')
          .orderBy('displayName')
          .limit(200)
          .snapshots(),
      builder: (context, supSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ref.collection('dispatches').snapshots(),
          builder: (context, dispSnap) {
            final sent = {
              for (final d in dispSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                d.id: d.data(),
            };
            final sups = (supSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => d.data()['active'] == true || sent.containsKey(d.id))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Таъминотчиларга юбориш', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (sups.isEmpty)
                  const Text('Фаол таъминотчи йўқ — «Таъминотчилар» табида қўшинг.'),
                for (final s in sups)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${s.data()['displayName']}'
                        '${'${s.data()['wechatId'] ?? ''}'.isNotEmpty ? '  (${s.data()['wechatId']})' : ''}'),
                    subtitle: sent.containsKey(s.id)
                        ? Text('Юборилган: ${_fmtTime(sent[s.id]!['sentAt'])}',
                            style: TextStyle(color: Colors.green.shade700))
                        : null,
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip: 'Матнни нусхалаш',
                        icon: const Icon(Icons.copy),
                        onPressed: textZh.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: textZh));
                                if (context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                      const SnackBar(content: Text('Нусхаланди — WeChat\'га юборинг')));
                                }
                              },
                      ),
                      if (!sent.containsKey(s.id))
                        FilledButton.tonal(
                          onPressed: open && !busy && textZh.isNotEmpty
                              ? () => run(
                                    () => _callChina(context, 'adminMarkChinaInquirySent',
                                        {'inquiryId': inquiryId, 'supplierId': s.id}),
                                    ok: 'Юборилди деб белгиланди',
                                  )
                              : null,
                          child: const Text('Юборилди'),
                        ),
                    ]),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _QuotesSection extends StatelessWidget {
  const _QuotesSection({
    required this.inquiryId,
    required this.open,
    required this.busy,
    required this.run,
  });

  final String inquiryId;
  final bool open;
  final bool busy;
  final _Runner run;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('china_inquiries').doc(inquiryId);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.collection('quotes').orderBy('createdAt').limit(50).snapshots(),
      builder: (context, snap) {
        final quotes = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Таклифлар', style: Theme.of(context).textTheme.titleSmall)),
              FilledButton.icon(
                onPressed: open && !busy
                    ? () => showDialog<void>(
                          context: context,
                          builder: (_) => _AddQuoteDialog(inquiryId: inquiryId, run: run),
                        )
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Таклиф киритиш'),
              ),
            ]),
            if (quotes.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Ҳали йўқ')),
            for (final q in quotes)
              Builder(builder: (context) {
                final d = q.data();
                final withdrawn = d['withdrawn'] == true;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${d['supplierName']}: ${formatPriceMinor((d['priceMinor'] as num).toInt())} ${d['currency']}'
                    '${d['minOrderQty'] != null ? ' · мин. ${d['minOrderQty']}' : ''}'
                    '${d['leadTimeDays'] != null ? ' · ${d['leadTimeDays']} кун' : ''}',
                    style: withdrawn
                        ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.black45)
                        : null,
                  ),
                  subtitle: Text([
                    if ('${d['customerNote'] ?? ''}'.isNotEmpty) 'Мижозга: ${d['customerNote']}',
                    if ('${d['internalNote'] ?? ''}'.isNotEmpty) 'Ички: ${d['internalNote']}',
                    if (withdrawn) 'Қайтариб олинган',
                  ].join('\n')),
                  trailing: withdrawn || !open
                      ? null
                      : TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final reason = await _askReason(context, 'Таклифни қайтариб олиш');
                                  if (reason == null || !context.mounted) return;
                                  await run(
                                    () => _callChina(context, 'adminWithdrawChinaQuote',
                                        {'inquiryId': inquiryId, 'quoteId': q.id, 'reason': reason}),
                                    ok: 'Таклиф қайтариб олинди',
                                  );
                                },
                          child: const Text('Қайтариб олиш'),
                        ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _AddQuoteDialog extends StatefulWidget {
  const _AddQuoteDialog({required this.inquiryId, required this.run});

  final String inquiryId;
  final _Runner run;

  @override
  State<_AddQuoteDialog> createState() => _AddQuoteDialogState();
}

class _AddQuoteDialogState extends State<_AddQuoteDialog> {
  final _price = TextEditingController();
  final _moq = TextEditingController();
  final _lead = TextEditingController();
  final _customerNote = TextEditingController();
  final _internalNote = TextEditingController();
  String? _supplierId;
  String _currency = 'USD';
  String? _error;
  // Қайта босилса ҲАМ бир хил таклиф (идемпотент калит) — дубликат ёзилмайди.
  final String _requestId = 'q${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    for (final c in [_price, _moq, _lead, _customerNote, _internalNote]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _optInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('china_inquiries')
        .doc(widget.inquiryId)
        .collection('dispatches');
    return AlertDialog(
      title: const Text('Таклиф киритиш'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ref.snapshots(),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _supplierId,
                    decoration: const InputDecoration(labelText: 'Таъминотчи (юборилганлар)'),
                    items: [
                      for (final d in docs)
                        DropdownMenuItem(value: d.id, child: Text('${d.data()['supplierName']}')),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  );
                },
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Нарх (бирлик учун), масалан 38.50'),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _currency,
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'CNY', child: Text('CNY')),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                ),
              ]),
              TextField(
                controller: _moq,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Минимал буюртма миқдори (ихтиёрий)'),
              ),
              TextField(
                controller: _lead,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Етказиш муддати, кун (ихтиёрий)'),
              ),
              TextField(
                controller: _customerNote,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Мижозга кўринадиган изоҳ'),
              ),
              TextField(
                controller: _internalNote,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Ички изоҳ (мижоз кўрмайди)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: () async {
            final minor = parsePriceMinor(_price.text);
            if (_supplierId == null) {
              setState(() => _error = 'Таъминотчини танланг');
              return;
            }
            if (minor == null) {
              setState(() => _error = 'Нархни тўғри киритинг (кўпи билан 2 хонали каср)');
              return;
            }
            final moq = _optInt(_moq.text);
            final lead = _optInt(_lead.text);
            if ((_moq.text.trim().isNotEmpty && moq == null) ||
                (_lead.text.trim().isNotEmpty && lead == null)) {
              setState(() => _error = 'Миқдор ва муддат бутун сон бўлсин');
              return;
            }
            Navigator.pop(context);
            await widget.run(
              () => _callChina(context, 'adminAddChinaQuote', {
                'inquiryId': widget.inquiryId,
                'supplierId': _supplierId,
                'priceMinor': minor,
                'currency': _currency,
                'minOrderQty': moq,
                'leadTimeDays': lead,
                'customerNote': _customerNote.text,
                'internalNote': _internalNote.text,
                'clientRequestId': _requestId,
              }),
              ok: 'Таклиф киритилди, мижозга хабар кетди',
            );
          },
          child: const Text('Киритиш'),
        ),
      ],
    );
  }
}

// ───────────────────────── Таъминотчилар ─────────────────────────

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _SupplierDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Таъминотчи қўшиш'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('china_suppliers')
            .orderBy('displayName')
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Рўйхатни юклаб бўлмади. Қайта уриниб кўринг.'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Таъминотчилар йўқ'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final active = d['active'] == true;
              return Card(
                child: ListTile(
                  title: Text('${d['displayName']}'),
                  subtitle: Text([
                    if ('${d['wechatId'] ?? ''}'.isNotEmpty) 'WeChat: ${d['wechatId']}',
                    if ('${d['note'] ?? ''}'.isNotEmpty) '${d['note']}',
                    active ? 'Фаол' : 'Фаол эмас',
                  ].join(' · ')),
                  trailing: const Icon(Icons.edit),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _SupplierDialog(supplierId: docs[i].id, initial: d),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({this.supplierId, this.initial});

  final String? supplierId;
  final Map<String, dynamic>? initial;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  late final _name = TextEditingController(text: '${widget.initial?['displayName'] ?? ''}');
  late final _wechat = TextEditingController(text: '${widget.initial?['wechatId'] ?? ''}');
  late final _note = TextEditingController(text: '${widget.initial?['note'] ?? ''}');
  late bool _active = widget.initial == null ? true : widget.initial!['active'] == true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _wechat.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.supplierId == null ? 'Таъминотчи қўшиш' : 'Таъминотчини таҳрирлаш'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Ном (мижозга кўринмайди)'),
            ),
            TextField(
              controller: _wechat,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'WeChat ID (ихтиёрий)'),
            ),
            TextField(
              controller: _note,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Изоҳ (қайси маҳсулотлар, тил…)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Фаол'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final res = await _callChina(context, 'adminUpsertChinaSupplier', {
                    if (widget.supplierId != null) 'supplierId': widget.supplierId,
                    'displayName': _name.text,
                    'wechatId': _wechat.text,
                    'note': _note.text,
                    'active': _active,
                  });
                  if (!context.mounted) return;
                  if (res != null) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _busy = false);
                  }
                },
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}

// ───────────────────────── Созлама (босқич) ─────────────────────────

class _ConfigTab extends StatefulWidget {
  const _ConfigTab();

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  final _testers = TextEditingController();
  String _stage = 'off';
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _testers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('china_inquiry_config/main').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Созламани юклаб бўлмади. Қайта уриниб кўринг.'));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!.data() ?? const <String, dynamic>{};
        if (!_loaded) {
          _stage = '${d['stage'] ?? 'off'}';
          _testers.text = (d['testerIds'] is List ? (d['testerIds'] as List).join('\n') : '');
          _loaded = true;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Версия: ${d['version'] ?? 0}  ·  охирги ўзгартирган: ${d['updatedBy'] ?? '—'}'
                '  ·  ${_fmtTime(d['updatedAt'])}'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _stage,
              decoration: const InputDecoration(labelText: 'Босқич'),
              items: const [
                DropdownMenuItem(value: 'off', child: Text('OFF — ҳеч кимга')),
                DropdownMenuItem(value: 'internal', child: Text('INTERNAL — фақат тестерларга')),
                DropdownMenuItem(value: 'public', child: Text('PUBLIC — ҳаммага')),
              ],
              onChanged: (v) => setState(() => _stage = v ?? 'off'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _testers,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Тестерлар (ҳар қаторда битта рақам, 998XXXXXXXXX)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final reason = await _askReason(context, 'Созламани сақлаш');
                        if (reason == null || !context.mounted) return;
                        setState(() => _busy = true);
                        final ids = _testers.text
                            .split(RegExp(r'[\s,;]+'))
                            .where((e) => e.isNotEmpty)
                            .toList();
                        final res = await _callChina(context, 'adminSetChinaInquiryConfig', {
                          'stage': _stage,
                          'testerIds': ids,
                          'reason': reason,
                        });
                        if (!context.mounted) return;
                        setState(() => _busy = false);
                        if (res != null) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                              content: Text(res['changed'] == true
                                  ? 'Сақланди (версия ${res['version']})'
                                  : 'Ўзгариш йўқ')));
                        }
                      },
                child: const Text('Сақлаш'),
              ),
            ),
          ],
        );
      },
    );
  }
}
