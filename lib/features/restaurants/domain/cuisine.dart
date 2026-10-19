// `restaurant_cuisines/{id}` — таом кухналарининг УМУМИЙ рўйхати (D-REST-24).
//
// «Миллий» ва «Дунё» — иккита алоҳида бўлим; ҳар кухна биттасига тегишли
// ([CuisineGroup]). Тайёр кухналарни админ скрипт билан киритади (`names` — 3 тилда),
// сотувчи ўз номини қўшади («Қашқадарё миллий таомлари») — сервер
// (`restaurantAddCuisine`) дубликатсиз яратади. Ёзув фақат сервердан.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/uz_script.dart';
import 'dish_facts.dart';

class Cuisine {
  const Cuisine({
    required this.id,
    required this.name,
    required this.group,
    this.names = const {},
    this.hidden = false,
  });

  final String id;

  /// Киритилган ном (тайёр кухнада — ўзбек кирилл шакли).
  final String name;

  /// [CuisineGroup.national] ёки [CuisineGroup.world].
  final String group;

  /// Тайёр кухналарда `uz_Cyrl`/`uz_Latn`/`ru` матнлари; сотувчи номида бўш.
  final Map<String, String> names;

  /// Админ яширган (суиистеъмол) — танлов рўйхатида чиқмайди.
  final bool hidden;

  bool get isNational => group == CuisineGroup.national;

  /// Фойдаланувчи тилида кўрсатиладиган ном. Тайёр номнинг тили бор — ўша;
  /// сотувчи ёзган ном — ўзбек кирилл ↔ лотин ўгирилади ([UzScript]), рус учун
  /// кирилл шакли. Бошқа тилга ТАРЖИМА қилинмайди (автоматик таржима йўқ).
  String displayName(String lang) {
    final preset = names[lang];
    if (preset != null && preset.trim().isNotEmpty) return preset;
    if (name.trim().isEmpty) return name;
    return lang == 'uz_Latn' ? UzScript.toLatin(name) : UzScript.toCyrillic(name);
  }

  factory Cuisine.fromMap(String id, Map<String, dynamic> d) {
    final rawNames = d['names'];
    return Cuisine(
      id: id,
      name: d['name'] is String ? d['name'] as String : '',
      group: d['group'] is String ? d['group'] as String : '',
      names: rawNames is Map
          ? {
              for (final e in rawNames.entries)
                if (e.key is String && e.value is String) e.key as String: e.value as String,
            }
          : const {},
      hidden: d['hidden'] == true,
    );
  }

  factory Cuisine.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Cuisine.fromMap(doc.id, doc.data() ?? const {});

  /// Ўзбек кирилл ҳарфлари Юникодда `я`дан кейин туради; алифбода эса ўз асосий
  /// ҳарфидан кейин. Сараланганда шу ҳарфлар асосидан кейинги ўринга қўйилади.
  static const _afterBase = {'ў': 'у', 'қ': 'к', 'ғ': 'г', 'ҳ': 'х'};

  static String _sortKey(String s) {
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final base = _afterBase[ch];
      b.write(base == null ? ch : '$base￿');
    }
    return b.toString();
  }

  /// Танлов рўйхати: яширилмаган, гуруҳи тўғри; ном [lang] бўйича алифбо тартибида.
  static List<Cuisine> selectable(Iterable<Cuisine> all, String lang) {
    final list = all.where((c) => !c.hidden && CuisineGroup.all.contains(c.group) && c.name.trim().isNotEmpty).toList()
      ..sort((a, b) => _sortKey(a.displayName(lang)).compareTo(_sortKey(b.displayName(lang))));
    return list;
  }
}
