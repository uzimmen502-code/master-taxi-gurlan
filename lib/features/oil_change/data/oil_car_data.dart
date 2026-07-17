// Avtomobil faktlari — motor moy hajmi va kilometraj bo'yicha tavsiyalar.
//
// Manba ajratmasi (chalkashmaslik uchun bitta manba):
//  • Sotuv katalogi (OilProduct) → oil_catalog.dart
//  • SAE ma'lumotnoma katalogi (OilRefProduct) → oil_ref_catalog.dart
//  • Avto faktlari (hajm + kilometraj) → shu fayl
//
// Hub («Мой алмаштириш») faqat shu faylni va oil_catalog.dart ni ishlatadi.

import 'oil_l10n.dart';

/// Motor kilometraji → соғлом / эътиборсиз tavsiya qatori.
class MileageReco {
  const MileageReco(
    this.range,
    this.healthy,
    this.neglected, {
    this.warn = false,
  });
  final L3 range;
  final L3 healthy;
  final L3 neglected;
  final bool warn;
}

/// Model uchun motor moy hajmi.
class OilModelCapacity {
  const OilModelCapacity({
    required this.engine,
    required this.oilCapacity,
    required this.filterCapacity,
    required this.total,
  });
  final String engine;
  final String oilCapacity;
  final String filterCapacity;
  final String total;
}

abstract final class OilCarData {
  // ─── MODEL BO'YICHA MOY HAJMI ──────────────────────────────

  static const modelCapacities = <String, OilModelCapacity>{
    'Damas': OilModelCapacity(
      engine: '0.8L (F8C)',
      oilCapacity: '2.7',
      filterCapacity: '0.2',
      total: '2.9',
    ),
    'Matiz': OilModelCapacity(
      engine: '0.8L / 1.0L',
      oilCapacity: '2.7',
      filterCapacity: '0.2',
      total: '2.9 / 3.2',
    ),
    'Nexia 1': OilModelCapacity(
      engine: '1.5L / 1.6L',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8',
    ),
    'Nexia 2': OilModelCapacity(
      engine: '1.5L / 1.6L',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8 / 4.0',
    ),
    'Nexia 3': OilModelCapacity(
      engine: '1.5L (L2B)',
      oilCapacity: '3.7',
      filterCapacity: '0.3',
      total: '4.0',
    ),
    'Spark': OilModelCapacity(
      engine: '1.0L / 1.2L',
      oilCapacity: '3.2',
      filterCapacity: '0.2',
      total: '3.4 / 3.7',
    ),
    'Cobalt': OilModelCapacity(
      engine: '1.5L (L2B)',
      oilCapacity: '3.7',
      filterCapacity: '0.3',
      total: '4.0',
    ),
    'Gentra': OilModelCapacity(
      engine: '1.5L (B15D2)',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8',
    ),
    'Lacetti': OilModelCapacity(
      engine: '1.4L / 1.6L',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8 / 4.0',
    ),
    'Malibu': OilModelCapacity(
      engine: '1.5T / 2.0T',
      oilCapacity: '4.0',
      filterCapacity: '0.3',
      total: '4.3 / 5.0',
    ),
    'Tracker': OilModelCapacity(
      engine: '1.0T / 1.2T',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8 / 4.2',
    ),
  };

  /// Кирилл / ностандарт ёзилган модел номлари → каталог калити.
  static const _modelAliases = <String, String>{
    'damas': 'Damas',
    'дамас': 'Damas',
    'matiz': 'Matiz',
    'матиз': 'Matiz',
    'nexia': 'Nexia',
    'нексия': 'Nexia',
    'nexia 3': 'Nexia 3',
    'нексия 3': 'Nexia 3',
    'spark': 'Spark',
    'спарк': 'Spark',
    'cobalt': 'Cobalt',
    'кобальт': 'Cobalt',
    'gentra': 'Gentra',
    'гентра': 'Gentra',
    'джентра': 'Gentra',
    'lacetti': 'Lacetti',
    'лачетти': 'Lacetti',
    'лачети': 'Lacetti',
    'malibu': 'Malibu',
    'малибу': 'Malibu',
    'tracker': 'Tracker',
    'трекер': 'Tracker',
  };

  static OilModelCapacity? modelCapacity(String model) =>
      modelCapacities[model];

  static String? _canonicalModelKey(String model) {
    final raw = model.trim();
    if (raw.isEmpty) return null;
    if (modelCapacities.containsKey(raw)) return raw;
    final aliased = _modelAliases[raw.toLowerCase()];
    if (aliased != null && modelCapacities.containsKey(aliased)) {
      return aliased;
    }
    final m = raw.toLowerCase();
    String? best;
    var bestLen = 0;
    for (final key in modelCapacities.keys) {
      final k = key.toLowerCase();
      if (k == m) return key;
      if (m.contains(k) || k.contains(m)) {
        if (k.length >= bestLen) {
          bestLen = k.length;
          best = key;
        }
      }
    }
    // Alias fuzzy: «малибу 1.5» → малибу
    for (final e in _modelAliases.entries) {
      if (m.contains(e.key) || e.key.contains(m)) {
        if (e.key.length >= bestLen) {
          bestLen = e.key.length;
          best = e.value;
        }
      }
    }
    return best;
  }

  /// Сақланган модел номи бўйича ҳажм (Latin/Cyrillic + fuzzy).
  static OilModelCapacity? resolveCapacity(String model) {
    final key = _canonicalModelKey(model);
    if (key == null) return null;
    return modelCapacities[key];
  }

  /// Модел номи бўйича каталог калити (ҳажм картаси учун).
  static String? resolveCapacityModelKey(String model) =>
      _canonicalModelKey(model);

  // ─── KILOMETRAJ BO'YICHA TAVSIYALAR ────────────────────────

  static const mileageRecos = <MileageReco>[
    MileageReco(
      L3('0–80/150 минг', '0–80/150 ming', '0–80/150 тыс.'),
      L3('0W-20 / 5W-30', '0W-20 / 5W-30', '0W-20 / 5W-30'),
      L3('5W-30', '5W-30', '5W-30'),
    ),
    MileageReco(
      L3('150–300 минг', '150–300 ming', '150–300 тыс.'),
      L3('5W-30 / 5W-40', '5W-30 / 5W-40', '5W-30 / 5W-40'),
      L3('5W-40', '5W-40', '5W-40'),
    ),
    MileageReco(
      L3('300–450 минг', '300–450 ming', '300–450 тыс.'),
      L3('5W-30 / 5W-40', '5W-30 / 5W-40', '5W-30 / 5W-40'),
      L3('5W-40', '5W-40', '5W-40'),
    ),
    MileageReco(
      L3('450 минг+', '450 ming+', '450 тыс.+'),
      L3('Ҳолатига қараб', 'Holatiga qarab', 'По состоянию'),
      L3('5W-40 / 10W-40', '5W-40 / 10W-40', '5W-40 / 10W-40'),
    ),
    MileageReco(
      L3('Мой сарфлайди', 'Moy sarflaydi', 'Расходует масло'),
      L3('10W-40 / 15W-40', '10W-40 / 15W-40', '10W-40 / 15W-40'),
      L3('10W-40 / 15W-40', '10W-40 / 15W-40', '10W-40 / 15W-40'),
      warn: true,
    ),
  ];
}
