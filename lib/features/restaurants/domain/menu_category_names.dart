// Меню бўлими НОМИ — мижозга ЎЗ тилида кўрсатиш (эга, 2026-10-18).
//
// Бўлим номи Firestore'да эга ёзган матн (`menu_categories.name`) — схема ва
// қоидалар ўзгармайди. Лекин кўрсатишда:
//   * тайёр (PRESET) ном — ҳар тилда таниб олинади ва мижозга ЎЗ тилида
//     чиқади (эга кирилда «Ичимликлар» ёзган бўлса, русча мижоз «Напитки»
//     кўради). Аввалги ёзувлар ҳам: матн қайси тилда сақланганидан қатъи назар;
//   * эганинг ўз номи — ўзбек кирилл ↔ лотин ўгирилади ([UzScript]); рус тили
//     учун кирилл шакли. Бошқа тилга ТАРЖИМА қилинмайди (автоматик таржима йўқ).
//
// Тайёр номларнинг ЯГОНА манбаси — шу жадвал: таклиф чиплари ҳам, таниб олиш
// ҳам ундан. Матн калитлари (`assets/lang`) ишлатилмайди.

import '../../../core/utils/uz_script.dart';

abstract final class MenuCategoryNames {
  /// Тил кодлари: `uz_Cyrl` · `uz_Latn` · `ru`.
  static const presets = <String, Map<String, String>>{
    'hot': {'uz_Cyrl': 'Иссиқ таомлар', 'uz_Latn': 'Issiq taomlar', 'ru': 'Горячие блюда'},
    'sweets': {'uz_Cyrl': 'Ширинликлар', 'uz_Latn': 'Shirinliklar', 'ru': 'Десерты'},
    'drinks': {'uz_Cyrl': 'Ичимликлар', 'uz_Latn': 'Ichimliklar', 'ru': 'Напитки'},
    'bread': {'uz_Cyrl': 'Нон ва хамир таомлари', 'uz_Latn': 'Non va xamir taomlari', 'ru': 'Хлеб и выпечка'},
    'first': {'uz_Cyrl': 'Биринчи таомлар', 'uz_Latn': 'Birinchi taomlar', 'ru': 'Первые блюда'},
    'second': {'uz_Cyrl': 'Иккинчи таомлар', 'uz_Latn': 'Ikkinchi taomlar', 'ru': 'Вторые блюда'},
    'salads': {'uz_Cyrl': 'Салатлар', 'uz_Latn': 'Salatlar', 'ru': 'Салаты'},
    'shashlik': {'uz_Cyrl': 'Шашлик', 'uz_Latn': 'Shashlik', 'ru': 'Шашлык'},
    'fastfood': {'uz_Cyrl': 'Фастфуд', 'uz_Latn': 'Fastfud', 'ru': 'Фастфуд'},
  };

  static String _norm(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase().replaceAll(RegExp('[ʻʼʽˈ`´‘’′]'), "'");

  static final Map<String, String> _index = () {
    final m = <String, String>{};
    presets.forEach((key, names) {
      for (final n in names.values) {
        m[_norm(n)] = key;
        m[_norm(UzScript.toLatin(n))] = key;
      }
    });
    return m;
  }();

  /// Сақланган матн тайёр номга мос келса — унинг калити.
  static String? presetKeyOf(String stored) {
    final n = _norm(stored);
    if (n.isEmpty) return null;
    return _index[n] ?? _index[_norm(UzScript.toLatin(stored))];
  }

  /// Тайёр номнинг [lang] даги матни.
  static String presetName(String key, String lang) {
    final names = presets[key];
    if (names == null) return '';
    return names[lang] ?? names['uz_Cyrl'] ?? '';
  }

  /// Мижозга/эгага ЎЗ тилида кўрсатиладиган матн.
  static String display(String stored, String lang) {
    final key = presetKeyOf(stored);
    if (key != null) return presetName(key, lang);
    if (stored.trim().isEmpty) return stored;
    return lang == 'uz_Latn' ? UzScript.toLatin(stored) : UzScript.toCyrillic(stored);
  }

  /// Икки ном БИР категорияними (кирилл/лотин/рус тайёр номлар бир хил):
  /// такрорий категория яратмаслик учун.
  static String identity(String name) {
    final key = presetKeyOf(name);
    if (key != null) return 'preset:$key';
    return _norm(UzScript.toLatin(name));
  }
}
