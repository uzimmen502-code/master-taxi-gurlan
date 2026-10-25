// Харидор шикояти — ресторан (маълумот варағи), таом варағи, кўчмас мулк эълони (2026-10-25, Agent B).
// Кириш эга/аъзога кўринмайди; варақ — мавжуд умумий шикоят варағи; хато матни хом эмас.

import 'package:ava_gurlan/features/admin_web/widgets/shop_complaints_panel.dart';
import 'package:ava_gurlan/features/complaints/widgets/content_complaint_button.dart';
import 'package:ava_gurlan/features/realty/screens/realty_detail_screen.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/dish_detail_sheet.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

const _owner = '998901112233';
const _rest = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved', ownerUid: _owner);
const _dish = MenuItem(id: 'osh', name: 'Osh', price: 40000);

class _Sent {
  _Sent(this.targetType, this.targetId, this.restaurantId, this.reason, this.comment);
  final String targetType, targetId, restaurantId, reason, comment;
  @override
  String toString() => '$targetType:$targetId:$restaurantId:$reason:$comment';
}

class _Submit {
  _Submit([this.error]);
  final Object? error;
  final sent = <_Sent>[];

  Future<void> call({
    required String targetType,
    required String targetId,
    String restaurantId = '',
    required String reason,
    String comment = '',
  }) async {
    sent.add(_Sent(targetType, targetId, restaurantId, reason, comment));
    if (error != null) throw error!;
  }
}

class _MenuRepo implements RestaurantsRepository {
  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(_rest);
  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) =>
      Stream.value(const [MenuCategory(id: 'c1', name: 'Asosiy', sort: 1)]);
  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) =>
      Stream.value(const [MenuItem(id: 'osh', name: 'Osh', price: 40000, categoryId: 'c1')]);
  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _RealtyRepo implements RealtyRepository {
  _RealtyRepo(this.myKey);
  final String myKey;
  @override
  Future<String> myOwnerKey() async => myKey;
  @override
  Future<RealtyDetail?> fetchDetail(String listingId) async => null;
  @override
  Stream<int> watchUnlocksLeft() => Stream.value(0);
  @override
  Future<String> fetchAgentPhone() async => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

RealtyListing _listing({String ownerKey = 'k_owner'}) => RealtyListing(
      id: 'L1',
      ownerKey: ownerKey,
      ownerName: 'Эга',
      deal: RealtyDeal.rent,
      tier: RealtyTier.plain,
      title: 'Икки хонали',
      text: 'Таъмирланган',
      areaLat: 41.85,
      areaLng: 60.39,
      status: 'active',
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);
  final entry = find.byKey(const ValueKey('content_report_entry'));

  setUp(ContentComplaintButton.clearMemberCache);

  Future<void> pumpButton(WidgetTester t, ContentComplaintButton button) async {
    await t.pumpWidget(l10nApp(home: Scaffold(body: Center(child: button))));
    await t.pumpAndSettle();
  }

  Future<void> pick(WidgetTester t, String labelKey) async {
    await t.tap(entry);
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('content_report_$labelKey')));
    await t.pumpAndSettle();
  }

  group('Кўриниш: эга/аъзога йўқ', () {
    testWidgets('эга (isMine true) — тугма йўқ; бегона — бор', (t) async {
      await pumpButton(t, ContentComplaintButton.restaurant(restaurant: _rest, isMine: () async => true));
      expect(entry, findsNothing);
      await pumpButton(t, ContentComplaintButton.restaurant(key: UniqueKey(), restaurant: _rest, isMine: () async => false));
      expect(entry, findsOneWidget);
      expect(find.text(tr('content_report_entry')), findsOneWidget);
    });

    testWidgets('эгалик аниқланмагунча тугма кўринмайди; хато — бегона деб ҳисобланади', (t) async {
      await pumpButton(t, ContentComplaintButton.restaurant(restaurant: _rest, isMine: () => Future.delayed(const Duration(seconds: 1), () => false)));
      expect(entry, findsNothing);
      await t.pump(const Duration(seconds: 1));
      expect(entry, findsOneWidget);
      await pumpButton(t, ContentComplaintButton.restaurant(key: UniqueKey(), restaurant: _rest, isMine: () async => throw StateError('x')));
      expect(entry, findsOneWidget);
    });

    test('restaurantIsMine: эга телефони (+998/9 хона), аъзо, бегона, логинсиз, рад этилган ўқиш', () async {
      Future<bool> member(String rid, String phone) async => phone == '998905556677';
      expect(await ContentComplaintButton.restaurantIsMine(_rest, me: '998901112233', memberLookup: member), isTrue);
      expect(await ContentComplaintButton.restaurantIsMine(_rest, me: '901112233', memberLookup: member), isTrue);
      expect(await ContentComplaintButton.restaurantIsMine(_rest, me: '998905556677', memberLookup: member), isTrue);
      expect(await ContentComplaintButton.restaurantIsMine(_rest, me: '998909999999', memberLookup: member), isFalse);
      expect(await ContentComplaintButton.restaurantIsMine(_rest, me: '', memberLookup: member), isFalse);
      Future<bool> denied(String rid, String phone) async =>
          throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      expect(await ContentComplaintButton.restaurantIsMine(_rest, me: '998908888888', memberLookup: denied), isFalse);
    });

    test('realtyIsMine: бир хил калит (жамоа ҳам) — ҳа; бошқа/бўш/хато — йўқ', () async {
      expect(await ContentComplaintButton.realtyIsMine(_listing(), () async => 'k_owner'), isTrue);
      expect(await ContentComplaintButton.realtyIsMine(_listing(), () async => 'k_other'), isFalse);
      expect(await ContentComplaintButton.realtyIsMine(_listing(), () async => ''), isFalse);
      expect(await ContentComplaintButton.realtyIsMine(_listing(ownerKey: ''), () async => ''), isFalse);
      expect(await ContentComplaintButton.realtyIsMine(_listing(), () async => throw StateError('x')), isFalse);
    });
  });

  group('Юбориш ва хато матнлари', () {
    testWidgets('таом: сабаб коди, restaurantId билан юборилади → «юборилди»', (t) async {
      final s = _Submit();
      await pumpButton(t, ContentComplaintButton.dish(restaurant: _rest, item: _dish, isMine: () async => false, submit: s.call));
      await pick(t, 'content_report_reason_fraud');
      expect(s.sent.map((e) => '$e'), ['restaurant_item:osh:r1:fraud:']);
      expect(find.text(tr('ad_report_sent')), findsOneWidget);
    });

    testWidgets('сабаб рўйхати — 5 та, сервер кодлари билан бир хил тартибда', (t) async {
      expect([for (final r in contentComplaintReasons) r.value], ['fraud', 'wrong_info', 'spam', 'abuse', 'other']);
      await pumpButton(t, ContentComplaintButton.restaurant(restaurant: _rest, isMine: () async => false, submit: _Submit().call));
      await t.tap(entry);
      await t.pumpAndSettle();
      for (final r in contentComplaintReasons) {
        expect(find.text(tr(r.labelKey)), findsOneWidget, reason: r.labelKey);
      }
    });

    testWidgets('«Бошқа сабаб»: изоҳ сўралади, 3 белгидан кам — юбориш ўчиқ; изоҳ билан юборилади', (t) async {
      final s = _Submit();
      await pumpButton(t, ContentComplaintButton.realty(listing: _listing(), ownerKeyLoader: () async => 'k_me', submit: s.call));
      await pick(t, 'content_report_reason_other');
      final send = find.byKey(const ValueKey('complaint_comment_send'));
      expect(t.widget<FilledButton>(send).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('complaint_comment_field')), 'ab');
      await t.pump();
      expect(t.widget<FilledButton>(send).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('complaint_comment_field')), '  Uy boshqa joyda  ');
      await t.pump();
      await t.tap(send);
      await t.pumpAndSettle();
      expect(s.sent.map((e) => '$e'), ['realty_listing:L1::other:Uy boshqa joyda']);
      expect(find.text(tr('ad_report_sent')), findsOneWidget);
    });

    testWidgets('изоҳ ойнасини бекор қилиш — ҳеч нарса юборилмайди', (t) async {
      final s = _Submit();
      await pumpButton(t, ContentComplaintButton.restaurant(restaurant: _rest, isMine: () async => false, submit: s.call));
      await pick(t, 'content_report_reason_other');
      await t.tap(find.text(tr('cancel')));
      await t.pumpAndSettle();
      expect(s.sent, isEmpty);
    });

    final cases = <(String, FirebaseFunctionsException, String)>[
      ('ўзиники', FirebaseFunctionsException(message: 'COMPLAINT_OWN', code: 'failed-precondition', details: {'code': 'COMPLAINT_OWN'}), 'content_report_own'),
      ('яширилган', FirebaseFunctionsException(message: 'x', code: 'not-found', details: {'code': 'COMPLAINT_TARGET_NOT_FOUND'}), 'content_report_unavailable'),
      ('чеклов', FirebaseFunctionsException(message: 'x', code: 'resource-exhausted', details: {'code': 'COMPLAINT_LIMIT'}), 'ad_report_limit'),
      ('логинсиз', FirebaseFunctionsException(message: 'x', code: 'unauthenticated'), 'shop_report_need_login'),
      ('бошқа хато', FirebaseFunctionsException(message: 'INTERNAL stack', code: 'internal', details: {'code': 'INTERNAL'}), 'shop_report_failed'),
    ];
    for (final (name, err, key) in cases) {
      testWidgets('хато: $name → тушунарли матн, хом матн йўқ', (t) async {
        await pumpButton(t, ContentComplaintButton.restaurant(restaurant: _rest, isMine: () async => false, submit: _Submit(err).call));
        await pick(t, 'content_report_reason_fraud');
        expect(find.text(tr(key)), findsOneWidget);
        expect(find.textContaining('INTERNAL'), findsNothing);
        expect(find.textContaining('COMPLAINT_'), findsNothing);
      });
    }
  });

  group('Экранлардаги кириш', () {
    testWidgets('ресторан: «Маълумот» варағида тугма; босилса варақ ёпилиб, сабаб варағи очилади', (t) async {
      await t.pumpWidget(l10nApp(
        home: RestaurantScreen(
          restaurant: _rest,
          repository: _MenuRepo(),
          cart: RestaurantCart(),
          itemClipsLoader: (_) async => const {},
          restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => const {},
        ),
      ));
      await t.pumpAndSettle();
      expect(entry, findsNothing, reason: 'асосий экранда эмас — маълумот варағида');
      await t.tap(find.byIcon(Icons.info_outline_rounded));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('content_report_restaurant')), findsOneWidget);
      await t.tap(entry);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('content_report_restaurant')), findsNothing, reason: 'маълумот варағи ёпилди');
      expect(find.text(tr('content_report_reason_wrong_info')), findsOneWidget);
    });

    testWidgets('таом варағи: тугма бор; босилса варақ ёпилиб, сабаб варағи очилади', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(l10nApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))));
      showDishDetailSheet(ctx, item: _dish, restaurant: _rest, cart: RestaurantCart());
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('content_report_dish')), findsOneWidget);
      await t.ensureVisible(entry);
      await t.tap(entry);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing, reason: 'таом варағи ёпилди');
      expect(find.text(tr('content_report_reason_fraud')), findsOneWidget);
    });

    testWidgets('кўчмас мулк: бегонага тугма бор, эгага (бир хил калит) — йўқ', (t) async {
      await t.pumpWidget(l10nApp(home: RealtyDetailScreen(listing: _listing(), repository: _RealtyRepo('k_buyer'))));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('content_report_realty')), findsOneWidget);

      await t.pumpWidget(l10nApp(home: RealtyDetailScreen(key: UniqueKey(), listing: _listing(), repository: _RealtyRepo('k_owner'))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('content_report_realty')), findsOneWidget, reason: 'виджет бор, лекин…');
      expect(entry, findsNothing, reason: 'эгага кириш кўринмайди');
    });
  });

  group('Админ: умумий шикоят панели (ресторан / кўчмас мулк)', () {
    testWidgets('ресторан/таом: сабаб коди матнга, изоҳ, «Ресторан:/Таом:»; эга телефони йўқ; «Ҳал қилинди»', (t) async {
      final src = _FakeComplaints([
        const ShopComplaint(id: 'a', targetType: 'restaurant', targetId: 'r1', ownerPhone: '', title: 'Gurlan osh', reason: 'wrong_info', reporterId: '998900000001', restaurantId: 'r1', comment: 'Narx boshqa'),
        const ShopComplaint(id: 'b', targetType: 'restaurant_item', targetId: 'osh', ownerPhone: '', title: 'Osh', reason: 'fraud', reporterId: '998900000002', restaurantId: 'r1'),
      ]);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [ShopComplaintsPanel(source: src, maxListHeight: 240)]))));
      await t.pumpAndSettle();
      expect(find.text('Очиқ шикоятлар: 2'), findsOneWidget);
      expect(find.text('Нотўғри маълумот: Narx boshqa'), findsOneWidget);
      expect(find.text('Алдов ёки фирибгарлик'), findsOneWidget);
      expect(find.textContaining('Ресторан: Gurlan osh'), findsOneWidget);
      expect(find.textContaining('Таом: Osh'), findsOneWidget);
      expect(find.textContaining('эга:'), findsNothing);
      expect(find.text('Дўконни очиш'), findsNothing, reason: 'дўкон амали фақат дўкон бўлимида');
      await t.tap(find.byKey(const ValueKey('shop_complaint_resolve_a')));
      await t.pumpAndSettle();
      expect(src.resolved, ['a']);
    });

    testWidgets('кўчмас мулк: модул амали («Блоклаш») бажарилгач шикоят ҳам ёпилади; амал хатоси — ёпилмайди, хом матнсиз', (t) async {
      final src = _FakeComplaints([
        const ShopComplaint(id: 'L', targetType: 'realty_listing', targetId: 'L1', ownerPhone: '', title: 'Uy', reason: 'spam', reporterId: '998900000003'),
      ]);
      final blocked = <String>[];
      var fail = true;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ShopComplaintsPanel(
        source: src,
        action: (label: 'Блоклаш', run: (_, c) async {
          if (fail) throw StateError('permission-denied raw');
          blocked.add(c.targetId);
        }),
      ))));
      await t.pumpAndSettle();
      expect(find.textContaining('Эълон: Uy'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('shop_complaint_action_L')));
      await t.pumpAndSettle();
      expect(src.resolved, isEmpty);
      expect(find.textContaining('permission-denied'), findsNothing);
      fail = false;
      await t.tap(find.byKey(const ValueKey('shop_complaint_action_L')));
      await t.pumpAndSettle();
      expect(blocked, ['L1']);
      expect(src.resolved, ['L']);
    });
  });
}

class _FakeComplaints implements ShopComplaintsSource {
  _FakeComplaints(this.list);
  final List<ShopComplaint> list;
  final resolved = <String>[];
  @override
  Stream<List<ShopComplaint>> watchOpen() => Stream.value(list);
  @override
  Future<void> resolve(BuildContext context, String reportId) async => resolved.add(reportId);
}
