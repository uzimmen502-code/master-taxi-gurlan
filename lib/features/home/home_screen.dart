import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import '../../models/active_trip.dart';
import '../../models/home_module.dart';
import '../../models/user_model.dart';
import '../../models/home_ticker_ad.dart';
import '../../repositories/intercity_bookings_repository.dart';
import '../../repositories/rides_repository.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/home_ticker_repository.dart';
import '../../shared/widgets/no_internet_banner.dart';
import 'widgets/home_info_ticker.dart';
import '../orders/screens/orders_screen.dart';
import '../ads/screens/cheap_products_screen.dart';
import '../bread/screens/bread_screen.dart';
import '../carpet_wash/screens/carpet_wash_screen.dart';
import '../agro_pickup/screens/milk_pickup_screen.dart';
import '../oil_change/screens/oil_change_home_screen.dart';
import '../food/screens/food_screen.dart';
import '../platform_store/screens/platform_store_screen.dart';
import 'screens/courier_services_hub_screen.dart';
import '../yuk_birja/screens/yuk_birja_screen.dart';
import '../intercity_taxi/driver/intercity_driver_resume.dart';
import '../intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../jobs/jobs_tabs.dart';
import '../jobs/screens/jobs_screen.dart';
import '../local_taxi/passenger/screens/local_taxi_active_trip_screen.dart';
import '../local_taxi/passenger/screens/local_taxi_screen.dart';
import '../local_taxi/passenger/screens/searching_screen.dart';
import '../marshrut/passenger/screens/marshrut_accepted_screen.dart';
import '../marshrut/passenger/screens/marshrut_taxi_screen.dart';
import '../profile/screens/profile_screen.dart';
import '../profile/screens/wallet_screen.dart';
import '../sell/screens/sell_hub_screen.dart';
import '../relatives/screens/relatives_screen.dart';
import 'controllers/home_controller.dart';
import 'home_module_gate.dart';
import 'home_modules_catalog.dart';
import '../../models/feed_item.dart';
import 'widgets/featured_products_section.dart';
import 'widgets/product_feed_section.dart';
import 'widgets/promo_carousel.dart';
import 'widgets/seller_cta_banner.dart';
import 'widgets/services_spotlight_carousel.dart';
import 'widgets/wallet_card.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
const _bg = AppColors.lime;
const _headerBorder = AppColors.limeEdge;
const _brandGreen = AppColors.limeDeep;
const _inactiveTab = Color(0xFF8AAB50);

/// Kichik ekranlar uchun matn/shrift masshtabini moslashtirish.
double _homeUiScale(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 340) return 0.86;
  if (w < 380) return 0.92;
  return 1.0;
}

/// Bo‘limlar orasidagi vertikal masofa — ekran balandligi/kengligiga qarab.
double _sectionGap(BuildContext context, {required double base}) {
  final h = MediaQuery.sizeOf(context).height;
  final scale = _homeUiScale(context);
  final heightFactor = h < 640
      ? 0.72
      : h < 720
          ? 0.82
          : h < 800
              ? 0.9
              : 1.0;
  return (base * scale * heightFactor).clamp(6.0, base);
}

String _todayText(BuildContext context) {
  final now = DateTime.now();
  final d = now.day.toString().padLeft(2, '0');
  final m = now.month.toString().padLeft(2, '0');
  return context
      .tr('home_date_today')
      .replaceAll('{day}', d)
      .replaceAll('{month}', m)
      .replaceAll('{year}', '${now.year}');
}

/// Bosh ekran — yangi layout (hamyon, taksi, xizmatlar).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeController(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  StreamSubscription<void>? _promoSub;
  VoidCallback? _configListener;
  bool _tripResumeDone = false;
  String? _lastAppliedServiceAreaId;
  /// Profile/orders/wallet дан қайтганда spotlight автони қайта ёқиш.
  int _servicesCarouselEpoch = 0;
  /// Home қайта очилганда ҳамён 11 с яна кўринсин.
  int _walletRevealEpoch = 0;
  bool _walletVisible = true;
  Timer? _walletHideTimer;

  @override
  void initState() {
    super.initState();
    _configListener = () {
      if (mounted) setState(() {});
    };
    ServiceConfigHolder.revision.addListener(_configListener!);
    _armWalletHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ServiceConfigHolder.bootstrap());
      unawaited(_runTripResumeOnce());
      _checkActiveIntercityBooking();
      final c = context.read<HomeController>();
      _promoSub = c.onAgroPromo.listen(_showAgroPromo);
      unawaited(IntercityDriverResume.tryResumeOnAppLaunch(context));
    });
  }

  void _onHomeResurface() {
    if (!mounted) return;
    setState(() {
      _servicesCarouselEpoch++;
      _walletRevealEpoch++;
      _walletVisible = true;
    });
    _armWalletHideTimer();
    // Admin config (Ёпиқ/Очиқ) янгиланиши учун.
    unawaited(ServiceConfigHolder.bootstrap());
  }

  void _armWalletHideTimer() {
    _walletHideTimer?.cancel();
    _walletHideTimer = Timer(const Duration(seconds: 11), () {
      if (!mounted) return;
      setState(() => _walletVisible = false);
    });
  }

  /// Single `users/{uid}` stream (WalletCard) also drives geo config — no
  /// second Firestore watch.
  void _maybeApplyUserGeo(UserModel? user) {
    if (user == null) return;
    final areaId = user.serviceAreaId.trim();
    if (areaId.isEmpty || areaId == _lastAppliedServiceAreaId) return;
    _lastAppliedServiceAreaId = areaId;
    unawaited(() async {
      if (user.regionId.isNotEmpty && user.districtId.isNotEmpty) {
        await ServiceConfigHolder.applyGeo(
          regionId: user.regionId,
          districtId: user.districtId,
          serviceAreaId: areaId,
        );
      } else {
        await ServiceConfigHolder.applyServiceArea(areaId);
      }
      if (mounted) setState(() {});
    }());
  }

  Future<void> _runTripResumeOnce() async {
    if (_tripResumeDone) return;
    _tripResumeDone = true;
    await _checkActiveLocalTrip();
    if (!mounted) return;
    await _checkActiveMarshrutTrip();
  }

  Future<void> _checkActiveIntercityBooking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'user';
      if (role == 'driver') return;

      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) return;

      final from = prefs.getString('last_intercity_from') ?? '';
      final to = prefs.getString('last_intercity_to') ?? '';
      if (from.isEmpty || to.isEmpty) return;

      final repo = IntercityBookingsRepository();
      final booking = await repo.findActiveBookingForUser(phone);
      if (booking == null) return;
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IntercityTaxiScreen(autoFrom: from, autoTo: to),
        ),
      );
    } catch (e) {
      debugPrint('_checkActiveIntercityBooking: $e');
    }
  }

  Future<void> _checkActiveLocalTrip() async {
    try {
      if (!mounted) return;
      final repo = context.read<RidesRepository>();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'user';
      if (role == 'driver') return;

      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) return;

      final resumeId = prefs.getString('resume_local_trip_id') ?? '';
      if (resumeId.isNotEmpty) {
        await prefs.remove('resume_local_trip_id');
        final trip = await repo.getTrip(resumeId);
        if (trip != null && mounted) {
          await _navigateLocalTrip(trip, resumeId);
          return;
        }
      }

      final doc = await repo.findActiveLocalTripDoc(phone);
      if (doc == null || !mounted) return;
      final trip = repo.activeTripFromDoc(doc);
      if (trip == null) return;
      await _navigateLocalTrip(trip, doc.id);
    } catch (e) {
      debugPrint('_checkActiveLocalTrip: $e');
    }
  }

  Future<void> _navigateLocalTrip(ActiveTrip trip, String tripId) async {
    if (!mounted) return;
    if (trip.status == 'accepted') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LocalTaxiActiveTripScreen(tripId: tripId),
        ),
      );
    } else if (trip.status == 'searching') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SearchingScreen(
            from: trip.fromAddr,
            to: trip.toAddr,
            taxiType: 'local',
            tripId: tripId,
          ),
        ),
      );
    }
  }

  Future<void> _checkActiveMarshrutTrip() async {
    try {
      if (!mounted) return;
      final repo = context.read<RidesRepository>();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'user';
      if (role == 'driver') return;

      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) return;

      final doc = await repo.findActiveMarshrutTripDoc(phone);
      if (doc == null || !mounted) return;
      final trip = repo.activeTripFromDoc(doc);
      if (trip == null || trip.status != 'accepted') return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MarshrutAcceptedScreen(trip: trip),
        ),
      );
    } catch (e) {
      debugPrint('_checkActiveMarshrutTrip: $e');
    }
  }

  @override
  void dispose() {
    _walletHideTimer?.cancel();
    _promoSub?.cancel();
    if (_configListener != null) {
      ServiceConfigHolder.revision.removeListener(_configListener!);
    }
    super.dispose();
  }

  void _showAgroPromo(void _) {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    final c = context.read<HomeController>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('agro_news_title')),
        content: Text(
          loc.translate(c.agroPromoBodyKey) +
              (c.agroPromoExtraKey.isNotEmpty
                  ? '\n\n${loc.translate(c.agroPromoExtraKey)}'
                  : ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('understand')),
          ),
        ],
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => screen,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
    // Home яна кўринганда spotlight авто / ҳамён 11 с қайта.
    if (mounted) _onHomeResurface();
  }

  static const _datingTelegramBotUrl = 'https://t.me/bilish_tanish_bot';

  Future<void> _openDatingTelegramBot() async {
    final uri = Uri.parse(_datingTelegramBotUrl);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telegram очилмади')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telegram очилмади')),
      );
    }
  }

  Future<void> _openModule(HomeModule m) async {
    if (!HomeModuleGate.canOpen(m.id)) {
      HomeModuleGate.onTapBlocked(context, m.id);
      return;
    }
    if (m.id == 'sell') {
      final phone = phoneDigits(context.read<HomeController>().phone);
      if (phone.length < 9) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('fill_phone_first'))),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SellHubScreen(phone: phone),
        ),
      );
      if (mounted) _onHomeResurface();
      return;
    }

    final Widget screen;
    switch (m.id) {
      case 'bread':
        screen = const BreadScreen();
        break;
      case 'food':
        screen = const FoodScreen();
        break;
      case 'cheap_products_home':
        screen = const CheapProductsScreen();
        break;
      case 'marshrut':
        screen = const MarshrutTaxiScreen();
        break;
      case 'local_taxi':
        screen = const LocalTaxiScreen();
        break;
      case 'intercity':
        screen = const IntercityTaxiScreen();
        break;
      case 'jobs':
        screen = const JobsScreen();
        break;
      default:
        return;
    }
    await _push(screen);
  }

  String _displayName(
      BuildContext context, UserModel? user, HomeController home) {
    final name = (user?.name ?? home.name).trim();
    final phone =
        user?.phone.trim().isNotEmpty == true ? user!.phone : home.phone;
    if (name.isEmpty) {
      return phone.isNotEmpty ? phone : context.tr('user_default_name');
    }
    return context.tr('home_display_name_aka').replaceAll('{name}', name);
  }

  void _showTezKundaSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('home_coming_soon')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final uid = phoneDigits(home.phone);
    final userRepo = context.read<UserRepository>();

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: _HomeBottomNav(
        onOrders: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OrdersScreen()),
          );
          if (mounted) _onHomeResurface();
        },
        onWallet: () async {
          await _HomeBottomNav.openWallet(context);
          if (mounted) _onHomeResurface();
        },
        onProfile: () async {
          await _HomeBottomNav.openProfile(context);
          if (!context.mounted) return;
          await context.read<HomeController>().refreshUser();
          if (mounted) _onHomeResurface();
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!home.hasInternet) const NoInternetBanner(),
            Expanded(
              child: StreamBuilder<UserModel?>(
                stream: uid.length >= 9
                    ? userRepo.watch(uid)
                    : Stream<UserModel?>.value(null),
                builder: (context, userSnap) {
                  final user = userSnap.data;
                  _maybeApplyUserGeo(user);
                  // Oxirgi tranzaksiya Wallet ekranida; Home faqat balans
                  // (users.bonusBalance) — wallet_ledger stream yo'q.
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal:
                              MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: _sectionGap(context, base: 10)),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: _walletVisible
                                  ? Column(
                                      key: ValueKey(_walletRevealEpoch),
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        WalletCard(
                                          balanceAmount: formatPrice(
                                              user?.bonusBalance ?? 0),
                                          balanceCurrency: kCurrencySum,
                                          lastTxAmount: '—',
                                          displayName: _displayName(
                                              context, user, home),
                                          dateText: _todayText(context),
                                          locationText: ServiceConfigHolder
                                              .districtLabel,
                                          lastTxIsCredit: null,
                                          onHistoryTap: () async {
                                            if (uid.length < 9) {
                                              _HomeBottomNav.needPhone(
                                                  context);
                                              return;
                                            }
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => WalletScreen(
                                                    phone: home.phone),
                                              ),
                                            );
                                            if (mounted) _onHomeResurface();
                                          },
                                        ),
                                        SizedBox(
                                          height: _sectionGap(context,
                                              base: 10),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            StreamBuilder<List<HomeTickerAd>>(
                              stream: context
                                  .read<HomeTickerRepository>()
                                  .watchForModule('home_search', 'user'),
                              builder: (context, snap) {
                                final ads = snap.data ?? const <HomeTickerAd>[];
                                if (ads.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final shuffled = List<HomeTickerAd>.of(ads)
                                  ..shuffle();
                                return HomeInfoTicker(ads: shuffled);
                              },
                            ),
                            SizedBox(height: _sectionGap(context, base: 12)),
                            PromoCarousel(
                              onNonTap: HomeModuleGate.gatedTap(
                                context,
                                'bread',
                                () => _openModule(
                                  HomeModulesCatalog.byId('bread'),
                                ),
                              ),
                              onCarpetWashTap: HomeModuleGate.gatedTap(
                                context,
                                'carpet_wash',
                                () => _push(const CarpetWashScreen()),
                              ),
                              onMilkTap: HomeModuleGate.gatedTap(
                                context,
                                'milk',
                                () => _push(const MilkPickupScreen()),
                              ),
                              onTaomTap: HomeModuleGate.gatedTap(
                                context,
                                'food',
                                () => _openModule(
                                  HomeModulesCatalog.byId('food'),
                                ),
                              ),
                              onBozorTap: HomeModuleGate.gatedTap(
                                context,
                                'cheap_products_home',
                                () => _openModule(
                                  HomeModulesCatalog.byId(
                                      'cheap_products_home'),
                                ),
                              ),
                              onLocalTaxiTap: HomeModuleGate.gatedTap(
                                context,
                                'local_taxi',
                                () => _openModule(
                                  HomeModulesCatalog.byId('local_taxi'),
                                ),
                              ),
                              onIntercityTap: HomeModuleGate.gatedTap(
                                context,
                                'intercity',
                                () => _openModule(
                                  HomeModulesCatalog.byId('intercity'),
                                ),
                              ),
                              onMarshrutTap: HomeModuleGate.gatedTap(
                                context,
                                'marshrut',
                                () => _openModule(
                                  HomeModulesCatalog.byId('marshrut'),
                                ),
                              ),
                            ),
                            SizedBox(height: _sectionGap(context, base: 12)),
                            ServicesSpotlightCarousel(
                              key: ValueKey(_servicesCarouselEpoch),
                              items: [
                                ServiceSpotlightItem(
                                  moduleId: 'local_taxi',
                                  label: context.tr('home_module_local'),
                                  imagePath:
                                      'assets/images/services/service_taxi_local.png',
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('local_taxi'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'intercity',
                                  label: context.tr('home_module_intercity'),
                                  imagePath:
                                      'assets/images/services/service_taxi_intercity.png',
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('intercity'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'marshrut',
                                  label: context.tr('home_module_marshrut'),
                                  imagePath:
                                      'assets/images/services/service_marshrut.png',
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('marshrut'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'yuk_birja',
                                  label: context.tr('home_module_yuk_birja'),
                                  imagePath:
                                      'assets/images/services/service_yuk_birja.png',
                                  onTap: () async {
                                    if (!ServiceConfigHolder.isOpenable(
                                        'yuk_birja')) {
                                      _showTezKundaSnack();
                                      return;
                                    }
                                    final phone = phoneDigits(
                                      context.read<HomeController>().phone,
                                    );
                                    if (phone.length < 9) {
                                      _HomeBottomNav.needPhone(context);
                                      return;
                                    }
                                    await _push(const YukBirjaScreen());
                                  },
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'sell',
                                  label: context.tr('home_module_sell'),
                                  imagePath:
                                      'assets/images/services/service_sell.png',
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('sell'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'food',
                                  label: context.tr('home_module_food'),
                                  imagePath:
                                      'assets/images/services/service_food.png',
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('food'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'jobs',
                                  label: context.tr('home_module_jobs'),
                                  imagePath:
                                      'assets/images/services/service_jobs.png',
                                  onTap: () {
                                    if (!ServiceConfigHolder.isOpenable(
                                        'jobs')) {
                                      _showTezKundaSnack();
                                      return;
                                    }
                                    _push(
                                      const JobsScreen(
                                        initialTabIndex: JobsTabs.ad,
                                      ),
                                    );
                                  },
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'cheap_products_home',
                                  label:
                                      context.tr('home_module_cheap_products'),
                                  imagePath:
                                      'assets/images/services/service_market.png',
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId(
                                        'cheap_products_home'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'bread',
                                  label: context.tr('home_module_bread'),
                                  imagePath:
                                      'assets/images/services/service_bread.png',
                                  iconScale: 1.15,
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('bread'),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'oil_change',
                                  label: context.tr('home_module_oil_change'),
                                  imagePath:
                                      'assets/images/services/service_oil_change.png',
                                  onTap: () => _push(
                                    const OilChangeHomeScreen(),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'circles',
                                  label: context.tr('home_module_relatives'),
                                  imagePath:
                                      'assets/images/services/service_relatives.png',
                                  onTap: () =>
                                      _push(const RelativesScreen()),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'dating',
                                  label: context.tr('dating_short_label'),
                                  icon: Icons.favorite_rounded,
                                  iconColor: const Color(0xFFE53935),
                                  iconScale: 1.05,
                                  onTap: () => _openDatingTelegramBot(),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'courier',
                                  label: context.tr('home_module_courier'),
                                  imagePath:
                                      'assets/images/services/service_courier.png',
                                  onTap: () async {
                                    if (!ServiceConfigHolder.isOpenable(
                                        'courier')) {
                                      _showTezKundaSnack();
                                      return;
                                    }
                                    final phone = phoneDigits(
                                      context.read<HomeController>().phone,
                                    );
                                    if (phone.length < 9) {
                                      _HomeBottomNav.needPhone(context);
                                      return;
                                    }
                                    await _push(
                                        const CourierServicesHubScreen());
                                  },
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'milk',
                                  label: context.tr('milk_short_label'),
                                  imagePath:
                                      'assets/images/services/service_milk.png',
                                  iconScale: 1.15,
                                  onTap: () =>
                                      _push(const MilkPickupScreen()),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'tire',
                                  label: context.tr('home_module_tire'),
                                  imagePath:
                                      'assets/images/services/service_tire.png',
                                  onTap: () {},
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'car_wash',
                                  label: context.tr('home_module_car_wash'),
                                  imagePath:
                                      'assets/images/services/service_car_wash.png',
                                  onTap: () {},
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'carpet_wash',
                                  label: context.tr('home_module_carpet'),
                                  imagePath:
                                      'assets/images/services/service_carpet_wash.png',
                                  onTap: () =>
                                      _push(const CarpetWashScreen()),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            FeaturedProductsSection(
                              onProductTap: (productId) => _push(
                                PlatformStoreScreen(
                                  highlightProductId: productId,
                                ),
                              ),
                            ),
                            if (HomeModuleGate.showInGrid('sell')) ...[
                              const SizedBox(height: 12),
                              SellerCtaBanner(
                                onTap: () =>
                                    SellerCtaBanner.openOnlineMarketSellFlow(
                                  context,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            ProductFeedSection(
                              onProductTap: (source) {
                                switch (source) {
                                  case FeedSource.bread:
                                    _openModule(
                                      HomeModulesCatalog.byId('bread'),
                                    );
                                  case FeedSource.food:
                                    _openModule(
                                      HomeModulesCatalog.byId('food'),
                                    );
                                  case FeedSource.market:
                                    _openModule(
                                      HomeModulesCatalog.byId(
                                        'cheap_products_home',
                                      ),
                                    );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav({
    required this.onOrders,
    required this.onWallet,
    required this.onProfile,
  });

  final VoidCallback onOrders;
  final VoidCallback onWallet;
  final VoidCallback onProfile;

  static void needPhone(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('need_phone_profile')),
        duration: const Duration(seconds: 3),
      ),
    );
    openProfile(context);
  }

  static Future<void> openWallet(BuildContext context) async {
    final phone = phoneDigits(context.read<HomeController>().phone);
    if (phone.length < 9) {
      needPhone(context);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletScreen(phone: phone)),
    );
  }

  static Future<void> openProfile(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _headerBorder, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              _NavItem(
                icon: _IconKind.home,
                label: context.tr('bottom_home'),
                active: true,
                onTap: () {},
              ),
              _NavItem(
                icon: _IconKind.package,
                label: context.tr('bottom_orders'),
                onTap: onOrders,
              ),
              _NavItem(
                icon: _IconKind.wallet,
                label: context.tr('bottom_wallet'),
                onTap: onWallet,
              ),
              _NavItem(
                icon: _IconKind.user,
                label: context.tr('bottom_profile'),
                onTap: onProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final _IconKind icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? _brandGreen : _inactiveTab;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StrokeIcon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stroke icons (Lucide-style) ───────────────────────────────────────────
enum _IconKind {
  home,
  search,
  message,
  wallet,
  user,
  car,
  navigation,
  bus,
  package,
  shoppingBag,
  wrench,
  store,
  briefcase,
  shoppingCart,
  tool,
  receipt,
  clock,
}

class _StrokeIcon extends StatelessWidget {
  const _StrokeIcon(this.kind, {required this.color, this.size = 20});

  final _IconKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StrokeIconPainter(kind: kind, color: color),
      ),
    );
  }
}

class _StrokeIconPainter extends CustomPainter {
  _StrokeIconPainter({required this.kind, required this.color});

  final _IconKind kind;
  final Color color;

  static const _sw = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final s = size.width / 24;
    canvas.scale(s);

    switch (kind) {
      case _IconKind.home:
        _home(canvas, paint);
      case _IconKind.search:
        _search(canvas, paint);
      case _IconKind.message:
        _message(canvas, paint);
      case _IconKind.wallet:
        _wallet(canvas, paint);
      case _IconKind.user:
        _user(canvas, paint);
      case _IconKind.car:
        _car(canvas, paint);
      case _IconKind.navigation:
        _navigation(canvas, paint);
      case _IconKind.bus:
        _bus(canvas, paint);
      case _IconKind.package:
        _package(canvas, paint);
      case _IconKind.shoppingBag:
        _shoppingBag(canvas, paint);
      case _IconKind.wrench:
        _wrench(canvas, paint);
      case _IconKind.store:
        _store(canvas, paint);
      case _IconKind.briefcase:
        _briefcase(canvas, paint);
      case _IconKind.shoppingCart:
        _shoppingCart(canvas, paint);
      case _IconKind.tool:
        _tool(canvas, paint);
      case _IconKind.receipt:
        _receipt(canvas, paint);
      case _IconKind.clock:
        _clock(canvas, paint);
    }
  }

  void _home(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(3, 10)
        ..lineTo(12, 3)
        ..lineTo(21, 10)
        ..lineTo(21, 20)
        ..lineTo(15, 20)
        ..lineTo(15, 14)
        ..lineTo(9, 14)
        ..lineTo(9, 20)
        ..lineTo(3, 20)
        ..close(),
      p,
    );
  }

  void _search(Canvas c, Paint p) {
    c.drawCircle(const Offset(10.5, 10.5), 5.5, p);
    c.drawLine(const Offset(14.5, 14.5), const Offset(20, 20), p);
  }

  void _message(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 4, 18, 14), const Radius.circular(3)),
      p,
    );
    c.drawPath(
        Path()
          ..moveTo(8, 18)
          ..lineTo(10, 21)
          ..lineTo(12, 18),
        p);
  }

  void _wallet(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 6, 18, 13), const Radius.circular(2)),
      p,
    );
    c.drawLine(const Offset(3, 10), const Offset(21, 10), p);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    c.drawCircle(const Offset(17, 14), 1.2, fill);
  }

  void _user(Canvas c, Paint p) {
    c.drawCircle(const Offset(12, 8), 3.5, p);
    c.drawPath(
      Path()
        ..moveTo(5, 21)
        ..quadraticBezierTo(12, 15, 19, 21),
      p,
    );
  }

  void _car(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(5, 16)
        ..lineTo(7, 11)
        ..lineTo(17, 11)
        ..lineTo(19, 16)
        ..close(),
      p,
    );
    c.drawLine(const Offset(5, 16), const Offset(19, 16), p);
    c.drawCircle(const Offset(8, 16), 2, p);
    c.drawCircle(const Offset(16, 16), 2, p);
  }

  void _navigation(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(12, 3)
        ..lineTo(20, 21)
        ..lineTo(12, 17)
        ..lineTo(4, 21)
        ..close(),
      p,
    );
  }

  void _bus(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 5, 16, 14), const Radius.circular(2)),
      p,
    );
    c.drawLine(const Offset(4, 11), const Offset(20, 11), p);
    c.drawCircle(const Offset(8, 19), 1.5, p);
    c.drawCircle(const Offset(16, 19), 1.5, p);
  }

  void _package(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(12, 3)
        ..lineTo(21, 7)
        ..lineTo(21, 19)
        ..lineTo(3, 19)
        ..lineTo(3, 7)
        ..close(),
      p,
    );
    c.drawLine(const Offset(12, 3), const Offset(12, 19), p);
    c.drawLine(const Offset(3, 7), const Offset(12, 11), p);
    c.drawLine(const Offset(21, 7), const Offset(12, 11), p);
  }

  void _shoppingBag(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(6, 8)
        ..lineTo(8, 21)
        ..lineTo(16, 21)
        ..lineTo(18, 8),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(9, 8)
        ..cubicTo(9, 4, 15, 4, 15, 8),
      p,
    );
  }

  void _wrench(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(14, 4)
        ..arcToPoint(const Offset(20, 10), radius: const Radius.circular(4))
        ..lineTo(10, 20)
        ..lineTo(6, 20)
        ..lineTo(6, 16)
        ..lineTo(14, 8),
      p,
    );
  }

  void _store(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(3, 9)
        ..lineTo(12, 3)
        ..lineTo(21, 9)
        ..lineTo(21, 21)
        ..lineTo(3, 21)
        ..close(),
      p,
    );
    c.drawLine(const Offset(9, 21), const Offset(9, 14), p);
    c.drawLine(const Offset(15, 21), const Offset(15, 14), p);
  }

  void _briefcase(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 8, 16, 12), const Radius.circular(2)),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(9, 8)
        ..lineTo(9, 6)
        ..lineTo(15, 6)
        ..lineTo(15, 8),
      p,
    );
    c.drawLine(const Offset(4, 13), const Offset(20, 13), p);
  }

  void _shoppingCart(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(3, 4)
        ..lineTo(5, 18)
        ..lineTo(19, 18)
        ..lineTo(21, 6)
        ..lineTo(7, 6)
        ..close(),
      p,
    );
    c.drawCircle(const Offset(8, 21), 1.5, p);
    c.drawCircle(const Offset(17, 21), 1.5, p);
  }

  void _tool(Canvas c, Paint p) {
    c.drawLine(const Offset(4, 20), const Offset(16, 8), p);
    c.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(14, 5, 6, 4), const Radius.circular(1)),
      p,
    );
    c.drawLine(const Offset(18, 12), const Offset(21, 15), p);
    c.drawLine(const Offset(21, 12), const Offset(18, 15), p);
  }

  void _receipt(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(6, 3)
        ..lineTo(18, 3)
        ..lineTo(18, 21)
        ..lineTo(6, 21)
        ..close(),
      p,
    );
    c.drawLine(const Offset(9, 8), const Offset(15, 8), p);
    c.drawLine(const Offset(9, 12), const Offset(15, 12), p);
    c.drawLine(const Offset(9, 16), const Offset(13, 16), p);
  }

  void _clock(Canvas c, Paint p) {
    c.drawCircle(const Offset(12, 12), 9, p);
    c.drawLine(const Offset(12, 12), const Offset(12, 7), p);
    c.drawLine(const Offset(12, 12), const Offset(16, 14), p);
  }

  @override
  bool shouldRepaint(covariant _StrokeIconPainter old) =>
      old.kind != kind || old.color != color;
}
