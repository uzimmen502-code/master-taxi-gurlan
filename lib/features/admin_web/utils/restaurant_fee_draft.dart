// Кафе-ресторан: AVA ҳақи (фоиз) ва тун коэффициенти — админ формасининг СОФ
// мантиқи. Ёзув: `adminSetRestaurantFeeSettings({avaFeeBps?, nightCoef?,
// reason})` (default, us-central1). Ўқиш: `settings/restaurant_delivery`
// (`avaFeeBps` — йўқ бўлса сервер стандартни ишлатади, `nightCoef`, `version`).
//
// Экран фоизни (bps/100) кўрсатади ва киритилганини bps'га айлантиради; чегара
// ва ҳисоб-китоб СЕРВЕРДА (бу ерда фақат ақлли текширув).

import '../../logistics/domain/tariff_adjust.dart' show bpsToPercentText, percentTextToBps;

/// Стандарт AVA ҳақи (bps) — ФАҚАТ кўрсатиш учун матн (`avaFeeBps` йўқ бўлганда
/// сервер шуни қўллайди: 200 bps = 2 %). Ҳисоб серверда.
const int kRestaurantStandardFeeBps = 200;

class RestaurantFeeCurrent {
  const RestaurantFeeCurrent({this.avaFeeBps, this.nightCoef, this.version = 0});

  /// `null` — ҳужжатда йўқ (стандарт).
  final int? avaFeeBps;
  final double? nightCoef;
  final int version;

  static RestaurantFeeCurrent fromDoc(Map<String, dynamic>? d) {
    final data = d ?? const <String, dynamic>{};
    final fee = data['avaFeeBps'];
    final night = data['nightCoef'];
    final ver = data['version'];
    return RestaurantFeeCurrent(
      avaFeeBps: fee is num ? fee.toInt() : null,
      nightCoef: night is num ? night.toDouble() : null,
      version: ver is num ? ver.toInt() : 0,
    );
  }

  /// Майдонда кўрсатиладиган фоиз («2», «2.5»); йўқ бўлса бўш.
  String get feePercentText => avaFeeBps == null ? '' : bpsToPercentText(avaFeeBps!);

  String get nightCoefText {
    final n = nightCoef;
    if (n == null) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }
}

class RestaurantFeePlan {
  const RestaurantFeePlan({this.payload, this.errors = const []});

  /// Юбориладиган майдонлар (reason'сиз). `null` ва `errors` бўш — ўзгариш йўқ.
  final Map<String, dynamic>? payload;
  final List<String> errors;

  bool get hasChange => payload != null && payload!.isNotEmpty;
}

/// Майдон матнларидан ўзгаришлар режаси. Фақат ЎЗГАРГАН майдонлар юборилади.
///  • AVA ҳақи: бўш ёки «стандарт» → `null` (стандартга қайтариш); аксы —
///    фоиз 0..100 (иккита ўнли хонагача);
///  • тун коэффициенти: бўш = ўзгармайди; 1..3.
RestaurantFeePlan planRestaurantFeeChange({
  required RestaurantFeeCurrent current,
  required String feeText,
  required String nightText,
}) {
  final errors = <String>[];
  final payload = <String, dynamic>{};

  final feeRaw = feeText.trim().toLowerCase();
  const resetWords = {'', 'стандарт', 'standart', 'standard', 'стандартный'};
  if (resetWords.contains(feeRaw)) {
    if (current.avaFeeBps != null) payload['avaFeeBps'] = null;
  } else {
    final bps = percentTextToBps(feeRaw);
    if (bps == null || bps < 0 || bps > 10000) {
      errors.add('AVA ҳақи: 0..100 % оралиғида фоиз (масалан 2 ёки 2,5)');
    } else if (bps != current.avaFeeBps) {
      payload['avaFeeBps'] = bps;
    }
  }

  final night = nightText.trim();
  if (night.isNotEmpty) {
    final c = double.tryParse(night.replaceAll(',', '.'));
    if (c == null || c.isNaN || c < 1 || c > 3) {
      errors.add('Тун коэффициенти: 1..3');
    } else if (c != current.nightCoef) {
      payload['nightCoef'] = c;
    }
  }

  if (errors.isNotEmpty) return RestaurantFeePlan(errors: errors);
  return RestaurantFeePlan(payload: payload);
}
