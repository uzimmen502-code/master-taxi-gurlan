// «Таом қўшиш» экранидаги Категория танлови — СОФ қоидалар (тестланади).
//
// Категория — эга ўзи яратадиган бўлим (`menu_categories`); мижозга меню
// шу бўлимлар бўйича кўрсатилади. `''` = категориясиз → мижозда «Бошқалар».

import 'menu_category_names.dart';
import 'restaurant_models.dart';

abstract final class MenuCategoryChoice {
  /// Категориясиз («Бошқалар»). Серверда `categoryId` бўш матн.
  static const none = '';

  /// Тизим таклиф қилган, ҲАЛИ яратилмаган бўлим: танлов қиймати `__suggest__:<калит>`.
  /// Бўлим таом САҚЛАНАЁТГАНДА яратилади (кўриб чиқиш ҳужжат яратмайди).
  static const _suggestPrefix = '__suggest__:';

  static String suggest(String presetKey) => '$_suggestPrefix$presetKey';

  /// `__suggest__:<калит>` бўлса — тайёр ном калити (рўйхатда борлиги шарт), акс ҳолда `null`.
  static String? suggestedKey(String id) {
    if (!id.startsWith(_suggestPrefix)) return null;
    final key = id.substring(_suggestPrefix.length);
    return MenuCategoryNames.presets.containsKey(key) ? key : null;
  }

  /// Шу id рўйхатда борми (бўш id — доим «категориясиз», яъни тўғри). Тизим таклифи
  /// (тайёр ном калити тўғри бўлса) ҳам тўғри танлов.
  static String known(String id, Iterable<MenuCategory> categories) {
    if (suggestedKey(id) != null) return id;
    return id.isNotEmpty && categories.any((c) => c.id == id) ? id : none;
  }

  /// Форма очилгандаги танлов.
  ///
  /// * таҳрирда — таомнинг ўз категорияси; у ўчирилган бўлса — `none`
  ///   (аввал жимгина БИРИНЧИ категорияга ўтказиларди ва сақлаганда таом
  ///   эгасидан сўрамасдан бошқа бўлимга тушарди);
  /// * янги таомда — менюда танланган фильтр бўлимига, бўлмаса `none`.
  ///   Аввал ҳамиша биринчи категория олинарди (эга эътибор бермаса таом
  ///   нотўғри бўлимга тушарди ва «категориясиз» вариант йўқ эди).
  static String initial({
    required bool isEdit,
    String? existingCategoryId,
    String? filterCategoryId,
    required Iterable<MenuCategory> categories,
  }) =>
      known(isEdit ? (existingCategoryId ?? none) : (filterCategoryId ?? none), categories);

  /// Шу номли категория бор бўлса — қайтаради (бир хил ном иккинчи марта
  /// яратилмасин: «Таомлар» / «таомлар »; шунингдек кирилл ↔ лотин ва тайёр
  /// номнинг бошқа тилдаги шакли: «Ичимликлар» = «Ichimliklar» = «Напитки»).
  static MenuCategory? findByName(Iterable<MenuCategory> categories, String name) {
    if (name.trim().isEmpty) return null;
    final id = MenuCategoryNames.identity(name);
    for (final c in categories) {
      if (MenuCategoryNames.identity(c.name) == id) return c;
    }
    return null;
  }

  /// Firestore batch чегараси (500) ичида қолиш учун бўлаклаш.
  static List<List<T>> chunks<T>(List<T> items, {int size = 400}) {
    final out = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
    }
    return out;
  }
}
