import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Эга, 2026-10-31 («А вариант»): хизматлар (модул дарвозаси) тепада ТАНЛАНГАН ҳудуд бўйича.
/// Ҳолат: профилда Яшнобод (такси ёпиқ), тепада Гурлан танланган (Гурланда такси очиқ).
void main() {
  const defaults = ServiceModuleConfig({
    'local_taxi': ModuleStatus.hidden,
    'marshrut': ModuleStatus.hidden,
    'intercity': ModuleStatus.enabled,
  });
  const gurlan = ServiceModuleConfig({
    'local_taxi': ModuleStatus.enabled,
    'marshrut': ModuleStatus.enabled,
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServiceConfigHolder.resetForTest();
  });

  test('танланган туман (Гурлан) яшаш жойидан бошқа — шу туман созламаси ишлайди', () {
    ServiceConfigHolder.setForTest(
      defaults: defaults,
      enforce: true,
      districtId: 'yashnobod',
      activeDistrictId: 'gurlan',
      activeDistrictOverride: gurlan,
    );
    expect(ServiceConfigHolder.isOpenable('local_taxi'), isTrue);
    expect(ServiceConfigHolder.isOpenable('marshrut'), isTrue);
    expect(ServiceConfigHolder.isOpenable('intercity'), isTrue, reason: 'глобал очиқ модул ўзгармайди');
  });

  test('танланган ҳудуд йўқ — аввалгидек яшаш жойи бўйича (Яшнободда такси ёпиқ)', () {
    ServiceConfigHolder.setForTest(defaults: defaults, enforce: true, districtId: 'yashnobod');
    expect(ServiceConfigHolder.isOpenable('local_taxi'), isFalse);
    expect(ServiceConfigHolder.isVisible('marshrut'), isFalse);
  });

  test('чегара: танланган туман = яшаш жойи — яшаш жойи ва МФЙ override\'лари ишлайди', () {
    ServiceConfigHolder.setForTest(
      defaults: defaults,
      enforce: true,
      districtId: 'gurlan',
      districtOverride: gurlan,
      areaOverride: const ServiceModuleConfig({'marshrut': ModuleStatus.soon}),
      activeDistrictId: 'gurlan',
      activeDistrictOverride: const ServiceModuleConfig({'local_taxi': ModuleStatus.hidden}),
    );
    expect(ServiceConfigHolder.isOpenable('local_taxi'), isTrue, reason: 'фаол override эътиборга олинмайди');
    expect(ServiceConfigHolder.statusOf('marshrut'), ModuleStatus.soon, reason: 'МФЙ override сақланади');
  });

  test('сафарда яшаш жойининг МФЙ override\'и қўлланмайди (у яшаш жойига тегишли)', () {
    ServiceConfigHolder.setForTest(
      defaults: defaults,
      enforce: true,
      districtId: 'yashnobod',
      areaOverride: const ServiceModuleConfig({'local_taxi': ModuleStatus.enabled}),
      activeDistrictId: 'urganch_shahri',
    );
    expect(ServiceConfigHolder.isOpenable('local_taxi'), isFalse);
  });

  test('applyActiveDistrict: бўш ёки яшаш жойи — сафар режими ўчади', () async {
    ServiceConfigHolder.setForTest(
      defaults: defaults,
      enforce: true,
      districtId: 'yashnobod',
      activeDistrictId: 'gurlan',
      activeDistrictOverride: gurlan,
    );
    await ServiceConfigHolder.applyActiveDistrict('');
    expect(ServiceConfigHolder.isOpenable('local_taxi'), isFalse);
    ServiceConfigHolder.setForTest(
      defaults: defaults,
      enforce: true,
      districtId: 'yashnobod',
      activeDistrictId: 'gurlan',
      activeDistrictOverride: gurlan,
    );
    await ServiceConfigHolder.applyActiveDistrict('yashnobod');
    expect(ServiceConfigHolder.isOpenable('local_taxi'), isFalse);
  });
}
