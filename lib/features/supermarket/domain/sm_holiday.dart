/// «Туғилган кун ва байрам саватчаси» (эга 2026-11-26) — тоза модел ва қоидалар (Flutter/Firebase'сиз).
///
/// Сервер шартномаси (feat/holiday-basket-srv 5eb77906, `functions/holiday.js`):
///  * `getHolidayCatalog()` → `{occasions:[{id, names, kind, bigHoliday, image, order, remindDaysBefore, nextDate}],
///    baskets:[{id, occasionId, tier, names, baseGuests, items(сони)}], today}` — кўриниш (босқич, тестер,
///    супермаркет дарвозаси) СЕРВЕРДА ҳал қилинади;
///  * `buildHolidayBasket({basketId, guests 1..500?, budget?})` → `{lines[{productId, groupId, name, price, qty, qtyStep,
///    unit, total, weighed, priority, varietyId?, imageUrl?}], goods, fee, total, changes[{type swap|drop|unavailable,
///    reason?, groupId, fromOfferId?, toOfferId?, offerId?, saving?}], guests, budget?, withinBudget?, feePercent}`;
///  * `placeSupermarketOrder` + `deliveryDate` (≤ 14 кун; `getSupermarketAccess({withDates:true})` → `dateSlots`),
///    `gift{recipientName ≤60, recipientPhone, message ≤200, hidePrice:true}`, `useIncentive`, `origin:'holiday'`,
///    `occasionId`, `basketId`;
///  * админ: `adminUpsertHolidayOccasion({occasion, reason?})` (`dateRule: null | {type:'fixed', md} |
///    {type:'list', dates[]}`), `adminUpsertHolidayBasket({basket, reason?})`.
/// Нарх, алмаштириш, тўлов — СЕРВЕР қарори (18, 44-банд); бу ерда фақат кўрсатиш ва форма текшируви.
library;

import 'sm_access.dart' show SmSlot;
import 'sm_qty.dart';
import 'sm_taxonomy.dart';

// ─── Байрамлар ───────────────────────────────────────────────────────────────

/// Туғилган кун — санаси қариндошдан олинади (байрам санаси йўқ).
const kHolidayKindBirthday = 'birthday';
const kHolidayKindHoliday = 'holiday';

/// Босқичлар (42-банд). `off` — ҳеч кимга кўринмайди.
const kHolidayStages = ['off', 'internal', 'pilot', 'public'];

/// Сервер `ID_RE` — байрам/сават id.
final kHolidayIdRe = RegExp(r'^[a-z][a-z0-9_]{1,39}$');

// ─── Байрам мақсади (сервер holiday-srv 6bde1531/2f51b761, эга 2026-11-27) ──────
//
// `target` турлари: `holiday_basket{occasionId, mode?: guests|gift}` · `restaurants_preorder` · `supermarket` ·
// `market{market, categories?}`. Йўқ/нотўғри — `null` (оддий: байрам саватчаси).

const kTargetHolidayBasket = 'holiday_basket';
const kTargetRestaurantsPreorder = 'restaurants_preorder';
const kTargetSupermarket = 'supermarket';
const kTargetMarket = 'market';
const kHolidayTargetTypes = [kTargetHolidayBasket, kTargetRestaurantsPreorder, kTargetSupermarket, kTargetMarket];

const kTargetModeGuests = 'guests';
const kTargetModeGift = 'gift';

class HolidayTarget {
  const HolidayTarget({required this.type, this.occasionId = '', this.mode = '', this.market = '', this.categories = const []});

  final String type;
  final String occasionId;

  /// `holiday_basket`: `guests` | `gift` | бўш.
  final String mode;
  final String market;
  final List<String> categories;

  bool get isMarket => type == kTargetMarket && market.isNotEmpty;
  bool get isBasket => type == kTargetHolidayBasket;

  /// Бозор экранида очилишда танланадиган бўлим (биринчиси; бозорда бўлмаса экран ўзи сукутга қайтади).
  String get initialCategory => categories.isEmpty ? '' : categories.first;

  static String _id(Object? v) => v is String && kHolidayIdRe.hasMatch(v.trim()) ? v.trim() : '';

  static List<String> _cats(Object? raw) => [
        if (raw is List)
          for (final c in raw)
            if (_id(c).isNotEmpty) _id(c),
        // Push маълумоти: вергул билан сатр.
        if (raw is String)
          for (final c in raw.split(','))
            if (_id(c).isNotEmpty) _id(c),
      ];

  /// Ҳужжат/каталог объекти ёки push сатрлари (`targetType`, `occasionId`, `mode`, `market`, `categories`). Нотўғри —
  /// `null`.
  static HolidayTarget? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String || !kHolidayTargetTypes.contains(type.trim())) return null;
    final t = type.trim();
    final mode = raw['mode'] is String ? (raw['mode'] as String).trim() : '';
    final out = HolidayTarget(
      type: t,
      occasionId: t == kTargetHolidayBasket ? _id(raw['occasionId']) : '',
      mode: t == kTargetHolidayBasket && (mode == kTargetModeGuests || mode == kTargetModeGift) ? mode : '',
      market: t == kTargetMarket ? _id(raw['market']) : '',
      categories: t == kTargetMarket ? _cats(raw['categories']) : const [],
    );
    if (t == kTargetMarket && out.market.isEmpty) return null;
    return out;
  }

  Map<String, Object> toMap() => {
        'type': type,
        if (type == kTargetHolidayBasket && occasionId.isNotEmpty) 'occasionId': occasionId,
        if (type == kTargetHolidayBasket && mode.isNotEmpty) 'mode': mode,
        if (type == kTargetMarket) 'market': market,
        if (type == kTargetMarket && categories.isNotEmpty) 'categories': categories,
      };

  @override
  bool operator ==(Object other) =>
      other is HolidayTarget &&
      other.type == type &&
      other.occasionId == occasionId &&
      other.mode == mode &&
      other.market == market &&
      other.categories.join(',') == categories.join(',');

  @override
  int get hashCode => Object.hash(type, occasionId, mode, market, categories.join(','));
}

// ─── Ўз туғилган куни эслатмалари (эга 2026-11-27) ───────────────────────────

/// Админ танлови (эга қарори: 3 мақсад) ↔ сервер `target` объекти.
const kSelfTargetBasket = 'birthday_basket';
const kSelfTargetPreorder = 'restaurants_preorder';
const kSelfTargetGuests = 'birthday_basket_guests';
const kSelfReminderTargets = [kSelfTargetBasket, kSelfTargetPreorder, kSelfTargetGuests];

HolidayTarget selfTargetObject(String key) => switch (key) {
      kSelfTargetPreorder => const HolidayTarget(type: kTargetRestaurantsPreorder),
      kSelfTargetGuests => const HolidayTarget(type: kTargetHolidayBasket, occasionId: kHolidayKindBirthday, mode: kTargetModeGuests),
      _ => const HolidayTarget(type: kTargetHolidayBasket, occasionId: kHolidayKindBirthday),
    };

/// Сервер объекти → админ танлови; бошқа шакл — бўш (админ қайта танлайди).
String selfTargetKey(HolidayTarget? t) {
  if (t == null) return '';
  if (t.type == kTargetRestaurantsPreorder) return kSelfTargetPreorder;
  if (t.isBasket) return t.mode == kTargetModeGuests ? kSelfTargetGuests : kSelfTargetBasket;
  return '';
}

/// Эга 2026-11-27: D-7, D-6, D-5, D-4, D-3 (сервер сукути — майдон йўқ бўлса). Админ 1..14 (эга; сервер 1..30
/// қабул қилади), кўпи билан 10 та (сервер).
const kSelfReminderDefaultDays = [7, 6, 5, 4, 3];
const int kSelfReminderDaysMin = 1;
const int kSelfReminderDaysMax = 14;
const int kSelfReminderMaxCount = 10;
const int kSelfReminderTitleMax = 80;
const int kSelfReminderBodyMax = 300;

class HolidaySelfReminder {
  const HolidaySelfReminder({required this.daysBefore, required this.texts, required this.target});

  final int daysBefore;

  /// Тил → (сарлавҳа ≤ 80, матн ≤ 300).
  final Map<String, ({String title, String body})> texts;

  /// Админ танлови ([kSelfReminderTargets]).
  final String target;

  static HolidaySelfReminder? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final d = raw['daysBefore'];
    if (d is! num) return null;
    final tx = raw['texts'];
    String s(Object? v) => v is String ? v.trim() : '';
    return HolidaySelfReminder(
      daysBefore: d.toInt(),
      texts: {
        if (tx is Map)
          for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
            if (tx[l] is Map) l: (title: s((tx[l] as Map)['title']), body: s((tx[l] as Map)['body'])),
      },
      target: selfTargetKey(HolidayTarget.fromMap(raw['target'])),
    );
  }

  Map<String, Object> toMap() => {
        'daysBefore': daysBefore,
        'texts': {
          for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
            l: {'title': (texts[l]?.title ?? '').trim(), 'body': (texts[l]?.body ?? '').trim()},
        },
        'target': selfTargetObject(target).toMap(),
      };
}

/// Админ формаси хатолари (Кирилл, админ конвенцияси). Бўш — тўғри.
List<String> holidaySelfReminderProblems(List<HolidaySelfReminder> list) {
  final seen = <int>{};
  return [
    if (list.length > kSelfReminderMaxCount) 'Эслатмалар $kSelfReminderMaxCount тагача.',
    for (final r in list) ...[
      if (r.daysBefore < kSelfReminderDaysMin || r.daysBefore > kSelfReminderDaysMax)
        'Кун: $kSelfReminderDaysMin–$kSelfReminderDaysMax оралиғида бўлсин (${r.daysBefore}).'
      else if (!seen.add(r.daysBefore))
        'Кун такрорланди: D-${r.daysBefore}.',
      if (!kSelfReminderTargets.contains(r.target)) 'Мақсадни танланг (D-${r.daysBefore}).',
      for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) ...[
        if ((r.texts[l]?.title ?? '').trim().isEmpty || (r.texts[l]?.title ?? '').trim().length > kSelfReminderTitleMax)
          'Сарлавҳа ($l, D-${r.daysBefore}) 1–$kSelfReminderTitleMax белги бўлсин.',
        if ((r.texts[l]?.body ?? '').trim().isEmpty || (r.texts[l]?.body ?? '').trim().length > kSelfReminderBodyMax)
          'Матн ($l, D-${r.daysBefore}) 1–$kSelfReminderBodyMax белги бўлсин.',
      ],
    ],
  ];
}

/// Қурбон ҳайит байрами id ва даври (эга 2026-11-27: байрамгача 15 кун ичида бозорда баннер ва чип).
const kQurbonOccasionId = 'qurbon_hayit';
const int kQurbonPeriodDays = 15;

/// Мол бозоридаги «Қурбонликка мос» белгиси — таксономия майдони (`attrs.qurbon_ready`, bool).
const kQurbonReadyAttr = 'qurbon_ready';

/// Шу бозор Қурбон ҳайит мақсади ва давр фаол (бозор id байрам `target`идан — hardcode эмас).
bool qurbonMarketActive(Iterable<HolidayOccasion> occasions, String marketId, DateTime today) {
  final q = occasions.where((o) => o.id == kQurbonOccasionId && (o.target?.isMarket ?? false) && o.target!.market == marketId);
  return q.isNotEmpty && qurbonPeriodActive(q, today);
}

/// Эълон «Қурбонликка мос» белгиланганми (таксономияда шу майдон бўлса).
bool qurbonReady(Map<String, Object?> attrs) => attrs[kQurbonReadyAttr] == true;

/// Қурбон даври: байрам санаси бугундан 0..[kQurbonPeriodDays] кун ичида.
bool qurbonPeriodActive(Iterable<HolidayOccasion> occasions, DateTime today) {
  for (final o in occasions) {
    if (o.id != kQurbonOccasionId) continue;
    final d = nextOccasionDate(o, today);
    if (d == null) return false;
    final diff = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return diff >= 0 && diff <= kQurbonPeriodDays;
  }
  return false;
}

class HolidayOccasion {
  const HolidayOccasion({
    required this.id,
    required this.names,
    this.kind = kHolidayKindHoliday,
    this.bigHoliday = false,
    this.ruleType = '',
    this.md = '',
    this.dates = const [],
    this.remindDaysBefore = 5,
    this.stage = '',
    this.order = 0,
    this.image = '',
    this.nextDate = '',
    this.target,
    this.selfReminders,
  });

  /// Байрам босилганда нима очилади (`null` — байрам саватчаси; Қурбон ҳайит — Мол бозори).
  final HolidayTarget? target;

  /// Фақат туғилган кун (`birthday`): фойдаланувчининг ЎЗ туғилган куни эслатмалари (админ). `null` — майдон йўқ
  /// (сервер сукути D-7..D-3); бўш рўйхат — ўчиқ.
  final List<HolidaySelfReminder>? selfReminders;

  final String id;
  final Map<String, String> names;
  final String kind;
  final bool bigHoliday;

  /// `dateRule.type`: `fixed` (ҳар йили [md]) | `list` (ой тақвими — Ҳайит [dates]) | `''` (туғилган кун).
  final String ruleType;
  final String md;
  final List<String> dates;
  final int remindDaysBefore;

  /// Фақат админ ҳужжатида; каталогда бўш (сервер аллақачон филтрлаган).
  final String stage;
  final int order;
  final String image;

  /// Каталогдан: энг яқин сана `YYYY-MM-DD` (байрам) ёки бўш.
  final String nextDate;

  bool get isBirthday => kind == kHolidayKindBirthday;

  /// Каталог ёзуви (босқичсиз) — кўринади; админ ҳужжати — `off` эмас.
  bool get isOn => stage.isEmpty || (stage != 'off' && kHolidayStages.contains(stage));

  String name(String lang) => localizedName(names, lang);

  static HolidayOccasion? fromMap(Object? raw, {String? id}) {
    if (raw is! Map) return null;
    final oid = id ?? (raw['id'] is String ? raw['id'] as String : '');
    if (oid.isEmpty) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    final rule = raw['dateRule'];
    final ruleType = rule is Map ? s(rule['type']) : '';
    final ds = rule is Map ? rule['dates'] : null;
    return HolidayOccasion(
      id: oid,
      names: smNames(raw['names']),
      kind: s(raw['kind']) == kHolidayKindBirthday ? kHolidayKindBirthday : kHolidayKindHoliday,
      bigHoliday: raw['bigHoliday'] == true,
      ruleType: ruleType == 'fixed' || ruleType == 'list' ? ruleType : '',
      md: rule is Map ? s(rule['md']) : '',
      dates: [
        if (ds is List)
          for (final x in ds)
            if (x is String) x.trim(),
      ],
      remindDaysBefore: raw['remindDaysBefore'] is num ? (raw['remindDaysBefore'] as num).toInt() : (raw['bigHoliday'] == true ? 10 : 5),
      stage: s(raw['stage']),
      order: raw['order'] is num ? (raw['order'] as num).toInt() : 0,
      image: s(raw['image']),
      nextDate: s(raw['nextDate']),
      target: HolidayTarget.fromMap(raw['target']),
      selfReminders: raw['selfReminders'] is List
          ? [...(raw['selfReminders'] as List).map(HolidaySelfReminder.fromMap).whereType<HolidaySelfReminder>()]
          : null,
    );
  }

  /// `adminUpsertHolidayOccasion.occasion` шакли.
  Map<String, Object?> toAdminMap() => {
        'id': id,
        'names': names,
        'kind': kind,
        'bigHoliday': bigHoliday,
        'dateRule': isBirthday
            ? null
            : ruleType == 'fixed'
                ? {'type': 'fixed', 'md': md}
                : {'type': 'list', 'dates': dates},
        'remindDaysBefore': remindDaysBefore,
        'stage': stage.isEmpty ? 'off' : stage,
        'order': order,
        'image': image,
        // Эга 2026-11-27: байрамда `target` (null — саватча, тозалаш учун ҳам юборилади); туғилган кунда эслатмалар
        // (йўқ — сервер сукути D-7..D-3; бўш рўйхат — ўчиқ).
        if (!isBirthday) 'target': target?.toMap(),
        if (isBirthday && selfReminders != null) 'selfReminders': [for (final r in selfReminders!) r.toMap()],
      };
}

final _fullDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _annualDate = RegExp(r'^\d{2}-\d{2}$');

/// `YYYY-MM-DD` — мавжуд календар санаси.
bool holidayFullDateValid(String s) {
  if (!_fullDate.hasMatch(s)) return false;
  final p = s.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

/// `MM-DD` (ҳар йили); сервер каби 02-29 рад этилади.
bool holidayMdValid(String s) {
  if (!_annualDate.hasMatch(s) || s == '02-29') return false;
  final p = s.split('-').map(int.parse).toList();
  final d = DateTime(2027, p[0], p[1]);
  return d.month == p[0] && d.day == p[1];
}

DateTime? _parseIso(String s) {
  if (!holidayFullDateValid(s)) return null;
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Энг яқин сана: аввал сервер `nextDate`, бўлмаса қоидадан (админ кўриниши); туғилган кун / ўтган — `null`.
DateTime? nextOccasionDate(HolidayOccasion o, DateTime today) {
  final server = _parseIso(o.nextDate);
  if (server != null) return server;
  final t = DateTime(today.year, today.month, today.day);
  if (o.ruleType == 'fixed' && holidayMdValid(o.md)) {
    final p = o.md.split('-').map(int.parse).toList();
    final d = DateTime(t.year, p[0], p[1]);
    return d.isBefore(t) ? DateTime(t.year + 1, p[0], p[1]) : d;
  }
  if (o.ruleType == 'list') {
    DateTime? best;
    for (final s in o.dates) {
      final d = _parseIso(s);
      if (d == null || d.isBefore(t)) continue;
      if (best == null || d.isBefore(best)) best = d;
    }
    return best;
  }
  return null;
}

/// Тартиб: `order`, кейин id (сервер билан бир хил).
List<HolidayOccasion> holidaySortOccasions(Iterable<HolidayOccasion> all) {
  final out = [for (final o in all) if (o.isOn) o];
  out.sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.id.compareTo(b.id));
  return out;
}

// ─── Тайёр саватчалар ────────────────────────────────────────────────────────

const kHolidayTiers = ['simple', 'medium', 'large'];

class HolidayBasketItem {
  const HolidayBasketItem({
    required this.groupId,
    required this.qtyMilli,
    this.varietyId = '',
    this.offerId = '',
    this.qtyPerGuestMilli = 0,
    this.priority = 0,
  });

  final String groupId;
  final String varietyId;
  final String offerId;
  final int qtyMilli;

  /// 0 — меҳмонга мутаносиб (qty × guests / baseGuests).
  final int qtyPerGuestMilli;

  /// 1..9 (бюджетда катта рақам аввал олиб ташланади); 0 — берилмаган (сервер 5 деб олади).
  final int priority;

  static HolidayBasketItem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final g = raw['groupId'];
    final q = raw['qty'];
    if (g is! String || g.trim().isEmpty || q is! num || q <= 0) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    final per = raw['qtyPerGuest'];
    return HolidayBasketItem(
      groupId: g.trim(),
      qtyMilli: smToMilli(q),
      varietyId: s(raw['varietyId']),
      offerId: s(raw['offerId']),
      qtyPerGuestMilli: per is num && per > 0 ? smToMilli(per) : 0,
      priority: raw['priority'] is num ? (raw['priority'] as num).toInt() : 0,
    );
  }

  Map<String, Object> toMap() => {
        'groupId': groupId,
        if (varietyId.isNotEmpty) 'varietyId': varietyId,
        if (offerId.isNotEmpty) 'offerId': offerId,
        if (qtyPerGuestMilli > 0) 'qtyPerGuest': smFromMilli(qtyPerGuestMilli),
        'qty': smFromMilli(qtyMilli),
        if (priority >= 1 && priority <= 9) 'priority': priority,
      };
}

class HolidayBasket {
  const HolidayBasket({
    required this.id,
    required this.occasionId,
    required this.tier,
    this.names = const {},
    this.items = const [],
    this.itemsCount = 0,
    this.baseGuests = 1,
    this.active = true,
  });

  final String id;
  final String occasionId;
  final String tier;
  final Map<String, String> names;

  /// Админ ҳужжатида тўлиқ; каталогда бўш (фақат [itemsCount]).
  final List<HolidayBasketItem> items;
  final int itemsCount;
  final int baseGuests;
  final bool active;

  String name(String lang) => localizedName(names, lang);

  static HolidayBasket? fromMap(Object? raw, {String? id}) {
    if (raw is! Map) return null;
    final bid = id ?? (raw['id'] is String ? raw['id'] as String : '');
    if (bid.isEmpty) return null;
    final it = raw['items'];
    final tier = raw['tier'] is String ? (raw['tier'] as String).trim() : '';
    final items = <HolidayBasketItem>[
      if (it is List) ...it.map(HolidayBasketItem.fromMap).whereType<HolidayBasketItem>(),
    ];
    return HolidayBasket(
      id: bid,
      occasionId: raw['occasionId'] is String ? (raw['occasionId'] as String).trim() : '',
      tier: kHolidayTiers.contains(tier) ? tier : 'simple',
      names: smNames(raw['names']),
      items: items,
      itemsCount: it is num ? it.toInt() : items.length,
      baseGuests: raw['baseGuests'] is num ? (raw['baseGuests'] as num).toInt() : 1,
      active: raw['active'] != false,
    );
  }

  /// `adminUpsertHolidayBasket.basket` шакли.
  Map<String, Object> toAdminMap() => {
        'id': id,
        'occasionId': occasionId,
        'tier': tier,
        'names': names,
        'items': [for (final i in items) i.toMap()],
        'baseGuests': baseGuests,
        'active': active,
      };
}

/// Шу байрам саватлари, даража тартибида (simple → medium → large).
List<HolidayBasket> holidayBasketsFor(Iterable<HolidayBasket> all, String occasionId) {
  final out = [for (final b in all) if (b.occasionId == occasionId && b.active) b];
  out.sort((a, b) => kHolidayTiers.indexOf(a.tier).compareTo(kHolidayTiers.indexOf(b.tier)));
  return out;
}

class HolidayCatalog {
  const HolidayCatalog({this.occasions = const [], this.baskets = const [], this.today = ''});

  static const empty = HolidayCatalog();

  final List<HolidayOccasion> occasions;
  final List<HolidayBasket> baskets;

  /// Сервер санаси (Тошкент) `YYYY-MM-DD`.
  final String today;

  bool get isEmpty => occasions.isEmpty;

  factory HolidayCatalog.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final o = m['occasions'];
    final b = m['baskets'];
    return HolidayCatalog(
      occasions: holidaySortOccasions([
        if (o is List) ...o.map((x) => HolidayOccasion.fromMap(x)).whereType<HolidayOccasion>(),
      ]),
      baskets: [
        if (b is List) ...b.map((x) => HolidayBasket.fromMap(x)).whereType<HolidayBasket>(),
      ],
      today: m['today'] is String ? m['today'] as String : '',
    );
  }
}

// ─── Меҳмон / бюджет ─────────────────────────────────────────────────────────

const int kHolidayGuestsMin = 1;
const int kHolidayGuestsMax = 500;
const int kHolidayBudgetMax = 100000000;

/// Меҳмонлар сони майдони: бўш → `null` (ихтиёрий); нотўғри → хато калити.
({int? value, String? error}) holidayParseGuests(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return (value: null, error: null);
  final v = int.tryParse(s);
  if (v == null || v < kHolidayGuestsMin || v > kHolidayGuestsMax) return (value: null, error: 'hb_err_guests');
  return (value: v, error: null);
}

/// Бюджет (бутун сўм): бўш → `null`; бўшлиқлар олиб ташланади.
({int? value, String? error}) holidayParseBudget(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s  ]'), '');
  if (s.isEmpty) return (value: null, error: null);
  final v = int.tryParse(s);
  if (v == null || v <= 0 || v > kHolidayBudgetMax) return (value: null, error: 'hb_err_budget');
  return (value: v, error: null);
}

// ─── buildHolidayBasket натижаси ─────────────────────────────────────────────

class HolidayLine {
  const HolidayLine({
    required this.productId,
    required this.groupId,
    required this.qtyMilli,
    required this.price,
    required this.total,
    this.name = '',
    this.unit = '',
    this.weighed = false,
    this.imageUrl = '',
  });

  final String productId;
  final String groupId;
  final String name;
  final int qtyMilli;
  final int price;
  final int total;
  final String unit;
  final bool weighed;
  final String imageUrl;

  static HolidayLine? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final p = raw['productId'];
    final q = raw['qty'];
    if (p is! String || p.isEmpty || q is! num || q <= 0) return null;
    int i(Object? v) => v is num ? v.toInt() : 0;
    String s(Object? v) => v is String ? v : '';
    return HolidayLine(
      productId: p,
      groupId: s(raw['groupId']),
      name: s(raw['name']),
      qtyMilli: smToMilli(q),
      price: i(raw['price']),
      total: i(raw['total']),
      unit: s(raw['unit']),
      weighed: raw['weighed'] == true,
      imageUrl: s(raw['imageUrl']),
    );
  }
}

/// `swap` — бошқа таклифга алмашди; `drop` — бюджетга сиғмади; `unavailable` — гуруҳда сотувда ҳеч нарса йўқ.
const kHolidayChangeTypes = ['swap', 'drop', 'unavailable'];

class HolidayChange {
  const HolidayChange({
    required this.type,
    required this.groupId,
    this.reason = '',
    this.fromOfferId = '',
    this.toOfferId = '',
    this.offerId = '',
    this.saving = 0,
  });

  final String type;
  final String groupId;

  /// `budget` | `unavailable` | бўш.
  final String reason;
  final String fromOfferId;
  final String toOfferId;
  final String offerId;

  /// Тежам (сўм); бўлмаса 0.
  final int saving;

  static HolidayChange? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['type'];
    if (t is! String || !kHolidayChangeTypes.contains(t)) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    return HolidayChange(
      type: t,
      groupId: s(raw['groupId']),
      reason: s(raw['reason']),
      fromOfferId: s(raw['fromOfferId']),
      toOfferId: s(raw['toOfferId']),
      offerId: s(raw['offerId']),
      saving: raw['saving'] is num ? (raw['saving'] as num).toInt() : 0,
    );
  }
}

class HolidayBuildResult {
  const HolidayBuildResult({
    this.lines = const [],
    this.changes = const [],
    this.goods = 0,
    this.fee = 0,
    this.total = 0,
    this.guests = 0,
    this.budget,
    this.withinBudget,
  });

  final List<HolidayLine> lines;
  final List<HolidayChange> changes;
  final int goods;
  final int fee;
  final int total;
  final int guests;
  final int? budget;
  final bool? withinBudget;

  /// Тизим бирор нарсани ўзгартирган бўлса — саватга қўшишдан олдин мижоз розилиги шарт.
  bool get needsApproval => changes.isNotEmpty;

  factory HolidayBuildResult.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final l = m['lines'];
    final c = m['changes'];
    int i(Object? v) => v is num ? v.toInt() : 0;
    return HolidayBuildResult(
      lines: [if (l is List) ...l.map(HolidayLine.fromMap).whereType<HolidayLine>()],
      changes: [if (c is List) ...c.map(HolidayChange.fromMap).whereType<HolidayChange>()],
      goods: i(m['goods']),
      fee: i(m['fee']),
      total: i(m['total']),
      guests: i(m['guests']),
      budget: m['budget'] is num ? (m['budget'] as num).toInt() : null,
      withinBudget: m['withinBudget'] is bool ? m['withinBudget'] as bool : null,
    );
  }
}

/// Ўзгариш қатори учун lang калити (`{group}`, `{from}`, `{to}`, `{saving}`).
String holidayChangeKey(HolidayChange c) => switch (c.type) {
      'swap' when c.fromOfferId.isEmpty => 'hb_change_swap_unavailable',
      'swap' => 'hb_change_swap',
      'drop' => 'hb_change_drop',
      _ => 'hb_change_unavailable',
    };

// ─── Совға ───────────────────────────────────────────────────────────────────

const int kSmGiftNameMax = 60;
const int kSmGiftMessageMax = 200;

class SmGift {
  const SmGift({required this.recipientName, required this.recipientPhone, this.message = ''});

  final String recipientName;
  final String recipientPhone;
  final String message;

  /// Шартнома: нарх доим яширин (`hidePrice: true`); телефон — каноник `998…`.
  Map<String, Object> toMap() => {
        'recipientName': recipientName.trim(),
        'recipientPhone': smGiftPhone(recipientPhone),
        'message': message.trim(),
        'hidePrice': true,
      };
}

/// `998XXXXXXXXX` ёки `''` (нотўғри) — сервер `parseGift` қоидаси.
String smGiftPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (d.length == 9) return '998$d';
  if (d.length == 12 && d.startsWith('998')) return d;
  return '';
}

/// Совға формаси хатолари (lang калитлари). Бўш — тўғри.
List<String> smGiftProblems(SmGift g) => [
      if (g.recipientName.trim().isEmpty || g.recipientName.trim().length > kSmGiftNameMax) 'sm_gift_err_name',
      if (smGiftPhone(g.recipientPhone).isEmpty) 'sm_gift_err_phone',
      if (g.message.trim().length > kSmGiftMessageMax) 'sm_gift_err_message',
    ];

/// Расмийлаштиришга байрам оқимидан келганда: байрам/сават id, совға олдиндан тўлдирилиши (қариндош).
class SmHolidayCheckout {
  const SmHolidayCheckout({
    this.occasionId = '',
    this.basketId = '',
    this.asGift = false,
    this.recipientName = '',
    this.recipientPhone = '',
  });

  final String occasionId;
  final String basketId;
  final bool asGift;
  final String recipientName;
  final String recipientPhone;

  SmHolidayCheckout copyWith({String? occasionId, String? basketId}) => SmHolidayCheckout(
        occasionId: occasionId ?? this.occasionId,
        basketId: basketId ?? this.basketId,
        asGift: asGift,
        recipientName: recipientName,
        recipientPhone: recipientPhone,
      );
}

// ─── Етказиш санаси ──────────────────────────────────────────────────────────

/// Сервер `MAX_AHEAD_DAYS` (захира; жавобда `maxAheadDays` бўлса — ўша).
const int kSmDeliveryMaxDays = 14;

/// Тошкент санаси (UTC+5, ёзги вақт йўқ) — қурилма вақт зонасига боғлиқ эмас.
DateTime smTashkentDate([DateTime? nowUtc]) {
  final t = (nowUtc ?? DateTime.now().toUtc()).toUtc().add(const Duration(hours: 5));
  return DateTime(t.year, t.month, t.day);
}

String smIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int _dayDiff(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Сана бугундан 0..[maxDays] кун оралиғидами.
bool smDeliveryDateOk(DateTime date, DateTime today, {int maxDays = kSmDeliveryMaxDays}) {
  final diff = _dayDiff(today, date);
  return diff >= 0 && diff <= maxDays;
}

/// Танлаш мумкин саналар: сервер оралиқ берган кунлар (`dateSlots`), бугундан 0..maxDays ичида, тартибли.
List<DateTime> smSelectableDates(Map<String, List<SmSlot>> dateSlots, DateTime today, {int maxDays = kSmDeliveryMaxDays}) {
  final out = <DateTime>[];
  for (final e in dateSlots.entries) {
    final d = _parseIso(e.key);
    if (d == null || e.value.isEmpty || !smDeliveryDateOk(d, today, maxDays: maxDays)) continue;
    out.add(d);
  }
  out.sort();
  return out;
}

// ─── Бош саҳифа карточкалари ─────────────────────────────────────────────────

/// «Байрам саватчаси» карточкаси: супермаркет очиқ ва рухсат бор + сервер камида битта байрам қайтарган.
bool holidayCardVisible({required bool smOpenable, required bool smAllowed, required Iterable<HolidayOccasion> occasions}) =>
    smOpenable && smAllowed && occasions.any((o) => o.isOn);

/// Туғилган куни киритилган қариндошлар шунча бўлса — «Яқинларингиз…» карточкаси яширилади (эга 2026-11-26).
const int kRelativesBirthdayGoal = 3;

bool relativesPromptVisible({required bool holidayAvailable, required int birthdaysCount}) =>
    holidayAvailable && birthdaysCount < kRelativesBirthdayGoal;

/// Бонус дастури фаол бўлса — `(n, goal, left)`; акс ҳолда `null` (прогресс кўрсатилмайди).
({int n, int goal, int left})? relativesBonusProgress({required bool bonusActive, required int birthdaysCount, int goal = kRelativesBirthdayGoal}) {
  if (!bonusActive || goal <= 0) return null;
  final n = birthdaysCount.clamp(0, goal);
  return (n: n, goal: goal, left: goal - n);
}

/// `claimRelativesBonus()` → `{ok, result granted|duplicate|skip, code?, count?}`. Дастур фаол ва шу фойдаланувчи
/// босқичида, лекин қариндош етмайди — `NOT_ENOUGH_RELATIVES` (прогресс кўрсатилади); `PROGRAM_OFF` / `NOT_IN_STAGE`
/// / бошқа — кўрсатилмайди.
({bool active, int? count}) relativesBonusFromClaim(Object? raw) {
  final m = raw is Map ? raw : const {};
  final active = m['result'] == 'skip' && m['code'] == 'NOT_ENOUGH_RELATIVES';
  return (active: active, count: m['count'] is num ? (m['count'] as num).toInt() : null);
}

// ─── Push / Хабарлар ─────────────────────────────────────────────────────────

/// Сервер `dataType` (push `type`) / хабар `source`.
const kHolidayReminderPush = 'holiday_reminder';
const kRelativeBirthdayPush = 'holiday_birthday_reminder';
const kHolidayBonusPush = 'holiday_relatives_bonus';
const kGiftReceivedPush = 'sm_gift_received';

/// Ўз туғилган куни эслатмаси (сервер holiday-srv 2f51b761, эга 2026-11-27).
const kSelfBirthdayPush = 'holiday_self_birthday';

final _docId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// [self] — фойдаланувчининг ЎЗ туғилган куни (совғасиз).
enum HolidayPushKind { occasion, self, birthday, bonus }

/// [target] — сервер `targetType` (+ `occasionId`, `mode`, `market`, `categories`) ёки `null`.
typedef HolidayPushTarget = ({HolidayPushKind kind, String occasionId, String personId, HolidayTarget? target});

/// Байрам push'и → мақсад; бошқа push — `null`. ID фақат Firestore шаклида (бошқаси — бўш); мақсад фақат маълум
/// турлардан ([HolidayTarget.fromMap]).
HolidayPushTarget? holidayPushTarget(Map<String, String> data, {Object? targetObject}) {
  final type = (data['type'] ?? '').trim();
  String id(String k) {
    final v = (data[k] ?? '').trim();
    return _docId.hasMatch(v) ? v : '';
  }

  // Push'да `type` — push тури; мақсад тури `targetType` сатрида.
  HolidayTarget? target() =>
      HolidayTarget.fromMap(targetObject) ?? HolidayTarget.fromMap({...data, 'type': data['targetType'] ?? ''});

  if (type == kHolidayReminderPush) {
    return (kind: HolidayPushKind.occasion, occasionId: id('occasionId'), personId: '', target: target());
  }
  if (type == kSelfBirthdayPush) {
    return (kind: HolidayPushKind.self, occasionId: id('occasionId'), personId: '', target: target());
  }
  if (type == kRelativeBirthdayPush) {
    return (kind: HolidayPushKind.birthday, occasionId: id('occasionId'), personId: id('personId'), target: null);
  }
  if (type == kHolidayBonusPush) return (kind: HolidayPushKind.bonus, occasionId: '', personId: '', target: null);
  return null;
}

/// Push/хабар мақсади қаерга олиб боради (тоза — тест учун).
enum HolidayRoute { bonus, occasionList, basket, basketGuests, basketGift, restaurantsPreorder, supermarket, market, relativeBirthday }

HolidayRoute holidayRouteOf(HolidayPushTarget t) {
  if (t.kind == HolidayPushKind.bonus) return HolidayRoute.bonus;
  if (t.kind == HolidayPushKind.birthday) return HolidayRoute.relativeBirthday;
  final tg = t.target;
  if (tg == null) return t.kind == HolidayPushKind.self ? HolidayRoute.basket : HolidayRoute.occasionList;
  return switch (tg.type) {
    kTargetRestaurantsPreorder => HolidayRoute.restaurantsPreorder,
    kTargetSupermarket => HolidayRoute.supermarket,
    kTargetMarket => HolidayRoute.market,
    _ => tg.mode == kTargetModeGuests
        ? HolidayRoute.basketGuests
        : tg.mode == kTargetModeGift
            ? HolidayRoute.basketGift
            : HolidayRoute.basket,
  };
}

/// Саватча очиладиган байрам: мақсаддаги → push'даги → ўз туғилган кунида `birthday`.
String holidayRouteOccasion(HolidayPushTarget t) {
  final fromTarget = t.target?.occasionId ?? '';
  if (fromTarget.isNotEmpty) return fromTarget;
  if (t.occasionId.isNotEmpty) return t.occasionId;
  return t.kind == HolidayPushKind.self ? kHolidayKindBirthday : '';
}
