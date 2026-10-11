import 'package:ava_gurlan/features/yuk_intercity/models/yuk_listing.dart';
import 'package:ava_gurlan/features/yuk_intercity/yuk_listing_filter.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 15, 12);

YukListing _listing(
  String id, {
  YukListingType type = YukListingType.cargo,
  String from = 'Гурлан',
  String to = 'Тошкент',
  List<String> stops = const [],
  String vehicleType = 'fura',
  YukListingStatus status = YukListingStatus.active,
  Duration age = Duration.zero,
  DateTime? expiresAt,
  DateTime? departDate,
}) {
  final created = _now.subtract(age);
  return YukListing(
    id: id,
    type: type,
    from: from,
    to: to,
    stops: stops,
    vehicleType: vehicleType,
    ownerId: '998900000000',
    ownerName: 'Test',
    phone: '+998900000000',
    status: status,
    createdAt: created,
    expiresAt: expiresAt ?? created.add(YukListing.ttl),
    departDate: departDate,
  );
}

List<String> _ids(List<YukListing> l) => l.map((e) => e.id).toList();

void main() {
  group('filterYukListings — status/muddat', () {
    test('closed ва муддати ўтган эълонлар чиқарилади', () {
      final r = filterYukListings(
        [
          _listing('active'),
          _listing('closed', status: YukListingStatus.closed),
          _listing('expired',
              age: const Duration(days: 5, minutes: 1)), // ttl 5 сутка → expired
        ],
        tab: 'all',
        now: _now,
      );
      expect(_ids(r), ['active']);
    });

    test('5 сутка: 4 кун 23 соатлик эълон ҳали фаол (аввалги 48 соатдан узоқ)', () {
      final r = filterYukListings(
        [_listing('old4d', age: const Duration(days: 4, hours: 23))],
        tab: 'all',
        now: _now,
      );
      expect(_ids(r), ['old4d']);
      expect(YukListing.ttl, const Duration(days: 5));
    });

    test('createdAt бўйича янги тепада', () {
      final r = filterYukListings(
        [
          _listing('old', age: const Duration(hours: 5)),
          _listing('new'),
          _listing('mid', age: const Duration(hours: 1)),
        ],
        tab: 'all',
        now: _now,
      );
      expect(_ids(r), ['new', 'mid', 'old']);
    });
  });

  group('filterYukListings — tab', () {
    final src = [
      _listing('c1'),
      _listing('t1', type: YukListingType.truck),
    ];

    test('all', () {
      expect(_ids(filterYukListings(src, tab: 'all', now: _now)),
          containsAll(['c1', 't1']));
    });
    test('cargo', () {
      expect(_ids(filterYukListings(src, tab: 'cargo', now: _now)), ['c1']);
    });
    test('truck', () {
      expect(_ids(filterYukListings(src, tab: 'truck', now: _now)), ['t1']);
    });
  });

  group('filterYukListings — vehicle type', () {
    test('moto/traktor шаҳарлараро рўйхатда кўринмайди', () {
      final r = filterYukListings(
        [
          _listing('fura'),
          _listing('moto', vehicleType: 'moto'),
          _listing('traktor', vehicleType: 'traktor'),
        ],
        tab: 'all',
        now: _now,
      );
      expect(_ids(r), ['fura']);
    });

    test('фильтр normalize қилинган код бўйича (legacy кириллча ҳам)', () {
      final src = [
        _listing('fura'),
        _listing('ref', vehicleType: 'ref'),
        _listing('legacy', vehicleType: 'рефрижератор'),
      ];
      expect(
        _ids(filterYukListings(src, tab: 'all', vehicleType: 'ref', now: _now)),
        containsAll(['ref', 'legacy']),
      );
      expect(
        _ids(filterYukListings(src, tab: 'all', vehicleType: 'ref', now: _now)),
        isNot(contains('fura')),
      );
    });
  });

  group('filterYukListings — from/to', () {
    final src = [
      _listing('gt', from: 'Гурлан', to: 'Тошкент'),
      _listing('us', from: 'Урганч', to: 'Самарқанд'),
      _listing('stops',
          from: 'Хива', to: 'Бухоро', stops: const ['Тошкент', 'Навоий']),
    ];

    test('from — routeCities ичида substring, катта-кичик ҳарф фарқсиз', () {
      expect(_ids(filterYukListings(src, tab: 'all', from: 'гурл', now: _now)),
          ['gt']);
    });

    test('to — оралиқ тўхташларда ҳам топилади', () {
      expect(
        _ids(filterYukListings(src, tab: 'all', to: 'Тошкент', now: _now)),
        containsAll(['gt', 'stops']),
      );
    });

    test('from + to бирга', () {
      expect(
        _ids(filterYukListings(src, tab: 'all',
            from: 'Хива', to: 'Навоий', now: _now)),
        ['stops'],
      );
    });

    test('мос келмаса бўш', () {
      expect(filterYukListings(src, tab: 'all', from: 'Андижон', now: _now),
          isEmpty);
    });

    // 3в: йўналиш тартиби.
    test('тескари йўналиш чиқмайди (Тошкент → Гурлан қидирувида Гурлан → Тошкент йўқ)', () {
      expect(
        filterYukListings(src, tab: 'all',
            from: 'Тошкент', to: 'Гурлан', now: _now),
        isEmpty,
      );
    });

    test('тўхташлар орқали: олдинги тўхташ → кейингиси — бор; тескариси — йўқ', () {
      expect(
        _ids(filterYukListings(src, tab: 'all',
            from: 'Тошкент', to: 'Бухоро', now: _now)),
        ['stops'],
      );
      expect(
        filterYukListings(src, tab: 'all',
            from: 'Навоий', to: 'Тошкент', now: _now),
        isEmpty,
      );
    });

    test('чегара: ёнма-ён тўхташлар (Тошкент → Навоий) — бор', () {
      expect(
        _ids(filterYukListings(src, tab: 'all',
            from: 'Тошкент', to: 'Навоий', now: _now)),
        ['stops'],
      );
    });

    test('жўнаш куни: ўтган кун — йўқ; кун филтри — шу кун + санасиз эскилар', () {
      final today = DateTime(2026, 9, 15);
      final src = [
        _listing('yesterday', departDate: DateTime(2026, 9, 14)),
        _listing('today', departDate: today),
        _listing('in3', departDate: DateTime(2026, 9, 18)),
        _listing('legacy'),
      ];
      expect(_ids(filterYukListings(src, tab: 'all', now: _now))..sort(),
          ['in3', 'legacy', 'today']);
      expect(
        _ids(filterYukListings(src,
            tab: 'all', departDay: DateTime(2026, 9, 18, 17), now: _now))
          ..sort(),
        ['in3', 'legacy'],
      );
    });

    test('departDate Firestore шакли: YYYY-MM-DD ўқилади, нотўғриси — null', () {
      final ok = YukListing.fromFirestore('a', {'departDate': '2026-10-13'});
      expect(ok.departDate, DateTime(2026, 10, 13));
      expect(ok.toJson()['departDate'], '2026-10-13');
      expect(YukListing.fromFirestore('b', {'departDate': '13.10.2026'}).departDate,
          isNull);
      expect(YukListing.fromFirestore('c', const {}).departDate, isNull);
    });

    test('фақат битта томон берилса — тартиб талаб қилинмайди', () {
      expect(
        _ids(filterYukListings(src, tab: 'all', from: 'Тошкент', now: _now)),
        containsAll(['gt', 'stops']),
      );
    });
  });
}
