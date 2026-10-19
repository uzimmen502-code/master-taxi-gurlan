// Таом маълумотлари (D-REST-16, D-REST-17, D-REST-24; docs/kafe_restoran_taklifi_uz.md §10.1).
//
// Бу — таомга сотувчи ўзи киритадиган ФАКТЛАР: порция, грамм, КБЖУ, кухна,
// теглар. Бўлимларга (Арзон, Енгил, Миллий…) тушиш бу маълумотнинг ТЎЛИҚЛИГИДАН
// келиб чиқади (модератор йўқ), шунинг учун ҳаммаси ИХТИЁРИЙ: бўш таом
// рад этилмайди, фақат тегишли бўлимда кўринмайди.
//
// Чегаралар `firestore.rules` (`restaurantMenuItemOk` → `dishFactsOk`) билан бир
// хил — rules клиентдан ташқари барибир текширади (18-қоида). Иккита нусха
// бўлишининг сабаби: rules кодни импорт қила олмайди; мослик икки томонда ҳам
// чегара тестлари билан қулфланган (`dish_facts_test.dart`, `restaurant_rules.test.js`).

/// Таомга қўйиладиган теглар (D-REST-17). Мавсумий теглар 2-қадамда
/// (мавсумлар рўйхати билан бирга) қўшилади.
abstract final class DishTag {
  static const kids = 'kids';
  static const breakfast = 'breakfast';
  static const night = 'night';
  static const light = 'light';

  static const all = [kids, breakfast, night, light];
  static const maxPerDish = 4;
}

/// Кухна гуруҳи (D-REST-16): «Миллий» ва «Дунё» — иккита алоҳида бўлим.
abstract final class CuisineGroup {
  static const national = 'national';
  static const world = 'world';

  static const all = [national, world];
}

/// Форма хатоси калитлари → `restaurants_m_dish_err_<калит>` (3 тилда).
abstract final class DishFactsError {
  static const servings = 'servings';
  static const weight = 'weight';
  static const nutritionIncomplete = 'nutrition_incomplete';
  static const nutritionRange = 'nutrition_range';
  static const nutritionMismatch = 'nutrition_mismatch';
  static const cuisine = 'cuisine';
  static const tags = 'tags';
}

class DishFacts {
  const DishFacts({
    this.servings,
    this.weightG,
    this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.cuisineGroup,
    this.cuisineId,
    this.tags = const [],
  });

  static const empty = DishFacts();

  /// Бир порция неча кишилик (1…[maxServings]) — «Арзон» бўлимда бир кишилик нарх.
  final int? servings;

  /// Порция оғирлиги, грамм.
  final int? weightG;

  /// КБЖУ — бир порцияга: калория (ккал), оқсил, ёғ, углевод (грамм). Тўртталаси
  /// ЁКИ бирга бор, ЁКИ бирорта ҳам йўқ.
  final int? kcal;
  final int? protein;
  final int? fat;
  final int? carbs;

  /// [CuisineGroup] ва `restaurant_cuisines/{id}` — иккаласи бирга.
  final String? cuisineGroup;
  final String? cuisineId;

  /// [DishTag] рўйхати.
  final List<String> tags;

  static const maxServings = 50;
  static const minWeightG = 10;
  static const maxWeightG = 5000;
  static const maxKcal = 5000;
  static const maxMacroG = 500;

  /// Калория ≈ 4·оқсил + 4·углевод + 9·ёғ: фарқ ≤ [kcalToleranceAbs] ккал ЁКИ
  /// ≤ [kcalTolerancePercent] % (PROPOSED — эга тасдиғи керак).
  static const kcalToleranceAbs = 20;
  static const kcalTolerancePercent = 15;

  bool get hasNutrition => kcal != null && protein != null && fat != null && carbs != null;

  bool get hasCuisine => cuisineId != null && cuisineGroup != null;

  /// Ҳеч бир факт киритилмаган.
  bool get isEmpty =>
      servings == null &&
      weightG == null &&
      !_anyNutrition &&
      cuisineId == null &&
      cuisineGroup == null &&
      tags.isEmpty;

  bool get _anyNutrition => kcal != null || protein != null || fat != null || carbs != null;

  /// КБЖУдаги калория макроэлементларга мосми (чегара: [kcalToleranceAbs] /
  /// [kcalTolerancePercent]). Тўртталаси ҳам берилмаса — `true` (текшириладиган нарса йўқ).
  static bool kcalConsistent({int? kcal, int? protein, int? fat, int? carbs}) {
    if (kcal == null || protein == null || fat == null || carbs == null) return true;
    final calc = 4 * protein + 4 * carbs + 9 * fat;
    final diff = (kcal - calc).abs();
    return diff <= kcalToleranceAbs || diff * 100 <= calc * kcalTolerancePercent;
  }

  /// Хато калитлари ([DishFactsError]); бўш рўйхат — тўғри.
  List<String> validate() {
    final errs = <String>[];
    if (servings != null && (servings! < 1 || servings! > maxServings)) errs.add(DishFactsError.servings);
    if (weightG != null && (weightG! < minWeightG || weightG! > maxWeightG)) errs.add(DishFactsError.weight);

    if (_anyNutrition) {
      if (!hasNutrition) {
        errs.add(DishFactsError.nutritionIncomplete);
      } else if (kcal! < 0 ||
          kcal! > maxKcal ||
          protein! < 0 ||
          protein! > maxMacroG ||
          fat! < 0 ||
          fat! > maxMacroG ||
          carbs! < 0 ||
          carbs! > maxMacroG) {
        errs.add(DishFactsError.nutritionRange);
      } else if (!kcalConsistent(kcal: kcal, protein: protein, fat: fat, carbs: carbs)) {
        errs.add(DishFactsError.nutritionMismatch);
      }
    }

    // Кухна: ё иккаласи ҳам йўқ, ё иккаласи бирга ва тўғри (биттаси — хато).
    final anyCuisine = cuisineId != null || cuisineGroup != null;
    if (anyCuisine &&
        (!hasCuisine ||
            !CuisineGroup.all.contains(cuisineGroup) ||
            cuisineId!.isEmpty ||
            cuisineId!.length > 80)) {
      errs.add(DishFactsError.cuisine);
    }

    if (tags.length > DishTag.maxPerDish ||
        tags.toSet().length != tags.length ||
        tags.any((t) => !DishTag.all.contains(t))) {
      errs.add(DishFactsError.tags);
    }
    return errs;
  }

  /// Firestore'га ёзиладиган майдонлар — фақат киритилганлари. Киритилмаган
  /// майдонни репозиторий ўчиради (`null` ёзилмайди — rules рад этади).
  Map<String, Object> toMap() => {
        if (servings != null) 'servings': servings!,
        if (weightG != null) 'weightG': weightG!,
        if (hasNutrition) ...{
          'kcal': kcal!,
          'protein': protein!,
          'fat': fat!,
          'carbs': carbs!,
        },
        if (hasCuisine) ...{
          'cuisineGroup': cuisineGroup!,
          'cuisineId': cuisineId!,
        },
        if (tags.isNotEmpty) 'tags': List<String>.of(tags),
      };

  /// `toMap` ёзадиган БАРЧА калитлар — репозиторий таҳрирда киритилмагани
  /// ўчириши учун.
  static const fieldKeys = [
    'servings',
    'weightG',
    'kcal',
    'protein',
    'fat',
    'carbs',
    'cuisineGroup',
    'cuisineId',
    'tags',
  ];

  /// Таомни сақлашдаги фактлар патчи (`set(..., merge: true)` учун).
  /// [facts] `null` — фактларга ТЕГИЛМАЙДИ (бўш патч): фактларни билмайдиган
  /// чақирувчи мавжуд маълумотни ўчириб юбормасин. Берилса — у форма ҲОЛАТИ:
  /// киритилганлар ёзилади, киритилмаганлари [removed] (`FieldValue.delete()`)
  /// билан ҳужжатдан ЎЧИРИЛАДИ (`null` ёзилмайди — rules рад этади).
  static Map<String, Object> patch(DishFacts? facts, Object removed) {
    if (facts == null) return const {};
    final fields = facts.toMap();
    return {for (final key in fieldKeys) key: fields[key] ?? removed};
  }

  /// Ҳужжатдан хавфсиз ўқиш: тип ёки чегара нотўғри қиймат — «йўқ» (эски/бузилган
  /// ҳужжат экранни синдирмайди).
  factory DishFacts.fromMap(Map<String, dynamic> d) {
    int? intIn(Object? v, int lo, int hi) {
      if (v is! num || v != v.truncate()) return null;
      final n = v.toInt();
      return n >= lo && n <= hi ? n : null;
    }

    final kcal = intIn(d['kcal'], 0, maxKcal);
    final protein = intIn(d['protein'], 0, maxMacroG);
    final fat = intIn(d['fat'], 0, maxMacroG);
    final carbs = intIn(d['carbs'], 0, maxMacroG);
    // КБЖУ бутун бўлмаса ҳеч қайси қисми ишлатилмайди.
    final nutritionOk = kcal != null && protein != null && fat != null && carbs != null;

    final group = d['cuisineGroup'];
    final cuisineId = d['cuisineId'];
    final cuisineOk = group is String && CuisineGroup.all.contains(group) && cuisineId is String && cuisineId.isNotEmpty;

    final rawTags = d['tags'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().where(DishTag.all.contains).toSet().take(DishTag.maxPerDish).toList()
        : const <String>[];

    return DishFacts(
      servings: intIn(d['servings'], 1, maxServings),
      weightG: intIn(d['weightG'], minWeightG, maxWeightG),
      kcal: nutritionOk ? kcal : null,
      protein: nutritionOk ? protein : null,
      fat: nutritionOk ? fat : null,
      carbs: nutritionOk ? carbs : null,
      cuisineGroup: cuisineOk ? group : null,
      cuisineId: cuisineOk ? cuisineId : null,
      tags: tags,
    );
  }
}
