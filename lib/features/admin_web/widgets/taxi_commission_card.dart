import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Callable чақирувчи (тестда алмаштирилади).
typedef TaxiCommissionCaller = Future<Map<String, dynamic>> Function(
  String name,
  Map<String, dynamic> data,
);

Future<Map<String, dynamic>> _defaultCaller(
  String name,
  Map<String, dynamic> data,
) async {
  final res = await FirebaseFunctions.instance.httpsCallable(name).call(data);
  final raw = res.data;
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

/// bps → «2 %», «2.50 %» (100 bps = 1 %), бутун арифметика.
String taxiCommissionPercentText(int bps) {
  final whole = bps ~/ 100;
  final frac = bps % 100;
  if (frac == 0) return '$whole %';
  return '$whole.${frac.toString().padLeft(2, '0')} %';
}

/// Админ — шаҳарлараро такси комиссияси (`taxi_commission/current`).
///
/// Манба фақат сервер: `adminGetTaxiCommission` / `adminSetTaxiCommission`
/// (`functions/taxi_billing.js`). Қиймат — бутун bps (100 bps = 1 %),
/// `expectedVersion` билан (икки админ бир вақтда ўзгартирса — VERSION_CONFLICT),
/// сабаб audit'га ёзилади. Фақат ЯНГИ эълон қилинган сафарларга таъсир қилади:
/// эълон қилинганлари ўз `rateBps` snapshot'ида қолади.
class TaxiCommissionCard extends StatefulWidget {
  const TaxiCommissionCard({super.key, this.caller});

  final TaxiCommissionCaller? caller;

  @override
  State<TaxiCommissionCard> createState() => _TaxiCommissionCardState();
}

class _TaxiCommissionCardState extends State<TaxiCommissionCard> {
  final _bpsCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;
  int _bps = 0;
  int _version = 0;
  bool _configured = false;
  int _minBps = 0;
  int _maxBps = 10000;

  TaxiCommissionCaller get _call => widget.caller ?? _defaultCaller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bpsCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _call('adminGetTaxiCommission', const {});
      if (!mounted) return;
      setState(() {
        _bps = _int(d['bps'], 0);
        _version = _int(d['version'], 0);
        _configured = d['configured'] == true;
        _minBps = _int(d['minBps'], 0);
        _maxBps = _int(d['maxBps'], 10000);
        _bpsCtrl.text = '$_bps';
        _loading = false;
      });
    } catch (e) {
      debugPrint('[taxiCommission] load: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Комиссияни юклаб бўлмади. Қайта уриниб кўринг.';
      });
    }
  }


  Future<void> _save() async {
    final bps = int.tryParse(_bpsCtrl.text.trim());
    final reason = _reasonCtrl.text.trim();
    if (bps == null || bps < _minBps || bps > _maxBps) {
      setState(() => _error = 'bps бутун сон бўлсин: $_minBps…$_maxBps');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Ўзгартириш сабабини ёзинг');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final d = await _call('adminSetTaxiCommission', {
        'bps': bps,
        'expectedVersion': _version,
        'reason': reason,
      });
      if (!mounted) return;
      final unchanged = d['unchanged'] == true;
      setState(() {
        _saving = false;
        _bps = _int(d['bps'], bps);
        _version = _int(d['version'], _version);
        _configured = true;
        _reasonCtrl.clear();
        _notice = unchanged
            ? 'Қиймат ўзгармади (версия $_version).'
            : 'Сақланди: ${taxiCommissionPercentText(_bps)} (версия $_version). '
                'Янги сафарларга таъсир қилади.';
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[taxiCommission] save: ${e.code} ${e.message} ${e.details}');
      if (!mounted) return;
      final conflict = e.code == 'aborted' || e.message == 'VERSION_CONFLICT';
      if (conflict) await _load();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = conflict
            ? 'Бошқа админ аввалроқ ўзгартирди. Янгиланди — қайта текширинг.'
            : 'Сақлаб бўлмади. Қайта уриниб кўринг.';
      });
    } catch (e) {
      debugPrint('[taxiCommission] save: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Сақлаб бўлмади. Қайта уриниб кўринг.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Такси комиссияси (шаҳарлараро)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ҳозир: ${taxiCommissionPercentText(_bps)} ($_bps bps), версия $_version'
                    '${_configured ? '' : ' — стандарт, созланмаган'}',
                    key: const ValueKey('taxi_commission_current'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Янги сафарларга таъсир қилади; эълон қилинган сафарлар '
                    'ўз ставкасида қолади. 100 bps = 1 %.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('taxi_commission_bps'),
                    controller: _bpsCtrl,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Янги ставка (bps, $_minBps…$_maxBps)',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('taxi_commission_reason'),
                    controller: _reasonCtrl,
                    enabled: !_saving,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Сабаб (audit учун)',
                      isDense: true,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12.5),
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _notice!,
                        style: TextStyle(color: Colors.green.shade800, fontSize: 12.5),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const ValueKey('taxi_commission_save'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Сақланмоқда…' : 'Сақлаш'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
