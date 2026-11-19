// Янги лотин алифбоси (эга 2026-11-19): қидирув эски (o‘ g‘ sh ch) ва янги (ö ğ ş ç) шаклни бирдек қабул қилади;
// токенлар ЭСКИ шаклда қолади (сақланган searchTokens ва сервер токенлари мос келаверади).
import 'package:ava_gurlan/core/utils/catalog_search.dart';
import 'package:ava_gurlan/features/ads/utils/ad_search_text.dart';
import 'package:ava_gurlan/features/markets/data/market_search.dart';
import 'package:ava_gurlan/features/markets/screens/market_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:flutter_test/flutter_test.dart';

TvShopItem _it(String title, {String description = ''}) => TvShopItem(
      id: 'x',
      ownerPhone: '998901111111',
      ownerName: 'Сотувчи',
      title: title,
      description: description,
      price: 100000,
      photoUrl: '',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      market: 'meat',
      category: 'beef',
      status: 'active',
    );

class _Ad implements AdSearchable {
  _Ad(this.title, [this.searchTokens = const []]);
  final String title;
  @override
  String get titleLower => title.toLowerCase();
  @override
  String get description => '';
  @override
  final List<String> searchTokens;
}

void main() {
  group('CatalogSearch (бозор/арзон маҳсулотлар/глобал)', () {
    test('янги сўров — эски матн; эски сўров — янги матн; кирилл', () {
      expect(CatalogSearch.matches('göşt', ["Mol go'sht"]), isTrue);
      expect(CatalogSearch.matches("go'sht", ['Mol göşt']), isTrue);
      expect(CatalogSearch.matches('göşt', ['Мол гўшт']), isTrue);
      expect(CatalogSearch.matches('Şaşlik', ['shashlik']), isTrue);
      expect(CatalogSearch.matches('çoy', ['Choy 1 kg']), isTrue);
      expect(CatalogSearch.matches('ğişt', ["G'isht"]), isTrue);
    });
    test('мос келмаса — false (folding ортиқча топмайди)', () {
      expect(CatalogSearch.matches('göşt', ['Sut']), isFalse);
    });
    test('normalize: ö ğ ş ç → o\' g\' sh ch', () {
      expect(CatalogSearch.normalize(' Özbekça  ŞAHAR '), "o'zbekcha shahar");
    });
    test('marketItemMatchesQuery (бозор экрани клиент филтри)', () {
      expect(marketItemMatchesQuery(_it("Qo'y go'sht"), 'göşt'), isTrue);
      expect(marketItemMatchesQuery(_it('Qöy göşt'), "go'sht"), isTrue);
    });
  });

  group('AdSearchText токенлари — эски шаклда', () {
    test('янги алифбода ёзилган эълон: сақланадиган токенлар эски шакл билан бир хил', () {
      expect(AdSearchText.buildTokens('Göşt', '').toSet(), AdSearchText.buildTokens("Go'sht", '').toSet());
      expect(AdSearchText.buildTokens('Göşt', ''), contains("go'sht"));
      expect(AdSearchText.buildTokens('Göşt', ''), contains('гўшт'));
    });
    test('сўров токенлари: янги ва эски шакл бир хил', () {
      expect(AdSearchText.queryTokens('şaşlik').toSet(), AdSearchText.queryTokens('shashlik').toSet());
    });
    test('matches/score: эски токенли эълонни янги сўров топади', () {
      final ad = _Ad("Go'sht", const ["go'sht", 'гўшт']);
      expect(AdSearchText.matches(ad, 'göşt'), isTrue);
      expect(AdSearchText.score(_Ad('Göşt'), "go'sht"), greaterThan(0));
    });
  });

  group('Бозор сервер қидируви', () {
    test('сервер токени янги сўровда ҳам эски шаклда (сақланган searchTokens билан мос)', () {
      expect(marketServerSearchToken('göşt'), marketServerSearchToken("go'sht"));
      expect(marketServerSearchToken('çoy'), 'choy');
    });
    test('сервер натижаси клиент текшируви: янги ёзувдаги сарлавҳа сўзга бўлиниб кетмайди', () {
      expect(marketServerItemMatches(_it('Mol göşti'), "go'sht"), isTrue);
      expect(marketServerItemMatches(_it("Mol go'shti"), 'göşt'), isTrue);
      expect(marketServerItemMatches(_it('Mol göşti'), 'sut'), isFalse);
    });
  });
}
