// «Бозор буюртмалари» (эга 2026-11-16) — бизнес объекти / ўз дўкони / бозор эълони буюртмалари модули босқичи.
// Ўқиш: `adminGetBusinessOrdersConfig`; ёзиш: `adminSetBusinessOrdersConfig` (сабаб мажбурий, audit серверда).
// Етказиш нархи — ресторан тарифи (`settings/restaurant_delivery`) → «Кафе-ресторанлар» → «Етказиш тарифи».

import 'package:flutter/material.dart';

import '../../../core/geo/geo_name_text.dart';
import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_selector.dart';
import '../../../core/theme/app_theme.dart';
import '../services/admin_business_orders_service.dart';
import 'restaurants_admin_screen.dart';

const _stageText = <String, String>{
  'off': 'OFF — ҳеч кимга ёпиқ',
  'internal': 'INTERNAL — фақат синовчилар',
  'pilot': 'PILOT — синовчилар + танланган туманлар',
  'public': 'PUBLIC — ҳамма',
};

class BusinessOrdersAdminScreen extends StatefulWidget {
  const BusinessOrdersAdminScreen({
    super.key,
    @visibleForTesting this.loadConfig,
    @visibleForTesting this.saveConfig,
    @visibleForTesting this.pickDistrict,
    @visibleForTesting this.openTariff,
  });

  /// Тест учун (бўлмаса — [AdminBusinessOrdersService.load]).
  final Future<BusinessOrdersConfig> Function()? loadConfig;

  /// Тест учун (бўлмаса — [AdminBusinessOrdersService.save]).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)? saveConfig;

  /// Тест учун (бўлмаса — мавжуд [GeoAreaPickScreen]).
  final Future<GeoArea?> Function(BuildContext context)? pickDistrict;

  /// Тест учун (бўлмаса — «Кафе-ресторанлар» → «Етказиш тарифи» таби).
  final void Function(BuildContext context)? openTariff;

  @override
  State<BusinessOrdersAdminScreen> createState() => _BusinessOrdersAdminScreenState();
}

class _BusinessOrdersAdminScreenState extends State<BusinessOrdersAdminScreen> {
  final _testers = TextEditingController();
  final _reason = TextEditingController();
  BusinessOrdersConfig? _cfg;
  Object? _loadError;
  String _stage = 'off';
  List<String> _districts = [];
  final Map<String, String> _districtLabels = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _testers.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final cfg = await (widget.loadConfig?.call() ?? AdminBusinessOrdersService().load());
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _stage = cfg.stage;
        _districts = [...cfg.pilotDistrictIds];
        _testers.text = cfg.testerIds.join('\n');
      });
    } catch (e) {
      debugPrint('[BusinessOrdersAdmin] load failed: $e');
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _addDistrict() async {
    final pick = widget.pickDistrict ??
        (BuildContext ctx) => Navigator.of(ctx).push<GeoArea>(MaterialPageRoute(builder: (_) => const GeoAreaPickScreen()));
    final area = await pick(context);
    if (!mounted || area == null || area.districtId.isEmpty) return;
    setState(() {
      if (!_districts.contains(area.districtId)) _districts = [..._districts, area.districtId];
      if (area.label.isNotEmpty) _districtLabels[area.districtId] = area.label;
    });
  }

  Future<void> _save() async {
    final cfg = _cfg;
    if (cfg == null || _busy) return;
    final testers = parseTesterPhones(_testers.text);
    final bad = invalidTesterPhones(testers);
    if (bad.isNotEmpty) return _snack('Нотўғри телефон: ${bad.take(3).join(', ')}', error: true);
    if (_reason.text.trim().length < 3) return _snack('Сабабни ёзинг (камида 3 белги).', error: true);
    if (_stage == 'pilot' && _districts.isEmpty && testers.isEmpty) {
      return _snack('PILOT учун камида битта туман ёки синовчи керак.', error: true);
    }
    if (_stage == 'public' && cfg.stage != 'public') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Бозор буюртмалари ҲАММАГА очилсинми?'),
          content: const Text('PUBLIC босқичда барча харидорлар бизнес ва ўз дўкони маҳсулотларига буюртма бера олади.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очиш')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final payload = businessOrdersSavePayload(
      current: cfg,
      stage: _stage,
      testerIds: testers,
      pilotDistrictIds: _districts,
      reason: _reason.text,
    );
    setState(() => _busy = true);
    try {
      final r = await (widget.saveConfig?.call(payload) ?? AdminBusinessOrdersService().save(payload));
      if (!mounted) return;
      _snack('Сақланди: ${r['stage'] ?? _stage} · v${r['version'] ?? ''} · синовчилар: ${r['testerCount'] ?? testers.length}');
      _reason.clear();
      await _load();
    } catch (e) {
      debugPrint('[BusinessOrdersAdmin] save failed: $e');
      if (mounted) _snack('Сақлаб бўлмади: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openTariff() {
    final open = widget.openTariff;
    if (open != null) return open(context);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RestaurantsAdminScreen(initialTab: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text('Бозор буюртмалари', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(tooltip: 'Янгилаш', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: cfg == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Юклаб бўлмади: $_loadError', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('Қайта уриниш')),
                    ]),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Серверда: ${cfg.stage.toUpperCase()} · v${cfg.version} · синовчилар: ${cfg.testerIds.length} · '
                  'пилот туманлар: ${cfg.pilotDistrictIds.length}${cfg.exists ? '' : ' (ҳужжат йўқ — сукут OFF)'}',
                  key: const ValueKey('bo_server_line'),
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                const Text('Босқич (42-банд)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                for (final s in kBusinessOrderStages)
                  ListTile(
                    key: ValueKey('bo_stage_$s'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_stage == s ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _stage == s ? AppColors.primaryText : Colors.grey),
                    title: Text(_stageText[s] ?? s),
                    onTap: () => setState(() => _stage = s),
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('bo_testers'),
                  controller: _testers,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Синовчилар телефони (ҳар қаторда битта; 998… ёки 9 рақам)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Пилот туманлар (PILOT босқичда)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final id in _districts)
                    InputChip(
                      key: ValueKey('bo_district_$id'),
                      label: GeoDistrictText(id, fallback: _districtLabels[id] ?? id),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => setState(() => _districts = _districts.where((x) => x != id).toList()),
                    ),
                  ActionChip(
                    key: const ValueKey('bo_add_district'),
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Туман қўшиш'),
                    onPressed: _addDistrict,
                  ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('bo_reason'),
                  controller: _reason,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Сабаб (audit учун, мажбурий)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  key: const ValueKey('bo_save'),
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Сақлаш'),
                ),
                const SizedBox(height: 22),
                const Text('Етказиш тарифи', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Card(
                  child: ListTile(
                    key: const ValueKey('bo_open_tariff'),
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: const Text('Ресторан етказиш тарифи (версияли)'),
                    subtitle: const Text('Бозор буюртмаларида ҳам шу тариф ишлатилади (settings/restaurant_delivery). '
                        'Йирик техника — «Етказиш нархи сўровлари».'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openTariff,
                  ),
                ),
                if (cfg.acceptTimeoutMin > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Сотувчи жавоб муддати: ${cfg.acceptTimeoutMin} дақ (серверда).',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                  ),
              ],
            ),
    );
  }
}
