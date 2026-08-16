import 'package:ava_gurlan/core/utils/catalog_search.dart';
import 'package:ava_gurlan/core/utils/global_search.dart';
import 'package:ava_gurlan/models/search_index_entry.dart';
import 'package:flutter_test/flutter_test.dart';

SearchIndexEntry _entry({
  required String type,
  required String moduleId,
  required String title,
  List<String> keywords = const [],
  List<String> tokens = const [],
  String subtitle = '',
  String from = '',
  String to = '',
  int boost = 0,
}) {
  return SearchIndexEntry(
    id: '${type}_$title',
    type: type,
    moduleId: moduleId,
    title: title,
    subtitle: subtitle,
    keywords: keywords,
    searchTokens: tokens,
    from: from,
    to: to,
    priorityBoost: boost,
  );
}

void main() {
  group('CatalogSearch morph / stem hotfix', () {
    test('такси → таклиф ❌ (false friend)', () {
      expect(CatalogSearch.score('такси', title: 'таклиф'), 0);
      expect(CatalogSearch.matches('такси', ['таклиф']), isFalse);
      expect(
        CatalogSearch.score(
          'такси',
          title: 'Савдо агентларига ҳамкорлик таклиф қилинади',
        ),
        0,
      );
    });

    test('нон → нонвой ✅', () {
      expect(CatalogSearch.score('нон', title: 'нонвой') > 0, isTrue);
      expect(CatalogSearch.matches('нон', ['нонвой']), isTrue);
    });

    test('нон → нонлар ✅', () {
      expect(CatalogSearch.score('нон', title: 'нонлар') > 0, isTrue);
      expect(CatalogSearch.matches('нон', ['нонлар']), isTrue);
    });

    test('такси → таксичи ✅', () {
      expect(CatalogSearch.score('такси', title: 'таксичи') > 0, isTrue);
      expect(CatalogSearch.matches('такси', ['таксичи']), isTrue);
    });

    test('иш → ишчи ✅', () {
      expect(CatalogSearch.score('иш', title: 'ишчи') > 0, isTrue);
      expect(CatalogSearch.matches('иш', ['ишчи']), isTrue);
    });

    test('иш → ишхона ✅ (morph -хона)', () {
      expect(CatalogSearch.score('иш', title: 'ишхона') > 0, isTrue);
      expect(CatalogSearch.matches('иш', ['ишхона']), isTrue);
    });

    test('иш → ишонч ❌ (эҳтиёткор, morph эмас)', () {
      expect(CatalogSearch.score('иш', title: 'ишонч'), 0);
      expect(CatalogSearch.matches('иш', ['ишонч']), isFalse);
    });

    test('Тошкент → Тошкентлик ✅', () {
      expect(CatalogSearch.score('Тошкент', title: 'Тошкентлик') > 0, isTrue);
      expect(CatalogSearch.matches('Тошкент', ['Тошкентлик']), isTrue);
    });

    test('юк → юкчи ✅', () {
      expect(CatalogSearch.score('юк', title: 'юкчи') > 0, isTrue);
      expect(CatalogSearch.matches('юк', ['юкчи']), isTrue);
    });

    test('stem-only common prefix (3) → 0', () {
      expect(CatalogSearch.isValidatedStem('такси', 'таклиф'), isFalse);
      expect(CatalogSearch.score('такси', title: 'таклиф'), 0);
    });

    test('exact / whole word', () {
      expect(
        CatalogSearch.score('такси', title: 'такси') >= CatalogSearch.wWholeWord,
        isTrue,
      );
      expect(CatalogSearch.matches('нон', ['Нон']), isTrue);
    });

    test('latin ↔ cyrillic', () {
      expect(CatalogSearch.matches('taksi', ['такси']), isTrue);
      expect(CatalogSearch.matches('non', ['нонвой']), isTrue);
      expect(CatalogSearch.score('taksi', title: 'таксичи') > 0, isTrue);
    });

    test("oʻ / o' / ў (3 yozuv)", () {
      const oz = 'o\u02BBqituvchi';
      expect(CatalogSearch.matches("o'qituvchi", ['ўқитувчи']), isTrue);
      expect(CatalogSearch.matches(oz, ['ўқитувчи']), isTrue);
      expect(CatalogSearch.matches('ўқитувчи', ["o'qituvchi"]), isTrue);
      expect(CatalogSearch.matches('mototsikl', ['мотоцикл']), isTrue);
      expect(CatalogSearch.matches('мотоцикл', ['mototsikl']), isTrue);
    });

    test('unrelated title → 0 (no weak fallback)', () {
      expect(CatalogSearch.score('такси', title: 'Лабо шоколад'), 0);
      expect(CatalogSearch.score('нон', title: 'Мой алмаштириш'), 0);
    });

    test('isMorphExtension helpers', () {
      expect(CatalogSearch.isMorphExtension('нон', 'нонвой'), isTrue);
      expect(CatalogSearch.isMorphExtension('такси', 'таксичи'), isTrue);
      expect(CatalogSearch.isMorphExtension('иш', 'ишхона'), isTrue);
      expect(CatalogSearch.isMorphExtension('такси', 'таклиф'), isFalse);
      expect(CatalogSearch.isMorphExtension('юк', 'юкчи'), isTrue);
    });
  });

  group('GlobalSearch rank gate', () {
    final salesJob = _entry(
      type: SearchIndexEntry.typeJob,
      moduleId: 'jobs',
      title: 'Савдо агентларига ҳамкорлик таклиф қилинади',
      keywords: const ['иш', 'эълон'],
      tokens: const [
        'савдо',
        'savdo',
        'таклиф',
        'taklif',
        'ҳамкорлик',
        'hamkorlik',
      ],
    );
    final taxiService = _entry(
      type: SearchIndexEntry.typeService,
      moduleId: 'local_taxi',
      title: 'Маҳаллий такси',
      keywords: const ['такси', 'taxi'],
      boost: 22,
    );
    final intercity = _entry(
      type: SearchIndexEntry.typeService,
      moduleId: 'intercity',
      title: 'Шаҳарлараро такси',
      keywords: const ['такси', 'taxi'],
      boost: 24,
    );
    final taxiChi = _entry(
      type: SearchIndexEntry.typeJob,
      moduleId: 'jobs',
      title: 'Таксичи керак',
      keywords: const ['иш'],
    );
    final bread = _entry(
      type: SearchIndexEntry.typeService,
      moduleId: 'bread',
      title: 'Нон',
      keywords: const ['нон', 'non'],
      boost: 20,
    );
    final nonvoy = _entry(
      type: SearchIndexEntry.typeBreadProduct,
      moduleId: 'bread',
      title: 'Нонвой патир',
    );
    final toshkentRoute = _entry(
      type: SearchIndexEntry.typeIntercityRoute,
      moduleId: 'intercity',
      title: 'Гурлан → Тошкент',
      from: 'Гурлан',
      to: 'Тошкент',
      keywords: const ['такси', 'тошкент'],
      boost: 10,
    );
    final yukchi = _entry(
      type: SearchIndexEntry.typeService,
      moduleId: 'yuk_birja',
      title: 'Юкчи хизмати',
      keywords: const ['юк', 'yuk'],
    );

    test('такси → савдо таклиф эълони ❌', () {
      final score = GlobalSearch.score(salesJob, 'такси');
      expect(score, 0);
      final ranked = GlobalSearch.rank([salesJob, taxiService], 'такси');
      expect(ranked.any((e) => e.title.contains('Савдо')), isFalse);
    });

    test('такси → такси хизматлари ✅', () {
      final ranked = GlobalSearch.rank(
        [salesJob, taxiService, intercity, taxiChi],
        'такси',
      );
      expect(ranked.length, greaterThanOrEqualTo(2));
      expect(ranked.any((e) => e.moduleId == 'local_taxi'), isTrue);
      expect(ranked.any((e) => e.moduleId == 'intercity'), isTrue);
      expect(ranked.any((e) => e.title.contains('Савдо')), isFalse);
    });

    test('такси → таксичи ✅', () {
      expect(GlobalSearch.score(taxiChi, 'такси'), greaterThan(0));
    });

    test('нон → нон / нонвой ✅', () {
      final ranked = GlobalSearch.rank([bread, nonvoy, salesJob], 'нон');
      expect(ranked.any((e) => e.moduleId == 'bread'), isTrue);
      expect(ranked.any((e) => e.title.contains('Савдо')), isFalse);
    });

    test('Тошкент → йўналиш ✅', () {
      expect(GlobalSearch.score(toshkentRoute, 'Тошкент'), greaterThan(0));
      expect(GlobalSearch.score(toshkentRoute, 'Тошкентлик'), greaterThan(0));
    });

    test('юк → юкчи ✅', () {
      expect(GlobalSearch.score(yukchi, 'юк'), greaterThan(0));
    });

    test('иш → ишчи ✅, ишонч эмас', () {
      final ishchi = _entry(
        type: SearchIndexEntry.typeJob,
        moduleId: 'jobs',
        title: 'Ишчи керак',
      );
      final ishonch = _entry(
        type: SearchIndexEntry.typeJob,
        moduleId: 'jobs',
        title: 'Ишончли ҳамкор',
      );
      expect(GlobalSearch.score(ishchi, 'иш'), greaterThan(0));
      expect(GlobalSearch.score(ishonch, 'иш'), 0);
    });

    test('multi-word false friend still gated', () {
      expect(GlobalSearch.score(salesJob, 'такси таклиф'), 0);
    });

    test('rank limit respects scores only', () {
      final pool = [
        salesJob,
        taxiService,
        intercity,
        bread,
        nonvoy,
        toshkentRoute,
        yukchi,
      ];
      final ranked = GlobalSearch.rank(pool, 'такси', limit: 10);
      for (final e in ranked) {
        expect(
          e.title.toLowerCase().contains('савдо') ||
              e.title.toLowerCase().contains('таклиф'),
          isFalse,
        );
      }
    });
  });

  group('CatalogSearch additional pairs', () {
    final pairsOk = <(String, String)>[
      ('нон', 'нонли'),
      ('нон', 'нончи'),
      ('патир', 'патирлар'),
      ('юк', 'юклар'),
      ('такси', 'таксига'),
      ('товар', 'товарлар'),
      ('дўкон', 'дўкончи'),
      ('marshrut', 'marshrutchi'),
      ('labo', 'labolar'),
    ];

    final pairsNo = <(String, String)>[
      ('такси', 'таклиф'),
      ('такси', 'такт'),
      ('юк', 'юқори'),
      ('иш', 'ишлаб'),
      ('иш', 'ишонч'),
      ('нон', 'ноль'),
      ('бог', 'бозор'),
    ];

    for (final p in pairsOk) {
      test('${p.$1} → ${p.$2} ✅', () {
        expect(CatalogSearch.score(p.$1, title: p.$2), greaterThan(0));
      });
    }

    for (final p in pairsNo) {
      test('${p.$1} → ${p.$2} ❌', () {
        expect(CatalogSearch.score(p.$1, title: p.$2), 0);
      });
    }
  });
}
