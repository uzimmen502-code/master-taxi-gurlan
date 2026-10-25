import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:ava_gurlan/core/utils/global_search.dart';
import 'package:ava_gurlan/features/ads/utils/market_shop_items.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/models/search_index_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 4-босқич (эга қарори 2026-10-25): Аҳоли бозори қидируви охирги 80 та билан чекланмайди, ҳудуд қоидаси эълонлар
/// билан бир хил, дўкон номи бўйича ҳам топилади.
TvShopItem _i(String id, {String district = '', String status = 'active'}) => TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'x',
      title: 'Товар $id',
      price: 1000,
      photoUrl: 'https://x/$id.jpg',
      photoUrls: ['https://x/$id.jpg'],
      kind: 'product',
      districtId: district,
      districtLabel: '',
      status: status,
    );

const _gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan');

void main() {
  group('marketShopPool', () {
    test('охирги + сервер топгани бирлашади, такрорсиз; фаол бўлмагани йўқ', () {
      final pool = marketShopPool(
        [_i('a'), _i('b')],
        [_i('b'), _i('c'), _i('d', status: 'blocked')],
        const GeoScope(level: GeoLevel.nation, area: _gurlan),
        const {},
      );
      expect([for (final x in pool) x.id], ['a', 'b', 'c']);
    });

    test('туман: шу туман ва ҳудудсиз эски ёзув; вилоят: вилоят туманлари; Республика: ҳаммаси', () {
      final items = [_i('g', district: 'gurlan'), _i('u', district: 'urganch'), _i('t', district: 'chilonzor'), _i('old')];
      List<String> ids(GeoScope s, Set<String> rd) => [for (final x in marketShopPool(items, const [], s, rd)) x.id];
      expect(ids(const GeoScope(level: GeoLevel.district, area: _gurlan), const {}), ['g', 'old']);
      expect(ids(const GeoScope(level: GeoLevel.region, area: _gurlan), const {'gurlan', 'urganch'}), ['g', 'u', 'old']);
      expect(ids(const GeoScope(level: GeoLevel.nation, area: _gurlan), const {}), ['g', 'u', 't', 'old']);
    });
  });

  group('SearchIndexEntry: онлайн дўкон', () {
    const shop = SearchIndexEntry(
      id: 'shop_998901111111',
      type: SearchIndexEntry.typeShop,
      moduleId: 'cheap_products_home',
      title: 'Сидабилла',
      searchTokens: ['сидабилла', 'sidabilla'],
      targetOwner: '998901111111',
    );
    const other = SearchIndexEntry(
      id: 'shop_x',
      type: SearchIndexEntry.typeShop,
      moduleId: 'cheap_products_home',
      title: 'Бошқа дўкон',
      searchTokens: ['бошқа', 'boshqa', 'дўкон'],
      targetOwner: '998902222222',
    );

    test('дўкон номи лотинда ёзилса ҳам топилади; номоси топилмайди', () {
      final r = GlobalSearch.rank([shop, other], 'sidabilla', limit: 10);
      expect([for (final e in r) e.id], ['shop_998901111111']);
    });
  });
}
