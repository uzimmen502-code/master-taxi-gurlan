// Фаолият тури профили — «Менинг бизнесим» занжирининг S0 шартномаси (2026-11-03).
//
// ЯГОНА манба (7-банд): объект тури (+ аниқроқ тури) бўйича таклиф тури (маҳсулот/хизмат), каталог номи,
// бўш ҳолат матни, «кейинги қадам» матнлари, тез бошлаш шаблонлари, нарх бирликлари, лицензия эслатмаси,
// курьер етказиши ва мавжуд модул кўприги. S1 (кейинги қадам), S2 (нарх бирлиги), S3 (харидор юзалари),
// S5 (каталог экрани) шу ердан ўқийди — матн ва қоида экранларда қайта ёзилмайди.
//
// Ҳолат:
// * CONFIRMED (эга 2026-11-03): овқатланиш → ресторан бўлими (меню, `business_food_flow.dart`); дўкон → мавжуд
//   маҳсулот оқими; лицензияли турлар (тиббиёт, молия, юридик/касбий, хавфсизлик, оила/болалар) — текширувсиз
//   дарҳол чиқади, фақат эслатма ([BusinessSubtypes.noteKey]); комиссия йўқ; курьерни харидор тўлайди (кейинги слайс).
// * PROPOSED (эга кўриб чиқади): шаблонлар, бошланғич нарх бирликлари, аниқроқ тур бўйича тур алмашуви, курьер
//   етказиши қайси турларга тегишли.
//
// Тиллар: шаблонлар (uz_Cyrl, ru) жуфтлиги, uz_Latn — [UzScript.toLatin] (`business_subtypes.dart` андозаси).
// Экран матнлари — `assets/lang/*.json` калитлари (3 тилда; тест қулфлайди).

import '../../../core/utils/uz_script.dart';
import '../../tv_market/domain/price_unit.dart';
import 'business.dart';
import 'business_category.dart';
import 'business_subtypes.dart';

/// Таклиф тури — `tv_shop_items.kind` қиймати ('product' / 'service').
enum OfferKind {
  product('product'),
  service('service');

  const OfferKind(this.wire);
  final String wire;

  /// Номаълум/бўш — [product] (TvShopItem.kind бошланғичи ҳам 'product').
  static OfferKind fromWire(Object? raw) => raw == 'service' ? OfferKind.service : OfferKind.product;
}

/// Каталог гуруҳи: экран номи, бўш ҳолат ва «кейинги қадам» матни шунга боғлиқ.
enum BusinessOfferGroup {
  /// Овқатланиш объекти — ресторан бўлими менюси (generic каталог эмас).
  menu,

  /// Маҳсулот сотувчи/ишлаб чиқарувчи.
  products,

  /// Хизмат кўрсатувчи.
  services,

  /// Маҳсулот ҳам, хизмат ҳам (тур танлови очиқ).
  mixed,
}

/// Объектнинг мавжуд AVA модулига кўприги (ихтиёрий «ўсиш» қадами, S1). Кириш нуқталари репода текширилган
/// (2026-11-03); экран импорти шу файлда ЙЎҚ — домен қатлами тоза қолади, S1 enum → экранни боғлайди.
enum BusinessModuleBridge {
  /// Уй-жой эълони: `lib/features/realty/screens/add_realty_listing_screen.dart` → `AddRealtyListingScreen()`
  /// (realty_screen.dart:72 да шундай очилади).
  realtyListing('realty_add_cta'),

  /// Туман ичида юк ташувчи: `YukLocalScreen(openPublish: true)` — «＋» → «Юк ташувчи бўлиш» билан бир хил
  /// (home_screen.dart `_openYukModule('yuk_local', …)`, модул ёпиқлиги шу ерда текширилади).
  cargoLocal('home_create_cargo'),

  /// Электромобиль қувватлаш станцияси — ПУЛЛИК қўшиш (эга 2026-09-22): тариф `EvStationTariffSheet` да
  /// танланади, сўнг `AddEvStationScreen(tariff: …)`; кириш — `EvChargingMapScreen` (ev_charging_map_screen.dart:296).
  /// Харита объекти билан битта пин қилиш — эга қарори UNKNOWN (аудит).
  evStation('ev_add_station_title');

  const BusinessModuleBridge(this.ctaKey);

  /// Тугма матни калити (мавжуд калитлар қайта ишлатилган).
  final String ctaKey;
}

/// Тез бошлаш шаблони: номи (uz_Cyrl, ru), таклиф тури, нарх бирлиги.
typedef OfferTemplate = ({String uzCyrl, String ru, OfferKind kind, PriceUnit unit});

OfferTemplate _s(String uz, String ru, [PriceUnit unit = PriceUnit.fixed]) =>
    (uzCyrl: uz, ru: ru, kind: OfferKind.service, unit: unit);
OfferTemplate _p(String uz, String ru, [PriceUnit unit = PriceUnit.fixed]) =>
    (uzCyrl: uz, ru: ru, kind: OfferKind.product, unit: unit);

/// Аниқроқ тур бўйича алмаштириш (фақат берилган майдонлар ўзгаради).
class _Override {
  const _Override({this.kind, this.unit, this.templates, this.bridge, this.noBridge = false, this.courier});
  final OfferKind? kind;
  final PriceUnit? unit;
  final List<OfferTemplate>? templates;
  final BusinessModuleBridge? bridge;

  /// Тур кўпригини шу аниқроқ тур учун олиб ташлаш (масалан кўчмас мулк баҳолаш — эълон эмас).
  final bool noBridge;
  final bool? courier;
}

/// Тур профили. Олиш: [BusinessTypeProfile.of] (тур + аниқроқ тур) ёки [BusinessTypeProfile.forBusiness].
class BusinessTypeProfile {
  const BusinessTypeProfile._({
    required this.category,
    required this.subtype,
    required this.group,
    required this.defaultKind,
    required this.kindSelectable,
    required this.defaultPriceUnit,
    required this.priceUnits,
    required this.templates,
    required this.courierDelivery,
    required this.moduleBridge,
  });

  final BusinessCategory category;

  /// Тан олинган аниқроқ тур (эга рўйхатидаги uz_Cyrl номи); тан олинмаса — `''`.
  final String subtype;

  final BusinessOfferGroup group;

  /// Формадаги бошланғич тур (эга ўзгартира олади, агар [kindSelectable]).
  final OfferKind defaultKind;

  /// «Маҳсулот / Хизмат» танлови кўринадими. Дўконда — йўқ (эга 2026-10-26, `sellsOnlyProducts`).
  final bool kindSelectable;

  /// Формадаги бошланғич нарх бирлиги (S2).
  final PriceUnit defaultPriceUnit;

  /// Формада танлаш мумкин бўлган бирликлар (enum тартибида; [defaultPriceUnit] доим ичида).
  final List<PriceUnit> priceUnits;

  /// Тез бошлаш чиплари (2–4 та).
  final List<OfferTemplate> templates;

  /// Бу турдаги МАҲСУЛОТни курьер етказиши мумкинми (PROPOSED; курьер — кейинги слайс, харидор тўлайди).
  /// Хизмат, тиббиёт, ташқи савдо партияси, тирик ҳайвон, ресторан менюси (ўз курьери бор) — йўқ.
  final bool courierDelivery;

  final BusinessModuleBridge? moduleBridge;

  /// Лицензия/рухсат эслатмаси калити (форма ва эга хабида; нашрни тўсмайди — эга 2026-11-03).
  String? get licenceNoteKey => BusinessSubtypes.noteKey(category);
  bool get needsLicenceNote => licenceNoteKey != null;

  /// Каталог сарлавҳаси («Маҳсулотлар» / «Хизматлар» / «Меню» / «Маҳсулотлар ва хизматлар»).
  String get catalogTitleKey => switch (group) {
        BusinessOfferGroup.products => 'bizprod_title_products',
        BusinessOfferGroup.services => 'biz_catalog_services',
        BusinessOfferGroup.menu => 'restaurants_m_tab_menu',
        BusinessOfferGroup.mixed => 'bizprod_title',
      };

  /// Харидор юзаларидаги каталог/саҳифа тугмаси (S3): дўкон — «Дўконга ўтиш», хизмат — «Барча хизматлар»,
  /// аралаш ва овқатланиш — «Саҳифага ўтиш» (овқатланиш менюси ўз «Меню» тугмасида).
  String get openCatalogKey => switch (group) {
        BusinessOfferGroup.products => 'shop_go_to_shop',
        BusinessOfferGroup.services => 'biz_open_services',
        BusinessOfferGroup.menu || BusinessOfferGroup.mixed => 'biz_open_page',
      };

  /// Харидор юзаларидаги таклифлар бўлими сарлавҳаси (S3): [catalogTitleKey], овқатланишда эса бу бўлим
  /// ресторан менюси эмас, объектнинг дўкон таклифлари — умумий «Маҳсулотлар ва хизматлар».
  String get offersSectionKey => group == BusinessOfferGroup.menu ? 'bizprod_section' : catalogTitleKey;

  /// Каталог бўш бўлгандаги матн.
  String get emptyStateKey => switch (group) {
        BusinessOfferGroup.products => 'bizprod_empty',
        BusinessOfferGroup.services => 'biz_empty_services',
        BusinessOfferGroup.menu => 'restaurants_menu_empty',
        BusinessOfferGroup.mixed => 'biz_empty_mixed',
      };

  /// «Кейинги қадам»: таклиф қўшиш қадамининг сарлавҳаси.
  String get nextStepTitleKey => switch (group) {
        BusinessOfferGroup.menu => 'bizmap_menu_sheet_title',
        _ => 'biz_next_${group.name}_title',
      };

  /// «Кейинги қадам»: изоҳ.
  String get nextStepSubtitleKey => 'biz_next_${group.name}_sub';

  /// «Кейинги қадам»: асосий тугма.
  String get nextStepCtaKey => switch (group) {
        BusinessOfferGroup.menu => 'bizmap_open_menu',
        BusinessOfferGroup.mixed => 'bizprod_add',
        _ => 'biz_next_${group.name}_cta',
      };

  /// Шаблон номлари [lang] тилида (`uz_Cyrl` / `uz_Latn` / `ru`).
  List<String> templateTitles(String lang) => [for (final t in templates) templateTitle(t, lang)];

  static String templateTitle(OfferTemplate t, String lang) => switch (lang) {
        'ru' => t.ru,
        'uz_Latn' => UzScript.toLatin(t.uzCyrl),
        _ => t.uzCyrl,
      };

  /// Шу таклифни курьер етказиши мумкинми: тур рухсат берган, таклиф маҳсулот ва объектнинг жисмоний жойи бор.
  bool courierDeliveryApplies({required OfferKind kind, required bool online}) =>
      courierDelivery && kind == OfferKind.product && !online;

  // ── Профил олиш ───────────────────────────────────────────────────────────────────────────────────

  /// [category] ва (ихтиёрий) [subtype] — сақланган матн исталган тилда/ёзувда ([BusinessSubtypes.norm]).
  /// Тан олинмаган ёки бўш [subtype] — тур бошланғичи.
  static BusinessTypeProfile of(BusinessCategory category, {String subtype = ''}) {
    final base = _base[category]!;
    final canon = canonicalSubtype(category, subtype);
    final o = _overrides[category]?[canon];
    final kind = o?.kind ?? base.kind;
    final unit = o?.unit ?? base.unit;
    final group = switch (base.group) {
      BusinessOfferGroup.menu => BusinessOfferGroup.menu,
      BusinessOfferGroup.mixed => BusinessOfferGroup.mixed,
      _ => kind == OfferKind.product ? BusinessOfferGroup.products : BusinessOfferGroup.services,
    };
    final shopOnly = category == BusinessCategory.retail;
    return BusinessTypeProfile._(
      category: category,
      subtype: canon,
      group: group,
      defaultKind: kind,
      kindSelectable: !shopOnly && group != BusinessOfferGroup.menu,
      defaultPriceUnit: unit,
      priceUnits: _unitsFor(group, unit),
      templates: o?.templates ?? base.templates,
      courierDelivery: o?.courier ?? (kind == OfferKind.product && base.courier),
      moduleBridge: (o?.noBridge ?? false) ? null : (o?.bridge ?? base.bridge),
    );
  }

  /// Объект бўйича. Асосий дўкон ([Business.isOwnShop]) — доим дўкон профили (`sellsOnlyProducts` билан бир хил).
  static BusinessTypeProfile forBusiness(Business b) =>
      b.isOwnShop ? of(BusinessCategory.retail) : of(b.category, subtype: b.subtype);

  /// Сақланган аниқроқ тур → эга рўйхатидаги uz_Cyrl номи ([category] ичида); топилмаса `''`.
  static String canonicalSubtype(BusinessCategory category, String stored) {
    final n = BusinessSubtypes.norm(stored);
    if (n.isEmpty) return '';
    for (final e in BusinessSubtypes.data[category] ?? const <(String, String)>[]) {
      if (BusinessSubtypes.norm(e.$1) == n || BusinessSubtypes.norm(e.$2) == n) return e.$1;
    }
    return '';
  }

  /// Гуруҳ бўйича танлов рўйхати (+ бошланғич бирлик), enum тартибида.
  static List<PriceUnit> _unitsFor(BusinessOfferGroup g, PriceUnit def) {
    final set = <PriceUnit>{
      ...switch (g) {
        BusinessOfferGroup.menu => const [PriceUnit.fixed],
        BusinessOfferGroup.products => const [
            PriceUnit.fixed,
            PriceUnit.from,
            PriceUnit.kg,
            PriceUnit.piece,
            PriceUnit.negotiable,
          ],
        BusinessOfferGroup.services => const [
            PriceUnit.fixed,
            PriceUnit.from,
            PriceUnit.hour,
            PriceUnit.day,
            PriceUnit.month,
            PriceUnit.session,
            PriceUnit.person,
            PriceUnit.m2,
            PriceUnit.negotiable,
          ],
        BusinessOfferGroup.mixed => PriceUnit.values,
      },
      def,
    };
    return [for (final u in PriceUnit.values) if (set.contains(u)) u];
  }
}

/// Тур бошланғичи.
typedef _Base = ({
  BusinessOfferGroup group,
  OfferKind kind,
  PriceUnit unit,
  bool courier,
  BusinessModuleBridge? bridge,
  List<OfferTemplate> templates,
});

_Base _prod(PriceUnit unit, List<OfferTemplate> t, {bool courier = true}) =>
    (group: BusinessOfferGroup.products, kind: OfferKind.product, unit: unit, courier: courier, bridge: null, templates: t);
_Base _serv(PriceUnit unit, List<OfferTemplate> t, {BusinessModuleBridge? bridge}) =>
    (group: BusinessOfferGroup.services, kind: OfferKind.service, unit: unit, courier: false, bridge: bridge, templates: t);

// ── Шаблонлар (PROPOSED) ────────────────────────────────────────────────────────────────────────────

final _autoParts = [
  _p('Мой фильтри', 'Масляный фильтр', PriceUnit.piece),
  _p('Аккумулятор', 'Аккумулятор', PriceUnit.piece),
  _p('Шина', 'Шина', PriceUnit.piece),
];
final _farmWork = [
  _s('Ер ҳайдаш', 'Вспашка земли', PriceUnit.from),
  _s('Экиш', 'Посев', PriceUnit.from),
  _s('Ўрим-йиғим', 'Уборка урожая', PriceUnit.from),
];
final _optics = [
  _p('Кўзойнак', 'Очки', PriceUnit.from),
  _p('Кўз линзаси', 'Контактные линзы', PriceUnit.piece),
  _p('Тонометр', 'Тонометр', PriceUnit.piece),
];
final _petGoods = [
  _p('Ит учун ем', 'Корм для собак', PriceUnit.kg),
  _p('Мушук учун ем', 'Корм для кошек', PriceUnit.kg),
  _p('Ҳайвон ўйинчоғи', 'Игрушка для животных', PriceUnit.piece),
];
final _livestock = [
  _p('Қўй', 'Овца', PriceUnit.negotiable),
  _p('Бузоқ', 'Телёнок', PriceUnit.negotiable),
  _p('Товуқ', 'Курица', PriceUnit.piece),
];
final _tailoring = [
  _s('Буюртмага тикиш', 'Пошив на заказ', PriceUnit.from),
  _s('Кийим таъмирлаш', 'Ремонт одежды', PriceUnit.from),
  _s('Парда тикиш', 'Пошив штор', PriceUnit.from),
];
final _salon = [
  _s('Соч олиш', 'Стрижка', PriceUnit.from),
  _s('Соқол олиш', 'Бритьё бороды'),
  _s('Болалар соч олиш', 'Детская стрижка'),
];
final _beauty = [
  _s('Маникюр', 'Маникюр', PriceUnit.from),
  _s('Педикюр', 'Педикюр', PriceUnit.from),
  _s('Массаж', 'Массаж', PriceUnit.session),
];
final _cleaning = [
  _s('Уй тозалаш', 'Уборка квартиры', PriceUnit.m2),
  _s('Гилам ювиш', 'Стирка ковров', PriceUnit.m2),
  _s('Дераза ювиш', 'Мойка окон', PriceUnit.from),
];
final _repair = [
  _s('Диагностика', 'Диагностика'),
  _s('Таъмирлаш', 'Ремонт', PriceUnit.from),
  _s('Уста чақириш', 'Вызов мастера'),
];

final Map<BusinessCategory, _Base> _base = {
  BusinessCategory.retail: _prod(PriceUnit.fixed, [
    _p('Ун 50 кг', 'Мука 50 кг'),
    _p('Пахта ёғи 1 л', 'Хлопковое масло 1 л'),
    _p('Шакар 1 кг', 'Сахар 1 кг'),
  ]),
  BusinessCategory.manufacturing: _prod(PriceUnit.piece, [
    _p('Ғишт (1000 дона)', 'Кирпич (1000 шт)'),
    _p('Буюртма мебель', 'Мебель на заказ', PriceUnit.from),
    _p('Тикув маҳсулоти', 'Швейные изделия', PriceUnit.piece),
  ]),
  BusinessCategory.agriculture: _prod(PriceUnit.kg, [
    _p('Помидор', 'Помидоры', PriceUnit.kg),
    _p('Сут 1 л', 'Молоко 1 л'),
    _p('Мева кўчати', 'Саженцы плодовых деревьев', PriceUnit.piece),
  ]),
  // Меню — ресторан бўлимида (эга 2026-11-03); шаблонлар фақат намуна сифатида.
  BusinessCategory.food: (
    group: BusinessOfferGroup.menu,
    kind: OfferKind.product,
    unit: PriceUnit.fixed,
    courier: false,
    bridge: null,
    templates: [_p('Палов', 'Плов'), _p('Сомса', 'Самса'), _p('Шашлик', 'Шашлык')],
  ),
  BusinessCategory.logistics: _serv(PriceUnit.from, [
    _s('Шаҳар ичида юк ташиш', 'Грузоперевозки по городу', PriceUnit.from),
    _s('Вилоятлараро юк ташиш', 'Междугородние грузоперевозки', PriceUnit.from),
    _s('Юк ортиш-тушириш', 'Погрузка-разгрузка', PriceUnit.hour),
  ]),
  BusinessCategory.auto: _serv(PriceUnit.from, [
    _s('Мой алмаштириш', 'Замена масла', PriceUnit.from),
    _s('Компьютер диагностикаси', 'Компьютерная диагностика'),
    _s('Шиномонтаж', 'Шиномонтаж', PriceUnit.from),
  ]),
  BusinessCategory.construction: _serv(PriceUnit.m2, [
    _s('Кафель ётқизиш', 'Укладка кафеля', PriceUnit.m2),
    _s('Электр монтаж', 'Электромонтаж', PriceUnit.from),
    _s('Сувоқ', 'Штукатурка', PriceUnit.m2),
  ]),
  BusinessCategory.realEstate: _serv(PriceUnit.month, [
    _s('Ижарага бериш', 'Сдача в аренду', PriceUnit.month),
    _s('Уй сотишда ёрдам', 'Помощь в продаже дома', PriceUnit.negotiable),
    _s('Кўчмас мулкни баҳолаш', 'Оценка недвижимости', PriceUnit.from),
  ], bridge: BusinessModuleBridge.realtyListing),
  BusinessCategory.personal: _serv(PriceUnit.from, _salon),
  BusinessCategory.education: _serv(PriceUnit.month, [
    _s('Инглиз тили курси', 'Курс английского языка', PriceUnit.month),
    _s('Математика репетитори', 'Репетитор по математике', PriceUnit.month),
    _s('ДТМ ва IELTS га тайёрлов', 'Подготовка к ДТМ и IELTS', PriceUnit.month),
  ]),
  BusinessCategory.health: _serv(PriceUnit.session, [
    _s('Шифокор кўриги', 'Приём врача', PriceUnit.session),
    _s('УЗИ текшируви', 'УЗИ-обследование'),
    _s('Тиш тозалаш', 'Чистка зубов'),
  ]),
  BusinessCategory.it: _serv(PriceUnit.from, [
    _s('Сайт яратиш', 'Создание сайта', PriceUnit.from),
    _s('Telegram бот', 'Telegram-бот', PriceUnit.from),
    _s('Компьютер созлаш', 'Настройка компьютера'),
  ]),
  BusinessCategory.marketing: _serv(PriceUnit.month, [
    _s('SMM юритиш', 'Ведение SMM', PriceUnit.month),
    _s('Логотип', 'Логотип', PriceUnit.from),
    _s('Баннер чоп этиш', 'Печать баннера', PriceUnit.m2),
  ]),
  BusinessCategory.finance: _serv(PriceUnit.month, [
    _s('Бухгалтерия юритиш', 'Ведение бухгалтерии', PriceUnit.month),
    _s('Солиқ ҳисоботи', 'Налоговая отчётность', PriceUnit.from),
    _s('Суғурта', 'Страхование', PriceUnit.negotiable),
  ]),
  BusinessCategory.professional: _serv(PriceUnit.hour, [
    _s('Юрист маслаҳати', 'Консультация юриста', PriceUnit.hour),
    _s('Ҳужжат тайёрлаш', 'Подготовка документов', PriceUnit.from),
    _s('Таржима (1 бет)', 'Перевод (1 страница)'),
  ]),
  BusinessCategory.tourism: _serv(PriceUnit.person, [
    _s('Хива бўйлаб саёҳат', 'Экскурсия по Хиве', PriceUnit.person),
    _s('Хона (бир кеча)', 'Номер (1 ночь)'),
    _s('Трансфер', 'Трансфер', PriceUnit.from),
  ]),
  BusinessCategory.sport: _serv(PriceUnit.month, [
    _s('Абонемент (бир ой)', 'Абонемент (1 месяц)'),
    _s('Шахсий машғулот', 'Персональная тренировка', PriceUnit.session),
    _s('Майдон ижараси', 'Аренда поля', PriceUnit.hour),
  ]),
  BusinessCategory.creative: _serv(PriceUnit.from, [
    _s('Тўй видеосъёмкаси', 'Свадебная видеосъёмка', PriceUnit.from),
    _s('Фотосессия', 'Фотосессия', PriceUnit.from),
    _s('Дизайн', 'Дизайн', PriceUnit.from),
  ]),
  BusinessCategory.family: _serv(PriceUnit.hour, [
    _s('Энага', 'Няня', PriceUnit.hour),
    _s('Тўй ташкиллаш', 'Организация свадьбы', PriceUnit.negotiable),
    _s('Болалар байрами', 'Детский праздник', PriceUnit.from),
  ]),
  BusinessCategory.animals: _serv(PriceUnit.session, [
    _s('Ветеринар кўриги', 'Осмотр ветеринара', PriceUnit.session),
    _s('Эмлаш', 'Вакцинация'),
    _s('Жун қирқиш', 'Стрижка шерсти', PriceUnit.from),
  ]),
  BusinessCategory.energy: _serv(PriceUnit.from, [
    _s('Қуёш панели ўрнатиш', 'Установка солнечных панелей', PriceUnit.from),
    _s('Генератор ижараси', 'Аренда генератора', PriceUnit.day),
    _s('Электр монтаж', 'Электромонтаж', PriceUnit.from),
  ]),
  BusinessCategory.rental: _serv(PriceUnit.day, [
    _s('Тўй либоси ижараси', 'Прокат свадебного платья', PriceUnit.day),
    _s('Асбоб-ускуна ижараси', 'Аренда инструмента', PriceUnit.day),
    _s('Автомобиль ижараси', 'Аренда автомобиля', PriceUnit.day),
  ]),
  BusinessCategory.agency: _serv(PriceUnit.from, [
    _s('Ҳужжат расмийлаштириш', 'Оформление документов', PriceUnit.from),
    _s('Чипта буюртма қилиш', 'Заказ билетов'),
    _s('Ишга жойлаштириш', 'Трудоустройство', PriceUnit.negotiable),
  ]),
  // Ташқи савдо — маҳсулот ҳам, хизмат ҳам; партия курьерга мос эмас.
  BusinessCategory.foreignTrade: (
    group: BusinessOfferGroup.mixed,
    kind: OfferKind.product,
    unit: PriceUnit.from,
    courier: false,
    bridge: null,
    templates: [
      _s('Хитойдан юк келтириш', 'Доставка грузов из Китая', PriceUnit.kg),
      _s('Экспорт ҳужжатлари', 'Экспортные документы', PriceUnit.from),
      _p('Улгуржи партия', 'Оптовая партия', PriceUnit.from),
    ],
  ),
  BusinessCategory.fashion: _prod(PriceUnit.fixed, [
    _p('Аёллар кўйлаги', 'Женское платье'),
    _p('Эркаклар костюми', 'Мужской костюм'),
    _s('Буюртмага тикиш', 'Пошив на заказ', PriceUnit.from),
  ]),
  BusinessCategory.ecology: _serv(PriceUnit.kg, [
    _s('Макулатура қабули', 'Приём макулатуры', PriceUnit.kg),
    _s('Чиқинди олиб кетиш', 'Вывоз мусора', PriceUnit.from),
    _s('Металл қабули', 'Приём металлолома', PriceUnit.kg),
  ]),
  BusinessCategory.security: _serv(PriceUnit.month, [
    _s('Объект қўриқлаш', 'Охрана объекта', PriceUnit.month),
    _s('Видеокузатув ўрнатиш', 'Установка видеонаблюдения', PriceUnit.from),
    _s('Сигнализация ўрнатиш', 'Установка сигнализации', PriceUnit.from),
  ]),
  BusinessCategory.businessSupport: _serv(PriceUnit.from, [
    _s('Бизнес-режа тузиш', 'Составление бизнес-плана', PriceUnit.from),
    _s('Корхона очишда ёрдам', 'Помощь в открытии компании', PriceUnit.from),
    _s('Консалтинг', 'Консалтинг', PriceUnit.hour),
  ]),
  BusinessCategory.social: _serv(PriceUnit.fixed, [
    _s('Бепул маслаҳат', 'Бесплатная консультация'),
    _s('Хайрия ёрдами', 'Благотворительная помощь'),
    _s('Кўнгилли ёрдам', 'Волонтёрская помощь'),
  ]),
  // «Бошқа» — маҳсулот ҳам, хизмат ҳам (тур танлови очиқ, бошланғичи маҳсулот).
  BusinessCategory.other: (
    group: BusinessOfferGroup.mixed,
    kind: OfferKind.product,
    unit: PriceUnit.fixed,
    courier: true,
    bridge: null,
    templates: [_p('Маҳсулот', 'Товар'), _s('Хизмат', 'Услуга')],
  ),
};

/// Аниқроқ тур бўйича алмаштиришлар; калит — эга рўйхатидаги uz_Cyrl номи (`business_subtypes.dart`).
final Map<BusinessCategory, Map<String, _Override>> _overrides = {
  // Аудит: auto аниқроқ турларининг кўпи хизмат; савдо турлари — маҳсулот.
  BusinessCategory.auto: {
    for (final s in const ['Автомобиль эҳтиёт қисмлари', 'Аккумулятор', 'Шина савдоси'])
      s: _Override(kind: OfferKind.product, unit: PriceUnit.piece, templates: _autoParts, courier: true),
    'Электромобиль қувватлаш станцияси': const _Override(bridge: BusinessModuleBridge.evStation),
  },
  BusinessCategory.energy: {
    'Электр қувватлаш станциялари': const _Override(bridge: BusinessModuleBridge.evStation),
  },
  BusinessCategory.agriculture: {
    for (final s in const ['Қишлоқ хўжалиги техникаси хизмати', 'Ер ҳайдаш', 'Экиш', 'Ўрим-йиғим'])
      s: _Override(kind: OfferKind.service, unit: PriceUnit.from, templates: _farmWork),
  },
  // Тиббий товар — маҳсулот, лекин курьер йўқ (дори етказиш ҳуқуқий ҳолати UNKNOWN, аудит).
  BusinessCategory.health: {
    for (final s in const ['Оптика', 'Кўзойнак', 'Тиббий асбоблар', 'Дорихона'])
      s: _Override(kind: OfferKind.product, unit: PriceUnit.piece, templates: _optics, courier: false),
  },
  BusinessCategory.animals: {
    for (final s in const ['Зоотоварлар', 'Ем ва озуқа'])
      s: _Override(kind: OfferKind.product, unit: PriceUnit.kg, templates: _petGoods, courier: true),
    'Ветеринар дорихонаси': _Override(kind: OfferKind.product, unit: PriceUnit.piece, templates: _petGoods, courier: false),
    for (final s in const ['Чорва сотиш', 'Парранда сотиш'])
      s: _Override(kind: OfferKind.product, unit: PriceUnit.negotiable, templates: _livestock, courier: false),
  },
  BusinessCategory.fashion: {
    for (final s in const ['Ателье', 'Индивидуал тикиш', 'Кийим дизайнери', 'Парда тикиш'])
      s: _Override(kind: OfferKind.service, unit: PriceUnit.from, templates: _tailoring),
    'Либос ижараси': const _Override(kind: OfferKind.service, unit: PriceUnit.day),
    for (final s in const ['Тўй безаги', 'Тўй ташкилотчиси'])
      s: const _Override(kind: OfferKind.service, unit: PriceUnit.from),
  },
  BusinessCategory.personal: {
    for (final s in const ['Маникюр', 'Педикюр', 'Косметология', 'Макияж', 'Қош-киприк хизмати', 'Массаж'])
      s: _Override(templates: _beauty),
    for (final s in const ['Кимёвий тозалаш', 'Гилам ювиш', 'Уй тозалаш', 'Офис тозалаш', 'Ҳовли тозалаш', 'Мебель тозалаш'])
      s: _Override(unit: PriceUnit.m2, templates: _cleaning),
    for (final s in const ['Кийим тикиш', 'Кийим таъмирлаш'])
      s: _Override(templates: _tailoring),
    for (final s in const [
      'Сантехник чақириш',
      'Электрик чақириш',
      'Уйда майда таъмирлаш',
      'Калит ясаш',
      'Пойабзал таъмири',
      'Соат таъмири',
      'Маиший техника таъмири',
      'Компьютер таъмири',
      'Телефон таъмири',
    ])
      s: _Override(templates: _repair),
  },
  BusinessCategory.realEstate: {
    for (final s in const ['Кўчмас мулк баҳолаш', 'Уй бошқаруви', 'Коммунал хизматларни ташкил этиш'])
      s: const _Override(noBridge: true),
  },
  BusinessCategory.logistics: {
    for (final s in const [
      'Юк машинаси',
      'Кичик юк машинаси',
      'Қурилиш юки',
      'Қишлоқ хўжалиги юки',
      'Мебель ташиш',
      'Кўчириш хизмати',
      'Юк ортиш-тушириш',
    ])
      s: const _Override(bridge: BusinessModuleBridge.cargoLocal),
  },
};
