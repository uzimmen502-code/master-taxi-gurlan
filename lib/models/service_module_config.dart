/// Ilovadagi barcha mumkin bo'lgan modul ID'lari (fallback va admin ro'yxati uchun).
/// Home xizmatlar grididagi 17 ta xizmat bilan sinxron.
const List<String> kKnownModuleIds = [
  'local_taxi',
  'intercity',
  'marshrut',
  'yuk_birja',
  'courier',
  'sell',
  'food',
  'jobs',
  'cheap_products_home',
  'bread',
  'carpet_wash',
  'circles',
  'dating',
  'milk',
  'tire',
  'car_wash',
  'oil_change',
  'platform_store',
  'tv_market',
];

/// Modul mavjudlik holati — Home ekran dinamik qurishi uchun.
enum ModuleStatus {
  /// Ko'rinadi va ochiladi.
  enabled,

  /// Ko'rinadi, lekin "Tez orada" — bosilmaydi/ogohlantiradi.
  comingSoon,

  /// Umuman ko'rsatilmaydi.
  hidden;

  bool get isVisible => this == enabled || this == comingSoon;
  bool get isOpenable => this == enabled;

  String get wire => switch (this) {
        ModuleStatus.enabled => 'enabled',
        ModuleStatus.comingSoon => 'coming_soon',
        ModuleStatus.hidden => 'hidden',
      };

  static ModuleStatus fromWire(Object? raw) {
    switch ((raw ?? '').toString().trim().toLowerCase()) {
      case 'enabled':
      case 'true':
        return ModuleStatus.enabled;
      case 'coming_soon':
      case 'comingsoon':
      case 'soon':
        return ModuleStatus.comingSoon;
      case 'hidden':
      case 'false':
      case 'disabled':
        return ModuleStatus.hidden;
      default:
        return ModuleStatus.hidden;
    }
  }
}

/// Modul mavjudligi konfiguratsiyasi — `moduleId → ModuleStatus`.
///
/// Ikki qatlam bir-biriga qo'shiladi (merge):
///   1. `config/module_defaults` — global baseline (masalan intercity hamma joyda)
///   2. `service_area_modules/{serviceAreaId}` — faqat farqlar (override)
///
/// Yakuniy mavjudlik: [merge] = default ustiga area override.
class ServiceModuleConfig {
  const ServiceModuleConfig(this.modules);

  final Map<String, ModuleStatus> modules;

  static const ServiceModuleConfig empty =
      ServiceModuleConfig(<String, ModuleStatus>{});

  /// Ma'lum moduldagi holat — topilmasa [fallback] (default: hidden).
  ModuleStatus statusOf(String moduleId,
          {ModuleStatus fallback = ModuleStatus.hidden}) =>
      modules[moduleId] ?? fallback;

  bool isVisible(String moduleId) => statusOf(moduleId).isVisible;
  bool isOpenable(String moduleId) => statusOf(moduleId).isOpenable;

  /// Firestore `modules` xaritasidan.
  /// Ikkala shakl qo'llab-quvvatlanadi:
  ///   { "intercity": { "status": "enabled" } }
  ///   { "intercity": "enabled" }
  factory ServiceModuleConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return empty;
    final raw = data['modules'];
    final source = raw is Map ? raw : data;
    final out = <String, ModuleStatus>{};
    source.forEach((key, value) {
      final id = key.toString();
      if (value is Map) {
        out[id] = ModuleStatus.fromWire(value['status']);
      } else {
        out[id] = ModuleStatus.fromWire(value);
      }
    });
    return ServiceModuleConfig(out);
  }

  Map<String, dynamic> toMap() => {
        'modules': {
          for (final e in modules.entries) e.key: {'status': e.value.wire},
        },
      };

  /// [override] ustunlik qiladi: har bir modul kaliti bo'yicha almashtiradi.
  ServiceModuleConfig merge(ServiceModuleConfig override) {
    if (override.modules.isEmpty) return this;
    return ServiceModuleConfig({
      ...modules,
      ...override.modules,
    });
  }

  /// Barcha [ids] `enabled` bo'lgan fallback — konfig umuman yo'q bo'lsa
  /// ilova hozirgidek ishlashi uchun (buzilmaslik kafolati).
  factory ServiceModuleConfig.allEnabled(Iterable<String> ids) =>
      ServiceModuleConfig({for (final id in ids) id: ModuleStatus.enabled});

  /// Keshga saqlash uchun `moduleId → wire` sodda xaritasi.
  Map<String, String> toCacheMap() =>
      {for (final e in modules.entries) e.key: e.value.wire};

  factory ServiceModuleConfig.fromCacheMap(Map<String, String>? cache) {
    if (cache == null || cache.isEmpty) return empty;
    return ServiceModuleConfig({
      for (final e in cache.entries) e.key: ModuleStatus.fromWire(e.value),
    });
  }
}
