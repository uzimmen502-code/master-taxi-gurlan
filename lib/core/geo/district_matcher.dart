/// Телефон манзил аниқлагичи (geocoder) қайтарган ном → `geo_districts`
/// туман (D-GEO-13, А вариант). Номлар тил ва ёзилишга қараб ҳар хил
/// келади: «Gurlan tumani», «Гурлан тумани», «Гурленский район», «Gurlan
/// District». Шунинг учун:
///
/// 1. Кирилл (ўзбек + рус) → лотин.
/// 2. «тумани / district / район / шаҳри / city / вилояти / область…»
///    қўшимчалари олиб ташланади, рус сифатдош қўшимчаси (-ский) ҳам.
/// 3. Унлисиз «скелет» солиштирилади (Гурлен ≈ Gurlan → `grln`,
///    Чиланзар ≈ Chilonzor → `chlnzr`).
///
/// ЭҲТИЁТКОР: бир нечта туман мос келса — `null` (нотўғри таклифдан
/// таклифсиз яхши). Аниқлик ҳақиқий қурилмада текширилиши керак (UNKNOWN).
library;

import 'package:flutter/foundation.dart';

@immutable
class DistrictCandidate {
  const DistrictCandidate({
    required this.id,
    required this.regionId,
    required this.names,
  });

  final String id;
  final String regionId;

  /// Барча маълум номлар: `name` (лотин), `nameUz` (кирилл)…
  final List<String> names;
}

@immutable
class RegionCandidate {
  const RegionCandidate({required this.id, required this.names});
  final String id;
  final List<String> names;
}

const _cyr = <String, String>{
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
  'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'x', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': '',
  'ы': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'ў': 'o', 'қ': 'q',
  'ғ': 'g', 'ҳ': 'h',
};

/// Олиб ташланадиган сўзлар (бутун сўз сифатида, лотинга ўгирилгандан кейин).
const _dropWords = <String>{
  'tumani', 'tuman', 'district', 'rayon', 'raion', 'shahri', 'shahar', 'city',
  'gorod', 'viloyati', 'viloyat', 'oblast', 'oblasti', 'region', 'province',
  'respublikasi', 'respublika', 'republic', 'of', 'the', 'shaxri', 'shaxar',
};

/// Кирилл → лотин, кичик ҳарф, апостроф ва белгиларсиз.
String latinize(String raw) {
  final lower = raw.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_cyr[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r"[ʻʼ'’`‘]"), '')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Солиштириш калити: қўшимчаларсиз, унлисиз ундош скелет.
String nameSkeleton(String raw) {
  final words = latinize(raw)
      .split(' ')
      .where((w) => w.isNotEmpty && !_dropWords.contains(w))
      .map((w) {
    // Рус сифатдош қўшимчаси: gurlenskiy, chilanzarskiy, yunusabadskiy…
    for (final suf in ['skiy', 'skii', 'skij', 'sky', 'skaya', 'ckiy']) {
      if (w.length > suf.length + 2 && w.endsWith(suf)) {
        return w.substring(0, w.length - suf.length);
      }
    }
    return w;
  }).toList();
  var s = words.join();
  // Транслитерация фарқлари: kh/x/h, q/k, ts/s, j/zh.
  s = s
      .replaceAll('sh', '§')
      .replaceAll('ch', '¢')
      .replaceAll('kh', 'x')
      .replaceAll('zh', 'j')
      .replaceAll('h', 'x')
      .replaceAll('q', 'k')
      .replaceAll('ts', 's')
      .replaceAll('w', 'v');
  s = s.replaceAll(RegExp(r'[aeiouy]'), '');
  s = s.replaceAll('§', 'sh').replaceAll('¢', 'ch');
  // Иккиланган ундошлар: Mirobod/Mirabad, Jizzax/Jizak.
  return s.replaceAll(RegExp(r'(.)\1+'), r'$1');
}

/// Мос келадиган вилоятлар (Тошкент шаҳри ва Тошкент вилояти бир хил
/// скелет — иккаласи қайтади; туман уларни ажратади).
List<String> matchRegions(String? adminArea, List<RegionCandidate> regions) {
  final key = adminArea == null ? '' : nameSkeleton(adminArea);
  if (key.length < 3) return const [];
  return regions
      .where((r) => r.names.any((n) => nameSkeleton(n) == key))
      .map((r) => r.id)
      .toSet()
      .toList();
}

/// Туманни аниқлаш. [candidates] — geocoder майдонлари тартиб бўйича
/// (subAdministrativeArea, locality, subLocality). [regionIds] бўш бўлмаса
/// фақат шу вилоятлар туманлари кўрилади.
DistrictCandidate? matchDistrict(
  List<String?> candidates,
  List<DistrictCandidate> districts, {
  List<String> regionIds = const [],
}) {
  final pool = regionIds.isEmpty
      ? districts
      : districts.where((d) => regionIds.contains(d.regionId)).toList();
  for (final raw in candidates) {
    final key = raw == null ? '' : nameSkeleton(raw);
    if (key.length < 3) continue;
    final hits = pool
        .where((d) => d.names.any((n) => nameSkeleton(n) == key))
        .toList();
    final ids = hits.map((d) => d.id).toSet();
    if (ids.length == 1) return hits.first;
    // Бир нечта мос (масалан шаҳар ва туман бир хил номда) — таклиф йўқ.
    if (ids.length > 1) return null;
  }
  return null;
}
