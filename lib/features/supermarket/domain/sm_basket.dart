/// «Менинг ҳафталик харид саватчам» (эга 2026-11-28) — ЯГОНА саватча: аввалги 3 тайёр байрам саватчаси ва
/// супермаркет «Ҳафталик сават» ўрнида. Маълумот — мавжуд `users/{uid}/sm_lists` (янги коллекция ЙЎҚ, 4-банд):
/// саватча — битта рўйхат; қолганлари «Бошқа рўйхатларим»да қолади.
///
/// Бу файл тоза (Flutter/Firebase'сиз): саватчани танлаш (миграция), сарлавҳа (туғилган кун 15 кун), гуруҳлар
/// тўри, гуруҳ таклифлари, миқдор, йиғинди. Нарх — фақат кўрсатиш; якуний сумма доим сервер (18-банд).
library;

import 'sm_cart.dart';
import 'sm_list.dart';
import 'sm_offer.dart';
import 'sm_qty.dart';
import 'sm_taxonomy.dart';

/// Янги саватча ҳужжати id'си (`users/{uid}/sm_lists/weekly_basket`) — rules: `^[A-Za-z0-9_-]{1,40}$`.
const kSmBasketListId = 'weekly_basket';

/// Туғилган кунгача шунча кун (ва ўша куни) — сарлавҳа «Туғилган кун саватчаси» (эга 2026-11-28).
const int kSmBirthdayTitleDays = 15;

/// «Байрам ва ширинликлар» (сервер taxonomy v3) категориясида Уй-рўзғордаги «Салфетка» ҳам кўрсатилади (эга
/// 2026-11-28: салфетка Уй-рўзғорда қолади, лекин саватчада байрам бўлимида ҳам кўринади).
const kSmBasketHolidayCategory = 'holiday_sweets';
const kSmBasketExtraGroups = <String, List<String>>{
  kSmBasketHolidayCategory: ['napkins'],
};

// ─── Миграция: қайси рўйхат саватча ──────────────────────────────────────────

/// Саватчани танлаш (эга 2026-11-28 «аввалги рўйхат саватчага айланади»):
/// 1) `weekly_basket` ҳужжати; 2) шу қурилмада эслаб қолинган id; 3) энг охирги янгиланган ОДДИЙ (байрамсиз)
/// рўйхат; 4) энг охирги ҳар қандай рўйхат. Қолганлари — [others] (ўчирилмайди, кўчирилмайди).
({SmList? basket, List<SmList> others}) smPickBasket(List<SmList> lists, {String remembered = ''}) {
  if (lists.isEmpty) return (basket: null, others: const []);
  final sorted = [...lists]..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
  SmList? pick;
  for (final l in sorted) {
    if (l.id == kSmBasketListId) pick = l;
  }
  if (pick == null && remembered.isNotEmpty) {
    for (final l in sorted) {
      if (l.id == remembered) pick = l;
    }
  }
  pick ??= sorted.where((l) => l.occasionId.isEmpty).firstOrNull ?? sorted.first;
  final chosen = pick;
  return (basket: chosen, others: List.unmodifiable(sorted.where((l) => l.id != chosen.id)));
}

// ─── Сарлавҳа ────────────────────────────────────────────────────────────────

/// Туғилган кунгача кун (бугун — 0). 29 феврал кабиса бўлмаган йилда — 28 феврал. Сана йўқ — `null`.
int? smDaysToBirthday(DateTime today, DateTime? birth) {
  if (birth == null) return null;
  final t = DateTime.utc(today.year, today.month, today.day);
  DateTime on(int y) {
    final leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    final day = birth.month == 2 && birth.day == 29 && !leap ? 28 : birth.day;
    return DateTime.utc(y, birth.month, day);
  }

  var next = on(t.year);
  if (next.isBefore(t)) next = on(t.year + 1);
  return next.difference(t).inDays;
}

/// Ўзининг ёки турмуш ўртоғининг туғилган кунига 0..[kSmBirthdayTitleDays] кун қолганми.
bool smBasketBirthdayMode({required DateTime today, DateTime? own, DateTime? spouse, int window = kSmBirthdayTitleDays}) {
  bool near(DateTime? d) {
    final n = smDaysToBirthday(today, d);
    return n != null && n <= window;
  }

  return near(own) || near(spouse);
}

/// Сарлавҳа калити (3 тил — lang файлларида).
String smBasketTitleKey({required bool birthday}) => birthday ? 'smb_title_birthday' : 'smb_title';

/// Эга расмлари (2026-11-28): туғилган кун ҳолати / оддий ҳолат — бош саҳифа карточкаси ва саватча сарлавҳаси.
const kSmBasketImageBirthday = 'assets/images/home/card_birthday_basket_v1.webp';
const kSmBasketImageWeekly = 'assets/images/home/card_weekly_basket_v1.webp';

String smBasketImage({required bool birthday}) => birthday ? kSmBasketImageBirthday : kSmBasketImageWeekly;

// ─── Гуруҳлар тўри ───────────────────────────────────────────────────────────

/// Категория чиплари: камида битта кўринадиган гуруҳи бор категориялар (тартиб — таксономия).
List<SmCategory> smBasketCategories(SmTaxonomy tx, Map<String, List<SmOffer>> offersByGroup) => [
      for (final c in tx.categories)
        if (smBasketGroups(tx, offersByGroup, categoryId: c.id).isNotEmpty) c,
    ];

/// Тўрдаги гуруҳлар: [categoryId] бўш — ҳаммаси (такрорсиз); акс ҳолда шу категория + [kSmBasketExtraGroups].
/// Фақат сотувда таклифи бор гуруҳлар.
List<SmGroup> smBasketGroups(SmTaxonomy tx, Map<String, List<SmOffer>> offersByGroup, {String categoryId = ''}) {
  bool has(SmGroup g) => (offersByGroup[g.id] ?? const <SmOffer>[]).any((o) => o.available);
  final out = <SmGroup>[];
  final seen = <String>{};
  void add(SmGroup? g) {
    if (g != null && has(g) && seen.add(g.id)) out.add(g);
  }

  for (final c in tx.categories) {
    if (categoryId.isNotEmpty && c.id != categoryId) continue;
    for (final g in c.groups) {
      add(g);
    }
    if (categoryId.isNotEmpty) {
      for (final id in kSmBasketExtraGroups[c.id] ?? const <String>[]) {
        add(tx.group(id));
      }
    }
  }
  return out;
}

/// Гуруҳ плиткаси расми: энг арзон мавжуд, расми бор таклифдан; йўқ — бўш.
String smBasketGroupImage(List<SmOffer>? offers) {
  for (final o in smBasketGroupOffers(offers)) {
    if (o.imageUrl.isNotEmpty) return o.imageUrl;
  }
  return '';
}

/// Гуруҳ экрани: шу гуруҳнинг сотувдаги БАРЧА таклифлари, энг арзони олдин (тенг нарх — id).
List<SmOffer> smBasketGroupOffers(List<SmOffer>? offers) =>
    smSortOffersAsc((offers ?? const <SmOffer>[]).where((o) => o.available));

/// Плиткадаги нишон: саватчадаги шу гуруҳ миқдори. Бирлик бир хил — йиғинди + бирлик; турли бирлик — қаторлар
/// сони ([lines], [unit] бўш). Гуруҳ саватчада йўқ — `null`.
({int qtyMilli, String unit, int lines})? smBasketGroupBadge(SmList basket, SmGroup group, Map<String, SmOffer> offers) {
  var qty = 0;
  var lines = 0;
  final units = <String>{};
  for (final i in basket.items) {
    if (i.groupId != group.id) continue;
    lines++;
    qty += i.qtyMilli;
    units.add(offers[i.offerId]?.unit.isNotEmpty == true ? offers[i.offerId]!.unit : group.unit);
  }
  if (lines == 0) return null;
  return units.length == 1 ? (qtyMilli: qty, unit: units.first, lines: lines) : (qtyMilli: 0, unit: '', lines: lines);
}

// ─── Миқдор ──────────────────────────────────────────────────────────────────

int smBasketQtyOf(SmList basket, String offerId) {
  for (final i in basket.items) {
    if (i.offerId == offerId) return i.qtyMilli;
  }
  return 0;
}

/// Таклиф миқдорини қўйиш (0 — олиб ташланади). Шу гуруҳдаги «ихтиёрий таклиф» қатори (эски намунадан, offerId
/// бўш) аниқ таклиф танланганда олиб ташланади — икки марта ҳисобланмасин. Чегара [kSmListItemsMax].
SmList smBasketSetOffer(SmList basket, SmOffer offer, int qtyMilli) {
  final items = [...basket.items];
  final idx = items.indexWhere((i) => i.offerId == offer.id);
  if (qtyMilli <= 0) {
    if (idx >= 0) items.removeAt(idx);
    return basket.copyWith(items: items);
  }
  final q = smIsValidQty(qtyMilli, offer.stepMilli) ? qtyMilli : smSnapQty(qtyMilli, offer.stepMilli);
  if (idx >= 0) {
    items[idx] = items[idx].copyWith(qtyMilli: q);
    return basket.copyWith(items: items);
  }
  items.removeWhere((i) => i.groupId == offer.groupId && i.offerId.isEmpty);
  if (items.length >= kSmListItemsMax) return basket;
  items.add(SmListItem(groupId: offer.groupId, varietyId: offer.varietyId, offerId: offer.id, qtyMilli: q));
  return basket.copyWith(items: items);
}

// ─── Йиғинди ва расмийлаштириш ───────────────────────────────────────────────

/// Пастки панел: [count] — саватчадаги қаторлар; [total] — ЖОРИЙ нархларда (сотувда йўқлари ҳисобланмайди);
/// [unavailable] — сотувда йўқ қаторлар сони.
typedef SmBasketTotals = ({int count, int total, int unavailable});

SmBasketTotals smBasketTotals(SmList basket, Map<String, SmOffer> offers, Map<String, List<SmOffer>> offersByGroup) {
  final lines = smCompareItems(basket.items, offers: offers, offersByGroup: offersByGroup);
  var total = 0;
  var bad = 0;
  for (final l in lines) {
    if (l.addable) {
      total += smLineTotal(l.offer!.price, l.qtyMilli);
    } else {
      bad++;
    }
  }
  return (count: basket.items.length, total: total, unavailable: bad);
}

/// Расмийлаштиришдан олдин мижоз тасдиғи керакми (нарх ўзгарди / бошқа қадоқ / йўқ / қолдиқ етмади).
bool smBasketNeedsConfirm(List<SmCompareLine> lines) =>
    lines.any((l) => l.status != SmCompareStatus.ok || l.qtyLimited);

/// Саватчадан сават қаторлари (жорий таклифлар; бир хил таклиф — бирлашади).
List<SmCartLine> smBasketCartLines(List<SmCompareLine> lines, {Set<int>? selected}) =>
    smCompareToCartLines(lines, selected: selected);
