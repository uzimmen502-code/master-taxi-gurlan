// Логистика тарифи — ВИЛОЯТЛАР МАТРИЦАСИ муҳаррири (Ulgurji Q-6, 2026-10-31).
//
// Фақат ҚОРАЛАМА тариф. N×N жадвал (`geo_regions`, кутилган 14), юқори учбурчак
// таҳрирланади, пасткиси — кўзгу. Бўш катак — бўш қолади (стандарт зона ЙЎҚ,
// CLAUDE.md §10). Сақлаш — мавжуд `adminUpsertLogisticsTariff({tariff})`: ҳужжат
// тўлиқ юборилади, фақат `matrix.regions` алмашади (шакли: `region_zone_matrix.dart`).
// 20 кг дан оғир (+1 кг, `prices.<ZONE>.extraPerKg`) — «Нархлар» жадвалида.

import 'package:flutter/material.dart';

import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';
import '../services/admin_callable.dart';
import '../services/admin_logistics_service.dart';
import '../utils/region_zone_matrix.dart';

/// Тариф ҳужжатидаги сервер майдонлари — қораламани қайта юборишда олиб ташланади
/// (`logistics_admin_screen.dart` ҳам шуни ишлатади).
const kLogisticsTariffServerKeys = <String>[
  'status', 'updatedAt', 'updatedBy', 'createdAt',
  'activatedAt', 'activatedBy', 'retiredAt', 'retiredBy',
];

/// Ҳудудлар — иловадаги манба (`ServiceConfigRepository.fetchRegions`, `geo_regions`).
/// `activeOnly: false`: матрица бутун Ўзбекистон учун (Q-2), иловада модул ёпиқ
/// вилоят ҳам жадвалда бўлсин. Тартиб — `order`.
Future<List<MatrixRegion>> loadMatrixRegions() async {
  final list = await ServiceConfigRepository().fetchRegions(activeOnly: false);
  return [for (final GeoRegion r in list) MatrixRegion(r.id, r.displayName.isEmpty ? r.id : r.displayName)];
}

/// Қоралама тарифнинг матрицасини таҳрирлаш → сақлаш. `true` — сақланди.
Future<bool> editTariffRegionMatrix(
  BuildContext context, {
  required Map<String, dynamic> tariff,
  required AdminLogisticsService service,
  Future<List<MatrixRegion>> Function()? loadRegions,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String text, {bool error = false}) => messenger.showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
        duration: Duration(seconds: error ? 10 : 5),
      ));

  if ((tariff['status'] ?? '').toString() != 'draft') {
    snack('Матрица фақат қоралама тарифда таҳрирланади — аввал «Нархлар → янги версия» ёки «Янги версия»', error: true);
    return false;
  }
  final version = (tariff['version'] as num?)?.toInt() ?? 0;
  List<MatrixRegion> regions;
  try {
    regions = await (loadRegions ?? loadMatrixRegions)();
  } catch (e) {
    snack('Вилоятлар рўйхати юкланмади: $e', error: true);
    return false;
  }
  if (regions.isEmpty) {
    snack('Вилоятлар рўйхати бўш (geo_regions) — матрицани кўрсатиб бўлмайди', error: true);
    return false;
  }
  if (!context.mounted) return false;
  final base = <String, dynamic>{...tariff}..removeWhere((k, _) => kLogisticsTariffServerKeys.contains(k));
  final doc = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RegionZoneMatrixDialog(tariff: base, version: version, regions: regions),
  );
  if (doc == null) return false;
  try {
    final res = await service.upsertTariff(doc);
    final errs = (res['activationErrors'] as List?) ?? const [];
    snack(errs.isEmpty
        ? 'Матрица сақланди: v${res['version']} (қоралама) — фаоллаштиришга тайёр'
        : 'Матрица сақланди (қоралама v${res['version']}). Фаоллаштириш учун етишмайди:\n${errs.take(6).join('\n')}');
    return true;
  } catch (e) {
    final details = e is AdminCallableException ? e.details : null;
    final errors = details?['errors'];
    snack(
      'Хато: ${adminErrorText(e)}${errors is List && errors.isNotEmpty ? '\n${errors.take(6).join('\n')}' : ''}',
      error: true,
    );
    return false;
  }
}

class RegionZoneMatrixDialog extends StatefulWidget {
  const RegionZoneMatrixDialog({
    super.key,
    required this.tariff,
    required this.version,
    required this.regions,
  });

  /// Сервер майдонларисиз тариф ҳужжати.
  final Map<String, dynamic> tariff;
  final int version;
  final List<MatrixRegion> regions;

  @override
  State<RegionZoneMatrixDialog> createState() => _RegionZoneMatrixDialogState();
}

class _RegionZoneMatrixDialogState extends State<RegionZoneMatrixDialog> {
  late final RegionZoneMatrix _m;

  static const _zoneColors = <String, Color>{
    'ZONE_0': Color(0xFFE8F5E9),
    'ZONE_1': Color(0xFFDCEDC8),
    'ZONE_2': Color(0xFFFFF9C4),
    'ZONE_3': Color(0xFFFFE0B2),
    'ZONE_4': Color(0xFFFFCCBC),
    'ZONE_5': Color(0xFFF8BBD0),
  };

  @override
  void initState() {
    super.initState();
    final m = widget.tariff['matrix'];
    _m = RegionZoneMatrix.fromTariff(
      [for (final r in widget.regions) r.id],
      m is Map ? m['regions'] : null,
    );
  }

  static String _short(String zone) => 'Z${zone.substring(5)}';

  Widget _cell(int row, int col) {
    final zone = _m.zoneAt(row, col);
    final editable = RegionZoneMatrix.isEditable(row, col);
    final conflict = _m.isConflict(row, col);
    final invalid = _m.isInvalid(row, col);
    final text = Text(
      zone == null ? '·' : _short(zone),
      style: TextStyle(
        fontSize: 12,
        fontWeight: editable ? FontWeight.w700 : FontWeight.w400,
        color: editable ? Colors.black87 : Colors.black38,
      ),
    );
    final box = Container(
      width: 44,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: zone == null
            ? (editable ? Colors.white : Colors.grey.shade100)
            : (_zoneColors[zone] ?? Colors.white).withValues(alpha: editable ? 1 : 0.45),
        border: Border.all(
          color: conflict || invalid ? Colors.red.shade700 : Colors.grey.shade300,
          width: conflict || invalid ? 2 : 1,
        ),
      ),
      child: text,
    );
    if (!editable) return box;
    return PopupMenuButton<String>(
      key: ValueKey('zcell-$row-$col'),
      tooltip: '${widget.regions[row].label} ↔ ${widget.regions[col].label}',
      padding: EdgeInsets.zero,
      onSelected: (v) => setState(() => _m.setZone(row, col, v.isEmpty ? null : v)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('— бўш (нарх йўқ)')),
        for (final z in kTariffZones) PopupMenuItem(value: z, child: Text(z)),
      ],
      child: box,
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.regions.length;
    final blocker = _m.saveBlocker;
    final muted = TextStyle(fontSize: 11.5, color: Colors.grey.shade700);
    return AlertDialog(
      title: Text('Вилоятлар матрицаси — қоралама v${widget.version}'),
      content: SizedBox(
        width: 980,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Тўлдирилган: ${_m.filledPairs} / ${_m.totalPairs} жуфтлик · бўш: ${_m.emptyPairs}',
                key: const ValueKey('matrix-fill'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Юқори учбурчакни таҳрирланг (катакни босинг) — пасткиси кўзгу, иккала йўналиш бир хил '
                'сақланади. Бўш катак — бу йўналишга етказиш нархи ЙЎҚ (харидор «нарх ҳали белгиланмаган» '
                'кўради); стандарт зона қўйилмайди. Зона маъноси — эга қарори.',
                style: muted,
              ),
              Text(
                '20 кг дан оғир посилка (+1 кг, extraPerKg) нархи — «Нархлар» жадвалининг охирги устунида.',
                style: muted,
              ),
              if (_m.foreignPairCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Жадвалдан ташқари ҳудуд ID\'лари бўйича ${_m.foreignPairCount} та жуфтлик бор — ўзгаришсиз сақланади.',
                    style: muted,
                  ),
                ),
              if (_m.hasConflicts || _m.invalidCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (_m.hasConflicts)
                        'Қизил катак: ҳужжатда икки йўналиш ҲАР ХИЛ зонали (${_m.conflictCount} та) — '
                            'юқоридагиси кўрсатилмоқда; катакни қайта танлаб тасдиқланг.',
                      if (_m.invalidCount > 0)
                        'Қизил бўш катак: ҳужжатда нотўғри қиймат бор эди (${_m.invalidCount} та) — бўш деб олинди.',
                    ].join('\n'),
                    style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
                  ),
                ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const SizedBox(width: 190),
                      for (var c = 0; c < n; c += 1)
                        Tooltip(
                          message: widget.regions[c].label,
                          child: SizedBox(
                            width: 44,
                            child: Text('${c + 1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ]),
                    for (var r = 0; r < n; r += 1)
                      Row(children: [
                        SizedBox(
                          width: 190,
                          child: Tooltip(
                            message: widget.regions[r].id,
                            child: Text(
                              '${r + 1}. ${widget.regions[r].label}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        for (var c = 0; c < n; c += 1) _cell(r, c),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final z in kTariffZones)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      color: _zoneColors[z],
                      child: Text('${_short(z)} = $z', style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
              if (blocker != null) ...[
                const SizedBox(height: 8),
                Text(blocker, key: const ValueKey('matrix-blocker'), style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: blocker != null ? null : () => Navigator.pop(context, _m.applyToTariff(widget.tariff)),
          child: const Text('Матрицани сақлаш'),
        ),
      ],
    );
  }
}
