/// «Кўчмас мулк» объект сонлари формасини текшириш — админга ТЕЗ хато
/// кўрсатиш учун (қулайлик). Ҳал қилувчи текширув СЕРВЕРДА
/// (`functions/realty_settings.js` `parseCounts`, 18-қоида): қоидалар бир хил.
///
/// Бепул лимит, ахборот пакети ва профессионал режалар — ҳаммаси `settings/app`
/// да; аввал кодда қотирилган эди.
library;

/// Серверда ҳам шундай (`FREE_LIMIT_*`, `PACKAGE_*`, `MAX_PRO_OBJECTS`).
const realtyFreeLimitMin = 1;
const realtyFreeLimitMax = 50;
const realtyPackageSizeMax = 100;
const realtyPackageRowsMax = 6;
const realtyPlanRowsMax = 6;
const realtyPlanObjectsMax = 200;
const realtyPlanDaysMax = 365;

final _planId = RegExp(r'^[a-z0-9_]{2,24}$');

int? _int(String s, int min, int max) {
  final n = int.tryParse(s.trim());
  return n == null || n < min || n > max ? null : n;
}

/// Хато матни ёки `null` (тўғри). [packages] — `(ўлчам, нарх)`,
/// [plans] — `(id, объект, кун, нарх)` матн кўринишида.
String? validateRealtyCounts({
  required String freeLimit,
  required List<(String size, String price)> packages,
  required List<(String id, String objects, String days, String price)> plans,
}) {
  if (freeLimit.trim().isNotEmpty &&
      _int(freeLimit, realtyFreeLimitMin, realtyFreeLimitMax) == null) {
    return 'Бепул лимит $realtyFreeLimitMin…$realtyFreeLimitMax орасида бутун сон бўлиши керак '
        '(бўш қолдирилса — бошланғич қиймат)';
  }

  if (packages.isEmpty || packages.length > realtyPackageRowsMax) {
    return 'Ахборот пакети: 1 тадан $realtyPackageRowsMax тагача қатор бўлиши керак';
  }
  final rows = <({int size, int price})>[];
  for (var i = 0; i < packages.length; i++) {
    final size = _int(packages[i].$1, 1, realtyPackageSizeMax);
    final price = _int(packages[i].$2, 0, 10000000000);
    if (size == null || price == null) {
      return 'Ахборот пакети, ${i + 1}-қатор: ўлчам 1…$realtyPackageSizeMax, нарх — бутун сўм (0 ёки катта)';
    }
    rows.add((size: size, price: price));
  }
  if (rows.map((r) => r.size).toSet().length != rows.length) {
    return 'Ахборот пакети: бир хил ўлчам икки марта киритилган';
  }
  rows.sort((a, b) => a.size.compareTo(b.size));
  for (var i = 1; i < rows.length; i++) {
    final small = rows[i - 1];
    final big = rows[i];
    if (big.price * small.size > small.price * big.size) {
      return '${big.size} объектли пакет битта объект ҳисобида ${small.size} '
          'объектлидан қиммат чиқяпти — уни ҳеч ким олмайди';
    }
  }

  if (plans.isEmpty || plans.length > realtyPlanRowsMax) {
    return 'Профессионал пакет: 1 тадан $realtyPlanRowsMax тагача режа бўлиши керак';
  }
  final ids = <String>{};
  for (var i = 0; i < plans.length; i++) {
    final p = plans[i];
    final id = p.$1.trim();
    if (!_planId.hasMatch(id)) {
      return 'Режа, ${i + 1}-қатор: ном (id) — 2…24 та кичик лотин ҳарф, рақам ёки _ (масалан pro_25)';
    }
    if (_int(p.$2, 1, realtyPlanObjectsMax) == null) {
      return 'Режа «$id»: объект сони 1…$realtyPlanObjectsMax орасида (юқори чегара — тизим хавфсизлиги учун)';
    }
    if (_int(p.$3, 1, realtyPlanDaysMax) == null) {
      return 'Режа «$id»: муддат 1…$realtyPlanDaysMax кун';
    }
    if (_int(p.$4, 0, 10000000000) == null) {
      return 'Режа «$id»: нарх — бутун сўм (0 ёки катта)';
    }
    if (!ids.add(id)) return 'Режа «$id» икки марта киритилган';
  }
  return null;
}

/// Сервер хато сабабини (`reason`) админ тушунадиган матнга айлантиради.
String realtyCountsServerError(String reason) {
  switch (reason) {
    case 'free_limit_invalid':
      return 'Бепул лимит нотўғри ($realtyFreeLimitMin…$realtyFreeLimitMax).';
    case 'package_count_invalid':
      return 'Ахборот пакети қаторлари сони нотўғри.';
    case 'package_invalid':
      return 'Ахборот пакети қаторида ўлчам ёки нарх нотўғри.';
    case 'package_duplicate_size':
      return 'Ахборот пакети: бир хил ўлчам такрорланган.';
    case 'package_per_object':
      return 'Катта пакет битта объект ҳисобида қиммат чиқяпти.';
    case 'plan_count_invalid':
      return 'Профессионал режалар сони нотўғри.';
    case 'plan_invalid':
      return 'Профессионал режада id, объект сони, муддат ёки нарх нотўғри.';
    case 'plan_duplicate_id':
      return 'Профессионал режа id такрорланган.';
    case 'admin_only':
    case 'Admin only':
      return 'Бу созламани фақат админ ўзгартира олади.';
    default:
      return 'Сақлаб бўлмади ($reason).';
  }
}
