// «Талаб ядроси» админ экрани — тоза мантиқ: сервер жавобини ўқиш ва тугма
// блоклаш сабаби. ҚОИДАНИ СЕРВЕР ҲАЛ ҚИЛАДИ (`api/core_config_admin.js`);
// бу ерда фақат тугмани олдиндан хира қилиш ва сабабни кўрсатиш.
import 'package:ava_gurlan/features/admin_web/utils/core_admin_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _overview({
  List<Map<String, dynamic>>? rows,
  Map<String, dynamic>? globalKill,
  Object? minScoreAll,
  List<Map<String, dynamic>>? audit,
  String mode = 'quote',
}) =>
    {
      'ok': true,
      'module': 'service',
      'mode': mode,
      'minProviders': 5,
      'minScoreAll': minScoreAll,
      'globalKill': globalKill ?? {'active': false, 'reason': ''},
      'rows': rows ??
          [
            {
              'regionId': 'xorazm',
              'name': 'Хоразм',
              'state': 'off',
              'providers': 5,
              'ready': true,
              'minScore': null,
              'ownConfig': false,
            },
          ],
      'audit': audit ?? [],
    };

void main() {
  group('CoreOverview.fromMap', () {
    test('асосий майдонлар', () {
      final o = CoreOverview.fromMap(_overview(minScoreAll: 0.75));
      expect(o.module, 'service');
      expect(o.minProviders, 5);
      expect(o.minScoreAll, 0.75);
      expect(o.globalKillActive, isFalse);
      expect(o.rows.single.regionId, 'xorazm');
      expect(o.rows.single.state, 'off');
      expect(o.rows.single.ready, isTrue);
    });

    test('сон (int) ҳам double бўлиб ўқилади', () {
      final o = CoreOverview.fromMap(_overview(minScoreAll: 1));
      expect(o.minScoreAll, 1.0);
    });

    test('номаълум/йўқ майдонлар йиқитмайди', () {
      final o = CoreOverview.fromMap({'rows': [{}], 'audit': [{}]});
      expect(o.minProviders, 5, reason: 'стандарт N = 5');
      expect(o.rows.single.state, 'off');
      expect(o.rows.single.providers, 0);
      expect(o.audit.single.regionId, '');
      expect(o.minScoreAll, isNull);
    });

    test('глобал kill ва сабаб', () {
      final o = CoreOverview.fromMap(
        _overview(globalKill: {'active': true, 'reason': 'incident'}),
      );
      expect(o.globalKillActive, isTrue);
      expect(o.globalKillReason, 'incident');
    });

    test('конфиг хатолари сақланади', () {
      final o = CoreOverview.fromMap(_overview(rows: [
        {
          'regionId': 'xorazm',
          'name': 'Хоразм',
          'state': 'shadow',
          'providers': 6,
          'ready': true,
          'configErrors': ['weights нотўғри'],
        }
      ]));
      expect(o.rows.single.configErrors, ['weights нотўғри']);
    });

    test('аудит: вақт, телефон ниқоби, ҳолатлар', () {
      final o = CoreOverview.fromMap(_overview(audit: [
        {
          'id': 'a1',
          'at': 1760954400000,
          'actor': '9989099****01',
          'regionId': 'xorazm',
          'from': {'state': 'off', 'minScore': null},
          'to': {'state': 'shadow', 'minScore': 0.75},
        }
      ]));
      final a = o.audit.single;
      expect(a.at, DateTime.fromMillisecondsSinceEpoch(1760954400000));
      expect(a.actor, '9989099****01');
      expect(a.fromState, 'off');
      expect(a.toState, 'shadow');
      expect(a.toMinScore, 0.75);
      expect(a.fromMinScore, isNull);
    });
  });

  group('blockReason — тугмани олдиндан хира қилиш (сервер барибир текширади)', () {
    CoreRegionRow row({
      String state = 'off',
      int providers = 5,
      double? minScore,
    }) =>
        CoreRegionRow(
          regionId: 'xorazm',
          name: 'Хоразм',
          state: state,
          providers: providers,
          ready: providers >= 5,
          minScore: minScore,
          ownConfig: false,
          configErrors: const [],
        );
    final ov = CoreOverview.fromMap(_overview());

    test('ҳозирги ҳолатнинг ўзи — блок (сабаб: current)', () {
      expect(blockReason(row(state: 'shadow'), 'shadow', ov), CoreBlock.current);
    });

    test('off ҳар доим мумкин (таклифчи 0 бўлса ҳам)', () {
      expect(blockReason(row(state: 'shadow', providers: 0), 'off', ov), isNull);
    });

    test('таклифчи N дан кам -> notEnoughProviders (shadow ва push учун)', () {
      expect(blockReason(row(providers: 4), 'shadow', ov), CoreBlock.notEnoughProviders);
      expect(blockReason(row(providers: 4, minScore: 0.7), 'push', ov), CoreBlock.notEnoughProviders);
    });

    test('таклифчи айнан N -> shadow мумкин', () {
      expect(blockReason(row(providers: 5), 'shadow', ov), isNull);
    });

    test('push: чегара йўқ -> minScoreMissing; чегара бор -> мумкин', () {
      expect(blockReason(row(), 'push', ov), CoreBlock.minScoreMissing);
      expect(blockReason(row(minScore: 0.75), 'push', ov), isNull);
    });

    test('push: dispatch режимида чегара шарт эмас', () {
      final d = CoreOverview.fromMap(_overview(mode: 'dispatch'));
      expect(blockReason(row(), 'push', d), isNull);
    });

    test('сабаб тартиби: аввал таклифчи сони, кейин чегара', () {
      expect(blockReason(row(providers: 1), 'push', ov), CoreBlock.notEnoughProviders);
    });

    test('matching_off ҳолатидан shadow га ўтиш мумкин', () {
      expect(blockReason(row(state: 'matching_off'), 'shadow', ov), isNull);
    });
  });

  group('матнлар', () {
    test('ҳолат ёрлиғи', () {
      expect(stateLabel('off'), 'Ўчиқ');
      expect(stateLabel('shadow'), 'Shadow');
      expect(stateLabel('push'), 'Push');
      expect(stateLabel('matching_off'), 'Matching ўчиқ');
      expect(stateLabel('нимадир'), 'нимадир');
    });

    test('сервер сабаб коди -> тушунарли матн', () {
      expect(serverReasonText('not_enough_providers', 'x'), contains('таклифчи'));
      expect(serverReasonText('min_score_not_calibrated', 'x'), contains('чегара'));
      expect(serverReasonText('нотаниш', 'сервер хабари'), 'сервер хабари');
      expect(serverReasonText(null, 'сервер хабари'), 'сервер хабари');
    });
  });

  group('parseMinScoreInput — чегара киритиш', () {
    test('тўғри қийматлар: 0.75, 0,75 (вергул), 1, 0.01', () {
      expect(parseMinScoreInput('0.75'), 0.75);
      expect(parseMinScoreInput('0,75'), 0.75);
      expect(parseMinScoreInput(' 1 '), 1.0);
      expect(parseMinScoreInput('0.01'), 0.01);
    });

    test('хато: 90 (фоиз), 0, манфий, матн, бўш — null (сабаб экранда)', () {
      for (final v in ['90', '0', '-0.5', '1.01', 'юқори', '', '  ', 'NaN']) {
        expect(parseMinScoreInput(v), isNull, reason: v);
      }
    });
  });
}
