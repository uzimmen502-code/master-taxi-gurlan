// «＋ Категория қўшиш»да эгага ёрдам: тайёр бўлим номлари (PROPOSED — рўйхат
// 2026-10-18 да таклиф қилинди, эга номларни тасдиқлайди/ўзгартиради).
//
// Номларнинг ўзи [MenuCategoryNames.presets] да (3 тилда). Тайёр ном
// танланса, мижоз уни ЎЗ тилида кўради. Категория нархга ёки мантиққа
// таъсир қилмайди — фақат мижозга меню бўлими.

import 'menu_category_choice.dart';
import 'menu_category_names.dart';
import 'restaurant_models.dart';

abstract final class MenuCategorySuggestions {
  /// Уй ошпази: кичик меню — қисқа рўйхат.
  static const homeCook = ['hot', 'sweets', 'drinks', 'bread'];

  /// Кафе-ресторан: кенгроқ меню.
  static const cafe = ['first', 'second', 'salads', 'shashlik', 'fastfood', 'drinks', 'sweets'];

  /// «Тайёр бўлимларни қўшиш» тугмаси яратадиган бошланғич 3 та.
  static const starterHomeCook = ['hot', 'sweets', 'drinks'];
  static const starterCafe = ['first', 'second', 'drinks'];

  static List<String> keysFor({required bool homeCook}) =>
      homeCook ? MenuCategorySuggestions.homeCook : cafe;

  static List<String> starterKeysFor({required bool homeCook}) =>
      homeCook ? starterHomeCook : starterCafe;

  /// Таклифлардан [existing] да ҲАЛИ ЙЎҚлари — [lang] (эганинг тили)
  /// матнида. Аллақачон бор бўлим бошқа тилда/ёзувда бўлса ҳам такрор
  /// таклиф қилинмайди.
  static List<String> missingNames({
    required Iterable<String> keys,
    required String lang,
    required Iterable<MenuCategory> existing,
  }) =>
      missingEntries(keys: keys, lang: lang, existing: existing).map((e) => e.name).toList();

  /// Худди [missingNames], лекин тайёр ном КАЛИТИ билан (форма танлови учун:
  /// `MenuCategoryChoice.suggest(key)`). Ягона мантиқ шу ерда.
  static List<({String key, String name})> missingEntries({
    required Iterable<String> keys,
    required String lang,
    required Iterable<MenuCategory> existing,
  }) {
    final out = <({String key, String name})>[];
    for (final k in keys) {
      final n = MenuCategoryNames.presetName(k, lang);
      if (n.isNotEmpty && MenuCategoryChoice.findByName(existing, n) == null) out.add((key: k, name: n));
    }
    return out;
  }
}
