// ТАЛАБ → ТАКЛИФ ядроси — модулнинг UI adapter интерфейси.
//
// МУҲИМ ЧЕГАРА: клиентда matching ЙЎҚ. Dart adapter'и фақат UI учун:
// форма, валидация ва карточкани чизиш. «Ким мос?» саволига сервер
// жавоб беради (`functions_demand/adapters/*.js`).
//
// Янги модул қўшиш = битта adapter ёзиш + реестрга битта қатор. Ядронинг
// бошқа ҳеч бир жойи ўзгармайди — концепциянинг асосий талаби.

import 'package:flutter/material.dart';

import '../domain/demand.dart';
import '../domain/demand_enums.dart';
import '../domain/demand_match.dart';
import '../domain/offer.dart';

/// Форма тўлдирилаётган пайтдаги ҳолат.
///
/// Иммутабл эмас (форма ҳар белги ёзилганда ўзгаради), лекин
/// `toCallablePayload` соф функция — шунинг учун тестланади.
class DemandDraft {
  DemandDraft({
    required this.module,
    required this.clientRequestId,
    this.categoryId,
    this.source = 'module',
    this.inputType = 'form',
    this.rawText,
    this.title = '',
    this.description = '',
    this.location,
    this.destination,
    this.timeMode = 'custom',
    this.ttlMinutes,
    this.neededBy,
    this.budgetMax,
    this.budgetPriceType,
    this.quantity,
    this.images = const [],
    this.recipientName,
    this.recipientPhone,
    Map<String, dynamic>? attributes,
  }) : attributes = attributes ?? <String, dynamic>{};

  final DemandModule module;

  /// Т-12: форма ОЧИЛГАНДА бир марта яратилади ва «Юбориш» бир неча
  /// марта босилса ҳам ЎЗГАРМАЙДИ. Шунда сервер дубликатни таниб,
  /// иккинчи талабни яратмайди.
  final String clientRequestId;

  String? categoryId;
  String source;
  String inputType;
  String? rawText;
  String title;
  String description;
  DemandPoint? location;
  DemandPoint? destination;

  /// `now` | `today` | `custom`
  String timeMode;
  int? ttlMinutes;
  DateTime? neededBy;

  num? budgetMax;
  String? budgetPriceType;
  int? quantity;
  List<String> images;
  String? recipientName;
  String? recipientPhone;

  /// Модулга хос майдонлар. Сервер JSON Schema билан текширади, шунинг
  /// учун бу ерда эркин `Map`.
  final Map<String, dynamic> attributes;

  /// `timeWindow` юкламаси.
  Map<String, dynamic>? get timeWindowPayload {
    if (timeMode == 'now') return {'mode': 'now'};
    if (timeMode == 'today') return {'mode': 'today'};
    if (ttlMinutes != null || neededBy != null) {
      return {
        'mode': 'custom',
        if (ttlMinutes != null) 'ttlMinutes': ttlMinutes,
        if (neededBy != null) 'neededBy': neededBy!.toUtc().toIso8601String(),
      };
    }
    return null;
  }

  DemandBudget? get budget {
    if (budgetMax == null && budgetPriceType == null) return null;
    return DemandBudget(max: budgetMax, priceType: budgetPriceType);
  }

  Map<String, dynamic> get inputPayload => {
        'type': inputType,
        if (rawText != null && rawText!.isNotEmpty) 'rawText': rawText,
      };
}

/// Валидация натижаси — майдон → хато матни калити.
///
/// Калит, тайёр матн ЭМАС: матн учала локал файлда бўлиши керак.
class DraftValidation {
  const DraftValidation(this.errors);

  const DraftValidation.valid() : errors = const {};

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
  String? errorFor(String field) => errors[field];
}

/// Модулнинг UI adapter'и.
abstract class DemandUiAdapter {
  DemandModule get module;

  /// Модул экранидаги асосий тугма матни калити.
  ///
  /// Модулга ХОС феъл: «Посилка юбориш», «Жой сўраш», «Уста чақириш».
  /// Умумий «Талаб яратиш» ИШЛАТИЛМАЙДИ — концепциянинг ўзгармайдиган
  /// қоидаси (фойдаланувчи техник сўзларни кўрмайди).
  String get primaryActionL10nKey;

  /// Хизмат карточкасининг сарлавҳа калити (Intent Router).
  String get intentCardTitleL10nKey;

  /// Бўш драфт.
  DemandDraft newDraft({required String clientRequestId, String source});

  /// Intent Router натижасидан олдиндан тўлдириш.
  ///
  /// Концепция: «Матндан тушунилган маълумот формага олдиндан ёзилади.»
  void prefillFromIntent(DemandDraft draft, IntentResult intent);

  /// Форма.
  Widget buildForm(BuildContext context, DemandDraft draft, VoidCallback onChanged);

  /// Юборишдан олдин валидация.
  ///
  /// ДИҚҚАТ: бу СЕРВЕР валидациясини алмаштирмайди — фақат фойдаланувчига
  /// тезроқ хабар бериш учун. Ҳақиқий чегара серверда (JSON Schema).
  DraftValidation validate(DemandDraft draft);

  /// «Шундай тушундик» экранидаги қаторлар.
  ///
  /// Концепция: «Юборишдан олдин фойдаланувчига AVA нимани тушунгани
  /// қисқа кўрсатилади… Бу нотўғри тушуниш натижасида номос одамларга
  /// юборишнинг олдини олади.»
  List<ConfirmRow> buildConfirmRows(BuildContext context, DemandDraft draft);

  /// Таклифчи кўрадиган карточка.
  Widget buildMatchCard(BuildContext context, DemandMatch match);

  /// Харидор кўрадиган таклиф карточкаси.
  Widget buildOfferCard(BuildContext context, Offer offer, VoidCallback? onChoose);
}

/// Тасдиқлаш экранидаги битта қатор.
class ConfirmRow {
  const ConfirmRow({
    required this.labelKey,
    required this.value,
    this.editField,
    this.icon,
  });

  /// Локал калити («Қаерда?»).
  final String labelKey;

  /// Тайёр матн («Урганч, Ал-Хоразмий атрофи»).
  final String value;

  /// «Тузатиш» босилганда фокус қайси майдонга тушади.
  final String? editField;

  final IconData? icon;
}

/// Intent Router натижаси.
///
/// Ҳозирча 1-босқич: калит сўзлар луғати (`module_config/intent_keywords`
/// + bundled fallback). 2-босқич (сервердаги LLM) — P1.
class IntentResult {
  const IntentResult({
    required this.rawText,
    this.module,
    this.categoryId,
    this.candidateCategoryIds = const [],
    this.needsChoice = false,
    this.destinationHint,
    this.matchedKeywords = const [],
    this.quantity,
    this.rooms,
    this.coreReady = false,
    this.existingScreen,
  });

  final String rawText;
  final DemandModule? module;

  /// Аниқ категория. `needsChoice` бўлса `null`.
  final String? categoryId;

  /// Бир нечта мос категория — фойдаланувчи танлайди.
  final List<String> candidateCategoryIds;

  /// Кўп маъноли калит сўз («котёл» → газ устаси ёки иситиш тизими).
  ///
  /// AVA ЎЗИ ТАНЛАМАЙДИ — иккита вариантни таклиф қилади.
  final bool needsChoice;

  /// «Тошкентга посилка» → «Қаерга» майдонига Тошкент.
  final String? destinationHint;

  final List<String> matchedKeywords;

  /// «500 дона футболка керак» → 500.
  ///
  /// ≥5 бўлса сервер талабни УЛГУРЖИ деб белгилайди (тасдиқланган
  /// чегара) — эганинг мисоли айни шунга тушади.
  final int? quantity;

  /// «3 хонали квартира керак» → 3.
  final int? rooms;

  /// Бу модул ЯДРОГА уланганми.
  ///
  /// P0'да фақат `service` уланган (Қ-1). Қолганлари учун иловада
  /// аллақачон ишлайдиган экранлар бор — карточка ўша ерга олиб боради.
  final bool coreReady;

  /// Ядрога уланмаган модулнинг мавжуд экрани (`courier`, `realty`…).
  final String? existingScreen;

  bool get hasModule => module != null;

  /// Хизмат карточкаси кўрсатиладими.
  ///
  /// Концепция: «Хизмат карточкаси форма эмас. AVA адашса, фойдаланувчи
  /// карточкани ўтказиб, оддий натижаларни кўради.»
  bool get showsServiceCard => hasModule;

  /// Ядро оқими очиладими (сўров формаси), ёки мавжуд модул экрани.
  bool get opensCoreFlow => hasModule && coreReady;

  IntentResult copyWith({
    String? rawText,
    DemandModule? module,
    String? categoryId,
    List<String>? candidateCategoryIds,
    bool? needsChoice,
    String? destinationHint,
    List<String>? matchedKeywords,
    int? quantity,
    int? rooms,
    bool? coreReady,
    String? existingScreen,
  }) {
    return IntentResult(
      rawText: rawText ?? this.rawText,
      module: module ?? this.module,
      categoryId: categoryId ?? this.categoryId,
      candidateCategoryIds: candidateCategoryIds ?? this.candidateCategoryIds,
      needsChoice: needsChoice ?? this.needsChoice,
      destinationHint: destinationHint ?? this.destinationHint,
      matchedKeywords: matchedKeywords ?? this.matchedKeywords,
      quantity: quantity ?? this.quantity,
      rooms: rooms ?? this.rooms,
      coreReady: coreReady ?? this.coreReady,
      existingScreen: existingScreen ?? this.existingScreen,
    );
  }
}
