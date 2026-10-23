import 'package:flutter/material.dart';

import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/domain/business_category.dart';
import '../../business_map/screens/business_map_screen.dart';

/// Админ: тадбиркорлик объектлари реестри (B-1, B-6). Админ ЯНГИ объект қўшмайди — фақат эгалар қўшган
/// объектларни таҳрирлайди ва ўчиради; ҳар бир ўзгариш `admin_audit`га сабаб билан тушади (41-банд,
/// сервер: `adminUpdateBusiness` / `adminDeleteBusiness`).
class BusinessAdminScreen extends StatefulWidget {
  const BusinessAdminScreen({super.key, BusinessRepository? repository}) : _repo = repository;

  final BusinessRepository? _repo;

  @override
  State<BusinessAdminScreen> createState() => _BusinessAdminScreenState();
}

class _BusinessAdminScreenState extends State<BusinessAdminScreen> {
  late final BusinessRepository _repo = widget._repo ?? BusinessRepository();
  final _search = TextEditingController();

  List<Business> _all = const [];
  BusinessCategory? _category;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchRecent();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Юклаб бўлмади. Қайта уриниб кўринг.';
      });
    }
  }

  List<Business> get _visible {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final b in _all)
        if ((_category == null || b.category == _category) &&
            (q.isEmpty ||
                b.name.toLowerCase().contains(q) ||
                b.phone.contains(q) ||
                b.ownerId.contains(q) ||
                b.address.toLowerCase().contains(q)))
          b,
    ];
  }

  void _snack(String text) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit(Business b) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDialog(business: b, repo: _repo),
    );
    if (saved == true) {
      _snack('Сақланди');
      await _load();
    }
  }

  Future<void> _delete(Business b) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteDialog(business: b),
    );
    if (text == null || !mounted) return;
    try {
      await _repo.adminDelete(b.id, reason: text);
      _snack('Ўчирилди');
      await _load();
    } catch (e) {
      _snack('Ўчириб бўлмади (${BusinessRepository.errorCode(e)})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺 Бизнес харитаси', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Харитада кўриш',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const BusinessMapScreen())),
          ),
          IconButton(tooltip: 'Янгилаш', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Ном, телефон, манзил ёки эга рақами',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<BusinessCategory?>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Барча турлар')),
                      for (final c in BusinessCategory.values)
                        DropdownMenuItem(value: c, child: Text(_catLabel(c), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _category = v),
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Кўрсатилди: ${rows.length} / ${_all.length} (энг сўнгги 200 тагача юкланади)'),
            ),
          ),
          Expanded(
            child: rows.isEmpty && !_loading
                ? const Center(child: Text('Объект йўқ'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final b = rows[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(b.category.icon),
                          title: Text(b.name),
                          subtitle: Text([
                            _catLabel(b.category),
                            if (b.subtype.isNotEmpty) b.subtype,
                            if (b.address.isNotEmpty) b.address,
                            'тел: ${b.phone}',
                            'эга: ${b.ownerId}',
                          ].join(' · ')),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Таҳрирлаш',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(b),
                              ),
                              IconButton(
                                tooltip: 'Ўчириш',
                                icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                                onPressed: () => _delete(b),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Админ панели матнлари Кирилл ёзувида қотирилган (бошқа админ экранлар каби) — иловадаги 3 тилли
/// калитлар админга керак эмас.
String _catLabel(BusinessCategory c) => switch (c) {
      BusinessCategory.retail => 'Чакана савдо',
      BusinessCategory.wholesale => 'Улгуржи савдо',
      BusinessCategory.food => 'Кафе ва ресторанлар',
      BusinessCategory.auto => 'Авто хизматлар',
      BusinessCategory.manufacturing => 'Ишлаб чиқариш',
      BusinessCategory.personal => 'Шахсий хизматлар',
      BusinessCategory.homeServices => 'Маиший ва техник хизматлар',
      BusinessCategory.health => 'Тиббиёт ва соғлиқ',
      BusinessCategory.education => 'Таълим',
      BusinessCategory.leisure => 'Дам олиш, спорт, туризм',
      BusinessCategory.logistics => 'Логистика ва транспорт',
      BusinessCategory.professional => 'Касбий ва молиявий хизматлар',
      BusinessCategory.itMedia => 'ИТ, реклама, алоқа',
      BusinessCategory.other => 'Бошқа',
    };

/// Ўчириш диалоги: сабаб (камида 3 белги) киритилмагунча тугма ўчиқ. Controller'ни диалогнинг ўзи
/// бошқаради ва ёпилиш анимацияси тугагач `dispose` қилади (route ёпилганда ҳам TextField чизилиб турадди).
/// Натижа — сабаб матни; бекор қилинса `null`.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.business});

  final Business business;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    final ok = _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Объектни ўчириш'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${b.name}\nЭга: ${b.ownerId}'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Сабаб (шарт)', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор қилиш')),
        TextButton(
          onPressed: ok ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: Text('Ўчириш', style: TextStyle(color: Colors.red.shade700)),
        ),
      ],
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.business, required this.repo});

  final Business business;
  final BusinessRepository repo;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.business.name);
  late final _subtype = TextEditingController(text: widget.business.subtype);
  late final _description = TextEditingController(text: widget.business.description);
  late final _phone = TextEditingController(text: widget.business.phone);
  late final _address = TextEditingController(text: widget.business.address);
  late final _hours = TextEditingController(text: widget.business.openingHours);
  late final _website = TextEditingController(text: widget.business.website);
  late final _lat = TextEditingController(text: '${widget.business.lat}');
  late final _lng = TextEditingController(text: '${widget.business.lng}');
  final _reason = TextEditingController();
  late BusinessCategory _category = widget.business.category;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _subtype, _description, _phone, _address, _hours, _website, _lat, _lng, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    if (lat == null || lng == null) return setState(() => _error = 'Координата нотўғри');
    if (_reason.text.trim().length < 3) return setState(() => _error = 'Сабабни ёзинг');
    setState(() {
      _busy = true;
      _error = null;
    });
    final b = widget.business;
    final edited = Business(
      id: b.id,
      ownerId: b.ownerId,
      name: _name.text.trim(),
      category: _category,
      subtype: _subtype.text.trim(),
      description: _description.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      lat: lat,
      lng: lng,
      regionId: b.regionId,
      districtId: b.districtId,
      openingHours: _hours.text.trim(),
      website: _website.text.trim(),
    );
    try {
      await widget.repo.adminUpdate(edited, reason: _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Сақлаб бўлмади (${BusinessRepository.errorCode(e)})';
      });
    }
  }

  Widget _field(TextEditingController c, String label, {int? max, TextInputType? type, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          enabled: !_busy,
          maxLength: max,
          maxLines: lines,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Объектни таҳрирлаш'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'Номи', max: 80),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<BusinessCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Тури', border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (final c in BusinessCategory.values)
                      DropdownMenuItem(value: c, child: Text(_catLabel(c), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _category = v ?? _category),
                ),
              ),
              _field(_subtype, 'Аниқроқ тури', max: 60),
              _field(_description, 'Тавсиф', max: 500, lines: 3),
              _field(_phone, 'Телефон', type: TextInputType.phone),
              _field(_address, 'Манзил', max: 200),
              _field(_hours, 'Иш вақти', max: 120),
              _field(_website, 'Сайт', max: 120),
              Row(
                children: [
                  Expanded(child: _field(_lat, 'Кенглик (lat)', type: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_lng, 'Узунлик (lng)', type: const TextInputType.numberWithOptions(decimal: true))),
                ],
              ),
              _field(_reason, 'Таҳрир сабаби (шарт)', max: 300),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Бекор қилиш')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сақлаш'),
        ),
      ],
    );
  }
}
