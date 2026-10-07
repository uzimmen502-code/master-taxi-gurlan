// AVA LOGISTICS — тариф нархларини ФОИЗГА ўзгартириш (admin «битта тугма»).
//
// Соф Dart, пул — БУТУН сўм (8-банд): фоиз bps (1/100 %) бутун сонда,
// ярим юқорига яхлитланади, кейин қадамга (1 / 100 / 1000 сўм). Натижа
// admin callable (`adminUpsertLogisticsTariff`) орқали ЯНГИ версия
// сифатида серверга боради — сервер яна текширади (мусбат бутун сонлар).

/// `price × (1 + percentBps/10000)`, бутун сўм, ярим юқорига; кейин
/// [step]га яхлитланади. Манфий натижа бўлмайди (0 дан кам эмас).
int adjustPrice(int price, {required int percentBps, int step = 1}) {
  assert(step > 0, 'step > 0');
  final scaled = price * (10000 + percentBps);
  var v = scaled <= 0 ? 0 : (scaled + 5000) ~/ 10000;
  if (step > 1) v = ((v + step ~/ 2) ~/ step) * step;
  return v;
}

/// Поғона нархи ҳеч қачон 0 бўлмасин (сервер мусбат бутун талаб қилади):
/// камида [step] (step=1 бўлса камида 1).
int adjustBracketPrice(int price, {required int percentBps, int step = 1}) {
  final v = adjustPrice(price, percentBps: percentBps, step: step);
  return v < 1 ? (step > 1 ? step : 1) : v;
}

/// «-10», «12,5», «+7.25» → bps (−1000, 1250, 725). Нотўғри матн → null.
int? percentTextToBps(String text) {
  final t = text.trim().replaceAll(',', '.').replaceAll('+', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

/// bps → «20» / «12.5» (фоиз матни, ортиқча нолсиз).
String bpsToPercentText(int bps) {
  if (bps % 100 == 0) return (bps ~/ 100).toString();
  final s = (bps / 100).toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Тарифнинг `prices` map'ини фоизга ўзгартиради:
/// `{ZONE: {brackets: [...], extraPerKg: n}}` → янги map (эскиси ўзгармайди).
Map<String, Map<String, dynamic>> adjustTariffPrices(
  Map<String, dynamic> prices, {
  required int percentBps,
  int step = 1,
}) {
  final out = <String, Map<String, dynamic>>{};
  prices.forEach((zone, raw) {
    if (raw is! Map) return;
    final brackets = (raw['brackets'] is List)
        ? (raw['brackets'] as List)
            .map((v) => adjustBracketPrice(_asInt(v), percentBps: percentBps, step: step))
            .toList()
        : <int>[];
    out[zone] = {
      'brackets': brackets,
      // null — «ҳали берилмаган»: 0 га айлантирилмайди (сервер фаоллаштиришни блоклайди).
      'extraPerKg': raw['extraPerKg'] == null
          ? null
          : adjustPrice(_asInt(raw['extraPerKg']), percentBps: percentBps, step: step),
    };
  });
  return out;
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse((v ?? '').toString().replaceAll(RegExp(r'\s'), '')) ?? 0;
}
