import 'package:ava_gurlan/features/ev_charging/data/ev_trip_destinations.dart';
import 'package:ava_gurlan/features/ev_charging/data/ev_trip_geo_catalog.dart';
import 'package:ava_gurlan/features/ev_charging/data/ev_trip_place_search.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:flutter_test/flutter_test.dart';

// Манзил қидируви: уч тил, катта-кичик ҳарф, "Вилоят • Туман" кўриниши,
// дедупликация, тартиб, лимит. Ҳужжат майдонлари `geo_regions` /
// `geo_districts` схемасидан (id, regionId, name=лотин, nameUz=кирилл,
// nameRu, nameRuShort) — координата ЙЎҚ.

const _xorazm = GeoRegion(
  id: 'xorazm',
  name: 'Xorazm',
  nameUz: 'Хоразм',
  nameRu: 'Хорезмская область',
  nameRuShort: 'Хорезм',
  order: 10,
);
const _qashqa = GeoRegion(
  id: 'qashqadaryo',
  name: 'Qashqadaryo',
  nameUz: 'Қашқадарё',
  nameRu: 'Кашкадарьинская область',
  nameRuShort: 'Кашкадарья',
  order: 20,
);

const _gurlan = GeoDistrict(
  id: 'gurlan',
  regionId: 'xorazm',
  name: 'Gurlan tumani',
  nameUz: 'Гурлан тумани',
  nameRu: 'Гурленский район',
  nameRuShort: 'Гурлен',
  order: 30,
);
const _urganchCity = GeoDistrict(
  id: 'urganch_shahri',
  regionId: 'xorazm',
  name: 'Urganch shahri',
  nameUz: 'Урганч шаҳри',
  nameRu: 'город Ургенч',
  order: 10,
);
const _urganchDistrict = GeoDistrict(
  id: 'urganch',
  regionId: 'xorazm',
  name: 'Urganch tumani',
  nameUz: 'Урганч тумани',
  nameRu: 'Ургенчский район',
  order: 50,
);
const _xivaCity = GeoDistrict(
  id: 'xiva_shahri',
  regionId: 'xorazm',
  name: 'Xiva shahri',
  nameUz: 'Хива шаҳри',
  nameRu: 'город Хива',
  order: 70,
);
const _xivaDistrict = GeoDistrict(
  id: 'xiva',
  regionId: 'xorazm',
  name: 'Xiva tumani',
  nameUz: 'Хива тумани',
  nameRu: 'Хивинский район',
  order: 80,
);
const _bogot = GeoDistrict(
  id: 'bogot',
  regionId: 'xorazm',
  name: 'Bogʻot tumani',
  nameUz: 'Боғот тумани',
  nameRu: 'Богатский район',
  order: 20,
);
// Бошқа вилоятда ҳам "Гурлан" номли туман бўлиши мумкин (тест учун).
const _gurlanOther = GeoDistrict(
  id: 'gurlan_q',
  regionId: 'qashqadaryo',
  name: 'Gurlan tumani',
  nameUz: 'Гурлан тумани',
  nameRu: 'Гурленский район',
  order: 5,
);
// Эски ҳужжат: nameRu йўқ.
const _oldDoc = GeoDistrict(
  id: 'kitob',
  regionId: 'qashqadaryo',
  name: 'Kitob tumani',
  nameUz: 'Китоб тумани',
  order: 10,
);

EvTripPlaceIndex _index({
  List<GeoRegion> regions = const [_xorazm, _qashqa],
  List<GeoDistrict> districts = const [
    _urganchCity,
    _bogot,
    _gurlan,
    _urganchDistrict,
    _xivaCity,
    _xivaDistrict,
    _gurlanOther,
    _oldDoc,
  ],
}) =>
    EvTripPlaceIndex.build(regions: regions, districts: districts);

List<String> _names(List<EvTripPlace> r, String lang) =>
    r.map((p) => p.displayFor(lang)).toList();

void main() {
  group('кўриниш (иловa тилида)', () {
    test('туман — "Вилоят • Туман": кирилл, лотин, рус', () {
      final p = _index().places.firstWhere((p) => p.id == 'd:gurlan');
      expect(p.displayFor('uz_Cyrl'), 'Хоразм • Гурлан');
      expect(p.displayFor('uz_Latn'), 'Xorazm • Gurlan');
      expect(p.displayFor('ru'), 'Хорезм • Гурлен');
    });

    test('эски ҳужжат (nameRu йўқ) — рус тилида кирилл номга қайтади', () {
      final p = _index().places.firstWhere((p) => p.id == 'd:kitob');
      expect(p.displayFor('ru'), 'Кашкадарья • Китоб');
      expect(p.displayFor('uz_Latn'), 'Qashqadaryo • Kitob');
    });

    test('вилоят маркази — ўз номи билан', () {
      final r = _index().places.firstWhere((p) => p.id == 'r:xorazm');
      expect(r.kind, EvTripPlaceKind.region);
      expect(r.displayFor('uz_Cyrl'), 'Хоразм');
      expect(r.displayFor('uz_Latn'), 'Xorazm');
      expect(r.displayFor('ru'), 'Хорезм');
    });

    test('қўлда ёзилган шаҳар — ном иловa тилида', () {
      final c = _index().places.firstWhere((p) => p.id == 'c:samarqand');
      expect(c.displayFor('uz_Cyrl'), 'Самарқанд');
      expect(c.displayFor('uz_Latn'), 'Samarqand');
      expect(c.displayFor('ru'), 'Самарканд');
    });
  });

  group('қидирув: уч тил ва катта-кичик ҳарф', () {
    test('лотинда ёзса кирилл фойдаланувчига кирилл номли туман чиқади', () {
      final r = _index().search('gurlan', 'uz_Cyrl');
      expect(_names(r, 'uz_Cyrl'), contains('Хоразм • Гурлан'));
    });

    test('кириллда ёзса лотин фойдаланувчига лотин номли туман чиқади', () {
      final r = _index().search('гурлан', 'uz_Latn');
      expect(_names(r, 'uz_Latn'), contains('Xorazm • Gurlan'));
    });

    test('русча ёзилиш билан топилади, кўриниш иловa тилида', () {
      final r = _index().search('гурлен', 'uz_Latn');
      expect(_names(r, 'uz_Latn'), contains('Xorazm • Gurlan'));
    });

    test('катта-кичик ҳарфга бефарқ', () {
      final a = _index().search('GURLAN', 'uz_Latn').map((p) => p.id);
      final b = _index().search('gUrLaN', 'uz_Latn').map((p) => p.id);
      final c = _index().search('ГУРЛАН', 'uz_Cyrl').map((p) => p.id);
      expect(a, b);
      expect(a, c);
      expect(a, contains('d:gurlan'));
    });

    test('апостроф турлари ва ё/е аҳамиятсиз', () {
      expect(_index().search('qoqon', 'uz_Latn').first.id, 'c:qoqon');
      expect(_index().search('Qo\'qon', 'uz_Latn').first.id, 'c:qoqon');
      expect(_index().search('Qoʻqon', 'uz_Latn').first.id, 'c:qoqon');
      expect(_index().search('Qo‘qon', 'uz_Latn').first.id, 'c:qoqon');
      expect(evTripNormalize('Ёлочка'), 'елочка');
    });

    test('бошидаги/охиридаги бўшлиқ эътиборга олинмайди', () {
      expect(_index().search('  gurlan  ', 'uz_Latn').map((p) => p.id),
          contains('d:gurlan'));
    });

    test('мос келмаса — бўш рўйхат', () {
      expect(_index().search('zzzxxyy', 'uz_Latn'), isEmpty);
    });

    test('вилоят номи билан ёзилса — вилоят маркази ва унинг туманлари', () {
      final r = _index().search('xorazm', 'uz_Latn', limit: 20);
      expect(r.first.id, 'r:xorazm');
      final ids = r.map((p) => p.id).toList();
      expect(ids, containsAll(['d:gurlan', 'd:bogot']));
      // Бошқа вилоят туманлари аралашмайди.
      expect(ids, isNot(contains('d:kitob')));
    });
  });

  group('тартиб ва лимит', () {
    test('бўш сўров — қўлда ёзилган 22 шаҳар, лимитсиз', () {
      final r = _index().search('', 'uz_Cyrl');
      expect(r.length, EvTripDestination.all.length);
      expect(r.every((p) => p.kind == EvTripPlaceKind.curated), isTrue);
      expect(_index().search('   ', 'uz_Cyrl').length, r.length);
    });

    test('ёзилганда кўпи билан 8 та таклиф', () {
      final r = _index().search('a', 'uz_Latn');
      expect(r.length, EvTripPlaceIndex.typedLimit);
      expect(EvTripPlaceIndex.typedLimit, 8);
    });

    test('лимит параметри ишлайди', () {
      expect(_index().search('a', 'uz_Latn', limit: 3).length, 3);
      expect(_index().search('', 'uz_Latn', limit: 5).length, 5);
    });

    test('тўлиқ тенглик → бошидан → ичида; тенг даражада шаҳар олдин', () {
      final r = _index().search('urganch', 'uz_Latn', limit: 20);
      // 1-ўринда қўлда ёзилган Урганч (тўлиқ тенглик, координатали).
      expect(r.first.id, 'c:urganch');
      expect(r.first.kind, EvTripPlaceKind.curated);
      // Қолганлар (бошидан мослик) — туман.
      expect(
          r.skip(1).every((p) => p.kind == EvTripPlaceKind.district), isTrue);
    });

    test('иловa тилидаги мослик бошқа тилдагидан юқори', () {
      final tashkent = EvTripPlaceIndex.build()
          .places
          .firstWhere((p) => p.id == 'c:tashkent');
      final q = evTripNormalize('тош');
      // "Тошкент" (uz_Cyrl) — кирилл фойдаланувчида иловa тилида, русда эмас.
      expect(tashkent.matchScore(q, 'uz_Cyrl')!,
          lessThan(tashkent.matchScore(q, 'ru')!));
    });

    test('сўз бошидан мослик "ичида"дан юқори', () {
      const a = GeoDistrict(
          id: 'a',
          regionId: 'xorazm',
          name: 'Aralash tumani',
          nameUz: 'Аралаш тумани');
      const b = GeoDistrict(
          id: 'b',
          regionId: 'xorazm',
          name: 'Qora Lash tumani',
          nameUz: 'Қора Лаш тумани');
      const c = GeoDistrict(
          id: 'c',
          regionId: 'xorazm',
          name: 'Xalash tumani',
          nameUz: 'Халаш тумани');
      final idx = EvTripPlaceIndex.build(
          curated: const [],
          regions: const [_xorazm],
          districts: const [c, b, a]);
      // "lash": b — сўз бошидан, c — ичида, a — ичида.
      final r = idx.search('lash', 'uz_Latn').map((p) => p.id).toList();
      expect(r.first, 'd:b');
      expect(r.sublist(1).toSet(), {'d:a', 'd:c'});
    });
  });

  group('дедупликация ва чалкашликлар', () {
    test('шаҳар типидаги туман қўлда ёзилган шаҳар билан бир номли — тушади',
        () {
      final ids = _index().places.map((p) => p.id).toSet();
      expect(ids, isNot(contains('d:urganch_shahri')));
      expect(ids, isNot(contains('d:xiva_shahri')));
      expect(ids, contains('c:urganch'));
      expect(ids, contains('c:xiva'));
    });

    test('шаҳар билан бир номли ODDIY туман қолади, лекин тўлиқ номда', () {
      final p = _index().places.firstWhere((p) => p.id == 'd:urganch');
      expect(p.displayFor('uz_Cyrl'), 'Хоразм • Урганч тумани');
      expect(p.displayFor('uz_Latn'), 'Xorazm • Urganch tumani');
      expect(p.displayFor('ru'), 'Хорезм • Ургенчский район');
      // Қўлда ёзилган шаҳардан фарқ қилади.
      expect(
          p.displayFor('uz_Latn'),
          isNot(_index()
              .places
              .firstWhere((p) => p.id == 'c:urganch')
              .displayFor('uz_Latn')));
    });

    test('бошқа вилоятдаги бир номли туман — алоҳида, вилоят номи билан', () {
      final r = _index()
          .search('gurlan', 'uz_Latn')
          .map((p) => p.displayFor('uz_Latn'));
      expect(r, containsAll(['Xorazm • Gurlan', 'Qashqadaryo • Gurlan']));
    });

    test('бир вилоятда қисқа ном такрорланса — иккаласи тўлиқ номда', () {
      const a = GeoDistrict(
          id: 'a1',
          regionId: 'xorazm',
          name: 'Toza tumani',
          nameUz: 'Тоза тумани');
      const b = GeoDistrict(
          id: 'a2',
          regionId: 'xorazm',
          name: 'Toza shahri',
          nameUz: 'Тоза шаҳри');
      final idx = EvTripPlaceIndex.build(
          curated: const [], regions: const [_xorazm], districts: const [a, b]);
      final names = idx.places
          .where((p) => p.kind == EvTripPlaceKind.district)
          .map((p) => p.displayFor('uz_Latn'))
          .toList();
      expect(names, ['Xorazm • Toza tumani', 'Xorazm • Toza shahri']);
    });

    test('вилоят номи қўлда ёзилган шаҳар номига тенг бўлса — такрорланмайди',
        () {
      const samarqand = GeoRegion(
          id: 'samarqand',
          name: 'Samarqand',
          nameUz: 'Самарқанд',
          nameRu: 'Самарканд');
      final idx = EvTripPlaceIndex.build(regions: const [samarqand]);
      expect(idx.places.where((p) => p.id == 'r:samarqand'), isEmpty);
      expect(idx.places.where((p) => p.id == 'c:samarqand'), hasLength(1));
    });

    test('ID такрори (икки марта келган ҳужжат) битта чиқади', () {
      final idx = _index(districts: const [_gurlan, _gurlan]);
      expect(idx.places.where((p) => p.id == 'd:gurlan'), hasLength(1));
    });

    test('номоактив ҳужжат киритилмайди', () {
      const off = GeoDistrict(
          id: 'off',
          regionId: 'xorazm',
          name: 'Off tumani',
          nameUz: 'Офф тумани',
          active: false);
      expect(
          _index(districts: const [off]).places.where((p) => p.id == 'd:off'),
          isEmpty);
    });
  });

  group('координата ва Directions матни', () {
    test('қўлда ёзилган шаҳарда координата бор, матн йўқ', () {
      final c = _index().places.firstWhere((p) => p.id == 'c:buxoro');
      expect(c.hasCoords, isTrue);
      expect(c.lat, 39.7747);
      expect(c.routeText, isNull);
    });

    test('туман/вилоятда координата ЙЎҚ (ўйлаб топилмайди), матн бор', () {
      final d = _index().places.firstWhere((p) => p.id == 'd:gurlan');
      final r = _index().places.firstWhere((p) => p.id == 'r:xorazm');
      expect(d.hasCoords, isFalse);
      expect(d.lat, isNull);
      expect(d.lng, isNull);
      expect(r.hasCoords, isFalse);
      expect(d.routeText, 'Gurlan tumani, Xorazm, Uzbekistan');
      expect(r.routeText, 'Xorazm, Uzbekistan');
    });

    test('вилоят матнга киритилади — бир номли туманлар аралашмайди', () {
      final a = _index().places.firstWhere((p) => p.id == 'd:gurlan');
      final b = _index().places.firstWhere((p) => p.id == 'd:gurlan_q');
      expect(a.routeText, isNot(b.routeText));
      expect(b.routeText, 'Gurlan tumani, Qashqadaryo, Uzbekistan');
    });

    test('лотин ном йўқ — кирилл ва "Ўзбекистон"', () {
      const noLatin = GeoDistrict(
          id: 'x', regionId: 'xorazm', name: '', nameUz: 'Номаълум тумани');
      final idx = EvTripPlaceIndex.build(
          curated: const [],
          regions: const [_xorazm],
          districts: const [noLatin]);
      final p = idx.places.firstWhere((p) => p.id == 'd:x');
      expect(p.routeText, 'Номаълум тумани, Хоразм, Ўзбекистон');
    });

    test('ном умуман йўқ — матн null (ўйлаб топилмайди)', () {
      const empty = GeoDistrict(id: 'e', regionId: '', name: '', nameUz: '');
      final p = EvTripPlace.district(empty, null);
      expect(p.routeText, isNull);
    });
  });

  group('EvTripGeoCatalog', () {
    setUp(EvTripGeoCatalog.reset);
    tearDown(EvTripGeoCatalog.reset);

    test('бир марта юкланади ва кешланади', () async {
      var calls = 0;
      EvTripGeoCatalog.loaderOverride = () async {
        calls++;
        return (regions: [_xorazm], districts: [_gurlan]);
      };
      final a = await EvTripGeoCatalog.load();
      final b = await EvTripGeoCatalog.load();
      expect(calls, 1);
      expect(identical(a, b), isTrue);
      expect(a.places.any((p) => p.id == 'd:gurlan'), isTrue);
    });

    test('хато — қўлда ёзилган шаҳарлар билан давом, кеш эсланмайди', () async {
      var calls = 0;
      EvTripGeoCatalog.loaderOverride = () async {
        calls++;
        throw StateError('offline');
      };
      final a = await EvTripGeoCatalog.load();
      expect(a.places.length, EvTripDestination.all.length);
      await EvTripGeoCatalog.load();
      expect(calls, 2, reason: 'хато кешланмаслиги керак');
    });

    test('бўш жавоб (репозиторий хатоси) кешланмайди', () async {
      var calls = 0;
      EvTripGeoCatalog.loaderOverride = () async {
        calls++;
        return (regions: <GeoRegion>[], districts: <GeoDistrict>[]);
      };
      await EvTripGeoCatalog.load();
      await EvTripGeoCatalog.load();
      expect(calls, 2);
    });
  });
}
