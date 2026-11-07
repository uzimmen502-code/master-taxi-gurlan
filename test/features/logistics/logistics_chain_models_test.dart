// Йўл бўлакларини йиғиш (эга 2026-11-07) — модел, дарвоза, хато калитлари,
// 3 тилдаги матнлар.
//
//   flutter test test/features/logistics/logistics_chain_models_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/logistics/data/logistics_repository.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';
import 'package:ava_gurlan/features/logistics/ui/logistics_text.dart';

Map<String, dynamic> _ship({Object? chain, Map<String, dynamic>? extra}) => {
      'orderId': 'O1',
      'ownerId': 'U1',
      'trackingNumber': 'AVA-1',
      'status': 'ready',
      'paymentStatus': 'escrow_funded',
      'legIds': ['L0', 'L1', 'L2'],
      'legCount': 3,
      if (chain != null) 'chain': chain,
      ...?extra,
    };

void main() {
  group('ShipmentChain.fromMap', () {
    test('chain йўқ — null (эски жўнатма, эски хулқ)', () {
      final s = Shipment.fromMap('S1', _ship());
      expect(s.chain, isNull);
      expect(s.legAssignments, isEmpty);
      expect(s.currentLegId, '');
    });

    test('chain Map эмас (бузилган) — null, қулаб тушмайди', () {
      expect(Shipment.fromMap('S1', _ship(chain: 'oops')).chain, isNull);
      expect(Shipment.fromMap('S1', _ship(chain: 42)).chain, isNull);
    });

    test('тўлиқ assemble_all / assembling', () {
      final deadline = DateTime.utc(2026, 11, 9, 10);
      final s = Shipment.fromMap(
        'S1',
        _ship(chain: {
          'mode': 'assemble_all',
          'state': 'assembling',
          'deadlineAt': deadline,
          'lockedAt': null,
          'claimed': 2,
          'legCount': 3,
        }),
      );
      final ch = s.chain!;
      expect(ch.mode, ChainMode.assembleAll);
      expect(ch.state, ChainState.assembling);
      expect(ch.isAssembling, isTrue);
      expect(ch.isLocked, isFalse);
      expect(ch.isGated, isTrue);
      expect(ch.deadlineAt, deadline);
      expect(ch.lockedAt, isNull);
      expect(ch.claimed, 2);
      expect(ch.legCount, 3);
    });

    test('Timestamp ўрнига toDate() берувчи объект ва ISO сатр', () {
      final ch = ShipmentChain.fromMap({
        'mode': 'assemble_all',
        'state': 'locked',
        'deadlineAt': '2026-11-09T10:00:00Z',
        'lockedAt': _FakeTs(DateTime.utc(2026, 11, 8, 9)),
        'claimed': 3,
        'legCount': 3,
      })!;
      expect(ch.isLocked, isTrue);
      expect(ch.lockedAt, DateTime.utc(2026, 11, 8, 9));
      expect(ch.deadlineAt, DateTime.utc(2026, 11, 9, 10));
    });

    test('номаълум mode/state — unknown, дарвоза йўқ (эски хулқ)', () {
      final a = ShipmentChain.fromMap({'mode': 'turbo', 'state': 'assembling'})!;
      expect(a.mode, ChainMode.unknown);
      expect(a.isAssembling, isFalse);
      expect(a.isGated, isFalse);
      final b = ShipmentChain.fromMap({'mode': 'assemble_all', 'state': 'weird'})!;
      expect(b.state, ChainState.unknown);
      expect(b.isGated, isFalse);
    });

    test('sequential — дарвоза йўқ', () {
      final ch = ShipmentChain.fromMap({'mode': 'sequential', 'state': 'assembling'})!;
      expect(ch.mode, ChainMode.sequential);
      expect(ch.isAssembling, isFalse);
      expect(ch.isGated, isFalse);
    });

    test('манфий/сатр сонлар — хавфсиз', () {
      final ch = ShipmentChain.fromMap({'mode': 'assemble_all', 'state': 'assembling', 'claimed': -1, 'legCount': '3'})!;
      expect(ch.claimed, 0);
      expect(ch.legCount, anyOf(0, 3));
    });

    test('remaining: муддат йўқ — null; ўтган — 0; чегара', () {
      final now = DateTime.utc(2026, 11, 7, 12);
      expect(const ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.assembling).remaining(now), isNull);
      final past = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.assembling, deadlineAt: now.subtract(const Duration(minutes: 1)));
      expect(past.remaining(now), Duration.zero);
      final exact = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.assembling, deadlineAt: now);
      expect(exact.remaining(now), Duration.zero);
      final h48 = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.assembling, deadlineAt: now.add(const Duration(hours: 48)));
      expect(h48.remaining(now), const Duration(hours: 48));
    });
  });

  group('chainRemainingParts', () {
    test('соат/дақиқа, дақиқа юқорига яхлитланади', () {
      expect(chainRemainingParts(const Duration(hours: 47, minutes: 5)), (hours: 47, minutes: 5));
      expect(chainRemainingParts(const Duration(minutes: 4, seconds: 1)), (hours: 0, minutes: 5));
      expect(chainRemainingParts(Duration.zero), (hours: 0, minutes: 0));
      expect(chainRemainingParts(const Duration(seconds: -5)), (hours: 0, minutes: 0));
    });
  });

  group('Shipment: legAssignments, currentLegId', () {
    test('ким қайси бўлакни ушлаб турибди', () {
      final s = Shipment.fromMap(
        'S1',
        _ship(extra: {
          'legAssignments': {'L0': 'K1', 'L1': 'K1', 'L2': null},
          'currentLegId': 'L0',
        }),
      );
      expect(s.legAssignments, {'L0': 'K1', 'L1': 'K1'});
      expect(s.holderOfLegIndex(0), 'K1');
      expect(s.holderOfLegIndex(1), 'K1');
      expect(s.holderOfLegIndex(2), isNull);
      expect(s.holderOfLegIndex(-1), isNull);
      expect(s.holderOfLegIndex(3), isNull);
      expect(s.currentLegId, 'L0');
    });
  });

  group('LegProjection.chainMode', () {
    test('бор / йўқ / номаълум', () {
      expect(LegProjection.fromAttributes({'chainMode': 'assemble_all'}).chainMode, ChainMode.assembleAll);
      expect(LegProjection.fromAttributes({'chainMode': 'sequential'}).chainMode, ChainMode.sequential);
      expect(LegProjection.fromAttributes(const {}).chainMode, ChainMode.unknown);
      expect(LegProjection.fromAttributes(null).chainMode, ChainMode.unknown);
    });
  });

  group('legChainGate', () {
    const assembling = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.assembling);
    const locked = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.locked);
    const expired = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.expired);
    const cancelled = ShipmentChain(mode: ChainMode.assembleAll, state: ChainState.cancelled);
    const seq = ShipmentChain(mode: ChainMode.sequential, state: ChainState.unknown);

    LegChainGate g(ShipmentChain? c, {ChainMode p = ChainMode.unknown, bool loaded = true}) =>
        legChainGate(chain: c, projectionMode: p, shipmentLoaded: loaded);

    test('йиғиш ҳолатлари', () {
      expect(g(assembling), LegChainGate.assembling);
      expect(g(locked), LegChainGate.locked);
      expect(g(expired), LegChainGate.closed);
      expect(g(cancelled), LegChainGate.closed);
    });

    test('эски хулқ: chain йўқ ёки sequential', () {
      expect(g(null), LegChainGate.none);
      expect(g(seq), LegChainGate.none);
      expect(g(null, p: ChainMode.sequential, loaded: false), LegChainGate.none);
    });

    test('проекция йиғиш дейди, жўнатма ҳали ўқилмаган — loading; ўқиб бўлмаса — none (сервер ҳал қилади)', () {
      expect(g(null, p: ChainMode.assembleAll, loaded: false), LegChainGate.loading);
      expect(g(null, p: ChainMode.assembleAll, loaded: true), LegChainGate.none);
    });
  });

  group('Хато калитлари', () {
    LogisticsException e(String reason) => LogisticsException('failed-precondition', reason, 'm');

    test('CHAIN_* → logistics_chain_err_*', () {
      expect(logisticsErrorKey(e('CHAIN_LOCKED')), 'logistics_chain_err_locked');
      expect(logisticsErrorKey(e('CHAIN_NOT_LOCKED')), 'logistics_chain_err_not_locked');
      expect(logisticsErrorKey(e('CHAIN_EXPIRED')), 'logistics_chain_err_expired');
      // Бошқалар ўзгармайди.
      expect(logisticsErrorKey(e('photo_url_invalid')), 'logistics_err_photo_url_invalid');
    });
  });

  group('3 тилда матн бор, ички сўзлар йўқ (45-банд)', () {
    const keys = [
      'logistics_chain_assembling',
      'logistics_chain_deadline',
      'logistics_chain_left',
      'logistics_chain_sender_note',
      'logistics_chain_expired_sender',
      'logistics_chain_expired_provider',
      'logistics_chain_locked',
      'logistics_chain_wait_pickup',
      'logistics_chain_give_back',
      'logistics_chain_give_back_confirm',
      'logistics_chain_given_back',
      'logistics_chain_self_continue',
      'logistics_chain_self_hint',
      'logistics_chain_self_done',
      'logistics_chain_next_is_mine',
      'logistics_chain_offer_hint',
      'logistics_chain_err_locked',
      'logistics_chain_err_not_locked',
      'logistics_chain_err_expired',
    ];
    for (final lang in const ['uz_Cyrl', 'uz_Latn', 'ru']) {
      test(lang, () {
        final m = json.decode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final k in keys) {
          expect((m[k] ?? '').toString().trim(), isNotEmpty, reason: '$lang: $k');
        }
        for (final k in kLogisticsChainErrorKeys.values) {
          expect(m.containsKey(k), isTrue, reason: '$lang: $k');
        }
        final all = keys.map((k) => m[k].toString().toLowerCase()).join(' ');
        for (final bad in ['leg', 'chain', 'settlement', 'zone', 'escrow', 'эскроу', 'занжир', 'zanjir']) {
          expect(all.contains(bad), isFalse, reason: '$lang: $bad');
        }
        // Плейсхолдерлар сақланган.
        expect(m['logistics_chain_assembling'], contains('{claimed}'));
        expect(m['logistics_chain_assembling'], contains('{total}'));
        expect(m['logistics_chain_deadline'], contains('{time}'));
        expect(m['logistics_chain_deadline'], contains('{left}'));
        expect(m['logistics_chain_left'], contains('{h}'));
        expect(m['logistics_chain_left'], contains('{m}'));
      });
    }
  });
}

class _FakeTs {
  _FakeTs(this._d);
  final DateTime _d;
  DateTime toDate() => _d;
}
