import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ServiceConfigHolder.resetForTest);

  test('APK dagi yangi modul baseline da yoqilmasa ON bolmaydi', () {
    ServiceConfigHolder.setForTest(
      defaults: const ServiceModuleConfig({
        'bread': ModuleStatus.enabled,
      }),
      enforce: true,
    );
    expect(ServiceConfigHolder.statusOf('bread'), ModuleStatus.enabled);
    expect(ServiceConfigHolder.statusOf('tv_market'), ModuleStatus.hidden);
    expect(ServiceConfigHolder.statusOf('new_service_x'), ModuleStatus.hidden);
  });

  test('Gurlan override Global OFF ustidan TV Market ni ON qiladi', () {
    ServiceConfigHolder.setForTest(
      defaults: const ServiceModuleConfig({
        'tv_market': ModuleStatus.hidden,
        'dating': ModuleStatus.hidden,
      }),
      districtOverride: const ServiceModuleConfig({
        'tv_market': ModuleStatus.enabled,
      }),
      enforce: true,
    );
    expect(ServiceConfigHolder.statusOf('tv_market'), ModuleStatus.enabled);
    expect(ServiceConfigHolder.statusOf('dating'), ModuleStatus.hidden);
  });

  test('enforce=false ham yangi APK modulini avtomatik ON qilmaydi', () {
    ServiceConfigHolder.setForTest(
      defaults: const ServiceModuleConfig({
        'bread': ModuleStatus.enabled,
      }),
      enforce: false,
    );
    expect(ServiceConfigHolder.statusOf('bread'), ModuleStatus.enabled);
    expect(ServiceConfigHolder.statusOf('tv_market'), ModuleStatus.hidden);
  });
}
