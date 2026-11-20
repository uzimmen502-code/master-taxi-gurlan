/// «Ҳафталик сават» (2-босқич, эга 2026-11-21) — `users/{uid}/sm_lists/{listId}` (шартнома):
/// `{name ≤40, items:[{groupId, varietyId?, offerId?, qty}] ≤100, remind{enabled, weekday 1..7, minute},
///   createdAt, updatedAt(serverTimestamp)}`. Клиент ўзи ёзади (rules: фақат эгаси). Рўйхатлар сони
/// ≤ [kSmMaxLists] (клиент чеклайди). Сервер ҳафталик эслатма юборади — АВТОМАТИК БУЮРТМА ЙЎҚ.
///
/// Бу файл тоза (Flutter/Firebase'сиз): модел, текширув, намунавий рўйхат, жорий нархлар билан
/// солиштириш. Солиштириш натижаси ФАҚАТ саватга қўшилади — буюртма бермайди, пул ечмайди.
library;

import 'sm_cart.dart';
import 'sm_offer.dart';
import 'sm_qty.dart';
import 'sm_taxonomy.dart';

const int kSmMaxLists = 10;
const int kSmListNameMax = 40;
const int kSmListItemsMax = 100;

class SmListItem {
  const SmListItem({required this.groupId, required this.qtyMilli, this.varietyId = '', this.offerId = ''});

  final String groupId;
  final String varietyId;
  final String offerId;
  final int qtyMilli;

  SmListItem copyWith({int? qtyMilli, String? offerId, String? varietyId}) => SmListItem(
        groupId: groupId,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        varietyId: varietyId ?? this.varietyId,
        offerId: offerId ?? this.offerId,
      );

  /// Шартнома: бўш ихтиёрий майдон ёзилмайди; миқдор — оддий сон (1.5).
  Map<String, Object> toMap() => {
        'groupId': groupId,
        if (varietyId.isNotEmpty) 'varietyId': varietyId,
        if (offerId.isNotEmpty) 'offerId': offerId,
        'qty': smFromMilli(qtyMilli),
      };

  static SmListItem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final g = raw['groupId'];
    final q = raw['qty'];
    if (g is! String || g.trim().isEmpty || q is! num || q <= 0) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    return SmListItem(groupId: g.trim(), qtyMilli: smToMilli(q), varietyId: s(raw['varietyId']), offerId: s(raw['offerId']));
  }

  /// Рўйхатда бир хил маҳсулотми (таклиф бўлса — таклиф, бўлмаса — гуруҳ + нав).
  bool sameAs(SmListItem o) =>
      offerId.isNotEmpty || o.offerId.isNotEmpty ? offerId == o.offerId : groupId == o.groupId && varietyId == o.varietyId;
}

/// Ҳафталик эслатма: ҳафта куни 1 (душанба) .. 7 (якшанба), кун дақиқаси 0..1439 (Тошкент вақти).
class SmRemind {
  const SmRemind({this.enabled = false, this.weekday = 6, this.minute = 10 * 60});

  final bool enabled;
  final int weekday;
  final int minute;

  bool get isValid => weekday >= 1 && weekday <= 7 && minute >= 0 && minute < 24 * 60;

  Map<String, Object> toMap() => {'enabled': enabled, 'weekday': weekday, 'minute': minute};

  static SmRemind fromMap(Object? raw) {
    if (raw is! Map) return const SmRemind();
    final r = SmRemind(
      enabled: raw['enabled'] == true,
      weekday: raw['weekday'] is num ? (raw['weekday'] as num).toInt() : 6,
      minute: raw['minute'] is num ? (raw['minute'] as num).toInt() : 600,
    );
    // Бузилган қиймат — ўчиқ эслатма (сервер ҳам рад этади).
    return r.isValid ? r : const SmRemind();
  }
}

/// Эслатма формаси хатолари (lang калитлари). Бўш — тўғри.
List<String> smRemindProblems(SmRemind r) => [
      if (r.weekday < 1 || r.weekday > 7) 'sm_err_remind_weekday',
      if (r.minute < 0 || r.minute >= 24 * 60) 'sm_err_remind_time',
    ];

class SmList {
  const SmList({required this.id, required this.name, this.items = const [], this.remind = const SmRemind(), this.updatedAt});

  final String id;
  final String name;
  final List<SmListItem> items;
  final SmRemind remind;
  final DateTime? updatedAt;

  SmList copyWith({String? name, List<SmListItem>? items, SmRemind? remind}) => SmList(
        id: id,
        name: name ?? this.name,
        items: List.unmodifiable(items ?? this.items),
        remind: remind ?? this.remind,
        updatedAt: updatedAt,
      );

  /// Ёзиш учун (вақт майдонлари — репозиторийда `serverTimestamp`).
  Map<String, Object> toMap() => {
        'name': name.trim(),
        'items': [for (final i in items) i.toMap()],
        'remind': remind.toMap(),
      };

  static SmList fromMap(String id, Map<String, dynamic> d, {DateTime? updatedAt}) {
    final raw = d['items'];
    final items = <SmListItem>[
      if (raw is List) ...raw.map(SmListItem.fromMap).whereType<SmListItem>().take(kSmListItemsMax),
    ];
    final name = d['name'];
    return SmList(
      id: id,
      name: name is String ? name.trim() : '',
      items: List.unmodifiable(items),
      remind: SmRemind.fromMap(d['remind']),
      updatedAt: updatedAt,
    );
  }

  /// Бир хил маҳсулот қайта қўшилса — миқдор қўшилади; чегарадан ошса — қўшилмайди.
  SmList addItem(SmListItem item) {
    final idx = items.indexWhere((i) => i.sameAs(item));
    if (idx >= 0) {
      final next = [...items];
      next[idx] = next[idx].copyWith(qtyMilli: next[idx].qtyMilli + item.qtyMilli);
      return copyWith(items: next);
    }
    if (items.length >= kSmListItemsMax) return this;
    return copyWith(items: [...items, item]);
  }

  SmList setQtyAt(int index, int qtyMilli) {
    if (index < 0 || index >= items.length) return this;
    if (qtyMilli <= 0) return removeAt(index);
    final next = [...items];
    next[index] = next[index].copyWith(qtyMilli: qtyMilli);
    return copyWith(items: next);
  }

  SmList removeAt(int index) {
    if (index < 0 || index >= items.length) return this;
    return copyWith(items: [...items]..removeAt(index));
  }
}

/// Рўйхат номи / таркиби хатолари (lang калитлари). Бўш — сақласа бўлади.
List<String> smListProblems(SmList l) => [
      if (l.name.trim().isEmpty) 'sm_err_list_name_empty',
      if (l.name.trim().length > kSmListNameMax) 'sm_err_list_name_long',
      if (l.items.length > kSmListItemsMax) 'sm_err_list_too_many',
      ...smRemindProblems(l.remind),
    ];

/// Намунавий рўйхат (эга 2026-11-21): мол гўшти, картошка, пиёз, сабзи, гуруч, нон, ёғ, тухум, сут, олма,
/// ичимлик суви. Гуруҳ id'лари — сервер seed `supermarket_taxonomy_v1.json` (CONFIRMED); «ёғ» — `cottonseed_oil`
/// (Пахта ёғи; INFERRED — энг кенг тарқалгани), «тухум» — `chicken_eggs`. Миқдорлар — PROPOSED (мижоз ўзгартиради).
/// Таксономияда йўқ гуруҳ — ташланади. Оила сони сўралмайди (эга).
const kSmTemplateItems = <({String groupId, num qty})>[
  (groupId: 'beef', qty: 1),
  (groupId: 'potato', qty: 3),
  (groupId: 'onion', qty: 2),
  (groupId: 'carrot', qty: 2),
  (groupId: 'rice', qty: 2),
  (groupId: 'bread', qty: 4),
  (groupId: 'cottonseed_oil', qty: 1),
  (groupId: 'chicken_eggs', qty: 1),
  (groupId: 'milk', qty: 2),
  (groupId: 'apple', qty: 2),
  (groupId: 'drinking_water', qty: 2),
];

List<SmListItem> smTemplateItems(SmTaxonomy tx) => [
      for (final t in kSmTemplateItems)
        if (tx.group(t.groupId) case final g?) SmListItem(groupId: g.id, qtyMilli: smSnapQty(smToMilli(t.qty), g.stepMilli)),
    ];

/// Солиштириш натижаси (бир қатор).
enum SmCompareStatus {
  /// Ўша таклиф, нарх ўзгармаган (ёки аввалги нарх номаълум).
  ok,

  /// Ўша таклиф, нарх ўзгарган ([SmCompareLine.previousPrice] → offer.price).
  priceChanged,

  /// Аввалги таклиф йўқ — шу гуруҳдан бошқа таклиф/қадоқ таклиф қилинади (аниқ кўрсатилади).
  differentPack,

  /// Шу гуруҳда сотувда ҳеч нарса йўқ — саватга қўшилмайди.
  unavailable,
}

class SmCompareLine {
  const SmCompareLine({
    required this.item,
    required this.status,
    this.offer,
    this.previousOffer,
    this.previousPrice,
    this.qtyMilli = 0,
    this.qtyLimited = false,
  });

  final SmListItem item;
  final SmCompareStatus status;

  /// Саватга қўшиладиган таклиф (unavailable — `null`).
  final SmOffer? offer;

  /// Рўйхат/буюртмадаги аввалги таклиф (каталогда бўлса).
  final SmOffer? previousOffer;
  final int? previousPrice;

  /// Саватга қўшиладиган миқдор (қадамга тўғриланган, қолдиқдан ошмайди).
  final int qtyMilli;

  /// Қолдиқ етмагани учун миқдор камайтирилди.
  final bool qtyLimited;

  bool get addable => offer != null && qtyMilli > 0;
}

/// Рўйхат (ёки эски буюртма) қаторларини ЖОРИЙ таклифлар билан солиштиради. Тоза функция.
///
/// Танлов тартиби: 1) сақланган таклиф сотувда бўлса — ўша; 2) акс ҳолда шу гуруҳ (нав сақланган бўлса —
/// аввал шу нав) ичидан энг арзон мавжуд таклиф → [SmCompareStatus.differentPack] (сақланган таклиф бор эди)
/// ёки ok (таклифсиз гуруҳ қатори, масалан намунадан); 3) ҳеч нарса йўқ — unavailable.
/// [previousPrices] — `offerId → аввалги нарх` (буюртмадан ёки охирги сақлашдан); йўқ — нарх ўзгариши
/// аниқланмайди.
List<SmCompareLine> smCompareItems(
  List<SmListItem> items, {
  required Map<String, SmOffer> offers,
  required Map<String, List<SmOffer>> offersByGroup,
  Map<String, int> previousPrices = const {},
}) {
  final out = <SmCompareLine>[];
  for (final item in items) {
    final saved = item.offerId.isEmpty ? null : offers[item.offerId];
    final prev = item.offerId.isEmpty ? null : previousPrices[item.offerId];
    SmOffer? pick;
    var status = SmCompareStatus.ok;
    if (saved != null && saved.available) {
      pick = saved;
      if (prev != null && prev != saved.price) status = SmCompareStatus.priceChanged;
    } else {
      final pool = (offersByGroup[item.groupId] ?? const <SmOffer>[]).where((o) => o.available).toList();
      final sameVariety = item.varietyId.isEmpty ? <SmOffer>[] : pool.where((o) => o.varietyId == item.varietyId).toList();
      final sorted = smSortOffersAsc(sameVariety.isNotEmpty ? sameVariety : pool);
      pick = sorted.isEmpty ? null : sorted.first;
      if (pick == null) {
        status = SmCompareStatus.unavailable;
      } else if (item.offerId.isNotEmpty) {
        status = SmCompareStatus.differentPack;
      }
    }
    var qty = 0;
    var limited = false;
    if (pick != null) {
      qty = smSnapQty(item.qtyMilli, pick.stepMilli);
      final max = pick.maxQtyMilli;
      if (max != null && qty > max) {
        qty = (max ~/ pick.stepMilli) * pick.stepMilli;
        limited = true;
      }
      if (qty <= 0) {
        pick = null;
        status = SmCompareStatus.unavailable;
      }
    }
    out.add(SmCompareLine(
      item: item,
      status: status,
      offer: pick,
      previousOffer: saved,
      previousPrice: prev,
      qtyMilli: qty,
      qtyLimited: limited,
    ));
  }
  return out;
}

/// Танланган қаторлардан саватга қўшиладиганлар (`offerId → qtyMilli`, бир хил таклиф — бирлашади).
/// ФАҚАТ сават: буюртма ҳам, тўлов ҳам йўқ.
List<SmCartLine> smCompareToCartLines(List<SmCompareLine> lines, {Set<int>? selected}) {
  final merged = <String, int>{};
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (!l.addable) continue;
    if (selected != null && !selected.contains(i)) continue;
    merged.update(l.offer!.id, (v) => v + l.qtyMilli, ifAbsent: () => l.qtyMilli);
  }
  return [for (final e in merged.entries) SmCartLine(e.key, e.value)];
}

/// Саватдан рўйхат қаторлари (таклиф + гуруҳ + нав сақланади).
List<SmListItem> smItemsFromCart(SmCart cart, Map<String, SmOffer> offers) => [
      for (final l in cart.lines)
        if (offers[l.productId] case final o?)
          SmListItem(groupId: o.groupId, varietyId: o.varietyId, offerId: o.id, qtyMilli: l.qtyMilli),
    ];

/// Саватдан аввалги нархлар (рўйхат сақланганда — кейин «нарх ўзгарди» учун).
Map<String, int> smPricesOf(Iterable<SmListItem> items, Map<String, SmOffer> offers) => {
      for (final i in items)
        if (i.offerId.isNotEmpty && offers[i.offerId] != null) i.offerId: offers[i.offerId]!.price,
    };

/// Эски буюртма қатори (`orders.items[]`, supermarket.js): `{productId, price, qty, groupId, varietyId?, removed?}`.
typedef SmOrderLineRef = ({String productId, String groupId, String varietyId, int price, int qtyMilli, bool removed});

List<SmOrderLineRef> smOrderLineRefs(Iterable<Map<String, dynamic>> rawItems) => [
      for (final m in rawItems)
        (
          productId: m['productId'] is String ? m['productId'] as String : '',
          groupId: m['groupId'] is String ? m['groupId'] as String : '',
          varietyId: m['varietyId'] is String ? m['varietyId'] as String : '',
          price: (m['price'] as num?)?.toInt() ?? 0,
          qtyMilli: m['qty'] is num ? smToMilli(m['qty'] as num) : 0,
          removed: m['removed'] != null && m['removed'] != false,
        ),
    ];

/// «Қайта буюртма»: олиб ташланмаган қаторлар → рўйхат қаторлари + аввалги нархлар. Сўнг [smCompareItems].
({List<SmListItem> items, Map<String, int> prices}) smReorderItems(Iterable<SmOrderLineRef> lines) {
  final items = <SmListItem>[];
  final prices = <String, int>{};
  for (final l in lines) {
    if (l.removed || l.productId.isEmpty || l.groupId.isEmpty || l.qtyMilli <= 0) continue;
    items.add(SmListItem(groupId: l.groupId, varietyId: l.varietyId, offerId: l.productId, qtyMilli: l.qtyMilli));
    if (l.price > 0) prices[l.productId] = l.price;
  }
  return (items: items, prices: prices);
}
