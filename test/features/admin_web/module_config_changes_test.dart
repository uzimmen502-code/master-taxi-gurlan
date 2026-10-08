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
}
