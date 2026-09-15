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

  group('yuk alias davri (yuk_local/yuk_intercity → yuk_birja)', () {
    test('yangi id sozlanmagan — eski yuk_birja holati meros olinadi (enforce)',
        () {
      ServiceConfigHolder.setForTest(
        defaults: const ServiceModuleConfig({
          'yuk_birja': ModuleStatus.enabled,
        }),
        enforce: true,
      );
      expect(ServiceConfigHolder.statusOf('yuk_local'), ModuleStatus.enabled);
      expect(
          ServiceConfigHolder.statusOf('yuk_intercity'), ModuleStatus.enabled);
    });

    test('yangi id sozlanmagan — eski ham sozlanmagan → hidden', () {
      ServiceConfigHolder.setForTest(
        defaults: const ServiceModuleConfig({'bread': ModuleStatus.enabled}),
        enforce: true,
      );
      expect(ServiceConfigHolder.statusOf('yuk_local'), ModuleStatus.hidden);
    });

    test('yangi id sozlangan — alias e\'tiborga olinmaydi', () {
      ServiceConfigHolder.setForTest(
        defaults: const ServiceModuleConfig({
          'yuk_birja': ModuleStatus.enabled,
          'yuk_local': ModuleStatus.hidden,
        }),
        enforce: true,
      );
      expect(ServiceConfigHolder.statusOf('yuk_local'), ModuleStatus.hidden);
      // intercity hali sozlanmagan → alias orqali enabled
      expect(
          ServiceConfigHolder.statusOf('yuk_intercity'), ModuleStatus.enabled);
    });

    test('tuman override yangi id ni alohida boshqaradi', () {
      ServiceConfigHolder.setForTest(
        defaults: const ServiceModuleConfig({
          'yuk_birja': ModuleStatus.hidden,
        }),
        districtOverride: const ServiceModuleConfig({
          'yuk_intercity': ModuleStatus.enabled,
        }),
        enforce: true,
      );
      expect(ServiceConfigHolder.statusOf('yuk_local'), ModuleStatus.hidden);
      expect(
          ServiceConfigHolder.statusOf('yuk_intercity'), ModuleStatus.enabled);
    });

    test('enforce=false: alias orqali configured hisoblanadi', () {
      ServiceConfigHolder.setForTest(
        defaults: const ServiceModuleConfig({
          'yuk_birja': ModuleStatus.enabled,
        }),
        enforce: false,
      );
      expect(ServiceConfigHolder.statusOf('yuk_local'), ModuleStatus.enabled);
    });
  });
}
