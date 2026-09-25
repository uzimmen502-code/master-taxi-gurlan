import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/payment_provider_launcher.dart';
import '../../models/home_module.dart';
import '../agro_pickup/screens/milk_pickup_screen.dart';
import '../assistant/assistant_entry.dart';
import '../carpet_wash/screens/carpet_wash_screen.dart';
import '../ev_charging/screens/ev_charging_map_screen.dart';
import '../jobs/jobs_tabs.dart';
import '../jobs/screens/jobs_screen.dart';
import '../oil_change/screens/oil_change_home_screen.dart';
import '../platform_store/screens/platform_store_screen.dart';
import '../relatives/screens/relatives_screen.dart';
import '../tv_market/screens/tv_market_feed_screen.dart';
import '../wholesale/screens/wholesale_market_screen.dart';
import '../yuk_intercity/screens/yuk_intercity_screen.dart';
import '../yuk_local/screens/yuk_local_screen.dart';
import 'controllers/home_controller.dart';
import 'home_modules_catalog.dart';
import 'home_screen.dart' show needPhoneForAction;
import 'screens/courier_services_hub_screen.dart';
import 'widgets/services_spotlight_carousel.dart';

/// Хизмат катаклари бажарадиган амаллар.
///
/// Рўйхат `home_screen.dart` дан шу ерга кўчирилди: у «Барча хизматлар»
/// экрани учун керак, бош саҳифадаги карусел эса олиб ташланди. Амаллар
/// параметр сифатида берилади — каталог экранга боғланиб қолмайди.
class HomeServiceActions {
  const HomeServiceActions({
    required this.push,
    required this.openModule,
    required this.openYukModule,
    required this.openPayment,
    required this.openDatingBot,
    required this.showComingSoon,
  });

  final Future<void> Function(Widget screen) push;
  final Future<void> Function(HomeModule module) openModule;
  final Future<void> Function(String moduleId, Widget screen) openYukModule;
  final Future<void> Function(PaymentProviderApp app) openPayment;
  final Future<void> Function() openDatingBot;
  final void Function() showComingSoon;
}

/// Иловадаги барча хизматлар — тартиби билан.
///
/// Кўринадиганини филтрлаш чақирувчида (`HomeModuleGate.showInGrid`).
List<ServiceSpotlightItem> buildHomeServices(
  BuildContext context, {
  required HomeServiceActions a,
}) {
  return <ServiceSpotlightItem>[
    ServiceSpotlightItem(
      moduleId: 'local_taxi',
      label: context.tr('home_module_local'),
      imagePath: 'assets/images/services/service_taxi_local.png',
      onTap: () => a.openModule(
        HomeModulesCatalog.byId('local_taxi'),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'intercity',
      label: context.tr('home_module_intercity'),
      imagePath: 'assets/images/services/service_taxi_intercity.png',
      onTap: () => a.openModule(
        HomeModulesCatalog.byId('intercity'),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'marshrut',
      label: context.tr('home_module_marshrut'),
      imagePath: 'assets/images/services/service_marshrut.png',
      onTap: () => a.openModule(
        HomeModulesCatalog.byId('marshrut'),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'yuk_local',
      label: context.tr('home_module_yuk_local'),
      imagePath: 'assets/images/services/service_yuk_local.png',
      onTap: () => a.openYukModule(
        'yuk_local',
        const YukLocalScreen(),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'yuk_intercity',
      label: context.tr('home_module_yuk_intercity'),
      imagePath: 'assets/images/services/service_yuk_birja.png',
      onTap: () => a.openYukModule(
        'yuk_intercity',
        const YukIntercityScreen(),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'food',
      label: context.tr('home_module_food'),
      imagePath: 'assets/images/services/service_food.png',
      onTap: () => a.openModule(
        HomeModulesCatalog.byId('food'),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'jobs',
      label: context.tr('home_module_jobs'),
      imagePath: 'assets/images/services/service_jobs.png',
      onTap: () {
        if (!ServiceConfigHolder.isOpenable('jobs')) {
          a.showComingSoon();
          return;
        }
        a.push(
          const JobsScreen(
            initialTabIndex: JobsTabs.ad,
          ),
        );
      },
    ),
    ServiceSpotlightItem(
      moduleId: 'cheap_products_home',
      label: context.tr('home_module_cheap_products'),
      imagePath: 'assets/images/services/service_market.png',
      onTap: () => a.openModule(
        HomeModulesCatalog.byId('cheap_products_home'),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'platform_store',
      label: context.tr('home_module_platform_store'),
      icon: Icons.storefront_rounded,
      iconColor: const Color(0xFF00BCD4),
      onTap: () {
        if (!ServiceConfigHolder.isOpenable('platform_store')) {
          a.showComingSoon();
          return;
        }
        a.push(const PlatformStoreScreen());
      },
    ),
    ServiceSpotlightItem(
      moduleId: 'tv_market',
      label: context.tr('home_module_tv_market'),
      icon: Icons.play_circle_filled_rounded,
      iconColor: const Color(0xFFFF1744),
      onTap: () {
        if (!ServiceConfigHolder.isOpenable('tv_market')) {
          a.showComingSoon();
          return;
        }
        a.push(const TvMarketFeedScreen());
      },
    ),
    ServiceSpotlightItem(
      moduleId: 'bread',
      label: context.tr('home_module_bread'),
      imagePath: 'assets/images/services/service_bread.png',
      iconScale: 1.15,
      onTap: () => a.openModule(
        HomeModulesCatalog.byId('bread'),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'oil_change',
      label: context.tr('home_module_oil_change'),
      imagePath: 'assets/images/services/service_oil_change.png',
      onTap: () => a.push(
        const OilChangeHomeScreen(),
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'circles',
      label: context.tr('home_module_relatives'),
      imagePath: 'assets/images/services/service_relatives.png',
      onTap: () => a.push(const RelativesScreen()),
    ),
    ServiceSpotlightItem(
      moduleId: 'dating',
      label: context.tr('dating_short_label'),
      icon: Icons.favorite_rounded,
      iconColor: const Color(0xFFE53935),
      iconScale: 1.05,
      onTap: () => a.openDatingBot(),
    ),
    ServiceSpotlightItem(
      moduleId: 'chatgpt',
      label: context.tr('home_module_chatgpt'),
      icon: Icons.auto_awesome_rounded,
      iconColor: const Color(0xFF10A37F),
      onTap: () => openAssistantEntry(
        context,
        phone: context.read<HomeController>().phone,
        push: a.push,
      ),
    ),
    ServiceSpotlightItem(
      moduleId: 'courier',
      label: context.tr('home_module_courier'),
      imagePath: 'assets/images/services/service_courier.png',
      onTap: () async {
        if (!ServiceConfigHolder.isOpenable('courier')) {
          a.showComingSoon();
          return;
        }
        final phone = phoneDigits(
          context.read<HomeController>().phone,
        );
        if (phone.length < 9) {
          needPhoneForAction(context);
          return;
        }
        await a.push(const CourierServicesHubScreen());
      },
    ),
    ServiceSpotlightItem(
      moduleId: 'milk',
      label: context.tr('milk_short_label'),
      imagePath: 'assets/images/services/service_milk.png',
      iconScale: 1.15,
      onTap: () => a.push(const MilkPickupScreen()),
    ),
    ServiceSpotlightItem(
      moduleId: 'tire',
      label: context.tr('home_module_tire'),
      imagePath: 'assets/images/services/service_tire.png',
      onTap: () {},
    ),
    ServiceSpotlightItem(
      moduleId: 'car_wash',
      label: context.tr('home_module_car_wash'),
      imagePath: 'assets/images/services/service_car_wash.png',
      onTap: () {},
    ),
    ServiceSpotlightItem(
      moduleId: 'carpet_wash',
      label: context.tr('home_module_carpet'),
      imagePath: 'assets/images/services/service_carpet_wash.png',
      onTap: () => a.push(const CarpetWashScreen()),
    ),
    ServiceSpotlightItem(
      moduleId: 'ev_charging',
      label: context.tr('home_module_ev_charging'),
      imagePath: 'assets/images/services/service_ev_charging.png',
      onTap: () => a.push(const EvChargingMapScreen()),
    ),
    ServiceSpotlightItem(
      moduleId: 'pay_click',
      label: context.tr('home_module_click'),
      svgPath: 'assets/images/services/service_pay_click.svg',
      onTap: () => a.openPayment(kClickApp),
    ),
    ServiceSpotlightItem(
      moduleId: 'pay_payme',
      label: context.tr('home_module_payme'),
      svgPath: 'assets/images/services/service_pay_payme.svg',
      onTap: () => a.openPayment(kPaymeApp),
    ),
    ServiceSpotlightItem(
      moduleId: 'pay_paynet',
      label: context.tr('home_module_paynet'),
      imagePath: 'assets/images/services/service_pay_paynet.png',
      onTap: () => a.openPayment(kPaynetApp),
    ),
    ServiceSpotlightItem(
      moduleId: 'wholesale_market',
      label: context.tr('home_module_wholesale'),
      icon: Icons.warehouse_outlined,
      iconColor: const Color(0xFF6D4C41),
      onTap: () {
        if (!ServiceConfigHolder.isOpenable('wholesale_market')) {
          a.showComingSoon();
          return;
        }
        a.push(WholesaleMarketScreen(
          userPhone: canonicalPhoneId(
            context.read<HomeController>().phone,
          ),
        ));
      },
    ),
  ];
}
