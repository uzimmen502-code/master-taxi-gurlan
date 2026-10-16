// Кафе-ресторан созламалари: AVA ҳақи (фоиз) ва тун коэффициенти.
// Ўқиш: `settings/restaurant_delivery`; ёзув: `adminSetRestaurantFeeSettings`
// (default, us-central1; версия, audit, чегаралар — сервер).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_callable.dart';
import '../services/admin_restaurants_service.dart';
import '../utils/restaurant_fee_draft.dart';
import 'admin_reason_dialog.dart';

class RestaurantFeeCard extends StatefulWidget {
  const RestaurantFeeCard({super.key, required this.svc, this.loader});

  final AdminRestaurantsService svc;

  /// Тест учун: ҳужжатни ўқишни алмаштириш.
  final Future<Map<String, dynamic>?> Function()? loader;

  @override
  State<RestaurantFeeCard> createState() => _RestaurantFeeCardState();
}

class _RestaurantFeeCardState extends State<RestaurantFeeCard> {
  final _fee = TextEditingController();
  final _night = TextEditingController();
  RestaurantFeeCurrent _current = const RestaurantFeeCurrent();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    _night.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = widget.loader != null
          ? await widget.loader!()
          : (await FirebaseFirestore.instance.collection('settings').doc('restaurant_delivery').get()).data();
      final cur = RestaurantFeeCurrent.fromDoc(data);
      _fee.text = cur.feePercentText;
      _night.text = cur.nightCoefText;
      if (mounted) setState(() => _current = cur);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 8 : 4),
    ));
  }

  Future<void> _save() async {
    final plan = planRestaurantFeeChange(current: _current, feeText: _fee.text, nightText: _night.text);
    if (plan.errors.isNotEmpty) {
      _snack(plan.errors.join('\n'), error: true);
      return;
    }
    if (!plan.hasChange) {
      _snack('Ўзгариш йўқ');
      return;
    }
    final parts = <String>[
      if (plan.payload!.containsKey('avaFeeBps'))
        'AVA ҳақи: ${plan.payload!['avaFeeBps'] == null ? 'стандарт (${_pct(kRestaurantStandardFeeBps)} %)' : '${_pct(plan.payload!['avaFeeBps'] as int)} %'}',
      if (plan.payload!.containsKey('nightCoef')) 'тун коэффициенти: ×${plan.payload!['nightCoef']}',
    ];
    final reason = await showAdminReasonDialog(
      context,
      title: 'Созламани сақлаш',
      message: '${parts.join('\n')}\n\nЯнги ҳақ шу заҳоти ЯНГИ буюртмаларга қўлланади.',
    );
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final res = await widget.svc.setFeeSettings(plan.payload!, reason: reason);
      if (!mounted) return;
      _snack(res['unchanged'] == true ? 'Ўзгариш йўқ (сервер)' : 'Сақланди: v${res['version']}');
      await _load();
    } catch (e) {
      _snack('Хато: ${e is AdminRestaurantsException ? e.toString() : adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _pct(int bps) => bps % 100 == 0 ? '${bps ~/ 100}' : (bps / 100).toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: Text('Хато: $_error', style: TextStyle(color: Colors.red.shade700))),
            TextButton(onPressed: _load, child: const Text('Қайта')),
          ]),
        ),
      );
    }
    final feeNow = _current.avaFeeBps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ҳозир: AVA ҳақи — ${feeNow == null ? 'стандарт (${_pct(kRestaurantStandardFeeBps)} %)' : '${_pct(feeNow)} %'}'
              '${_current.nightCoef != null ? ' · тун коэффициенти ×${_current.nightCoefText}' : ''}'
              '${_current.version > 0 ? ' · v${_current.version}' : ''}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _fee,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,A-Za-zА-Яа-я]'))],
                    decoration: const InputDecoration(
                      labelText: 'AVA ҳақи, % (бўш = стандарт)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _night,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: const InputDecoration(
                      labelText: 'Тун коэф. (1..3)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Сақлаш'),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Қайта юклаш'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
