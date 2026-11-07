// Админ: бўлак (LEG) ҳақини қўлда ўзгартириш — киритишни текшириш (соф Dart).
//
// Эга 2026-11-07: админ ҳар бўлак ҳақини ўзгартира олади; йиғинди ижрочилар
// пулига (provider pool) тенг бўлиши ШАРТ. Сервер (`adminPlanShipmentRoute`,
// `payoutOverrides`) ҳал қилувчи — бу ерда фақат аниқ хатони эртароқ кўрсатиш.
// Пул — бутун сўм (8-банд): каср, манфий ва 0 рад этилади.

/// Текширув натижаси: [overrides] (`[{legIndex, amount}]`) ёки [error].
class PayoutOverrideCheck {
  const PayoutOverrideCheck._(this.overrides, this.error, this.sum);

  final List<Map<String, int>>? overrides;
  final String? error;

  /// Киритилган бутун сонлар йиғиндиси (хато бўлса — ўқилганлари).
  final int sum;

  bool get isValid => error == null && overrides != null;
}

/// «48 000», «48000» → 48000. Бўш, каср, ҳарф → `null`.
int? parseAdminSum(String text) {
  final t = text.replaceAll(RegExp(r'[\s ]'), '');
  if (t.isEmpty || !RegExp(r'^-?\d+$').hasMatch(t)) return null;
  return int.tryParse(t);
}

/// Ҳар бўлак ҳақини текширади. [pool] — жорий бўлак ҳақлари йиғиндиси
/// (ижрочилар пули); `null` ёки ≤ 0 бўлса текшириб бўлмайди.
PayoutOverrideCheck validatePayoutOverrides(List<String> texts, {required int? pool}) {
  if (texts.isEmpty) return const PayoutOverrideCheck._(null, 'Бўлаклар йўқ', 0);
  if (pool == null || pool <= 0) {
    return const PayoutOverrideCheck._(
        null, 'Ижрочилар пули номаълум (бўлак ҳақлари ўқилмади) — ўзгартириб бўлмайди', 0);
  }
  final out = <Map<String, int>>[];
  var sum = 0;
  for (var i = 0; i < texts.length; i += 1) {
    final v = parseAdminSum(texts[i]);
    if (v == null) {
      return PayoutOverrideCheck._(null, '${i + 1}-бўлак: бутун сўм киритинг', sum);
    }
    if (v <= 0) {
      return PayoutOverrideCheck._(null, '${i + 1}-бўлак: ҳақ 0 дан катта бўлиши керак', sum);
    }
    sum += v;
    out.add({'legIndex': i, 'amount': v});
  }
  if (sum != pool) {
    final diff = sum - pool;
    return PayoutOverrideCheck._(
      null,
      'Йиғинди $sum, ижрочилар пули $pool — фарқ ${diff > 0 ? '+' : ''}$diff сўм',
      sum,
    );
  }
  return PayoutOverrideCheck._(out, null, sum);
}
