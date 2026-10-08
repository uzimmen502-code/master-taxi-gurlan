import 'package:ava_gurlan/features/admin_web/utils/module_config_changes.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Ҳудудлар ва хизматлар» нуқсонлари (эга, 2026-10-08).
void main() {
  group('cellPickChanges — ойна ёпилса катак ўзгармайди', () {
    test('ташқарига босиб ёпилган ойна (null) — override сақланади', () {
      expect(cellPickChanges(null, ModuleStatus.enabled), isFalse);
      expect(cellPickChanges(null, null), isFalse);
    });

    test('«мерос» аниқ танланса — override олиб ташланади', () {
      expect(
          cellPickChanges(const CellPick(null), ModuleStatus.enabled), isTrue);
    });

    test('ўша ҳолат қайта танланса — ўзгариш йўқ', () {
      expect(
          cellPickChanges(
              const CellPick(ModuleStatus.hidden), ModuleStatus.hidden),
          isFalse);
      expect(cellPickChanges(const CellPick(null), null), isFalse);
    });

    test('бошқа ҳолат — ўзгаради', () {
      expect(
          cellPickChanges(
              const CellPick(ModuleStatus.hidden), ModuleStatus.enabled),
          isTrue);
    });
  });

  group('diffModuleStatuses — фақат ўзгарган катаклар', () {
    const ids = ['local_taxi', 'intercity', 'marshrut', 'courier'];

    test('ўзгармаган модул юборилмайди (бутун устун қайта ёзилмайди)', () {
      final saved = {
        'local_taxi': ModuleStatus.hidden,
        'intercity': ModuleStatus.enabled,
        'marshrut': ModuleStatus.hidden,
        'courier': ModuleStatus.enabled,
      };
      final current = {...saved, 'local_taxi': ModuleStatus.enabled};
      final d = diffModuleStatuses(saved, current, ids);
      expect(d, hasLength(1));
      expect(d.single.toJson(),
          {'moduleId': 'local_taxi', 'from': 'hidden', 'to': 'enabled'});
    });

    test('мерос (null) ↔ override — wire ичида null', () {
      final saved = <String, ModuleStatus?>{'courier': ModuleStatus.enabled};
      final current = <String, ModuleStatus?>{
        'courier': null,
        'local_taxi': ModuleStatus.enabled,
      };
      final d = diffModuleStatuses(saved, current, ids);
      expect(d.map((c) => c.toJson()), [
        {'moduleId': 'local_taxi', 'from': null, 'to': 'enabled'},
        {'moduleId': 'courier', 'from': 'enabled', 'to': null},
      ]);
    });

    test('фарқ йўқ — бўш рўйхат', () {
      final m = {'local_taxi': ModuleStatus.enabled};
      expect(diffModuleStatuses(m, Map.of(m), ids), isEmpty);
    });
  });

  group('ModuleAuditEntry.fromMap — «Журнал» ёзуви', () {
    test('сервер жавоби тўлиқ ўқилади', () {
      final e = ModuleAuditEntry.fromMap({
        'actor': '998912778777',
        'scope': 'district',
        'targetId': 'gurlan',
        'source': 'admin_ui',
        'changes': [
          {'moduleId': 'local_taxi', 'from': 'hidden', 'to': 'enabled'},
          {'moduleId': 'courier', 'from': 'enabled', 'to': null},
        ],
        'enforce': null,
        'at': 1791457200000,
      });
      expect(e.actor, '998912778777');
      expect(e.scope, 'district');
      expect(e.changes.map((c) => c.toJson()), [
        {'moduleId': 'local_taxi', 'from': 'hidden', 'to': 'enabled'},
        {'moduleId': 'courier', 'from': 'enabled', 'to': null},
      ]);
      expect(e.enforceFrom, isNull);
      expect(e.at, DateTime.fromMillisecondsSinceEpoch(1791457200000));
    });

    test('enforce ўзгариши ва бўш/нотўғри майдонлар йиқитмайди', () {
      final e = ModuleAuditEntry.fromMap({
        'scope': 'global',
        'changes': 'xato',
        'enforce': {'from': true, 'to': false},
        'at': null,
      });
      expect(e.changes, isEmpty);
      expect(e.enforceFrom, isTrue);
      expect(e.enforceTo, isFalse);
      expect(e.at, isNull);
      expect(e.actor, '');
    });
  });
}
