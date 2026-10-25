import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../../business_map/domain/business.dart';
import '../models/tv_shop.dart';

/// Ягона онлайн дўкон ичидаги йўналиш (эга қарори 2026-10-25: «битта онлайн дўкон, унинг таркибида турли
/// йўналишдаги дўконлар»): эганинг ўз дўкони (`businessId` бўш) ёки йўналиш дўкони (`businesses/{id}`).
class ShopDirection {
  const ShopDirection.own(this.name)
      : businessId = '',
        business = null;

  ShopDirection.business(Business b)
      : businessId = b.id,
        name = b.name,
        business = b;

  /// Бўш — эганинг ўз дўкони.
  final String businessId;
  final String name;
  final Business? business;

  bool get isOwn => businessId.isEmpty;
}

/// Харидор кўрадиган танлов: «Барчаси» ([all]) ёки битта йўналиш.
class ShopSelection {
  const ShopSelection.all()
      : businessId = null;
  const ShopSelection.direction(String this.businessId);

  /// `null` — барча маҳсулотлар; `''` — ўз дўкони; бошқаси — йўналиш ID'си.
  final String? businessId;

  bool get isAll => businessId == null;

  @override
  bool operator ==(Object other) => other is ShopSelection && other.businessId == businessId;

  @override
  int get hashCode => businessId.hashCode;
}

/// Дўкон саҳифаси мантиғи (соф — тест учун; Firebase'сиз).
class ShopDirections {
  ShopDirections._(this.directions, this.businessesKnown, [Map<String, List<Business>> branches = const {}])
      : _branches = branches,
        _dirOf = {
          '': '',
          for (final d in directions) d.businessId: d.businessId,
          for (final e in branches.entries)
            for (final b in e.value) b.id: e.key,
        };

  final List<ShopDirection> directions;

  /// Филиаллар: ота йўналиш ID'си → унинг жисмоний нуқталари (алоҳида тугма эмас — шу йўналиш карточкасида).
  final Map<String, List<Business>> _branches;

  /// Ҳар бир маълум объект (йўналиш ёки филиал) → у тегишли йўналиш ID'си.
  final Map<String, String> _dirOf;

  /// Йўналишнинг филиаллари (энг эскиси биринчи).
  List<Business> branchesOf(String directionId) => _branches[directionId] ?? const [];

  /// `false` — йўналишлар ўқилмади (меҳмон: `businesses` фақат телефон билан кирганларга, rules). Унда йўналиш
  /// тугмалари йўқ, барча фаол маҳсулот «Барчаси»да кўринади (блокланганлари барибир `status` бўйича чиқмайди).
  final bool businessesKnown;

  /// Эганинг йўналишлари: блокланганлари (админ) ва бошқа эганики чиқарилади; энг эскиси биринчи (барқарор тартиб).
  /// Йўналиш дўкони маҳсулотсиз ҳам кўринади (харитадаги объект: манзил, иш вақти, телефон). Ўз дўкони —
  /// [hasOwnItems] бўлса ёки бошқа йўналиш бўлмаса; биринчи туради (номи — онлайн дўкон номи).
  factory ShopDirections.build({
    required String ownerPhone,
    required String shopName,
    required List<Business> businesses,
    bool hasOwnItems = true,
    bool businessesKnown = true,
  }) {
    final owner = canonicalPhoneId(ownerPhone);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final own = businesses
        .where((b) => !b.isBlocked && b.id.isNotEmpty && canonicalPhoneId(b.ownerId) == owner)
        .toList()
      ..sort((a, b) => (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch));
    if (!businessesKnown) return ShopDirections._([ShopDirection.own(shopName)], false);
    // Филиал — отаси шу рўйхатда (эганинг, блокланмаган, ўзи филиал эмас) бўлса отага қўшилади; отаси йўқ бўлса
    // (ўчирилган/блокланган) — алоҳида йўналиш каби кўринади (харидор барибир тўғри дўконга тушади).
    final parentIds = {for (final b in own) if (!b.isBranch) b.id};
    final branches = <String, List<Business>>{};
    final mains = <Business>[];
    for (final b in own) {
      if (b.isBranch && parentIds.contains(b.branchOf)) {
        (branches[b.branchOf] ??= []).add(b);
      } else {
        mains.add(b);
      }
    }
    return ShopDirections._([
      if (hasOwnItems || mains.isEmpty) ShopDirection.own(shopName),
      for (final b in mains) ShopDirection.business(b),
    ], true, branches);
  }

  /// Йўналиш тугмалари керакми (битта бўлса — танлов йўқ).
  bool get hasChoice => directions.length > 1;

  /// Йўналиш ёки унинг филиали ID'си бўйича — йўналиш (филиал нуқтасидан келинса ҳам отанинг дўкони).
  ShopDirection? byId(String businessId) {
    final dirId = _dirOf[businessId];
    if (dirId == null) return null;
    for (final d in directions) {
      if (d.businessId == dirId) return d;
    }
    return null;
  }

  /// Қайси танлов билан очилади:
  /// 1) аниқ [businessId] (харита, ҳавола) — мавжуд ва блокланмаган бўлса;
  /// 2) кирилган маҳсулотнинг йўналиши ([highlightBusinessId]) — маҳсулот ёки видеодан;
  /// 3) акс ҳолда — «Барчаси» (йўналиш битта бўлса — ўша).
  /// Номаълум/блокланган йўналиш — хавфсиз: бутун дўкон очилади, бошқа дўкон эмас.
  ShopSelection initial({String businessId = '', String? highlightBusinessId}) {
    if (!businessesKnown) return const ShopSelection.all();
    final byTarget = businessId.isNotEmpty ? byId(businessId) : null;
    if (byTarget != null) return ShopSelection.direction(byTarget.businessId);
    final h = highlightBusinessId;
    final byItem = h != null ? byId(h) : null;
    if (byItem != null) return ShopSelection.direction(byItem.businessId);
    return hasChoice ? const ShopSelection.all() : ShopSelection.direction(directions.first.businessId);
  }

  /// Танловга мос маҳсулотлар: фақат фаол, фақат шу эганики; йўналиш маҳсулоти фақат эганинг маълум
  /// (блокланмаган) йўналишига тегишли бўлса кўринади (бегона `businessId` ёзиб қўйилган ҳужжат — йўқ).
  /// Ўз дўкони маҳсулоти ҳар доим маълум (тугмаси яширилган бўлса ҳам «Барчаси»да кўринади).
  List<TvShopItem> itemsFor(ShopSelection s, Iterable<TvShopItem> items, {required String ownerPhone}) {
    final owner = canonicalPhoneId(ownerPhone);
    return [
      for (final i in items)
        if (i.isActive &&
            canonicalPhoneId(i.ownerPhone) == owner &&
            (!businessesKnown || _dirOf.containsKey(i.businessId)) &&
            (s.isAll || !businessesKnown || _dirOf[i.businessId] == s.businessId))
          i,
    ];
  }

  /// Дўкон ичидаги қидирув ва тур фильтри (`product` | `service` | `null` — ҳаммаси). Қидирувда энг мосси биринчи
  /// (Аҳоли бозори қидируви билан бир хил қоида — `CatalogSearch`).
  static List<TvShopItem> filter(List<TvShopItem> items, {String query = '', String? kind}) {
    var list = kind == null ? items : items.where((i) => i.kind == kind).toList();
    if (CatalogSearch.normalize(query).isEmpty) return list;
    list = list.where((i) => CatalogSearch.matches(query, [i.title, i.description, '${i.price}'])).toList();
    int scoreOf(TvShopItem i) => CatalogSearch.score(query, title: i.title, extra: [i.description, '${i.price}']);
    list.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    return list;
  }
}
