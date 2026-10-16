// Админ «Курьер вазифалари» — СОФ мантиқ (тестланади):
//   1. Курьер ҳақи фоизи (D2): `adminGetCourierTaskPayoutSettings` /
//      `adminSetCourierTaskPayoutPct` (default, us-central1). Рules'га кўра
//      `settings/courier_task_payout` клиентдан ЎҚИЛМАЙДИ — фақат getter callable.
//   2. Қотиб қолган вазифалар (D6): `adminListStaleTasks({hours})` — фақат ўқиш.
// Ҳақ ҳисоби ва чегаралар СЕРВЕРДА; экран фоизни (bps/100) кўрсатади ва
// киритилганини bps'га айлантиради (44-банд).

import '../../logistics/domain/tariff_adjust.dart' show bpsToPercentText, percentTextToBps;

// ── Курьер ҳақи фоизи ────────────────────────────────────────────────

/// Тартиб ва ёрлиқлар (сервер `MODULE_KEYS`).
const kCourierPayoutModules = <String, String>{
  'carpet': 'Гилам юваш',
  'agro': 'Сут қабул',
  'collection': 'Йиғиб олиш',
};

class CourierPayoutSettings {
  const CourierPayoutSettings({
    this.version = 0,
    this.bps = const {},
    this.updatedAtMs,
    this.updatedBy = '',
  });

  final int version;

  /// модул → bps; `null` = «созланмаган».
  final Map<String, int?> bps;
  final int? updatedAtMs;
  final String updatedBy;

  static CourierPayoutSettings fromMap(Map<String, dynamic> m) {
    final rawModules = m['modules'];
    final modules = rawModules is Map ? rawModules : const {};
    final out = <String, int?>{};
    for (final k in kCourierPayoutModules.keys) {
      final v = modules[k];
      final b = v is Map ? v['bps'] : null;
      out[k] = b is num ? b.toInt() : null;
    }
    final ver = m['version'];
    final at = m['updatedAtMs'];
    return CourierPayoutSettings(
      version: ver is num ? ver.toInt() : 0,
      bps: out,
      updatedAtMs: at is num ? at.toInt() : null,
      updatedBy: (m['updatedBy'] ?? '').toString(),
    );
  }

  /// Майдон матни: `null` → бўш («созланмаган»).
  String percentText(String module) {
    final b = bps[module];
    return b == null ? '' : bpsToPercentText(b);
  }
}

class PayoutPctPlan {
  const PayoutPctPlan({this.bps, this.changed = false, this.error});

  /// Юбориладиган қиймат (`null` — «созланмаган»га қайтариш).
  final int? bps;
  final bool changed;
  final String? error;
}

/// Матн → режа. Бўш ёки «созланмаган» → `null` (қайтариш). Фоиз 0..100.
PayoutPctPlan planPayoutPctChange({required int? currentBps, required String text}) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || t == 'созланмаган' || t == 'sozlanmagan') {
    return PayoutPctPlan(bps: null, changed: currentBps != null);
  }
  final bps = percentTextToBps(t);
  if (bps == null || bps < 0 || bps > 10000) {
    return const PayoutPctPlan(error: 'Фоиз 0..100 оралиғида бўлиши керак (масалан 70 ёки 62,5)');
  }
  return PayoutPctPlan(bps: bps, changed: bps != currentBps);
}

// ── Қотиб қолган вазифалар ───────────────────────────────────────────

const kStaleMinHours = 1;
const kStaleMaxHours = 168;
const kStaleDefaultHours = 3;

/// Модул калити (сервер `SPECS`) → ёрлиқ; тартиб шу.
const kStaleModuleLabels = <String, String>{
  'courier_orders': 'Курьер буюртмалари (йўлда)',
  'restaurant_orders': 'Ресторан буюртмалари (курьерли)',
  'carpet': 'Гилам юваш',
  'agro': 'Сут қабул',
  'relay_shipments': 'Жўнатмалар (AVA Logistics)',
  'relay_legs': 'Жўнатма босқичлари (LEG)',
};

class StaleItem {
  const StaleItem({required this.id, this.status = '', this.courierId = '', this.ageHours, this.updatedAtMs});

  final String id;
  final String status;
  final String courierId;

  /// Ёши (соат); `null` — вақти номаълум.
  final double? ageHours;
  final int? updatedAtMs;
}

class StaleModule {
  const StaleModule({this.items = const [], this.total = 0, this.scanned = 0, this.truncated = false});

  final List<StaleItem> items;
  final int total;
  final int scanned;

  /// Сервер рўйхатни/сканни чеклади — «кўпроқ бор».
  final bool truncated;

  static StaleModule fromMap(Object? raw) {
    if (raw is! Map) return const StaleModule();
    final rawItems = raw['items'];
    final items = <StaleItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is! Map) continue;
        final age = e['ageHours'];
        final at = e['updatedAtMs'];
        items.add(StaleItem(
          id: (e['id'] ?? '').toString(),
          status: (e['status'] ?? '').toString(),
          courierId: (e['courierId'] ?? '').toString(),
          ageHours: age is num ? age.toDouble() : null,
          updatedAtMs: at is num ? at.toInt() : null,
        ));
      }
    }
    final total = raw['total'];
    final scanned = raw['scanned'];
    return StaleModule(
      items: items,
      total: total is num ? total.toInt() : items.length,
      scanned: scanned is num ? scanned.toInt() : 0,
      truncated: raw['truncated'] == true,
    );
  }
}

class StaleTasksResult {
  const StaleTasksResult({required this.hours, this.generatedAtMs, this.modules = const {}});

  final int hours;
  final int? generatedAtMs;
  final Map<String, StaleModule> modules;

  int get totalAll => modules.values.fold(0, (a, m) => a + m.total);

  static StaleTasksResult fromMap(Map<String, dynamic> m) {
    final raw = m['modules'];
    final mods = raw is Map ? raw : const {};
    final h = m['hours'];
    final g = m['generatedAtMs'];
    return StaleTasksResult(
      hours: h is num ? h.toInt() : kStaleDefaultHours,
      generatedAtMs: g is num ? g.toInt() : null,
      modules: {
        for (final k in kStaleModuleLabels.keys) k: StaleModule.fromMap(mods[k]),
      },
    );
  }
}

/// Соат майдони → 1..168 бутун; нотўғри — `null`.
int? parseStaleHours(String text) {
  final v = int.tryParse(text.trim());
  if (v == null || v < kStaleMinHours || v > kStaleMaxHours) return null;
  return v;
}

/// Ёш матни: 5,2 соат · 2 кун 3 соат · номаълум.
String formatStaleAge(double? hours) {
  if (hours == null) return 'вақти номаълум';
  if (hours < 48) {
    final s = hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toStringAsFixed(1).replaceAll('.', ',');
    return '$s соат';
  }
  final days = hours ~/ 24;
  final rest = (hours - days * 24).floor();
  return '$days кун${rest > 0 ? ' $rest соат' : ''}';
}
