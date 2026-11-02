// ignore_for_file: subtype_of_sealed_class
// (Firestore турлари @sealed; тестда фақат керакли методлари сохталаштирилади.)
import 'package:ava_gurlan/features/business_map/data/business_pin_loader.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ҳар қандай чақирув хато беради: `load` ичидаги `guarded` ҳар манбанинг ўқишга УРИНГАНИНИ `failed` да қолдиради.
/// EV яширилган бўлса — унга умуман уринилмайди (эга, 2026-10-23).
class _ThrowingFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('firestore: ${invocation.memberName}');
}

/// Объектлар — тайёр рўйхат (катакча ва катта ҳудуд сўровлари учун бир хил).
class _FakeBiz extends Fake implements BusinessRepository {
  _FakeBiz(this.rows);
  final List<Business> rows;

  @override
  Future<List<Business>> fetchInCells(List<String> cells, {int limit = 400}) async => rows;

  @override
  Future<List<Business>> fetchRecent({int limit = 200}) async => rows;
}

class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  Map<String, dynamic> data() => _data;
}

class _Snap extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snap(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

/// Сўров занжири (`where/orderBy/startAt/endAt/limit`) ўзини қайтаради; `get` — коллекциянинг ҳамма ҳужжатлари.
class _Query implements CollectionReference<Map<String, dynamic>> {
  _Query(this.docs);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #get) return Future<QuerySnapshot<Map<String, dynamic>>>.value(_Snap(docs));
    if (const [#where, #orderBy, #startAt, #endAt, #limit].contains(i.memberName)) return this;
    return super.noSuchMethod(i);
  }
}

class _Db implements FirebaseFirestore {
  _Db(this.collections);
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> collections;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => _Query(collections[path] ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('firestore: ${invocation.memberName}');
}

void main() {
  test('EV яширилган: флаг ўчиқ', () {
    expect(BusinessPinLoader.showEvStations, isFalse);
  });

  Future<void> expectEvNotTouched(MapBounds bounds) async {
    final r = await BusinessPinLoader(firestore: _ThrowingFirestore()).load(bounds);
    expect(r.failed, contains(BusinessSource.restaurant), reason: 'назорат: бошқа манбалар ўқишга уринган');
    expect(r.failed, isNot(contains(BusinessSource.evStation)));
    expect(r.pins.where((p) => p.source == BusinessSource.evStation), isEmpty);
  }

  test('кичик ҳудуд (катакчалар): EV ўқилмайди', () async {
    await expectEvNotTouched(const MapBounds(south: 41.8, west: 60.3, north: 41.9, east: 60.5));
  });

  test('катта ҳудуд (бутун мамлакат): EV ўқилмайди', () async {
    await expectEvNotTouched(const MapBounds(south: 37, west: 56, north: 45.6, east: 73));
  });

  group('ресторанга уланган объект — харитада битта белги (эга, 2026-11-03)', () {
    Business biz(String id, {String rid = '', String status = 'active'}) => Business(
          id: id, ownerId: '998901111111', name: id, category: BusinessCategory.food, phone: '998901111111',
          lat: 41.85, lng: 60.4, restaurantId: rid, status: status,
        );
    _Doc rest(String id) => _Doc(id, {'name': id, 'status': 'approved', 'lat': 41.85, 'lng': 60.4});

    BusinessPinLoader loader() => BusinessPinLoader(
          businesses: _FakeBiz([
            biz('b1', rid: 'r1'), // уланган → r1 белгиси йўқолади
            biz('b2', rid: 'r9'), // r9 харитада йўқ → ҳеч нарса яширилмайди
            biz('b3', rid: 'r3', status: 'blocked'), // блокланган объект чизилмайди → r3 белгиси қолади
            biz('b4'),
          ]),
          firestore: _Db({
            'restaurants': [rest('r1'), rest('r2'), rest('r3')],
          }),
        );

    Future<void> expectMerged(MapBounds bounds, {required bool tooWide}) async {
      final r = await loader().load(bounds);
      expect(r.failed, isEmpty);
      expect(r.tooWide, tooWide);
      expect(
        [for (final p in r.pins) p.key]..sort(),
        ['business:b1', 'business:b2', 'business:b4', 'restaurant:r2', 'restaurant:r3'],
      );
      final b1 = r.pins.singleWhere((p) => p.key == 'business:b1');
      expect(b1.linkedRestaurantId, 'r1', reason: 'меню объект белгисидан очилади');
    }

    test('кичик ҳудуд (катакчалар): ресторан белгиси объект белгисига қўшилади', () async {
      await expectMerged(const MapBounds(south: 41.8, west: 60.3, north: 41.9, east: 60.5), tooWide: false);
    });

    test('катта ҳудуд (намуна): ҳам шундай', () async {
      await expectMerged(const MapBounds(south: 37, west: 56, north: 45.6, east: 73), tooWide: true);
    });
  });
}
