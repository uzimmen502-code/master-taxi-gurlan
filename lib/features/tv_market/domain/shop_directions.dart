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
  ShopDirections._(this.directions, this.businessesKnown);

  final List<ShopDirection> directions;

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
    return ShopDirections._([
      if (hasOwnItems || own.isEmpty) ShopDirection.own(shopName),
      for (final b in own) ShopDirection.business(b),
    ], true);
  }

  /// Йўналиш тугмалари керакми (битта бўлса — танлов йўқ).
  bool get hasChoice => directions.length > 1;

  ShopDirection? byId(String businessId) {
    for (final d in directions) {
      if (d.businessId == businessId) return d;
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
    if (businessId.isNotEmpty && byId(businessId) != null) return ShopSelection.direction(businessId);
    final h = highlightBusinessId;
    if (h != null && byId(h) != null) return ShopSelection.direction(h);
    return hasChoice ? const ShopSelection.all() : ShopSelection.direction(directions.first.businessId);
  }

  /// Танловга мос маҳсулотлар: фақат фаол, фақат шу эганики; йўналиш маҳсулоти фақат эганинг маълум
  /// (блокланмаган) йўналишига тегишли бўлса кўринади (бегона `businessId` ёзиб қўйилган ҳужжат — йўқ).
  /// Ўз дўкони маҳсулоти ҳар доим маълум (тугмаси яширилган бўлса ҳам «Барчаси»да кўринади).
  List<TvShopItem> itemsFor(ShopSelection s, Iterable<TvShopItem> items, {required String ownerPhone}) {
    final owner = canonicalPhoneId(ownerPhone);
    final known = {'', for (final d in directions) d.businessId};
    return [
      for (final i in items)
        if (i.isActive &&
            canonicalPhoneId(i.ownerPhone) == owner &&
            (!businessesKnown || known.contains(i.businessId)) &&
            (s.isAll || i.businessId == s.businessId))
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
