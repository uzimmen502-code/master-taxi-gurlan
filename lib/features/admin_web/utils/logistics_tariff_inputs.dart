// AVA Logistics тарифи — админ формасидаги қўшимча майдонлар (соф мантиқ).
//
// `volumetricDivisor` — ҳажмий вазн бўлувчиси (L×W×H / divisor). Қиймат —
// ЭГА ҚАРОРИ (12-банд): форма сукут қиймат ўйлаб топмайди; бўш майдон =
// «ўзгартирилмайди» (мавжуд қолади). Сервер: мусбат бутун сон
// (`core/tariff.js` → `isPosInt`).

class DivisorInput {
  const DivisorInput({this.value, this.error});

  /// `null` — майдон бўш (ҳужжатдаги қиймат сақланади) ёки хато.
  final int? value;
  final String? error;
}

DivisorInput parseVolumetricDivisor(String text) {
  final t = text.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return const DivisorInput();
  final v = int.tryParse(t);
  if (v == null || v <= 0 || t.contains(RegExp(r'[^\d]'))) {
    return const DivisorInput(error: 'Ҳажмий вазн бўлувчиси — мусбат бутун сон');
  }
  return DivisorInput(value: v);
}
