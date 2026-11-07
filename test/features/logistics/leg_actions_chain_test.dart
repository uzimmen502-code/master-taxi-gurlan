// Курьер экрани: йўл бўлакларини йиғиш (эга 2026-11-07).
//
//   flutter test test/features/logistics/leg_actions_chain_test.dart
//
// Локализация делегати атайлаб йўқ (`service_ui_adapter_test` изоҳи):
// `context.tr(key)` калитнинг ўзини қайтаради — тест калитларга қарайди.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/logistics/data/logistics_repository.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';
import 'package:ava_gurlan/features/logistics/ui/leg_actions.dart';

const _me = 'K1';

class _FakeRepo implements LogisticsRepository {
  _FakeRepo(this.shipment);

  final Shipment? shipment;
  final List<Map<String, Object?>> scans = [];
  final List<String> givenBack = [];

  @override
  Stream<Shipment?> watchShipment(String shipmentId) => Stream.value(shipment);

  @override
  Future<void> giveBackLeg(String legId) async => givenBack.add(legId);

  @override
  Future<Map<String, dynamic>> scanHandover({
    required String legId,
    String? code,
    String? qrPayload,
    required List<String> photoUrls,
    List<String> conditionFlags = const [ConditionFlags.intact],
    double? lat,
    double? lng,
    double? accuracy,
    bool selfTransfer = false,
  }) async {
    scans.add({'legId': legId, 'code': code, 'photoUrls': photoUrls, 'selfTransfer': selfTransfer});
    return const {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DemandMatch _match({
  required String status,
  int legIndex = 1,
  int legCount = 3,
  String? chainMode,
  String demandId = 'L1',
}) =>
    DemandMatch.fromMap('${demandId}_$_me', {
      'demandId': demandId,
      'providerId': _me,
      'module': 'logistics',
      'mode': 'quote',
      'status': status,
      'score': 0.5,
      'createdAt': '2026-11-07T08:00:00.000Z',
      'expiresAt': '2026-11-20T08:00:00.000Z',
      'projection': {
        'title': 'Jo\'natma AVA-1',
        'attributes': {
          'shipmentId': 'S1',
          'trackingNumber': 'AVA-1',
          'legKind': 'line_haul',
          'legIndex': legIndex,
          'legCount': legCount,
          'payout': 20000,
          if (chainMode != null) 'chainMode': chainMode,
        },
      },
    });

Shipment _ship({
  Map<String, dynamic>? chain,
  Map<String, String> assignments = const {},
  Map<String, dynamic>? custodian,
  String currentLegId = '',
}) =>
    Shipment.fromMap('S1', {
      'orderId': 'O1',
      'ownerId': 'U1',
      'trackingNumber': 'AVA-1',
      'status': 'ready',
      'paymentStatus': 'escrow_funded',
      'legIds': ['L0', 'L1', 'L2'],
      'legCount': 3,
      if (chain != null) 'chain': chain,
      'legAssignments': assignments,
      if (custodian != null) 'currentCustodian': custodian,
      if (currentLegId.isNotEmpty) 'currentLegId': currentLegId,
    });

Map<String, dynamic> _chain(String state, {int claimed = 2, List<String> selfTransferLegIds = const []}) => {
      'mode': 'assemble_all',
      'state': state,
      'deadlineAt': DateTime.now().add(const Duration(hours: 40)),
      'lockedAt': state == 'locked' ? DateTime.now() : null,
      'claimed': claimed,
      'legCount': 3,
      'selfTransferLegIds': selfTransferLegIds,
    };

Future<void> _pump(WidgetTester tester, DemandMatch match, _FakeRepo repo) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: LogisticsLegActions(match: match, providerId: _me, repository: repo),
        ),
      ),
    ),
  ));
  await tester.pump(); // stream биринчи қиймати
  await tester.pump();
}

void main() {
  testWidgets('йиғилмоқда: олиш ЙЎҚ, ҳолат + «Бўлакни қайтариш» бор', (tester) async {
    final repo = _FakeRepo(_ship(chain: _chain('assembling'), assignments: {'L1': _me}));
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('logistics-pickup')), findsNothing);
    expect(find.text('logistics_picked_up_btn'), findsNothing);
    expect(find.byKey(const ValueKey('chain-assembling')), findsOneWidget);
    expect(find.text('logistics_chain_assembling'), findsOneWidget);
    expect(find.text('logistics_chain_wait_pickup'), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-give-back')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chain-give-back')));
    await tester.pumpAndSettle();
    expect(find.text('logistics_chain_give_back_confirm'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chain-give-back-yes')));
    await tester.pumpAndSettle();
    expect(repo.givenBack, ['L1']);
    expect(find.text('logistics_chain_given_back'), findsOneWidget);
  });

  testWidgets('қулфланди: олиш БОР, «қайтариш» ЙЎҚ', (tester) async {
    final repo = _FakeRepo(_ship(chain: _chain('locked', claimed: 3), assignments: {'L1': _me}));
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('logistics-pickup')), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-give-back')), findsNothing);
    expect(find.byKey(const ValueKey('chain-locked')), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-self-continue')), findsNothing);
  });

  testWidgets('муддат ўтди: амал йўқ, изоҳ бор', (tester) async {
    final repo = _FakeRepo(_ship(chain: _chain('expired')));
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('logistics-pickup')), findsNothing);
    expect(find.byKey(const ValueKey('chain-give-back')), findsNothing);
    expect(find.text('logistics_chain_expired_provider'), findsOneWidget);
  });

  testWidgets('эски жўнатма (chain йўқ): аввалгидек олиш, янги элементлар йўқ', (tester) async {
    final repo = _FakeRepo(_ship());
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('logistics-pickup')), findsOneWidget);
    expect(find.text('logistics_code_hint'), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-give-back')), findsNothing);
    expect(find.byKey(const ValueKey('chain-assembling')), findsNothing);
    expect(find.byKey(const ValueKey('chain-locked')), findsNothing);
  });

  testWidgets('олдинги бўлак ҳам менда ва посилка қўлимда: бир тап давом эттириш (selfTransfer)', (tester) async {
    final repo = _FakeRepo(_ship(
      // Занжирда сервер `legAssignments` ёзмайди — фақат телефонсиз `selfTransferLegIds`.
      chain: _chain('locked', claimed: 3, selfTransferLegIds: ['L1']),
      custodian: {'kind': 'provider', 'id': _me},
      currentLegId: 'L0',
    ));
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('chain-self-continue')), findsOneWidget);
    expect(find.byKey(const ValueKey('logistics-pickup')), findsNothing);
    expect(find.text('logistics_chain_self_hint'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chain-self-continue')));
    await tester.pumpAndSettle();
    expect(repo.scans, hasLength(1));
    expect(repo.scans.single['legId'], 'L1');
    expect(repo.scans.single['selfTransfer'], isTrue);
    expect(repo.scans.single['code'], isNull);
    expect(repo.scans.single['photoUrls'], isEmpty);
    expect(find.text('logistics_chain_self_done'), findsOneWidget);
  });

  testWidgets('олдинги бўлак бошқа курьерда: давом эттириш ЙЎҚ, оддий олиш', (tester) async {
    final repo = _FakeRepo(_ship(
      chain: _chain('locked', claimed: 3),
      assignments: {'L0': 'K9', 'L1': _me},
      custodian: {'kind': 'provider', 'id': 'K9'},
      currentLegId: 'L0',
    ));
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('chain-self-continue')), findsNothing);
    expect(find.byKey(const ValueKey('logistics-pickup')), findsOneWidget);
  });

  testWidgets('олдинги бўлак менда, лекин посилка ҳали олинмаган: давом эттириш ЙЎҚ', (tester) async {
    final repo = _FakeRepo(_ship(
      chain: _chain('locked', claimed: 3, selfTransferLegIds: ['L1']),
      custodian: {'kind': 'sender', 'id': 'U1'},
    ));
    await _pump(tester, _match(status: 'accepted'), repo);

    expect(find.byKey(const ValueKey('chain-self-continue')), findsNothing);
  });

  testWidgets('эълон (new): йиғиш режими изоҳи', (tester) async {
    final repo = _FakeRepo(null);
    await _pump(tester, _match(status: 'new', chainMode: 'assemble_all'), repo);
    expect(find.text('logistics_leg_take'), findsOneWidget);
    expect(find.text('logistics_chain_offer_hint'), findsOneWidget);
  });

  testWidgets('жўнатма ҳали ўқилмаган, проекция йиғиш дейди: олиш ёпиқ (loading)', (tester) async {
    final ctrl = StreamController<Shipment?>();
    addTearDown(ctrl.close);
    final repo = _PendingRepo(ctrl.stream);
    await _pump(tester, _match(status: 'accepted', chainMode: 'assemble_all'), repo);
    expect(find.byKey(const ValueKey('chain-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('logistics-pickup')), findsNothing);
  });
}

class _PendingRepo extends _FakeRepo {
  _PendingRepo(this.stream) : super(null);
  final Stream<Shipment?> stream;

  @override
  Stream<Shipment?> watchShipment(String shipmentId) => stream;
}
