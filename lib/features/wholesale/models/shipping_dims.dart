// Улгуржи товарнинг етказиш параметрлари — СОФ мантиқ (Firestore'сиз,
// тестланади). Етказиш ҳақи ҳисоби учун сотувчи БИР ДОНА товарнинг
// вазни (грамм) ва ўлчамини (см) киритади; тизим ҳажмий вазнни ҳисоблайди.
//
// Қоида — relay тариф двигатели билан бир хил (`functions_demand/core/tariff.js`):
//   volumetricG = ceil(L × W × H × 1000 / divisor),  divisor = 6000 (BTS,
//   «Умумий шартлар» 1-илова; AVA учун конфиг — docs/relay §7.5)
//   chargeableG = max(actualG, volumetricG)
// Нарх шу ерда ҳисобланмайди (18-банд): фақат вазн — ҳақни сервер беради.

/// BTS ички ташиш бўлувчиси (BTS_CONFIRMED). AVA қиймати конфигдан келади;
/// бу — клиентдаги кўрсатиш учун стандарт.
const int kDefaultVolumetricDivisor = 6000;

/// Чегаралар — Firestore Rules билан бир хил (`wholesaleProductCreateOk`).
const int kMaxUnitWeightG = 10000000; // 10 т
const int kMaxDimCm = 1000;

class ShippingDims {
  const ShippingDims({required this.l, required this.w, required this.h});

  /// Сантиметр, бутун сон, ҳар бири 1..[kMaxDimCm].
  final int l;
  final int w;
  final int h;

  bool get isValid =>
      l >= 1 && l <= kMaxDimCm && w >= 1 && w <= kMaxDimCm && h >= 1 && h <= kMaxDimCm;

  /// `{l, w, h}` — Firestore майдони `unitDims`. Нотўғри шакл → `null`.
  static ShippingDims? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final l = _int(raw['l']);
    final w = _int(raw['w']);
    final h = _int(raw['h']);
    if (l == null || w == null || h == null) return null;
    final d = ShippingDims(l: l, w: w, h: h);
    return d.isValid ? d : null;
  }

  Map<String, int> toMap() => {'l': l, 'w': w, 'h': h};

  /// Ҳажмий вазн, грамм — юқорига яхлитланади (сервер билан бир хил).
  int volumetricWeightG({int divisor = kDefaultVolumetricDivisor}) {
    final num = l * w * h * 1000;
    return (num + divisor - 1) ~/ divisor;
  }

  /// «30×20×15 см».
  String get label => '$l×$w×$h см';

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ShippingDims && other.l == l && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(l, w, h);
}

/// Пулли (тариф учун) вазн — ҳақиқий ва ҳажмийнинг каттаси. Ўлчам
/// бўлмаса — ҳақиқий вазн.
int chargeableWeightG(
  int actualG,
  ShippingDims? dims, {
  int divisor = kDefaultVolumetricDivisor,
}) {
  if (dims == null) return actualG;
  final v = dims.volumetricWeightG(divisor: divisor);
  return v > actualG ? v : actualG;
}

/// Фойдаланувчи киритган килограмм матни → грамм (бутун). `1,25` ва `1.25`
/// қабул қилинади; нотўғри/нол/чегарадан ташқари → `null`.
int? parseWeightKgToGrams(String raw) {
  final s = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  final kg = double.tryParse(s);
  if (kg == null || kg <= 0) return null;
  final g = (kg * 1000).round();
  if (g < 1 || g > kMaxUnitWeightG) return null;
  return g;
}

/// Грамм → форма майдони учун килограмм матни («1,25», «0,8», «12»).
String weightKgFieldText(int g) {
  if (g <= 0) return '';
  var s = (g / 1000).toStringAsFixed(3);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

/// Грамм → «1,25 кг» / «800 г» (кўрсатиш учун).
String formatWeightG(int g) {
  if (g < 1000) return '$g г';
  final kg = g / 1000;
  final s = kg == kg.roundToDouble()
      ? kg.toInt().toString()
      : kg.toStringAsFixed(kg * 100 == (kg * 100).roundToDouble() ? 2 : 3)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
  return '${s.replaceAll('.', ',')} кг';
}
