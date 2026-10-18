// «＋ Категория қўшиш»да эгага ёрдам: тайёр бўлим номлари (PROPOSED — рўйхат
// 2026-10-18 да таклиф қилинди, эга номларни тасдиқлайди/ўзгартиради).
//
// Номлар матн калитлари (`restaurants_cat_*`, 3 тилда); категория нархи ёки
// мантиққа таъсир қилмайди — фақат мижозга меню бўлими. Танланган матн эга
// тилида САҚЛАНАДИ (категория эга ёзган матн, калит эмас).

import 'menu_category_choice.dart';
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

  /// Матн калити.
  static String textKey(String key) => 'restaurants_cat_$key';

  /// Таклифлардан бирортаси [existing] да йўқлари (аллақачон бор бўлимни
  /// такрор таклиф қилмаймиз). [name] — калитни эга тилидаги матнга айлантиради.
  static List<String> missingNames({
    required Iterable<String> keys,
    required String Function(String key) name,
    required Iterable<MenuCategory> existing,
  }) {
    final out = <String>[];
    for (final k in keys) {
      final n = name(k);
      if (MenuCategoryChoice.findByName(existing, n) == null) out.add(n);
    }
    return out;
  }
}
