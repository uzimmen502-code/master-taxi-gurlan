import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/geo_area.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/service_config_repository.dart';
import '../../car_insurance/car_insurance_service.dart';

/// «Автомобил суғуртаси» — админ (эга 2026-11-28; матн фақат кирилл):
/// Аризалар (суғурта агенти: полис юклаш / бекор қилиш — пул қайтади) · Сервис ҳисоботи (кунлик номерлар) ·
/// Нарх жадвали (янги версия) · Созламалар (босқич, рухсатлар, кампания/бонус). Рухсат серверда
/// (`car_insurance.js`): агент — admin/superadmin ёки agentPhones; ҳисобот — reporterPhones; созлама — admin.
class CarInsuranceAdminScreen extends StatelessWidget {
  const CarInsuranceAdminScreen({super.key, this.service});
  final CarInsuranceService? service;

  @override
  Widget build(BuildContext context) {
    final svc = service ?? CarInsuranceService();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Автомобил суғуртаси'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Аризалар'),
            Tab(text: 'Сервис ҳисоботи'),
            Tab(text: 'Нарх жадвали'),
            Tab(text: 'Созламалар'),
          ]),
        ),
        body: TabBarView(children: [
          InsuranceRequestsAdminTab(service: svc),
          _ServiceReportTab(service: svc),
          _TariffTab(service: svc),
          _SettingsTab(service: svc),
        ]),
      ),
    );
  }
}

const _statusNames = {
  'paid': 'Тўланган',
  'in_progress': 'Расмийлаштирилмоқда',
  'requested': 'Тўланмаган',
  'issued': 'Берилган',
  'cancelled': 'Бекор қилинган',
};
const _vehicleNames = {'car': 'Енгил', 'truck': 'Юк', 'bus': 'Автобус', 'moto': 'Мото'};
const _policyNames = {'osago': 'ОСАГО', 'kasko': 'КАСКО'};
const _stageNames = {'off': 'Ўчиқ', 'internal': 'Ички синов', 'pilot': 'Пилот', 'public': 'Ҳамма'};

String _adminErr(Object e) {
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    final code = d is Map ? '${d['code'] ?? e.code}' : e.code;
    final msg = d is Map && d['messages'] is Map ? '${(d['messages'] as Map)['uz_Cyrl']}' : '';
    final errors = d is Map && d['errors'] is List ? ' ${(d['errors'] as List).join(', ')}' : '';
    return '$msg ($code)$errors'.trim();
  }
  return 'Хатолик';
}

void _snack(BuildContext context, String m) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

/// Вергул/бўшлиқ/қатор билан ажратилган рўйхат (соф).
@visibleForTesting
List<String> splitList(String s) =>
    s.split(RegExp(r'[\s,;]+')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

/// «1:50, 2:100» → [{count, pct}] ёки null (соф).
@visibleForTesting
List<Map<String, int>>? parseOilSteps(String s) {
  final out = <Map<String, int>>[];
  for (final part in s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty)) {
    final m = RegExp(r'^(\d+)\s*:\s*(\d+)$').firstMatch(part);
    if (m == null) return null;
    out.add({'count': int.parse(m.group(1)!), 'pct': int.parse(m.group(2)!)});
  }
  return out.isEmpty ? null : out;
}

String _steps(Object? v) => [
      for (final s in (v is List ? v : const []))
        if (s is Map) '${s['count']}:${s['pct']}',
    ].join(', ');

// ══════════════════ Аризалар (агент) ══════════════════

class InsuranceRequestsAdminTab extends StatefulWidget {
  const InsuranceRequestsAdminTab({super.key, required this.service});
  final CarInsuranceService service;

  @override
  State<InsuranceRequestsAdminTab> createState() => _InsuranceRequestsAdminTabState();
}

class _InsuranceRequestsAdminTabState extends State<InsuranceRequestsAdminTab> {
  String _status = 'paid';
  late Future<List<InsuranceRequest>> _list = widget.service.agentList(_status);
  bool _busy = false;

  void _reload() => setState(() => _list = widget.service.agentList(_status));

  Future<void> _do(Future<void> Function() job, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) _snack(context, ok);
      _reload();
    } catch (e) {
      if (mounted) _snack(context, _adminErr(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: [
              for (final s in _statusNames.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('ins_admin_status_$s'),
                    label: Text(_statusNames[s]!),
                    selected: _status == s,
                    onSelected: (_) {
                      _status = s;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<InsuranceRequest>>(
            future: _list,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Юклаб бўлмади: ${_adminErr(snap.error!)}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              if (list.isEmpty) return const Center(child: Text('Ариза йўқ'));
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _tile(list[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(InsuranceRequest r) {
    final car = [r.carBrand, r.carModel, if (r.carYear > 0) '${r.carYear}'].where((x) => x.isNotEmpty).join(' ');
    return Card(
      key: ValueKey('ins_admin_req_${r.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_policyNames[r.policyType] ?? r.policyType} · ${r.termMonths} ой · ${_vehicleNames[r.vehicleType] ?? r.vehicleType}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Машина: $car · ${r.carPlate}'),
            Text('Мижоз: +${r.uid} · вилоят: ${r.regionId.isEmpty ? '—' : r.regionId}'),
            Text('Нарх: ${formatMoney(r.price)} · ҳамёндан: ${formatMoney(r.walletPaid)} · бонус: ${formatMoney(r.incentiveApplied)} · мой чегирмаси: ${formatMoney(r.oilDiscount)}'),
            if (r.status == 'issued') Text('Полис № ${r.policyNumber}: ${insuranceDisplayDate(r.validFrom)} — ${insuranceDisplayDate(r.validTo)}'),
            if (r.status == 'cancelled') Text('Сабаб: ${r.cancelReason}'),
            Wrap(spacing: 8, children: [
              if (r.status == 'paid')
                TextButton(
                  onPressed: _busy ? null : () => _do(() => widget.service.agentStart(r.id), 'Иш бошланди'),
                  child: const Text('Ишни бошлаш'),
                ),
              if (r.status == 'paid' || r.status == 'in_progress')
                FilledButton.icon(
                  key: ValueKey('ins_admin_issue_${r.id}'),
                  onPressed: _busy ? null : () => _issue(r),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Полисни юклаш'),
                ),
              if (r.status == 'requested' || r.status == 'paid' || r.status == 'in_progress')
                TextButton(
                  onPressed: _busy ? null : () => _cancel(r),
                  child: Text(r.status == 'requested' ? 'Бекор қилиш' : 'Бекор қилиш (пул қайтади)'),
                ),
              if (r.status == 'issued')
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _do(() async {
                            await launchUrl(Uri.parse(await widget.service.policyLink(r.id)), mode: LaunchMode.externalApplication);
                          }, 'Очилди'),
                  child: const Text('Полисни очиш'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(InsuranceRequest r) async {
    final ctl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Аризани бекор қилиш'),
        content: TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Сабаб (мижозга кўринади)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ёпиш')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Бекор қилиш')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _do(() => widget.service.agentCancel(r.id, reason), 'Бекор қилинди, маблағ қайтарилди');
  }

  Future<void> _issue(InsuranceRequest r) async {
    final number = TextEditingController();
    final from = TextEditingController(text: insuranceDateKey(DateTime.now()));
    final to = TextEditingController(
        text: insuranceDateKey(DateTime.now().add(Duration(days: (r.termMonths * 30.4).round()))));
    PlatformFile? file;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Полисни юклаш'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: number, decoration: const InputDecoration(labelText: 'Полис рақами')),
              TextField(controller: from, decoration: const InputDecoration(labelText: 'Бошланиши (ЙЙЙЙ-ОО-КК)')),
              TextField(controller: to, decoration: const InputDecoration(labelText: 'Тугаши (ЙЙЙЙ-ОО-КК)')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
                    withData: true,
                  );
                  final f = picked?.files.single;
                  if (f != null) set(() => file = f);
                },
                icon: const Icon(Icons.attach_file),
                label: Text(file == null ? 'Файл танлаш (PDF/расм, ≤5 МБ)' : file!.name),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ёпиш')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Юклаш ва бериш')),
          ],
        ),
      ),
    );
    final bytes = file?.bytes;
    if (ok != true) return;
    if (bytes == null) {
      if (mounted) _snack(context, 'Файл танланмади');
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) _snack(context, 'Файл 5 МБ дан катта');
      return;
    }
    await _do(
      () => widget.service.agentIssue(
        requestId: r.id,
        policyNumber: number.text.trim(),
        validFrom: from.text.trim(),
        validTo: to.text.trim(),
        fileBase64: base64Encode(bytes),
      ),
      'Полис берилди, мижозга хабар юборилди',
    );
  }
}

// ══════════════════ Сервис маркази ҳисоботи ══════════════════

class _ServiceReportTab extends StatefulWidget {
  const _ServiceReportTab({required this.service});
  final CarInsuranceService service;

  @override
  State<_ServiceReportTab> createState() => _ServiceReportTabState();
}

class _ServiceReportTabState extends State<_ServiceReportTab> {
  final _plates = TextEditingController();
  String? _centerId;
  DateTime _date = DateTime.now();
  bool _busy = false;
  Map? _last;
  late Future<List<Map>> _history = widget.service.listServiceReports();

  static const _resultNames = {
    'credited': 'ҳисобланди',
    'duplicate': 'такрор (ҳисобланмади)',
    'not_enrolled': 'дастурда йўқ',
    'goal_reached': 'дастур тўлган',
    'invalid': 'нотўғри рақам',
  };

  Future<void> _submit() async {
    final plates = _plates.text.split(RegExp(r'[\n,;]+')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (_centerId == null || plates.isEmpty) {
      _snack(context, 'Марказ ва рақамларни киритинг');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.service.submitServiceReport(centerId: _centerId!, date: insuranceDateKey(_date), plates: plates);
      setState(() {
        _last = r;
        _plates.clear();
        _history = widget.service.listServiceReports();
      });
    } catch (e) {
      if (mounted) _snack(context, _adminErr(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Кунлик ҳисобот: мой алмаштирилган машиналар рақамлари (ҳар қаторда биттадан). Бир рақам бир кунда бир марта ҳисобланади.'),
        const SizedBox(height: 10),
        StreamBuilder<List<OilServicePoint>>(
          stream: OilChangeRepository().watchAvaCenters(),
          builder: (context, snap) {
            final centers = snap.data ?? const <OilServicePoint>[];
            return DropdownButtonFormField<String>(
              initialValue: centers.any((c) => c.id == _centerId) ? _centerId : null,
              decoration: const InputDecoration(labelText: 'AVA Сервис маркази'),
              items: [for (final c in centers) DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.districtId})'))],
              onChanged: (v) => setState(() => _centerId = v),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('Сана: ${insuranceDisplayDate(insuranceDateKey(_date))}'),
          TextButton(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: now.subtract(const Duration(days: 7)), lastDate: now);
              if (d != null) setState(() => _date = d);
            },
            child: const Text('Ўзгартириш'),
          ),
        ]),
        TextField(
          controller: _plates,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(labelText: 'Давлат рақамлари', hintText: '01 A 123 BC\n90 777 ZZZ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Ҳисоботни юбориш')),
        if (_last != null) ...[
          const SizedBox(height: 12),
          const Text('Натижа:', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final x in (_last!['results'] is List ? _last!['results'] as List : const []))
            if (x is Map) Text('${x['plate']} — ${_resultNames[x['result']] ?? x['result']}'),
        ],
        const Divider(height: 32),
        const Text('Тарих', style: TextStyle(fontWeight: FontWeight.w700)),
        FutureBuilder<List<Map>>(
          future: _history,
          builder: (context, snap) {
            if (snap.hasError) return Text('Юклаб бўлмади: ${_adminErr(snap.error!)}');
            final list = snap.data ?? const <Map>[];
            return Column(children: [
              for (final r in list)
                ListTile(
                  dense: true,
                  title: Text('${r['date']} · ${r['centerId']}'),
                  subtitle: Text((r['counts'] is Map ? (r['counts'] as Map) : const {})
                      .entries
                      .map((e) => '${_resultNames[e.key] ?? e.key}: ${e.value}')
                      .join(' · ')),
                  trailing: Text('${r['submittedBy'] ?? ''}'),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

// ══════════════════ Нарх жадвали ══════════════════

class _TariffTab extends StatefulWidget {
  const _TariffTab({required this.service});
  final CarInsuranceService service;

  @override
  State<_TariffTab> createState() => _TariffTabState();
}

class _TariffTabState extends State<_TariffTab> {
  final List<Map<String, dynamic>> _rows = [];
  final _note = TextEditingController();
  late final Future<List<GeoRegion>> _regions = ServiceConfigRepository().fetchRegions(activeOnly: false);
  Map? _settings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.service.adminSettings();
      final t = s['tariff'];
      setState(() {
        _settings = s;
        _rows
          ..clear()
          ..addAll([
            for (final r in (t is Map && t['rows'] is List ? t['rows'] as List : const []))
              if (r is Map) Map<String, dynamic>.from(r),
          ]);
      });
    } catch (e) {
      if (mounted) _snack(context, _adminErr(e));
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      final v = await widget.service.adminPublishTariff(_rows, _note.text.trim());
      if (mounted) _snack(context, 'Янги версия v$v фаол. Эски аризалар ўз нархида қолади.');
      _note.clear();
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _adminErr(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _settings?['config'];
    final versions = _settings?['tariffVersions'] is List ? _settings!['tariffVersions'] as List : const [];
    return FutureBuilder<List<GeoRegion>>(
      future: _regions,
      builder: (context, rs) {
        final regions = rs.data ?? const <GeoRegion>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Фаол версия: v${cfg is Map ? cfg['activeTariffVersion'] ?? 0 : 0}. Нархлар бутун сўм. «Барча вилоятлар» қатори — вилоят қатори бўлмаса.'),
            const SizedBox(height: 8),
            for (var i = 0; i < _rows.length; i++) _rowEditor(i, regions),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _rows.add({'policyType': 'osago', 'regionId': '*', 'vehicleType': 'car', 'termMonths': 12, 'price': 0})),
                icon: const Icon(Icons.add),
                label: const Text('Қатор қўшиш'),
              ),
            ),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Изоҳ (нима ўзгарди)')),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy || _rows.isEmpty ? null : _publish, child: const Text('Янги версияни эълон қилиш')),
            const Divider(height: 32),
            const Text('Версиялар', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final v in versions)
              if (v is Map) Text('v${v['version']} · ${v['rowCount']} қатор · ${v['note'] ?? ''}'),
          ],
        );
      },
    );
  }

  Widget _rowEditor(int i, List<GeoRegion> regions) {
    final r = _rows[i];
    final regionIds = ['*', ...regions.map((g) => g.id)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: r['policyType'] as String?,
            items: [for (final e in _policyNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => r['policyType'] = v),
          ),
          DropdownButton<String>(
            value: regionIds.contains(r['regionId']) ? r['regionId'] as String : '*',
            items: [
              const DropdownMenuItem(value: '*', child: Text('Барча вилоятлар')),
              for (final g in regions) DropdownMenuItem(value: g.id, child: Text(g.nameFor('uz_Cyrl'))),
            ],
            onChanged: (v) => setState(() => r['regionId'] = v),
          ),
          DropdownButton<String>(
            value: r['vehicleType'] as String?,
            items: [for (final e in _vehicleNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => r['vehicleType'] = v),
          ),
          SizedBox(
            width: 70,
            child: TextFormField(
              initialValue: '${r['termMonths']}',
              decoration: const InputDecoration(labelText: 'Ой'),
              keyboardType: TextInputType.number,
              onChanged: (v) => r['termMonths'] = int.tryParse(v.trim()) ?? 0,
            ),
          ),
          SizedBox(
            width: 130,
            child: TextFormField(
              initialValue: '${r['price']}',
              decoration: const InputDecoration(labelText: 'Нарх, сўм'),
              keyboardType: TextInputType.number,
              onChanged: (v) => r['price'] = int.tryParse(v.replaceAll(RegExp(r'\D'), '')) ?? 0,
            ),
          ),
          IconButton(onPressed: () => setState(() => _rows.removeAt(i)), icon: const Icon(Icons.delete_outline)),
        ],
      ),
    );
  }
}

// ══════════════════ Созламалар (босқич + кампания) ══════════════════

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.service});
  final CarInsuranceService service;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _loaded = false;
  bool _busy = false;
  List _campaigns = const [];
  // config
  String _stage = 'off';
  bool _kasko = false;
  bool _reminders = true;
  final _internal = TextEditingController();
  final _pilot = TextEditingController();
  final _agents = TextEditingController();
  final _reporters = TextEditingController();
  // campaign
  final _year = TextEditingController(text: '${DateTime.now().year}');
  String _cStage = 'off';
  final _cInternal = TextEditingController();
  final _cPilot = TextEditingController();
  bool _bonus = false;
  final _bonusAmount = TextEditingController(text: '100000');
  final _bonusDays = TextEditingController(text: '60');
  final _bonusShare = TextEditingController(text: '100');
  final _bonusBudget = TextEditingController(text: '10000000');
  bool _oil = false;
  final _oilSteps = TextEditingController(text: '1:50, 2:100');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.service.adminSettings();
      final c = s['config'] is Map ? s['config'] as Map : const {};
      setState(() {
        _stage = '${c['stage'] ?? 'off'}';
        _kasko = c['kaskoEnabled'] == true;
        _reminders = c['remindersEnabled'] != false;
        _internal.text = ((c['internalPhones'] as List?) ?? const []).join(', ');
        _pilot.text = ((c['pilotDistrictIds'] as List?) ?? const []).join(', ');
        _agents.text = ((c['agentPhones'] as List?) ?? const []).join(', ');
        _reporters.text = ((c['reporterPhones'] as List?) ?? const []).join(', ');
        _campaigns = s['campaigns'] is List ? s['campaigns'] as List : const [];
        _loaded = true;
      });
      _fillCampaign();
    } catch (e) {
      if (mounted) _snack(context, _adminErr(e));
    }
  }

  void _fillCampaign() {
    final y = int.tryParse(_year.text.trim());
    final c = _campaigns.firstWhere((x) => x is Map && x['year'] == y, orElse: () => null);
    if (c is! Map) return;
    setState(() {
      _cStage = '${c['stage'] ?? 'off'}';
      _cInternal.text = ((c['internalPhones'] as List?) ?? const []).join(', ');
      _cPilot.text = ((c['pilotDistrictIds'] as List?) ?? const []).join(', ');
      _bonus = c['bonusEnabled'] == true;
      if (_bonus) {
        _bonusAmount.text = '${c['bonusAmount']}';
        _bonusDays.text = '${c['bonusValidityDays']}';
        _bonusShare.text = '${c['bonusMaxOrderSharePct']}';
        _bonusBudget.text = '${c['bonusBudgetTotal']}';
      }
      _oil = c['oilEnabled'] == true;
      if (_oil) _oilSteps.text = _steps(c['oilSteps']);
    });
  }

  Future<void> _guard(Future<void> Function() job, String ok) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) _snack(context, ok);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _adminErr(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stageDrop(String tag, String value, ValueChanged<String> on) => DropdownButtonFormField<String>(
        key: ValueKey('stage_${tag}_$value'), // `initialValue` — юклангандан кейин янгилансин.
        initialValue: value,
        decoration: const InputDecoration(labelText: 'Босқич'),
        items: [for (final e in _stageNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => on(v ?? 'off'),
      );

  int _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Хизмат', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        _stageDrop('cfg', _stage, (v) => setState(() => _stage = v)),
        TextField(controller: _internal, decoration: const InputDecoration(labelText: 'Ички синовчилар (телефонлар, вергул билан)')),
        TextField(controller: _pilot, decoration: const InputDecoration(labelText: 'Пилот туманлар (id, вергул билан)')),
        TextField(controller: _agents, decoration: const InputDecoration(labelText: 'Суғурта агентлари (панел ходими телефони)')),
        TextField(controller: _reporters, decoration: const InputDecoration(labelText: 'Сервис ҳисоботи топширувчилар (телефонлар)')),
        SwitchListTile(value: _kasko, title: const Text('КАСКО ёқилган'), onChanged: (v) => setState(() => _kasko = v)),
        SwitchListTile(value: _reminders, title: const Text('Муддат эслатмалари (4 ва 3 кун олдин)'), onChanged: (v) => setState(() => _reminders = v)),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _guard(
                    () => widget.service.adminSaveConfig({
                      'stage': _stage,
                      'internalPhones': splitList(_internal.text),
                      'pilotDistrictIds': splitList(_pilot.text),
                      'agentPhones': splitList(_agents.text),
                      'reporterPhones': splitList(_reporters.text),
                      'kaskoEnabled': _kasko,
                      'remindersEnabled': _reminders,
                    }),
                    'Сақланди',
                  ),
          child: const Text('Хизмат созламасини сақлаш'),
        ),
        const Divider(height: 32),
        const Text('Машина рағбати (полис йили бўйича)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Row(children: [
          SizedBox(width: 100, child: TextField(controller: _year, decoration: const InputDecoration(labelText: 'Йил'), keyboardType: TextInputType.number)),
          TextButton(onPressed: _fillCampaign, child: const Text('Юклаш')),
        ]),
        _stageDrop('camp', _cStage, (v) => setState(() => _cStage = v)),
        TextField(controller: _cInternal, decoration: const InputDecoration(labelText: 'Ички синовчилар (телефонлар)')),
        TextField(controller: _cPilot, decoration: const InputDecoration(labelText: 'Пилот туманлар (id)')),
        SwitchListTile(value: _bonus, title: const Text('А) AVA бонуси (ечиб бўлмайди)'), onChanged: (v) => setState(() => _bonus = v)),
        if (_bonus)
          Wrap(spacing: 8, children: [
            SizedBox(width: 140, child: TextField(controller: _bonusAmount, decoration: const InputDecoration(labelText: 'Миқдор, сўм'))),
            SizedBox(width: 110, child: TextField(controller: _bonusDays, decoration: const InputDecoration(labelText: 'Муддат, кун'))),
            SizedBox(width: 140, child: TextField(controller: _bonusShare, decoration: const InputDecoration(labelText: 'Буюртмада улуш, %'))),
            SizedBox(width: 160, child: TextField(controller: _bonusBudget, decoration: const InputDecoration(labelText: 'Бюджет, сўм'))),
          ]),
        SwitchListTile(value: _oil, title: const Text('Б) Мой алмаштириш дастури'), onChanged: (v) => setState(() => _oil = v)),
        if (_oil)
          TextField(
            controller: _oilSteps,
            decoration: const InputDecoration(labelText: 'Босқичлар «марта:чегирма%», масалан 1:50, 2:100'),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  final steps = _oil ? parseOilSteps(_oilSteps.text) : null;
                  if (_oil && steps == null) {
                    _snack(context, 'Босқичлар нотўғри');
                    return;
                  }
                  _guard(
                    () => widget.service.adminSaveCampaign(int.tryParse(_year.text.trim()) ?? 0, {
                      'stage': _cStage,
                      'internalPhones': splitList(_cInternal.text),
                      'pilotDistrictIds': splitList(_cPilot.text),
                      'bonusEnabled': _bonus,
                      if (_bonus) ...{
                        'bonusAmount': _int(_bonusAmount),
                        'bonusValidityDays': _int(_bonusDays),
                        'bonusMaxOrderSharePct': _int(_bonusShare),
                        'bonusBudgetTotal': _int(_bonusBudget),
                      },
                      'oilEnabled': _oil,
                      if (_oil) 'oilSteps': steps,
                    }),
                    'Рағбат сақланди',
                  );
                },
          child: const Text('Рағбатни сақлаш'),
        ),
        const SizedBox(height: 8),
        for (final c in _campaigns)
          if (c is Map)
            Text('${c['year']}: ${_stageNames[c['stage']] ?? c['stage']} · бонус ${c['bonusEnabled'] == true ? formatMoney((c['bonusAmount'] as num?) ?? 0) : 'йўқ'} · '
                'мой ${c['oilEnabled'] == true ? _steps(c['oilSteps']) : 'йўқ'} · берилган ${formatMoney(((c['counters'] as Map?)?['bonusGrantedAmount'] as num?) ?? 0)}'),
      ],
    );
  }
}
