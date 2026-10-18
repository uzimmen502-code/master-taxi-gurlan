// «Таом қўшиш» экранидаги Категория танлови — СОФ қоидалар (тестланади).
//
// Категория — эга ўзи яратадиган бўлим (`menu_categories`); мижозга меню
// шу бўлимлар бўйича кўрсатилади. `''` = категориясиз → мижозда «Бошқалар».

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

  static String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Шу номли категория бор бўлса — қайтаради (бир хил ном иккинчи марта
  /// яратилмасин: «Таомлар» / «таомлар »).
  static MenuCategory? findByName(Iterable<MenuCategory> categories, String name) {
    final n = _norm(name);
    if (n.isEmpty) return null;
    for (final c in categories) {
      if (_norm(c.name) == n) return c;
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
