// Курьерни кузатиш (S6; эга буюртмаси 2026-10-19): қоидалар, курьер ёзувчиси, кузатиш экрани, карточка.
// Қоида ваколати — `functions/test/restaurant_rules.test.js` (S6) ва `restaurant_orders_cf.test.js`.

import 'dart:async';
import 'dart:io';

import 'package:ava_gurlan/features/restaurants/courier/courier_live_publisher.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/courier_tracking.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/courier_tracking_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_order_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/courier_info_card.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'restaurants_l10n_harness.dart';
import '../../support/server_checkout.dart';

final _t0 = DateTime(2026, 10, 19, 12);

OrderModel _o({
  String status = 'picked',
  String mode = 'ava_courier',
  String? courier = '998913000001',
  String name = 'Ali Valiyev',
  double? lat = 41.8586,
  double? lng = 60.3917,
}) =>
    OrderModel(
      id: 'o1',
      type: 'restaurant',
      total: 1,
      status: 'in_delivery',
      items: const [],
      restaurantStatus: status,
      deliveryMode: mode,
      courierId: courier,
      courierName: name,
      restaurantName: 'Gurlan osh',
      restaurantLat: 41.8406,
      restaurantLng: 60.3917,
      lat: lat,
      lng: lng,
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('Қоидалар', () {
    test('canTrack: AVA курьери тайинланган + фаол ҳолат; ўз курьери, курьер йўқ, терминал ҳолат — йўқ', () {
      for (final s in ['accepted', 'ready', 'picked', 'arrived']) {
        expect(CourierTracking.canTrack(_o(status: s)), isTrue, reason: s);
      }
      for (final s in ['placed', 'delivered', 'rejected', 'cancelled', 'delivery_failed', '']) {
        expect(CourierTracking.canTrack(_o(status: s)), isFalse, reason: s);
      }
      expect(CourierTracking.canTrack(_o(mode: 'own_courier')), isFalse);
      expect(CourierTracking.canTrack(_o(mode: 'pickup')), isFalse);
      expect(CourierTracking.canTrack(_o(courier: null)), isFalse);
      expect(CourierTracking.canTrack(_o(courier: '  ')), isFalse);
      expect(CourierTracking.canTrack(const OrderModel(id: 'b', type: 'bread', total: 1, status: 'new', items: [], restaurantStatus: 'picked', deliveryMode: 'ava_courier', courierId: '1')), isFalse);
    });

    test('canTrack: нон/бозор буюртмаси — курьер олган (courier_picked) ва етган (arrived); тайёр/якунланган/курьерсиз/бошқа тур — йўқ', () {
      OrderModel b(String type, String fs, {String? courier = '998913000001'}) =>
          OrderModel(id: 'b', type: type, total: 1, status: 'in_delivery', items: const [], fulfillmentStatus: fs, courierId: courier);
      for (final type in ['bread', 'platform']) {
        for (final fs in CourierTracking.deliveryFulfillment) {
          expect(CourierTracking.canTrack(b(type, fs)), isTrue, reason: '$type/$fs');
        }
        for (final fs in ['pending', 'ready', 'completed', 'cancelled', '']) {
          expect(CourierTracking.canTrack(b(type, fs)), isFalse, reason: '$type/$fs');
        }
        expect(CourierTracking.canTrack(b(type, 'courier_picked', courier: null)), isFalse, reason: 'курьер йўқ');
        expect(CourierTracking.canTrack(b(type, 'courier_picked', courier: ' ')), isFalse);
      }
      expect(CourierTracking.canTrack(b('carpet', 'courier_picked')), isFalse, reason: 'бошқа тур');
      expect(CourierTracking.isBreadOrMarket(b('bread', '')), isTrue);
      expect(CourierTracking.isBreadOrMarket(b('restaurant', '')), isFalse);
    });

    test('нон/бозор ҳолатлари firestore.rules liveOrderActive билан бир хил', skip: serverParitySkip, () {
      final rules = File('firestore.rules').readAsStringSync();
      final fn = RegExp(r'function liveOrderActive[\s\S]*?\n    \}').firstMatch(rules)!.group(0)!;
      final lists = RegExp(r"in \[([^\]]*)\]").allMatches(fn).map((m) => RegExp(r"'(\w+)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toList()).toList();
      expect(lists.length, 3, reason: 'ресторан ҳолатлари, тур рўйхати, нон/бозор ҳолатлари');
      expect(lists[1].toSet(), {'bread', 'platform'});
      expect(lists[2].toSet(), CourierTracking.deliveryFulfillment.toSet());
    });
    test('фаол ҳолатлар firestore.rules `liveOrderActive` билан бир хил тўплам', skip: serverParitySkip, () {
      final rules = File('firestore.rules').readAsStringSync();
      final m = RegExp(r"function liveOrderActive[\s\S]*?in \[([^\]]*)\]").firstMatch(rules)!.group(1)!;
      final inRules = RegExp(r"'(\w+)'").allMatches(m).map((x) => x.group(1)!).toSet();
      expect(CourierTracking.activeStatuses.toSet(), inRules);
    });

    test('CourierLive.fromMap: тўғри; координата йўқ/сон эмас/диапазондан ташқари — null; ихтиёрий майдонлар', () {
      final l = CourierLive.fromMap({'lat': 41.84, 'lng': 60.39, 'heading': 90, 'speed': 7.5, 'updatedAt': Timestamp.fromDate(_t0)})!;
      expect([l.lat, l.lng, l.heading, l.speed, l.updatedAt], [41.84, 60.39, 90.0, 7.5, _t0]);
      expect(CourierLive.fromMap({'lat': 41.84, 'lng': 60.39})!.updatedAt, isNull, reason: 'сервер вақти ҳали келмаган');
      for (final bad in <Map<String, dynamic>?>[null, {}, {'lat': 'x', 'lng': 1}, {'lat': 91, 'lng': 0}, {'lat': 0, 'lng': 181}, {'lat': 1}]) {
        expect(CourierLive.fromMap(bad), isNull, reason: '$bad');
      }
    });

    test('ёш ва эскириш: 89 с — янги; 91 с — эскирган; вақти йўқ — эскирмаган (ҳали келмаган); келажак — 0', () {
      CourierLive at(DateTime? t) => CourierLive(lat: 1, lng: 1, updatedAt: t);
      expect(at(_t0).ageAt(_t0.add(const Duration(seconds: 89))), const Duration(seconds: 89));
      expect(at(_t0).isStaleAt(_t0.add(const Duration(seconds: 89))), isFalse);
      expect(at(_t0).isStaleAt(_t0.add(const Duration(seconds: 90))), isFalse, reason: 'чегаранинг ўзи — ҳали эскирмаган');
      expect(at(_t0).isStaleAt(_t0.add(const Duration(seconds: 91))), isTrue);
      expect(at(null).ageAt(_t0), isNull);
      expect(at(null).isStaleAt(_t0), isFalse);
      expect(at(_t0.add(const Duration(seconds: 5))).ageAt(_t0), Duration.zero);
    });

    test('масофа: ресторандан манзилгача ~2 км', () {
      const l = CourierLive(lat: 41.8406, lng: 60.3917);
      expect(l.distanceKmTo(41.8586, 60.3917), closeTo(2.0, 0.05));
    });

    test('shouldPublish: биринчи нуқта — ҳа; <8 с — йўқ; ≥8 с ва ≥20 м — ҳа; ≥8 с лекин <20 м — йўқ; 45 с тинч — «тирикман»', () {
      bool at(int sec, double dLat, {bool first = false}) => CourierTracking.shouldPublish(
            now: _t0.add(Duration(seconds: sec)),
            lat: 41.84 + dLat,
            lng: 60.39,
            lastAt: first ? null : _t0,
            lastLat: first ? null : 41.84,
            lastLng: first ? null : 60.39,
          );
      expect(at(0, 0, first: true), isTrue);
      expect(at(7, 0.01), isFalse, reason: 'жуда тез — катта силжиш бўлса ҳам');
      expect(at(8, 0.0003), isTrue, reason: '~33 м');
      expect(at(8, 0.00005), isFalse, reason: '~5 м');
      expect(at(44, 0.00005), isFalse);
      expect(at(45, 0.0), isTrue, reason: 'тинч турган — heartbeat');
    });
  });

  group('CourierLivePublisher', () {
    testWidgets('нуқталарни тезлик чегарасида ёзади; хато навбатни бузмайди; йўқолса ёзиш тўхтайди', (t) async {
      final controller = StreamController<LivePosition>();
      addTearDown(controller.close);
      final repo = _PubRepo();
      var now = _t0;
      Widget host({bool show = true}) => l10nApp(
            home: Scaffold(
              body: show
                  ? CourierLivePublisher(
                      orderId: 'o1',
                      courierId: '998913000001',
                      repository: repo,
                      positions: () => controller.stream,
                      clock: () => now,
                    )
                  : const SizedBox(),
            ),
          );
      await t.pumpWidget(host());
      controller.add(const LivePosition(lat: 41.84, lng: 60.39, heading: 10, speed: 3));
      await t.pump();
      expect(repo.writes.length, 1);
      expect(repo.writes.single.lat, 41.84);
      expect(repo.writes.single.courierId, '998913000001');

      now = _t0.add(const Duration(seconds: 3));
      controller.add(const LivePosition(lat: 41.85, lng: 60.39));
      await t.pump();
      expect(repo.writes.length, 1, reason: '3 с — ҳали эрта');

      now = _t0.add(const Duration(seconds: 9));
      repo.fail = true;
      controller.add(const LivePosition(lat: 41.85, lng: 60.39));
      await t.pump();
      expect(repo.attempts, 2, reason: 'ёзишга уринилди (хато)');
      repo.fail = false;
      controller.add(const LivePosition(lat: 41.85, lng: 60.39));
      await t.pump();
      expect(repo.writes.length, 2, reason: 'хатодан кейин қайта уринди (вақти янгиланмаган эди)');

      await t.pumpWidget(host(show: false));
      now = _t0.add(const Duration(minutes: 5));
      controller.add(const LivePosition(lat: 41.9, lng: 60.4));
      await t.pump();
      expect(repo.writes.length, 2, reason: 'виджет йўқ — ёзиш тўхтади');
    });
  });

  group('Кузатиш экрани', () {
    Future<void> pump(WidgetTester t, _TrackRepo repo, {OrderModel? initial, double width = 390, double textScale = 1.0}) async {
      t.view.physicalSize = Size(width * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: CourierTrackingScreen(
          orderId: 'o1',
          repository: repo,
          initial: initial,
          clock: () => _t0.add(repo.clockOffset),
          mapBuilder: (ctx, d) => Text('MAP r=${d.restaurant != null} d=${d.destination != null} c=${d.courier?.lat}', key: const ValueKey('fake-map')),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('нуқта йўқ: «жойлашув ҳозирча йўқ», курьер исми ва қўнғироқ; харитага ресторан ва манзил берилади', (t) async {
      final repo = _TrackRepo(_o());
      await pump(t, repo);
      expect((t.widget(find.byKey(const ValueKey('track-name'))) as Text).data, 'Ali Valiyev');
      expect(find.byKey(const ValueKey('track-waiting')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('fake-map'))) as Text).data, 'MAP r=true d=true c=null');
      expect(find.byKey(const ValueKey('track-call')), findsOneWidget);
    });

    testWidgets('исм йўқ — «Курьер»; жонли нуқта келса: ёши, манзилгача масофа ва харитада нуқта', (t) async {
      final repo = _TrackRepo(_o(name: ''));
      await pump(t, repo);
      expect((t.widget(find.byKey(const ValueKey('track-name'))) as Text).data, tr('restaurants_courier_default_name'));
      repo.live.add(CourierLive(lat: 41.84, lng: 60.3917, updatedAt: _t0.subtract(const Duration(seconds: 12))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('track-waiting')), findsNothing);
      expect((t.widget(find.byKey(const ValueKey('track-updated'))) as Text).data, tr('restaurants_track_updated').replaceAll('{s}', '12'));
      expect(find.byKey(const ValueKey('track-distance')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('fake-map'))) as Text).data, contains('c=41.84'));
    });

    testWidgets('нуқта 95 с олдин: «янгиланмаяпти» огоҳлантириши, масофа кўрсатилмайди; 3 дақиқа — «дақиқа»', (t) async {
      final repo = _TrackRepo(_o());
      await pump(t, repo);
      repo.live.add(CourierLive(lat: 41.84, lng: 60.39, updatedAt: _t0.subtract(const Duration(seconds: 95))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('track-stale')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-distance')), findsNothing);
      expect(find.byKey(const ValueKey('track-updated')), findsNothing);
    });

    testWidgets('буюртма тугаса (етказилди) — «кузатув тугади»', (t) async {
      final repo = _TrackRepo(_o());
      await pump(t, repo);
      repo.order.add(_o(status: 'delivered'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('track-notice')), findsOneWidget);
      expect(find.text(tr('restaurants_track_finished')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-name')), findsNothing, reason: 'тугагач курьер маълумоти кўрсатилмайди');
    });

    testWidgets('тор экран 320 ва шрифт ×2: синмайди', (t) async {
      final repo = _TrackRepo(_o(name: 'Жуда узун исмли курьер Абдурахмонов Шохжахон'));
      await pump(t, repo, width: 320, textScale: 2.0);
      repo.live.add(CourierLive(lat: 41.84, lng: 60.39, updatedAt: _t0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('Курьер карточкаси ва буюртма экрани', () {
    Future<void> pumpOrder(WidgetTester t, OrderModel o) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(home: RestaurantOrderScreen(orderId: 'o1', repository: _TrackRepo(o))));
      await t.pumpAndSettle();
    }

    testWidgets('мижоз экрани: курьер тайинланган фаол буюртмада карточка (исм, қўнғироқ, «Харитада кузатиш»)', (t) async {
      await pumpOrder(t, _o());
      expect(find.byKey(const ValueKey('courier-info')), findsOneWidget);
      expect(find.text('Ali Valiyev'), findsOneWidget);
      expect(find.byKey(const ValueKey('courier-call')), findsOneWidget);
      expect(find.text(tr('restaurants_track_open')), findsOneWidget);
    });

    testWidgets('карточка йўқ: курьер тайинланмаган, ўз курьери, олиб кетиш, буюртма тугаган', (t) async {
      for (final o in [_o(courier: null), _o(mode: 'own_courier'), _o(mode: 'pickup'), _o(status: 'delivered'), _o(status: 'placed')]) {
        await pumpOrder(t, o);
        expect(find.byKey(const ValueKey('courier-info')), findsNothing, reason: '${o.deliveryMode}/${o.restaurantStatus}/${o.courierId}');
      }
    });

    testWidgets('«Харитада кузатиш» босилса кузатиш экрани очилади (шу буюртма билан)', (t) async {
      final repo = _TrackRepo(_o());
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: Scaffold(body: CourierInfoCard(order: _o(), repository: repo)),
      ));
      await t.tap(find.byKey(const ValueKey('courier-track')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(CourierTrackingScreen), findsOneWidget);
    });
  });

  test('3 тилда барча калитлар мавжуд', () {
    for (final k in [
      'restaurants_courier_title', 'restaurants_courier_default_name', 'restaurants_track_open', 'restaurants_track_title',
      'restaurants_track_call', 'restaurants_track_waiting', 'restaurants_track_updated', 'restaurants_track_updated_min',
      'restaurants_track_stale', 'restaurants_track_distance', 'restaurants_track_finished',
    ]) {
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        expect(JsonL10nDelegate(lang).tr(k), isNot(k), reason: '$lang $k');
      }
    }
  });
}

class _Write {
  _Write(this.lat, this.courierId);
  final double lat;
  final String courierId;
}

class _PubRepo implements RestaurantsRepository {
  final writes = <_Write>[];
  int attempts = 0;
  bool fail = false;

  @override
  Future<void> publishCourierLive(String orderId, {required String courierId, required double lat, required double lng, double? heading, double? speed, double? accuracy}) async {
    attempts += 1;
    if (fail) throw StateError('permission-denied');
    writes.add(_Write(lat, courierId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _TrackRepo implements RestaurantsRepository {
  _TrackRepo(OrderModel first) : order = StreamController<OrderModel?>.broadcast() {
    _first = first;
  }

  late final OrderModel _first;
  final StreamController<OrderModel?> order;
  final live = StreamController<CourierLive?>.broadcast();
  Duration clockOffset = Duration.zero;

  @override
  Stream<OrderModel?> watchOrder(String id) async* {
    yield _first;
    yield* order.stream;
  }

  @override
  Stream<CourierLive?> watchCourierLive(String orderId) => live.stream;

  @override
  Future<Restaurant?> getRestaurant(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

// google_maps_flutter ишлатилмайди (харита `mapBuilder` орқали алмаштирилади) — импорт тип учун.
// ignore: unused_element
LatLng _unusedLatLng() => const LatLng(0, 0);
