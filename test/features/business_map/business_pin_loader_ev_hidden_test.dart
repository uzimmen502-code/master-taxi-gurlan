import 'package:ava_gurlan/features/business_map/data/business_pin_loader.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ҳар қандай чақирув хато беради: `load` ичидаги `guarded` ҳар манбанинг ўқишга УРИНГАНИНИ `failed` да қолдиради.
/// EV яширилган бўлса — унга умуман уринилмайди (эга, 2026-10-23).
class _ThrowingFirestore implements FirebaseFirestore {
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
}
