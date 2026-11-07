// Жўнатувчи ва курьер учун йиғиш ҳолати виджети (эга 2026-11-07).
//
//   flutter test test/features/logistics/chain_status_banner_test.dart
//
// Делегатсиз `trMsg` калитни қайтаради (плейсхолдерсиз), шунинг учун
// қолган вақт ҳисоби `chainRemainingParts` ва соатли [clock] билан
// текширилади.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';
import 'package:ava_gurlan/features/logistics/widgets/chain_status_banner.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SizedBox(width: 360, child: child)),
  ));
  await tester.pump();
}

void main() {
  final now = DateTime(2026, 11, 7, 12);
  DateTime clock() => now;

  testWidgets('жўнатувчи, йиғилмоқда: ҳолат + муддат + пул қайтиши изоҳи', (tester) async {
    final ch = ShipmentChain(
      mode: ChainMode.assembleAll,
      state: ChainState.assembling,
      deadlineAt: now.add(const Duration(hours: 47, minutes: 30)),
      claimed: 1,
      legCount: 3,
    );
    await _pump(tester, ChainStatusBanner(chain: ch, forSender: true, clock: clock));
    expect(find.byKey(const ValueKey('chain-assembling')), findsOneWidget);
    expect(find.text('logistics_chain_assembling'), findsOneWidget);
    expect(find.text('logistics_chain_deadline'), findsOneWidget);
    expect(find.text('logistics_chain_sender_note'), findsOneWidget);
    expect(chainRemainingParts(ch.remaining(now)!), (hours: 47, minutes: 30));
  });

  testWidgets('курьер, йиғилмоқда: пул изоҳи ЙЎҚ', (tester) async {
    final ch = ShipmentChain(
      mode: ChainMode.assembleAll,
      state: ChainState.assembling,
      deadlineAt: now.add(const Duration(hours: 2)),
      claimed: 2,
      legCount: 3,
    );
    await _pump(tester, ChainStatusBanner(chain: ch, clock: clock));
    expect(find.text('logistics_chain_assembling'), findsOneWidget);
    expect(find.text('logistics_chain_sender_note'), findsNothing);
  });

  testWidgets('муддатсиз йиғилмоқда: муддат қатори йўқ', (tester) async {
    const ch = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.assembling, claimed: 0, legCount: 2);
    await _pump(tester, ChainStatusBanner(chain: ch, forSender: true, clock: clock));
    expect(find.text('logistics_chain_assembling'), findsOneWidget);
    expect(find.text('logistics_chain_deadline'), findsNothing);
  });

  testWidgets('жўнатувчи, муддат ўтди: изоҳ', (tester) async {
    const ch = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.expired, claimed: 1, legCount: 3);
    await _pump(tester, ChainStatusBanner(chain: ch, forSender: true, clock: clock));
    expect(find.byKey(const ValueKey('chain-expired')), findsOneWidget);
    expect(find.text('logistics_chain_expired_sender'), findsOneWidget);
  });

  testWidgets('жўнатувчи, қулфланди: ҳеч нарса (оддий кузатув)', (tester) async {
    const ch = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.locked, claimed: 3, legCount: 3);
    await _pump(tester, ChainStatusBanner(chain: ch, forSender: true, clock: clock));
    expect(find.byKey(const ValueKey('chain-locked')), findsNothing);
    expect(find.byKey(const ValueKey('chain-assembling')), findsNothing);
  });

  testWidgets('кетма-кет режим: ҳеч нарса', (tester) async {
    const ch = ShipmentChain(mode: ChainMode.sequential, state: ChainState.assembling);
    await _pump(tester, ChainStatusBanner(chain: ch, forSender: true, clock: clock));
    expect(find.byKey(const ValueKey('chain-assembling')), findsNothing);
  });

  testWidgets('ҳолат ўзгарса (йиғилмоқда → қулфланди) виджет янгиланади, таймер тўхтайди', (tester) async {
    final a = ShipmentChain(
      mode: ChainMode.assembleAll,
      state: ChainState.assembling,
      deadlineAt: now.add(const Duration(hours: 1)),
      claimed: 2,
      legCount: 3,
    );
    await _pump(tester, ChainStatusBanner(chain: a, clock: clock));
    expect(find.byKey(const ValueKey('chain-assembling')), findsOneWidget);
    const b = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.locked, claimed: 3, legCount: 3);
    await _pump(tester, ChainStatusBanner(chain: b, clock: clock));
    expect(find.byKey(const ValueKey('chain-locked')), findsOneWidget);
  });
}
