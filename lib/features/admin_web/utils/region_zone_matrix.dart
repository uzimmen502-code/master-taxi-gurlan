// Логистика тарифи — ВИЛОЯТЛАР МАТРИЦАСИ (Ulgurji Q-6, 2026-10-31) — СОФ мантиқ.
//
// Сервер шакли (`functions_demand/core/tariff.js` `validateTariff` / `resolveZone`):
//   tariff.matrix.regions = { <originRegionId>: { <destRegionId>: 'ZONE_0'..'ZONE_5' } }
//   • ҳар қиймат ФАҚАТ 6 зонадан бири (null/бўш қатор рад этилмайди, null қиймат РАД);
//   • `regions` бутунлай бўш бўлса қоралама ҳам сақланмайди («kamida bitta juftlik»);
//   • `matrix.symmetric !== false` бўлса сервер тескари йўналишни ҳам қарайди.
//
// Админ жадвали: N×N (N — `geo_regions` сони, кутилган 14), фақат ЮҚОРИ учбурчак
// (диагонал билан) таҳрирланади, пасткиси — кўзгу. Юборишда ИККАЛА йўналиш ёзилади
// (`symmetric` байроғига боғлиқ бўлмасин). Бўш катак — юборилмайди (стандарт ЙЎҚ —
// CLAUDE.md §10: матрица authoritative, зона ўйлаб топилмайди).
// Жадвалдан ташқаридаги ҳудуд ID'лари (масалан эски seed) — ЎЗГАРИШСИЗ сақланади.

/// 6 зона (`core/tariff.js` `ZONES`, CLAUDE.md §10).
const kTariffZones = <String>['ZONE_0', 'ZONE_1', 'ZONE_2', 'ZONE_3', 'ZONE_4', 'ZONE_5'];

class MatrixRegion {
  const MatrixRegion(this.id, this.label);

  final String id;
  final String label;
}

class RegionZoneMatrix {
  RegionZoneMatrix._(this.regionIds, this._cells, this._conflicts, this._invalid, this._foreign);

  /// Жадвал тартиби (сатр = устун).
  final List<String> regionIds;

  /// `i|j` (i ≤ j) → зона.
  final Map<String, String> _cells;

  /// Ҳужжатда икки йўналиш ҲАР ХИЛ зона — админ кўриб ҳал қилмагунча сақлаш йўқ.
  final Set<String> _conflicts;

  /// Ҳужжатдаги нотўғри қиймат (6 зонадан эмас) — бўш деб кўрсатилади, огоҳлантирилади.
  final Set<String> _invalid;

  /// Жадвалдан ташқари ҳудуд иштирок этган жуфтликлар (ўзгаришсиз қайтади).
  final Map<String, Map<String, Object?>> _foreign;

  static String _key(int a, int b) => a <= b ? '$a|$b' : '$b|$a';

  /// [regions] — `tariff.matrix.regions` (ёки `null`).
  factory RegionZoneMatrix.fromTariff(List<String> regionIds, Object? regions) {
    final index = <String, int>{for (var i = 0; i < regionIds.length; i += 1) regionIds[i]: i};
    final cells = <String, String>{};
    final conflicts = <String>{};
    final invalid = <String>{};
    final foreign = <String, Map<String, Object?>>{};
    if (regions is Map) {
      regions.forEach((o, row) {
        final origin = o.toString();
        if (row is! Map) {
          // Сервер бундайни қабул қилмайди; ўзгаришсиз қолдирамиз (админ JSON'да кўради).
          foreign[origin] = {'__invalid_row__': row};
          return;
        }
        row.forEach((d, z) {
          final dest = d.toString();
          final oi = index[origin];
          final di = index[dest];
          if (oi == null || di == null) {
            (foreign[origin] ??= <String, Object?>{})[dest] = z;
            return;
          }
          final k = _key(oi, di);
          if (z is! String || !kTariffZones.contains(z)) {
            invalid.add(k);
            return;
          }
          final prev = cells[k];
          if (prev == null) {
            cells[k] = z;
          } else if (prev != z) {
            conflicts.add(k);
            // Юқори учбурчак йўналиши (кичик индекс → катта) устун.
            if (oi <= di) cells[k] = z;
          }
        });
      });
    }
    invalid.removeAll(cells.keys);
    return RegionZoneMatrix._(List.unmodifiable(regionIds), cells, conflicts, invalid, foreign);
  }

  int get size => regionIds.length;

  /// Диагонал билан: N·(N+1)/2.
  int get totalPairs => size * (size + 1) ~/ 2;
  int get filledPairs => _cells.length;
  int get emptyPairs => totalPairs - filledPairs;

  bool get hasConflicts => _conflicts.isNotEmpty;
  int get conflictCount => _conflicts.length;
  bool isConflict(int row, int col) => _conflicts.contains(_key(row, col));
  bool isInvalid(int row, int col) => _invalid.contains(_key(row, col));
  int get invalidCount => _invalid.length;

  /// Жадвалдан ташқари ҳудуд жуфтликлари сони (ўзгармайди).
  int get foreignPairCount => _foreign.values.fold(0, (s, r) => s + r.length);

  /// Катак таҳрирланадими (юқори учбурчак + диагонал).
  static bool isEditable(int row, int col) => col >= row;

  String? zoneAt(int row, int col) => _cells[_key(row, col)];

  /// [zone] `null` — бўш (жуфтлик юборилмайди). Конфликт шу катакда ҳал бўлади.
  void setZone(int row, int col, String? zone) {
    if (zone != null && !kTariffZones.contains(zone)) {
      throw ArgumentError.value(zone, 'zone', 'ZONE_0..ZONE_5 ёки null');
    }
    final k = _key(row, col);
    if (zone == null) {
      _cells.remove(k);
    } else {
      _cells[k] = zone;
    }
    _conflicts.remove(k);
    _invalid.remove(k);
  }

  /// `matrix.regions` учун тўлиқ қиймат: жадвал жуфтликлари ИККАЛА йўналишда
  /// (диагонал бир марта) + жадвалдан ташқари жуфтликлар ўзгаришсиз. Бўш катак ва
  /// бўш сатр йўқ, `null` қиймат йўқ.
  Map<String, Map<String, Object?>> toRegionsPayload() {
    final out = <String, Map<String, Object?>>{};
    _foreign.forEach((o, row) {
      if (row.containsKey('__invalid_row__')) return;
      out[o] = {...row};
    });
    final keys = _cells.keys.toList()..sort();
    for (final k in keys) {
      final parts = k.split('|');
      final a = regionIds[int.parse(parts[0])];
      final b = regionIds[int.parse(parts[1])];
      final z = _cells[k]!;
      (out[a] ??= <String, Object?>{})[b] = z;
      (out[b] ??= <String, Object?>{})[a] = z;
    }
    out.removeWhere((_, row) => row.isEmpty);
    return out;
  }

  /// Ҳужжатдаги нотўғри сатр (Map эмас) — сақлашда тушиб қолмаслиги учун огоҳлантириш.
  bool get hasInvalidRows => _foreign.values.any((r) => r.containsKey('__invalid_row__'));

  /// Тариф ҳужжати + янги `matrix.regions` (бошқа `matrix` калитлари — `districts`,
  /// `symmetric` — ва ҳужжатнинг қолгани ўзгармайди).
  Map<String, dynamic> applyToTariff(Map<String, dynamic> tariff) {
    final m = tariff['matrix'];
    final matrix = m is Map ? m.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    return {
      ...tariff,
      'matrix': {...matrix, 'regions': toRegionsPayload()},
    };
  }

  /// Сақлаш мумкинми: конфликт йўқ, нотўғри сатр йўқ ва камида битта жуфтлик бор
  /// (сервер бўш `regions`ни қоралама учун ҳам рад этади).
  String? get saveBlocker {
    if (hasConflicts) return 'Икки йўналиши ҳар хил зонали $conflictCount та жуфтлик бор — қизил катакларни кўриб чиқинг';
    if (hasInvalidRows) return 'matrix.regions ичида нотўғри сатр бор — JSON таҳририда тузатинг';
    if (toRegionsPayload().isEmpty) return 'Камида битта жуфтликка зона беринг (сервер бўш матрицани қабул қилмайди)';
    return null;
  }
}

/// Тарифдаги жадвал тўлдирилганлиги (рўйхат учун қисқа ҳисоб).
({int filled, int total}) regionMatrixFill(List<String> regionIds, Object? regions) {
  final m = RegionZoneMatrix.fromTariff(regionIds, regions);
  return (filled: m.filledPairs, total: m.totalPairs);
}
