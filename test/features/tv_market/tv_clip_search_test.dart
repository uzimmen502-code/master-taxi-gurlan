import 'package:ava_gurlan/core/utils/catalog_search.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/utils/tv_clip_search.dart';
import 'package:flutter_test/flutter_test.dart';

TvClip _clip({
  String title = 'Yamaha',
  String description = '',
  String category = 'product',
  String districtLabel = 'Гурлан',
  String ownerName = 'Али',
  List<String> tokens = const [],
}) {
  return TvClip(
    id: title,
    videoUrl: '',
    posterUrl: '',
    title: title,
    price: 1000,
    districtId: 'gurlan',
    districtLabel: districtLabel,
    ownerPhone: '998901234567',
    ownerName: ownerName,
    category: category,
    description: description,
    searchTokens: tokens,
  );
}

void main() {
  group('TvClipSearch 3 til', () {
    test('кирилл сўров ↔ лотин сарлавҳа', () {
      final c = _clip(title: 'Mototsikl');
      expect(TvClipSearch.matches(c, 'мотоцикл'), isTrue);
      expect(TvClipSearch.score(c, 'мотоцикл'), greaterThan(0));
    });

    test('лотин сўров ↔ кирилл сарлавҳа', () {
      final c = _clip(title: 'Мотоцикл сотилади');
      expect(TvClipSearch.matches(c, 'mototsikl'), isTrue);
    });

    test('рус категория: услуга → service', () {
      final svc = _clip(title: 'Yamaha', category: 'service');
      final prod = _clip(title: 'Yamaha', category: 'product');
      expect(TvClipSearch.matches(svc, 'услуга'), isTrue);
      expect(TvClipSearch.matches(prod, 'услуга'), isFalse);
      expect(TvClipSearch.matches(prod, 'товар'), isTrue);
    });

    test('ўзбек категория: хизмат / xizmat', () {
      final svc = _clip(title: 'Tuzatish', category: 'service');
      expect(TvClipSearch.matches(svc, 'хизмат'), isTrue);
      expect(TvClipSearch.matches(svc, 'xizmat'), isTrue);
    });

    test('туман номи', () {
      final c = _clip(title: 'Yamaha', districtLabel: 'Гурлан');
      expect(TvClipSearch.matches(c, 'гурлан'), isTrue);
      expect(TvClipSearch.matches(c, 'gurlan'), isTrue);
    });

    test('morph: такси → таксичи, таклиф эмас', () {
      expect(TvClipSearch.matches(_clip(title: 'Таксичи'), 'такси'), isTrue);
      expect(TvClipSearch.matches(_clip(title: 'Ҳамкорлик таклиф'), 'такси'), isFalse);
    });

    test('buildTokens икки скрипт + категория', () {
      final tokens = TvClipSearch.buildTokens(
        title: 'Мотоцикл',
        category: 'product',
        districtLabel: 'Гурлан',
      );
      expect(tokens.contains('мотоцикл'), isTrue);
      expect(tokens.contains('mototsikl'), isTrue);
      expect(tokens.any((t) => t == 'товар' || t == 'tovar'), isTrue);
    });

    test('AND: услуга + ном', () {
      final c = _clip(title: 'Мотоцикл', category: 'service');
      expect(TvClipSearch.matches(c, 'услуга мотоцикл'), isTrue);
      expect(TvClipSearch.matches(c, 'услуга нон'), isFalse);
    });

    test('score title > extra', () {
      final titled = _clip(title: 'Нонвой', category: 'product');
      final extra = _clip(title: 'Yamaha', category: 'product', description: 'нон');
      expect(
        TvClipSearch.score(titled, 'нон'),
        greaterThan(TvClipSearch.score(extra, 'нон')),
      );
      expect(CatalogSearch.score('нон', title: 'нонвой'), greaterThan(0));
    });
  });
}
