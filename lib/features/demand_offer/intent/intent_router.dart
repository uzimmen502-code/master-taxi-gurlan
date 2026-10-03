// INTENT ROUTER (13.4.9, 13.6.4) — АСОСИЙ КИРИШ НУҚТАСИ.
//
// Эга қарори (2026-10-03): «Уста чақириш» алоҳида катта тугма ЭМАС.
// Биринчи навбатда AVA'дан қидириш майдони орқали ишлайди:
//
//   фойдаланувчи ёзади «Сантехник керак»
//     → AVA буни ХИЗМАТ ТАЛАБИ деб тушунади
//     → «Уста топиш» оқими очилади
//
//   натижа топилмаса
//     → «Моси топилмадими? → Таклиф олиш»
//
// АЛГОРИТМ СЕРВЕР БИЛАН БИР ХИЛ (`functions_demand/core/keywords.js`):
//   аниқ сўз мослиги     — вазн = узунлик × 2
//   префикс (≥4 белги)   — вазн = узунлик        («электрикман» → «электрик»)
//   кўп сўзли ибора      — вазн = узунлик × 3    («уй тозалаш» яккадан устун)
//   натижалар тенг (10%) + кўп маъноли калит → ЎЗИ ТАНЛАМАЙДИ, сўрайди
//
// ИККИ ТОМОН АЖРАЛИБ КЕТМАЙДИ: луғат `taxonomy_services.json`дан
// генерация қилинади (`functions_demand/tools/build_intent_keywords.js`)
// ва паритет тести иккала томонни бир хил кейслар билан текширади.
//
// ТРАНСЛИТЕРАЦИЯ: мавжуд `AdSearchText.toLatin` ишлатилади — учинчи
// нусха ясалмайди (`search_index` аллақачон шу жадвал билан тўлдирилган).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../ads/utils/ad_search_text.dart';
import '../domain/demand_enums.dart';
import '../ui_adapters/demand_ui_adapter.dart';

/// Bundled луғат йўли.
///
/// Remote Config ИШЛАТИЛМАЙДИ (Т-13): `firebase_remote_config`
/// dependency репода йўқ ва фақат калит сўз рўйхати учун уни қўшиш
/// оқланмайди. Кейинчалик `module_config/intent_keywords` ҳужжатидан
/// устига ёзиш қўшилади — интерфейс шунга тайёр ([loadOverride]).
const String kIntentKeywordsAsset = 'assets/data/intent_keywords.json';

/// Матндан категория топувчи.
///
/// Қурилмада ишлайди, тармоқ сўрови ЙЎҚ — қидирув майдонида ҳар белги
/// ёзилганда чақирилади, шунинг учун тез бўлиши шарт.
class IntentRouter {
  IntentRouter._(this._data);

  final _IntentData _data;

  static IntentRouter? _instance;
  static Future<IntentRouter>? _loading;

  /// Луғатни юклайди (бир марта) ва синглтон қайтаради.
  static Future<IntentRouter> instance() {
    if (_instance != null) return Future.value(_instance!);
    return _loading ??= _load();
  }

  static Future<IntentRouter> _load() async {
    try {
      final raw = await rootBundle.loadString(kIntentKeywordsAsset);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _instance = IntentRouter._(_IntentData.fromJson(json));
    } catch (_) {
      // Луғат юкланмаса Intent Router ЖИМ ТУРАДИ — қидирув оддий
      // ҳолида ишлашда давом этади. Хато кўрсатилмайди: фойдаланувчи
      // учун бу «карточка чиқмади» дегани, холос.
      _instance = IntentRouter._(_IntentData.empty());
    }
    return _instance!;
  }

  /// Серверда таҳрирланган луғатни устига ёзиш (кейинги босқич).
  ///
  /// Ҳозир чақирилмайди, лекин интерфейс мавжуд: `module_config/
  /// intent_keywords` ҳужжати қўшилганда фақат шу метод уланади.
  static void loadOverride(Map<String, dynamic> json) {
    try {
      _instance = IntentRouter._(_IntentData.fromJson(json));
    } catch (_) {
      // Нотўғри override — bundled нусха қолади.
    }
  }

  /// Тестлар учун.
  static void resetForTest() {
    _instance = null;
    _loading = null;
  }

  /// Тестлар учун луғатни ўрнатади ва роутерни қайтаради.
  static IntentRouter setForTest(Map<String, dynamic> json) {
    final r = IntentRouter._(_IntentData.fromJson(json));
    _instance = r;
    _loading = null;
    return r;
  }

  int get keywordCount => _data.keywords.length;
  int get categoryCount => _data.categories.length;

  /// Категориянинг кўринадиган номи.
  String categoryName(String categoryId, String langCode) {
    final c = _data.categories[categoryId];
    if (c == null) return categoryId;
    return c.names[langCode] ?? c.names['uz_Cyrl'] ?? categoryId;
  }

  String? categoryGroup(String categoryId) =>
      _data.categories[categoryId]?.group;

  bool get isEmpty => _data.keywords.isEmpty;

  /// Матнни таҳлил қилади.
  ///
  /// P0.3 (эга спецификацияси) — беш хил сўровни тушунади:
  ///   «Курьер керак»             → courier
  ///   «Сантехник керак»          → service + категория
  ///   «3 хонали квартира керак»  → realty + хона сони
  ///   «Тошкентга такси керак»    → intercity_taxi + манзил
  ///   «500 дона футболка керак»  → market + миқдор (улгуржи)
  ///
  /// Ҳеч нарса топилмаса `module == null` — карточка КЎРСАТИЛМАЙДИ ва
  /// фойдаланувчи оддий натижаларни кўради. Концепция: «AVA адашса,
  /// фойдаланувчи карточкани ўтказиб, оддий натижаларни кўради.»
  IntentResult detect(String rawText) {
    final hay = _canon(rawText);
    if (hay.isEmpty) return IntentResult(rawText: rawText);

    // 0) ИШ ҚИДИРИШ — КАРТОЧКА УМУМАН ЧИҚМАЙДИ.
    //
    // Концепция жадвали: «курьер иш», «ҳайдовчи бўлиб ишлаш» → иш
    // қидириш → хизмат карточкаси чиқмайди.
    //
    // Сабаб: бу одам «курьер керак» демаяпти, у ЎЗИ курьер бўлиб
    // ишлашни хоҳлаяпти. Карточка чиқса, илова унга «курьер топамиз»
    // деб таклиф қилади — тескариси.
    if (_isJobSearch(hay)) {
      return IntentResult(rawText: rawText);
    }

    // Ажратиб олинадиган маълумот — модулдан қатъи назар.
    final extracted = _extract(hay);

    // 1) МОДУЛ: хизматдан бошқа модул аниқ айтилганми.
    //
    // Тартиб муҳим: «Тошкентга такси керак»да «такси» модул калити,
    // хизмат категорияси эмас. Шунинг учун модул ТЕКШИРУВИ ОЛДИН.
    final moduleHit = _detectModule(hay, extracted);
    if (moduleHit != null) return moduleHit.copyWith(rawText: rawText);

    // 2) ХИЗМАТ: 40 категория бўйича.
    if (_data.keywords.isEmpty) return IntentResult(rawText: rawText);

    final words = hay.split(' ').where((w) => w.isNotEmpty).toList();
    final scores = <String, double>{};
    final matched = <String>{};
    var ambiguousHit = false;

    // УМУМИЙ КАЛИТ: «уста керак», «ремонт», «хизмат керак».
    //
    // Эга мисоли: «Уста керак» — ҳеч қайси категорияга тушмайди, лекин
    // хизмат карточкаси КЎРСАТИЛИШИ шарт, акс ҳолда фойдаланувчи учун
    // бошқа кириш нуқтаси қолмайди.
    var genericHit = false;
    for (final g in _data.generic) {
      if (g.contains(' ')) {
        if (_containsPhrase(hay, g)) { genericHit = true; break; }
      } else if (words.contains(g)) {
        genericHit = true;
        break;
      } else if (g.length >= _data.minPrefixLen
          && words.any((w) => w.startsWith(g))) {
        genericHit = true;
        break;
      }
    }

    for (final entry in _data.keywords.entries) {
      final keyword = entry.key;
      var weight = 0.0;

      if (keyword.contains(' ')) {
        // Кўп сўзли ибора — тўлиқ мос келиши керак ва вазни энг катта.
        if (_containsPhrase(hay, keyword)) {
          weight = (keyword.length * _data.phraseWeight).toDouble();
        }
      } else {
        for (final w in words) {
          if (w == keyword) {
            weight = _max(weight, keyword.length * 2);
            continue;
          }
          // Префикс: «электрикман» → «электрик». Фақат узун калитлар
          // учун, акс ҳолда «ток» → «токайгача» каби тасодифий мослик
          // пайдо бўлади.
          if (keyword.length >= _data.minPrefixLen && w.startsWith(keyword)) {
            weight = _max(weight, keyword.length.toDouble());
          }
        }
      }

      if (weight <= 0) continue;
      matched.add(keyword);
      if (_data.ambiguous.containsKey(keyword)) ambiguousHit = true;

      for (final catId in entry.value) {
        scores[catId] = (scores[catId] ?? 0) + weight;
      }
    }

    final serviceMeta = _data.modules['service'];
    final serviceReady = serviceMeta?.coreReady ?? true;

    if (scores.isEmpty) {
      // Аниқ категория йўқ, лекин умумий калит бор → карточка
      // кўрсатилади ва фойдаланувчи категорияни ЎЗИ танлайди.
      if (genericHit) {
        return IntentResult(
          rawText: rawText,
          module: DemandModule.service,
          needsChoice: true,
          coreReady: serviceReady,
          quantity: extracted.quantity,
          rooms: extracted.rooms,
          destinationHint: extracted.destination,
          matchedKeywords: matched.toList()..sort(),
        );
      }
      return IntentResult(
        rawText: rawText,
        quantity: extracted.quantity,
        rooms: extracted.rooms,
        destinationHint: extracted.destination,
        matchedKeywords: matched.toList()..sort(),
      );
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    final top = ranked.first;
    final second = ranked.length > 1 ? ranked[1] : null;
    // Чегара ТОР (10%) — кенг чегара ҳар кичик фарқда танлов сўраб,
    // фойдаланувчини безовта қилади.
    final tie = second != null && (top.value - second.value) < top.value * 0.1;
    final needsChoice = ambiguousHit && tie;

    return IntentResult(
      rawText: rawText,
      module: DemandModule.service,
      categoryId: needsChoice ? null : top.key,
      candidateCategoryIds:
          ranked.take(3).map((e) => e.key).toList(growable: false),
      needsChoice: needsChoice,
      coreReady: serviceReady,
      quantity: extracted.quantity,
      rooms: extracted.rooms,
      destinationHint: extracted.destination,
      matchedKeywords: matched.toList()..sort(),
    );
  }

  /// Иш қидириш сўровими.
  ///
  /// `иш`, `ish` — ҚИСҚА сўзлар, шунинг учун фақат АНИҚ сўз мослиги
  /// текширилади (префикс эмас). Акс ҳолда «ишлатиш», «ишонч» каби
  /// сўзлар ҳам тўсилиб қоларди.
  bool _isJobSearch(String hay) {
    if (_data.suppressWords.isEmpty) return false;
    final words = hay.split(' ').where((w) => w.isNotEmpty).toSet();
    for (final s in _data.suppressWords) {
      if (s.contains(' ')) {
        if (_containsPhrase(hay, s)) return true;
      } else if (words.contains(s)) {
        return true;
      }
    }
    return false;
  }

  /// P0.3 — МОДУЛ АНИҚЛАШ.
  ///
  /// Хизматдан бошқа модул калити топилса, ўша модул қайтарилади.
  /// Ядрога уланмаган модул учун `existingScreen` берилади — карточка
  /// мавжуд ишлайдиган экранга олиб боради, «тез орада» демайди.
  IntentResult? _detectModule(String hay, _Extracted ex) {
    if (_data.moduleKeywords.isEmpty) return null;

    final words = hay.split(' ').where((w) => w.isNotEmpty).toList();
    final scores = <String, double>{};
    final matched = <String>{};

    for (final entry in _data.moduleKeywords.entries) {
      final keyword = entry.key;
      var weight = 0.0;

      if (keyword.contains(' ')) {
        if (_containsPhrase(hay, keyword)) {
          weight = (keyword.length * _data.phraseWeight).toDouble();
        }
      } else {
        for (final w in words) {
          if (w == keyword) {
            weight = _max(weight, keyword.length * 2);
            continue;
          }
          if (keyword.length >= _data.minPrefixLen && w.startsWith(keyword)) {
            weight = _max(weight, keyword.length.toDouble());
          }
        }
      }

      if (weight <= 0) continue;
      matched.add(keyword);
      for (final m in entry.value) {
        scores[m] = (scores[m] ?? 0) + weight;
      }
    }

    if (scores.isEmpty) return null;

    // Хона сони топилса кўчмас мулк, миқдор топилса бозор — ажратилган
    // маълумот модул танловини кучайтиради.
    if (ex.rooms != null) scores['realty'] = (scores['realty'] ?? 0) + 10;
    if (ex.quantity != null && ex.quantity! >= 5) {
      scores['market'] = (scores['market'] ?? 0) + 8;
    }
    if (ex.destination != null) {
      scores['intercity_taxi'] = (scores['intercity_taxi'] ?? 0) + 6;
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    final moduleId = ranked.first.key;
    final meta = _data.modules[moduleId];

    return IntentResult(
      rawText: '',
      module: DemandModule.tryParse(moduleId),
      destinationHint: ex.destination,
      quantity: ex.quantity,
      rooms: ex.rooms,
      coreReady: meta?.coreReady ?? false,
      existingScreen: meta?.existingScreen,
      matchedKeywords: matched.toList()..sort(),
    );
  }

  /// P0.3 — МАЪЛУМОТ АЖРАТИШ.
  ///
  /// Концепция: «Матндан тушунилган маълумот формага олдиндан ёзилади.
  /// "Тошкентга посилка" деса, "Қаерга" майдонида Тошкент туради.»
  _Extracted _extract(String hay) {
    int? quantity;
    int? rooms;
    String? destination;

    final words = hay.split(' ').where((w) => w.isNotEmpty).toList();

    for (var i = 0; i < words.length; i += 1) {
      final n = int.tryParse(words[i]);
      if (n == null || n <= 0) continue;

      // Рақамдан кейинги сўз — бирлик ёки «хонали».
      final next = i + 1 < words.length ? words[i + 1] : '';
      if (next.isEmpty) continue;

      if (_data.roomWords.any((r) => next == r || next.startsWith(r))) {
        rooms ??= n;
        continue;
      }
      if (_data.quantityUnits.any((u) => next == u || next.startsWith(u))) {
        quantity ??= n;
      }
    }

    // Манзил — «Тошкентга» каби қўшимча билан ҳам.
    //
    // Умумий «-га» қоидаси ИШЛАТИЛМАЙДИ: у «уйга», «ишга» каби
    // сўзларни ҳам ушлаб, нотўғри манзил берарди. Шунинг учун фақат
    // маълум шаҳар/туман рўйхати бўйича.
    for (final d in _data.destinations) {
      if (d.canon.isEmpty) continue;
      final hit = words.any((w) => w == d.canon || w.startsWith(d.canon));
      if (hit) {
        destination = d.name;
        break;
      }
    }

    return _Extracted(quantity: quantity, rooms: rooms, destination: destination);
  }

  /// Паритет тести учун — `test/features/demand_offer/canon_parity_test.dart`.
  static String canonForTest(String s) => _canon(s);

  /// Канон шакл — сервердаги `canonText` билан бир хил натижа бериши
  /// ШАРТ (паритет тести текширади).
  static String _canon(String s) {
    final folded = AdSearchText.foldMarks(s).toLowerCase();
    final latin = AdSearchText.toLatin(folded);
    return latin
        .replaceAll(RegExp(r"[^0-9a-z' ]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _max(double a, num b) => a > b ? a : b.toDouble();

  /// Ибора СЎЗ ЧЕГАРАСИ билан топилганми.
  ///
  /// Оддий `contains` ЯРАМАЙДИ. Тест топган ҳақиқий хато:
  /// «kuryer kerak» ичида «yer kerak» (кўчмас мулк ибораси) substring
  /// сифатида бор эди, шунинг учун «Курьер керак» сўрови КЎЧМАС МУЛК
  /// деб таниларди. Бўшлиқ билан ўраб текшириш буни ёпади.
  ///
  /// Сервердаги жуфти: `keywords.js` → `containsPhrase`.
  static bool _containsPhrase(String hay, String phrase) =>
      ' $hay '.contains(' $phrase ');
}

// ── Луғат модели ──────────────────────────────────────────────────────

/// Матндан ажратиб олинган маълумот.
class _Extracted {
  const _Extracted({this.quantity, this.rooms, this.destination});

  final int? quantity;
  final int? rooms;
  final String? destination;
}

/// Манзил — кўринадиган ном ва канон шакл.
class _Destination {
  const _Destination(this.name, this.canon);

  final String name;
  final String canon;
}

/// Модул мета-маълумоти.
class _ModuleMeta {
  const _ModuleMeta({
    required this.labels,
    required this.coreReady,
    required this.existingScreen,
  });

  final Map<String, String> labels;

  /// Ядрога уланганми. P0'да фақат `service`.
  final bool coreReady;

  /// Уланмаган модулнинг мавжуд экрани.
  final String? existingScreen;

  static _ModuleMeta fromJson(Map<String, dynamic> m) {
    final labels = <String, String>{};
    final raw = m['label'];
    if (raw is Map) raw.forEach((k, v) => labels[k.toString()] = v.toString());
    return _ModuleMeta(
      labels: labels,
      coreReady: m['coreReady'] == true,
      existingScreen: (m['existingScreen'] as Object?)?.toString(),
    );
  }
}

class _IntentCategory {
  const _IntentCategory({
    required this.group,
    required this.names,
    required this.unit,
    required this.urgent,
  });

  final String group;
  final Map<String, String> names;
  final String unit;
  final bool urgent;

  static _IntentCategory fromJson(Map<String, dynamic> m) {
    final names = <String, String>{};
    final raw = m['names'];
    if (raw is Map) {
      raw.forEach((k, v) => names[k.toString()] = v.toString());
    }
    return _IntentCategory(
      group: (m['group'] ?? '').toString(),
      names: names,
      unit: (m['unit'] ?? 'job').toString(),
      urgent: m['urgent'] == true,
    );
  }
}

class _IntentData {
  const _IntentData({
    required this.keywords,
    required this.ambiguous,
    required this.generic,
    required this.categories,
    required this.minPrefixLen,
    required this.phraseWeight,
    this.moduleKeywords = const {},
    this.modules = const {},
    this.quantityUnits = const [],
    this.suppressWords = const [],
    this.roomWords = const [],
    this.destinations = const [],
  });

  // ── P0.3 — модул даражаси ───────────────────────────────────────────
  /// канон калит → модуллар.
  final Map<String, List<String>> moduleKeywords;
  final Map<String, _ModuleMeta> modules;
  final List<String> quantityUnits;

  /// Иш қидириш сўзлари — карточкани тўсади.
  final List<String> suppressWords;
  final List<String> roomWords;
  final List<_Destination> destinations;

  /// канон калит → категориялар.
  final Map<String, List<String>> keywords;

  /// канон калит → кўп маъноли категориялар.
  final Map<String, List<String>> ambiguous;

  /// «Хизмат керак», лекин қайси хизмат номаълум («уста», «ремонт»).
  final List<String> generic;

  final Map<String, _IntentCategory> categories;
  final int minPrefixLen;
  final int phraseWeight;

  static _IntentData empty() => const _IntentData(
        keywords: {},
        ambiguous: {},
        generic: [],
        categories: {},
        minPrefixLen: 4,
        phraseWeight: 3,
        moduleKeywords: {},
        modules: {},
      );

  static _IntentData fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> readMap(Object? raw) {
      final out = <String, List<String>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }
      return out;
    }

    final cats = <String, _IntentCategory>{};
    final rawCats = json['categories'];
    if (rawCats is Map) {
      rawCats.forEach((k, v) {
        if (v is Map) {
          cats[k.toString()] =
              _IntentCategory.fromJson(v.map((a, b) => MapEntry(a.toString(), b)));
        }
      });
    }

    final rawGeneric = json['generic'];
    final generic = rawGeneric is List
        ? rawGeneric.map((e) => e.toString()).toList()
        : const <String>[];

    final mods = <String, _ModuleMeta>{};
    final rawMods = json['modules'];
    if (rawMods is Map) {
      rawMods.forEach((k, v) {
        if (v is Map) {
          mods[k.toString()] =
              _ModuleMeta.fromJson(v.map((a, b) => MapEntry(a.toString(), b)));
        }
      });
    }

    List<String> readList(Object? raw) => raw is List
        ? raw.map((e) => e.toString()).toList()
        : const <String>[];

    final ex = json['extract'];
    final exMap = ex is Map ? ex : const {};
    final dests = <_Destination>[];
    final rawDests = exMap['destinations'];
    if (rawDests is List) {
      for (final d in rawDests) {
        if (d is Map) {
          dests.add(_Destination(
            (d['name'] ?? '').toString(),
            (d['canon'] ?? '').toString(),
          ));
        }
      }
    }

    return _IntentData(
      keywords: readMap(json['keywords']),
      ambiguous: readMap(json['ambiguous']),
      generic: generic,
      categories: cats,
      minPrefixLen: (json['minPrefixLen'] as num?)?.toInt() ?? 4,
      phraseWeight: (json['phraseWeight'] as num?)?.toInt() ?? 3,
      moduleKeywords: readMap(json['moduleKeywords']),
      modules: mods,
      quantityUnits: readList(exMap['quantityUnits']),
      suppressWords: readList(json['suppressWords']),
      roomWords: readList(exMap['roomWords']),
      destinations: dests,
    );
  }
}
