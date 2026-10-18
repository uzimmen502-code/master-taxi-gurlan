import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../utils/realty_counts_validation.dart';

/// Админ — 🏠 Кўчмас мулк: ОБЪЕКТ СОНЛАРИ (аввал кодда қотирилган эди):
/// бепул лимит, ахборот пакети (ўлчам + нарх), профессионал режалар.
///
/// Виджет Firebase'га тегмайди: бошланғич қийматлар ташқаридан келади,
/// сақлаш — [onSave] орқали (`AdminRealtyService.saveCounts` — сервер
/// текширади ва аудитга ёзади). Шунинг учун тестланади.
class RealtyCountsEditor extends StatefulWidget {
  const RealtyCountsEditor({
    super.key,
    required this.initialFreeLimit,
    required this.initialPackages,
    required this.initialPlans,
    required this.onSave,
  });

  /// `null` — созлама йўқ (бошланғич қиймат ишлайди).
  final int? initialFreeLimit;

  /// `(ўлчам, нарх)` — амалдаги (сервер ҳисобга олган) қийматлар.
  final List<(int size, int price)> initialPackages;

  /// `(id, объект, кун, нарх)`.
  final List<(String id, int objects, int days, int price)> initialPlans;

  /// Сақлаш: хатода [StateError] (матни админга кўрсатилади).
  final Future<void> Function({
    required int? freeLimit,
    required List<Map<String, int>> packages,
    required List<Map<String, Object>> proPlans,
  }) onSave;

  @override
  State<RealtyCountsEditor> createState() => _RealtyCountsEditorState();
}

class _PkgRow {
  _PkgRow(String size, String price)
      : size = TextEditingController(text: size),
        price = TextEditingController(text: price);
  final TextEditingController size;
  final TextEditingController price;
  void dispose() {
    size.dispose();
    price.dispose();
  }
}

class _PlanRow {
  _PlanRow(String id, String objects, String days, String price)
      : id = TextEditingController(text: id),
        objects = TextEditingController(text: objects),
        days = TextEditingController(text: days),
        price = TextEditingController(text: price);
  final TextEditingController id;
  final TextEditingController objects;
  final TextEditingController days;
  final TextEditingController price;
  void dispose() {
    id.dispose();
    objects.dispose();
    days.dispose();
    price.dispose();
  }
}

class _RealtyCountsEditorState extends State<RealtyCountsEditor> {
  late final TextEditingController _free =
      TextEditingController(text: widget.initialFreeLimit?.toString() ?? '');
  late final List<_PkgRow> _pkgs = [
    for (final p in widget.initialPackages) _PkgRow('${p.$1}', '${p.$2}'),
  ];
  late final List<_PlanRow> _plans = [
    for (final p in widget.initialPlans) _PlanRow(p.$1, '${p.$2}', '${p.$3}', '${p.$4}'),
  ];

  bool _saving = false;
  String? _error;
  String? _ok;

  @override
  void dispose() {
    _free.dispose();
    for (final r in _pkgs) {
      r.dispose();
    }
    for (final r in _plans) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final err = validateRealtyCounts(
      freeLimit: _free.text,
      packages: [for (final r in _pkgs) (r.size.text, r.price.text)],
      plans: [for (final r in _plans) (r.id.text, r.objects.text, r.days.text, r.price.text)],
    );
    if (err != null) {
      setState(() {
        _error = err;
        _ok = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });
    try {
      await widget.onSave(
        freeLimit: _free.text.trim().isEmpty ? null : int.parse(_free.text.trim()),
        packages: [
          for (final r in _pkgs) {'size': int.parse(r.size.text.trim()), 'price': int.parse(r.price.text.trim())},
        ],
        proPlans: [
          for (final r in _plans)
            {
              'id': r.id.text.trim(),
              'objects': int.parse(r.objects.text.trim()),
              'days': int.parse(r.days.text.trim()),
              'price': int.parse(r.price.text.trim()),
            },
        ],
      );
      if (mounted) {
        setState(() => _ok = 'Сақланди. Янги сонлар кейинги сўровдан кучга киради; '
            'мавжуд эълонлар ва аввал олинган пакетлар ўзгармайди.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message : 'Сақлаб бўлмади: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _num(TextEditingController c, String label, {Key? key, double? width}) {
    final field = TextField(
      key: key,
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
    return width == null ? Expanded(child: field) : SizedBox(width: width, child: field);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('realty-counts-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Объект сонлари', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'Аввал бу сонлар кодда қотирилган эди. Ўзгартириш мавжуд эълонларга ва '
          'аввал олинган пакетларга таъсир қилмайди; ҳар ўзгариш журналга ёзилади.',
          style: TextStyle(fontSize: AppText.bodySmall),
        ),
        const SizedBox(height: 14),

        const Text('Бепул объект ўринлари', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SizedBox(
          width: 320,
          child: TextField(
            key: const ValueKey('counts-free-limit'),
            controller: _free,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Ҳар бир фойдаланувчига бепул объект',
              helperText: '$realtyFreeLimitMin…$realtyFreeLimitMax. Бўш қолса — бошланғич қиймат',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),

        const Divider(height: 32),
        const Text('Ахборот пакети (харидор тўлайди)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Пакет — шунча объектнинг аниқ маълумотини очиш ҳуқуқи. Катта пакет битта '
          'объект ҳисобида қиммат бўлмаслиги керак.',
          style: TextStyle(fontSize: AppText.bodySmall),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _pkgs.length; i++)
          Padding(
            key: ObjectKey(_pkgs[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              _num(_pkgs[i].size, 'Объект сони', key: ValueKey('counts-pkg-size-$i'), width: 140),
              const SizedBox(width: 10),
              _num(_pkgs[i].price, 'Нарх (сўм)', key: ValueKey('counts-pkg-price-$i')),
              IconButton(
                key: ValueKey('counts-pkg-del-$i'),
                tooltip: 'Қаторни олиб ташлаш',
                onPressed: _pkgs.length > 1 && !_saving
                    ? () => setState(() => _pkgs.removeAt(i).dispose())
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
          ),
        TextButton.icon(
          key: const ValueKey('counts-pkg-add'),
          onPressed: _pkgs.length >= realtyPackageRowsMax || _saving
              ? null
              : () => setState(() => _pkgs.add(_PkgRow('', ''))),
          icon: const Icon(Icons.add),
          label: const Text('Пакет ўлчамини қўшиш'),
        ),

        const Divider(height: 32),
        const Text('Профессионал пакет (риэлторлар)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Объект сони энг кўпи $realtyPlanObjectsMax — тизим хавфсизлиги учун коддаги чегара. '
          'id — режанинг ички номи (кичик лотин ҳарф, рақам, _); у ўзгартирилса янги режа ҳисобланади.',
          style: TextStyle(fontSize: AppText.bodySmall),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _plans.length; i++)
          Padding(
            key: ObjectKey(_plans[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              _num2(_plans[i].id, 'id', ValueKey('counts-plan-id-$i'), 120),
              const SizedBox(width: 8),
              _num(_plans[i].objects, 'Объект', key: ValueKey('counts-plan-objects-$i'), width: 100),
              const SizedBox(width: 8),
              _num(_plans[i].days, 'Кун', key: ValueKey('counts-plan-days-$i'), width: 90),
              const SizedBox(width: 8),
              _num(_plans[i].price, 'Нарх (сўм)', key: ValueKey('counts-plan-price-$i')),
              IconButton(
                key: ValueKey('counts-plan-del-$i'),
                tooltip: 'Режани олиб ташлаш',
                onPressed: _plans.length > 1 && !_saving
                    ? () => setState(() => _plans.removeAt(i).dispose())
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
          ),
        TextButton.icon(
          key: const ValueKey('counts-plan-add'),
          onPressed: _plans.length >= realtyPlanRowsMax || _saving
              ? null
              : () => setState(() => _plans.add(_PlanRow('', '', '', ''))),
          icon: const Icon(Icons.add),
          label: const Text('Режа қўшиш'),
        ),

        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, key: const ValueKey('counts-error'), style: const TextStyle(color: Colors.red)),
          ),
        if (_ok != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_ok!, key: const ValueKey('counts-ok'), style: const TextStyle(color: AppColors.primaryText)),
          ),
        ElevatedButton.icon(
          key: const ValueKey('counts-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Сақланмоқда...' : 'Объект сонларини сақлаш'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: AppColors.onPrimary,
          ),
        ),
      ],
    );
  }

  /// Матнли майдон (id) — `_num` дан фарқи: рақам филтри йўқ.
  Widget _num2(TextEditingController c, String label, Key key, double width) => SizedBox(
        width: width,
        child: TextField(
          key: key,
          controller: c,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );
}
