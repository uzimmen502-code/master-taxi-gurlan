import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/home/home_grid_layout.dart';
import 'package:ava_gurlan/features/home/home_modules_catalog.dart';
import 'package:ava_gurlan/models/home_module.dart';

void main() {
  group('HomeGridLayout.buildLayout', () {
    test('hozirgi katalog — bread/jobs yuqori, 3 taksi', () {
      final layout = HomeGridLayout.buildLayout(HomeModulesCatalog.modules);
      expect(layout.featuredLeft?.id, 'bread');
      expect(layout.featuredRight?.id, 'jobs');
      expect(layout.taxiModules.map((m) => m.id).toList(), [
        'marshrut',
        'local_taxi',
        'intercity',
      ]);
      expect(layout.extraModules, isEmpty);
    });

    test('food yoqilsa — extra qatorga tushadi', () {
      final catalog = [
        for (final m in HomeModulesCatalog.modules)
          HomeModule(
            id: m.id,
            label: m.label,
            enabled: m.id == 'food' || m.enabled,
          ),
      ];
      final layout = HomeGridLayout.buildLayout(catalog);
      expect(layout.extraModules.single.id, 'food');
    });
  });
}
