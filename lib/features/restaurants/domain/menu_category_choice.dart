// «Таом қўшиш» экранидаги Категория танлови — СОФ қоидалар (тестланади).
//
// Категория — эга ўзи яратадиган бўлим (`menu_categories`); мижозга меню
// шу бўлимлар бўйича кўрсатилади. `''` = категориясиз → мижозда «Бошқалар».

import 'menu_category_names.dart';
import 'restaurant_models.dart';

abstract final class MenuCategoryChoice {
  /// Категориясиз («Бошқалар»). Серверда `categoryId` бўш матн.
  static const none = '';

  /// Рўйхатдаги «＋ Категория қўшиш» банди (ҳақиқий id эмас).
  static const createNew = '__new_category__';

  /// Шу id рўйхатда борми (бўш id — доим «категориясиз», яъни тўғри).
  static String known(String id, Iterable<MenuCategory> categories) =>
      id.isNotEmpty && categories.any((c) => c.id == id) ? id : none;

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
