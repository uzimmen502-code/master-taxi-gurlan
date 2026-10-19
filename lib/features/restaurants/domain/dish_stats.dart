// Таом баҳоси агрегати (D-REST-18/32): `restaurants/{rid}/menu_item_stats/{itemId}`.
//
// Сервер ЯГОНА ёзувчи (`submitDishRatings`); бу ерда фақат ўқиш ва кўрсатиш. Сақланадиган
// қийматлар — бутун сонлар (`ratingSum`, `ratingCount`); ўртача ҳар сафар ҳисобда чиқарилади,
// float сақланмайди.

/// «Янги» чегараси: шунча баҳодан кам бўлса таом «янги» ҳисобланади (эга, 2026-10-19: <5).
/// Бу рақам фақат баҳолар сонига тааллуқли; «30 кундан ошмаган» шарти S3 лента қатламида.
const int dishNewRatingCount = 5;

class DishStats {
  const DishStats({this.ratingSum = 0, this.ratingCount = 0});

  final int ratingSum;
  final int ratingCount;

  static const empty = DishStats();

  /// Ўртача баҳо (1..5); баҳо йўқ бўлса 0.
  double get average => ratingCount > 0 ? ratingSum / ratingCount : 0;

  /// Баҳолар сони чегарадан кам — таом «янги».
  bool get isNew => ratingCount < dishNewRatingCount;

  /// Рўйхатда ★ ни кўрсатиш мумкин: етарли баҳо йиғилган (ресторан каби, 5 та).
  bool get showRating => !isNew;

  factory DishStats.fromMap(Map<String, dynamic>? d) {
    if (d == null) return empty;
    int nonNeg(dynamic v) {
      final n = v is num ? v.toInt() : 0;
      return n < 0 ? 0 : n;
    }

    final count = nonNeg(d['ratingCount']);
    var sum = nonNeg(d['ratingSum']);
    // Бузилган ҳужжатдан ҳимоя: ўртача 1..5 дан чиқмаслиги керак.
    if (count == 0) return empty;
    if (sum < count) sum = count;
    if (sum > count * 5) sum = count * 5;
    return DishStats(ratingSum: sum, ratingCount: count);
  }
}
