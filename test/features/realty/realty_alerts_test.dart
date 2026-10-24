import 'package:ava_gurlan/features/realty/screens/realty_alert_form_screen.dart';
import 'package:ava_gurlan/features/realty/screens/realty_detail_screen.dart';
import 'package:ava_gurlan/models/map_picker_result.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга қарори 2026-10-08: кўча/уй пакетдан кейин; «шундай уй чиқса,
/// хабар бер» формаси.
///
/// Локализация делегати атайлаб уланмаган — `context.tr` калитнинг ўзини
/// қайтаради.
class _FakeRepo implements RealtyRepository {
  RealtyDetail? detail;
  Map<String, Object?>? created;
  RealtyException? createError;

  @override
  Future<RealtyDetail?> fetchDetail(String listingId) async => detail;

  @override
  Stream<int> watchUnlocksLeft() => Stream.value(0);

  @override
  Future<String> fetchAgentPhone() async => '';

  @override
  Future<RealtyAlertCreateResult> createAlert({
    required RealtyDeal deal,
    required double lat,
    required double lng,
    required int radiusKm,
    int? roomsMin,
    int? roomsMax,
    int? priceMax,
  }) async {
    if (createError != null) throw createError!;
    created = {
      'deal': deal, 'lat': lat, 'lng': lng, 'radiusKm': radiusKm,
      'roomsMin': roomsMin, 'roomsMax': roomsMax, 'priceMax': priceMax,
    };
    return const RealtyAlertCreateResult(alertId: 'a1', matchIds: ['L1']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

RealtyListing _listing({String publicAddress = ''}) => RealtyListing(
      id: 'L1',
      ownerKey: 'k',
      ownerName: 'Эга',
      deal: RealtyDeal.rent,
      tier: RealtyTier.plain,
      title: 'Икки хонали',
      text: 'Таъмирланган',
      areaLat: 41.85,
      areaLng: 60.39,
      status: 'active',
      addressText: publicAddress,
    );

void main() {
  group('модел', () {
    test('RealtyDetail: манзил ёпиқдан, эски ёзувда очиқдан', () {
      final d = RealtyDetail.fromMap(const {
        'lat': 41.0, 'lng': 60.0, 'ownerPhone': '998900000001',
        'addressText': 'Навоий 12',
      });
      expect(d.addressText, 'Навоий 12');
      expect(d.addressOr('Эски'), 'Навоий 12');
      const legacy = RealtyDetail(lat: 1, lng: 1, ownerPhone: '1');
      expect(legacy.addressOr('  Эски кўча 5 '), 'Эски кўча 5');
    });

    test('RealtyListing: priceAmount бутун сўм; йўқ бўлса null', () {
      expect(RealtyListing.fromMap('x', const {'priceAmount': 3000000}).priceAmount, 3000000);
      expect(RealtyListing.fromMap('x', const {}).priceAmount, isNull);
    });
  });

  group('тафсилот: манзил ПАКЕТДАН КЕЙИН', () {
    testWidgets('очилмаган — эски очиқ манзил ҳам КЎРИНМАЙДИ', (tester) async {
      final repo = _FakeRepo()..detail = null;
      await tester.pumpWidget(MaterialApp(
        home: RealtyDetailScreen(
          listing: _listing(publicAddress: 'Гурлан, Эски кўча 5'),
          repository: repo,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Эски кўча'), findsNothing);
      expect(find.text('realty_locked_title'), findsOneWidget);
    });

    testWidgets('очилган — манзил ёпиқ ҳужжатдан', (tester) async {
      final repo = _FakeRepo()
        ..detail = const RealtyDetail(
          lat: 41.85, lng: 60.39, ownerPhone: '998900000001',
          addressText: 'Гурлан, Навоий 12',
        );
      await tester.pumpWidget(MaterialApp(
        home: RealtyDetailScreen(listing: _listing(), repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Гурлан, Навоий 12'), findsOneWidget);
    });

    testWidgets('очилган эски ёзув — очиқдаги манзил кўрсатилади', (tester) async {
      final repo = _FakeRepo()
        ..detail = const RealtyDetail(lat: 41.85, lng: 60.39, ownerPhone: '998900000001');
      await tester.pumpWidget(MaterialApp(
        home: RealtyDetailScreen(
          listing: _listing(publicAddress: 'Гурлан, Эски кўча 5'),
          repository: repo,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Гурлан, Эски кўча 5'), findsOneWidget);
    });
  });

  group('хабарнома формаси', () {
    Future<_FakeRepo> pumpForm(WidgetTester tester, {bool withPoint = true}) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RealtyAlertFormScreen(
                    repository: repo,
                    pickPoint: (_) async => withPoint
                        ? const MapPickerResult(lat: 41.844, lng: 60.392, label: 'Гурлан')
                        : null,
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return repo;
    }

    // `ElevatedButton.icon` — ички subclass, шунинг учун калит бўйича.
    ButtonStyleButton saveButton(WidgetTester tester) =>
        tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('realty_alert_save')));

    testWidgets('жой танланмагунча сақлаш ўчиқ', (tester) async {
      await pumpForm(tester, withPoint: false);
      expect(saveButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('realty_alert_pick')));
      await tester.pumpAndSettle();
      expect(saveButton(tester).onPressed, isNull, reason: 'харитадан қайтмади');
    });

    testWidgets('сақлаш: радиус, хона оралиғи, нарх (рақамлар) серверга кетади', (tester) async {
      final repo = await pumpForm(tester);
      await tester.tap(find.byKey(const ValueKey('realty_alert_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 ev_trip_km'));
      await tester.tap(find.text('2'));
      await tester.tap(find.text('3'));
      await tester.enterText(find.byKey(const ValueKey('realty_alert_price')), '3 000 000');
      await tester.pumpAndSettle();
      expect(saveButton(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('realty_alert_save')));
      await tester.pumpAndSettle();
      expect(repo.created, {
        'deal': RealtyDeal.rent, 'lat': 41.844, 'lng': 60.392, 'radiusKm': 5,
        'roomsMin': 2, 'roomsMax': 3, 'priceMax': 3000000,
      });
      expect(find.byType(RealtyAlertFormScreen), findsNothing, reason: 'сақлангач ёпилади');
    });

    testWidgets('«4+» — юқори чегарасиз; қайта босилса тозаланади', (tester) async {
      final repo = await pumpForm(tester);
      await tester.tap(find.byKey(const ValueKey('realty_alert_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4+'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('realty_alert_save')));
      await tester.pumpAndSettle();
      expect(repo.created!['roomsMin'], 4);
      expect(repo.created!['roomsMax'], isNull);
    });

    testWidgets('сервер лимити — тушунарли хабар, форма очиқ қолади', (tester) async {
      final repo = await pumpForm(tester);
      repo.createError = const RealtyException('alert_limit_reached');
      await tester.tap(find.byKey(const ValueKey('realty_alert_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('realty_alert_save')));
      await tester.pumpAndSettle();
      expect(find.text('realty_alert_error_limit'), findsOneWidget);
      expect(find.byType(RealtyAlertFormScreen), findsOneWidget);
    });
  });
}
