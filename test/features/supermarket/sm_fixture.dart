import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_access.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';

Map<String, String> n(String s) => {'uz_Cyrl': s, 'uz_Latn': '$s-lat', 'ru': '$s-ru'};

final smTaxonomyFixture = SmTaxonomy.fromMap({
  'version': 3,
  'categories': [
    {
      'id': 'vegetables',
      'order': 1,
      'icon': 'vegetables',
      'names': n('Сабзавотлар'),
      'groups': [
        {'id': 'onion', 'order': 1, 'names': n('Пиёз'), 'unit': 'kg', 'step': 0.5, 'weighed': true, 'synonyms': ['piyoz', 'лук']},
        {'id': 'potato', 'order': 2, 'names': n('Картошка'), 'unit': 'kg', 'step': 1, 'weighed': true},
        {'id': 'empty', 'order': 3, 'names': n('Бўш'), 'unit': 'kg', 'step': 1},
      ],
    },
    {
      'id': 'dairy',
      'order': 2,
      'icon': 'dairy',
      'names': n('Сут маҳсулотлари'),
      'groups': [
        {'id': 'milk', 'order': 1, 'names': n('Сут'), 'unit': 'pack', 'step': 1},
        {'id': 'bad', 'order': 2, 'names': n('X'), 'unit': 'ton'},
      ],
    },
  ],
});

SmOffer offer(
  String id, {
  String group = 'onion',
  int price = 5000,
  String variety = 'red',
  Map<String, String>? varietyNames,
  String status = 'active',
  bool weighed = true,
  num step = 0.5,
  String unit = 'kg',
  num? packQty,
  String packUnit = '',
  String quality = '',
  String packLabel = '',
}) =>
    SmOffer.fromMap(id, {
      'name': 'Offer $id',
      'smGroupId': group,
      'smCategoryId': 'vegetables',
      'smVariety': {'id': variety, 'names': varietyNames ?? n(variety == 'red' ? 'Қизил пиёз' : 'Оқ пиёз')},
      if (quality.isNotEmpty) 'smQuality': n(quality),
      'packLabel': packLabel,
      'unit': unit,
      'qtyStep': step,
      'weighed': weighed,
      'smStatus': status,
      'price': price,
      if (packQty != null) 'packQty': packQty,
      if (packUnit.isNotEmpty) 'packUnit': packUnit,
    });

List<SmOffer> smOffersFixture() => [
      offer('o_red_exp', price: 7000),
      offer('o_red_cheap', price: 5000, quality: '1-сорт'),
      offer('o_red_oos', price: 3000, status: 'out_of_stock'),
      offer('o_red_hidden', price: 1000, status: 'hidden'),
      offer('o_white', price: 4000, variety: 'white'),
      offer('p1', group: 'potato', price: 6000, variety: '', varietyNames: const {}, step: 1),
      offer('m1',
          group: 'milk', price: 12000, variety: '', varietyNames: const {}, unit: 'pack', step: 1, weighed: false,
          packQty: 0.9, packUnit: 'l', packLabel: '0,9 л'),
    ];

const smAccessFixture = SmAccess(
  allowed: true,
  feePercent: 11,
  slots: [
    SmSlot(id: 's1', names: {}, startMin: 600, endMin: 720, day: 'today'),
    SmSlot(id: 's2', names: {}, startMin: 900, endMin: 1020, day: 'tomorrow'),
  ],
);

class FakeSupermarketApi implements SupermarketApi {
  FakeSupermarketApi({this.access = smAccessFixture});

  SmAccess access;
  final payloads = <Map<String, dynamic>>[];

  /// Навбатдаги жавоблар: `Exception` — ташланади, `SmPlaceResult` — қайтарилади.
  final placeResults = <Object>[];

  @override
  Future<SmAccess> getAccess() async => access;

  @override
  Future<List<SmOffer>> loadOffers(SmTaxonomy taxonomy) async => smOffersFixture();

  @override
  Future<SmTaxonomy> loadTaxonomy() async => smTaxonomyFixture;

  @override
  Future<SmPlaceResult> placeOrder(Map<String, dynamic> payload) async {
    payloads.add(payload);
    final r = placeResults.isEmpty
        ? const SmPlaceResult(orderId: 'ord1', goodsTotal: 1, fee: 1, hold: 2)
        : placeResults.removeAt(0);
    if (r is Future<SmPlaceResult>) return await r;
    if (r is Exception) throw r;
    return r as SmPlaceResult;
  }
}
