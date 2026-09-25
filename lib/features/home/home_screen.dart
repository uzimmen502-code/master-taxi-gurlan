import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_share.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/payment_provider_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/home_module.dart';
import '../../models/user_model.dart';
import '../../models/home_ticker_ad.dart';
import '../../repositories/rides_repository.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/home_ticker_repository.dart';
import '../../shared/widgets/no_internet_banner.dart';
import 'widgets/home_info_ticker.dart';
import '../../core/widgets/zone_gate.dart';
import '../ads/screens/cheap_products_screen.dart';
import '../ads/screens/create_ad_screen.dart';
import '../profile/screens/news_hub_screen.dart';
import '../tv_market/screens/tv_publish_screen.dart';
import 'widgets/ava_bottom_nav.dart';
import 'widgets/ava_top_bar.dart';
import '../bread/screens/bread_screen.dart';
import '../carpet_wash/screens/carpet_wash_screen.dart';
import '../dating/screens/dating_home_screen.dart';
import '../ev_charging/screens/ev_charging_map_screen.dart';
import '../agro_pickup/screens/milk_pickup_screen.dart';
import '../assistant/assistant_entry.dart';
import '../oil_change/screens/oil_change_home_screen.dart';
import '../food/screens/food_screen.dart';
import '../platform_store/screens/platform_store_screen.dart';
import '../wholesale/models/wholesale_product.dart';
import '../wholesale/screens/wholesale_market_screen.dart';
import '../wholesale/screens/wholesale_product_detail_screen.dart';
import 'screens/courier_services_hub_screen.dart';
import '../yuk_intercity/screens/yuk_intercity_screen.dart';
import '../yuk_local/screens/yuk_local_screen.dart';
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
import '../relatives/screens/relatives_screen.dart';
import 'controllers/active_orders_controller.dart';
import 'controllers/home_controller.dart';
import 'home_services_catalog.dart';
import 'widgets/ava_quick_actions.dart';
import 'widgets/active_order_card.dart';
import 'home_module_gate.dart';
import 'home_modules_catalog.dart';
import '../../models/search_index_entry.dart';
import 'widgets/all_services_screen.dart';
import 'widgets/home_alive_background.dart';
import 'widgets/home_global_search.dart';
import '../tv_market/screens/tv_market_feed_screen.dart';
import 'widgets/home_ads_section.dart';
import 'widgets/home_avagram_section.dart';
import 'widgets/home_dating_section.dart';
import 'widgets/home_ev_section.dart';
import 'widgets/home_intercity_section.dart';
import 'widgets/home_market_section.dart';
import 'widgets/home_wholesale_section.dart';
import 'widgets/home_yuk_local_section.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
// Эски пастки меню ранглари (`_headerBorder`, `_brandGreen`,
// `_inactiveTab`) билан бирга олиб ташланди — янги `AvaBottomNav`
// токенлардан фойдаланади.
const _bg = AvaLight.bg;

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

/// Бош саҳифа — янги дизайн тизими.
///
/// Тартиби: юқори қатор (AVA + ҳудуд) · фаол буюртма карточкаси ·
/// сариқ банер · асосий ўтишлар · универсал қидирув · 2–11-бўлимлар ·
/// пастки меню. Ҳар бўлим `AvaSection` устига қурилган, шунинг учун
/// юкланиш / бўш / хатолик ҳолатлари бир хил.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeController()),
        ChangeNotifierProvider(
          create: (ctx) =>
              ActiveOrdersController(rides: ctx.read<RidesRepository>()),
        ),
      ],
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
  String? _lastAppliedServiceAreaId;
  Timer? _deferredBootstrapTimer;
  DateTime? _lastDeferredBootstrapAt;

  @override
  void initState() {
    super.initState();
    _configListener = () {
      if (mounted) setState(() {});
    };
    ServiceConfigHolder.revision.addListener(_configListener!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ServiceConfigHolder.bootstrap());
      // Фаол буюртма топилганда АВТОМАТИК кузатиш экранига ўтиш олиб
      // ташланди (эга қарори) — энди `ActiveOrderCard` кўринади ва ўтиш
      // фойдаланувчи босганда бўлади. Push орқали келган «сафар қабул
      // қилинди» йўли тегилмади: `push_navigation` ўзи `LocalTaxiScreen`
      // га ўтади ва `resume_local_trip_id` ни ўша экран ишлатади.
      final c = context.read<HomeController>();
      _promoSub = c.onAgroPromo.listen(_showAgroPromo);
      unawaited(IntercityDriverResume.tryResumeOnAppLaunch(context));
    });
  }

  /// Home яна кўринганда.
  void _onHomeResurface() {
    if (!mounted) return;
    // Config sync — fade тугагач, фақат керак бўлса; ортиқча rebuild йўқ.
    _scheduleDeferredConfigBootstrap();
  }

  /// Pop анимациясидан кейин silent bootstrap; 45 с ичида такрорланмайди.
  void _scheduleDeferredConfigBootstrap() {
    final now = DateTime.now();
    if (_lastDeferredBootstrapAt != null &&
        now.difference(_lastDeferredBootstrapAt!) <
            const Duration(seconds: 45)) {
      return;
    }
    _deferredBootstrapTimer?.cancel();
    _deferredBootstrapTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _lastDeferredBootstrapAt = DateTime.now();
      unawaited(ServiceConfigHolder.bootstrap());
    });
  }

  /// Битта `users/{uid}` стрими geo конфигни ҳам боқади — иккинчи
  /// Firestore кузатувчиси йўқ. (Илгари бу стрим ҳамён карточкаси учун
  /// ҳам ишлатиларди; карточка олиб ташланди, стрим қолди.)
  void _maybeApplyUserGeo(UserModel? user) {
    if (user == null) return;
    final areaId = user.serviceAreaId.trim();
    final districtId = user.districtId.trim();
    if (areaId.isEmpty && districtId.isEmpty) return;
    if (areaId == _lastAppliedServiceAreaId &&
        districtId == ServiceConfigHolder.districtId) {
      return;
    }
    _lastAppliedServiceAreaId = areaId;
    unawaited(() async {
      if (user.regionId.isNotEmpty && districtId.isNotEmpty) {
        await ServiceConfigHolder.applyGeo(
          regionId: user.regionId,
          districtId: districtId,
          serviceAreaId: areaId,
        );
      } else if (areaId.isNotEmpty) {
        await ServiceConfigHolder.applyServiceArea(areaId);
      }
      if (mounted) setState(() {});
    }());
  }


  @override
  void dispose() {
    _deferredBootstrapTimer?.cancel();
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

  static const _paymentOpenFailedKeys = {
    'pay_click': 'click_open_failed',
    'pay_payme': 'payme_open_failed',
    'pay_paynet': 'paynet_open_failed',
  };

  Future<void> _openPaymentProvider(PaymentProviderApp app) async {
    final opened = await openPaymentProviderApp(app);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(_paymentOpenFailedKeys[app.id]!)),
        ),
      );
    }
  }

  /// Танишув — иловадаги ўз экрани (эга қарори). Эски Telegram бот
  /// ўчирилмади: у [DatingHomeScreen] нинг AppBar'идаги тугмадан очилади.
  Future<void> _openDating() async {
    if (!ServiceConfigHolder.isOpenable('dating')) {
      _showTezKundaSnack();
      return;
    }
    await _push(const DatingHomeScreen());
  }

  Future<void> _openModule(HomeModule m) async {
    if (!HomeModuleGate.canOpen(m.id)) {
      HomeModuleGate.onTapBlocked(context, m.id);
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
      case 'platform_store':
        screen = const PlatformStoreScreen();
        break;
      case 'tv_market':
        screen = const TvMarketFeedScreen();
        break;
      default:
        return;
    }
    await _push(screen);
  }

  void _showTezKundaSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('home_coming_soon')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Yuk modullari (`yuk_local` / `yuk_intercity`): region gate + telefon
  /// majburiy (e'lon egaligi telefon bo'yicha).
  Future<void> _openYukModule(String moduleId, Widget screen) async {
    if (!ServiceConfigHolder.isOpenable(moduleId)) {
      _showTezKundaSnack();
      return;
    }
    final phone = phoneDigits(context.read<HomeController>().phone);
    if (phone.length < 9) {
      needPhoneForAction(context);
      return;
    }
    await _push(screen);
  }

  Future<void> _openSearchEntry(SearchIndexEntry e) async {
    final module = e.moduleId.trim();
    if (module.isEmpty) return;

    if (e.type == SearchIndexEntry.typeIntercityRoute) {
      await _push(
        IntercityTaxiScreen(
          autoFrom: e.from.isNotEmpty ? e.from : null,
          autoTo: e.to.isNotEmpty ? e.to : null,
        ),
      );
      return;
    }

    if (e.type == SearchIndexEntry.typePlatformProduct ||
        module == 'platform') {
      await _push(
        PlatformStoreScreen(
          highlightProductId:
              e.type == SearchIndexEntry.typePlatformProduct ? e.sourceId : null,
        ),
      );
      return;
    }

    if (e.type == SearchIndexEntry.typeBreadProduct ||
        (module == 'bread' && e.sourceId.isNotEmpty && e.type != SearchIndexEntry.typeService)) {
      await _push(
        BreadScreen(
          highlightProductId:
              e.type == SearchIndexEntry.typeBreadProduct ? e.sourceId : null,
        ),
      );
      return;
    }

    if (e.type == SearchIndexEntry.typeFoodProduct ||
        (module == 'food' && e.sourceId.isNotEmpty && e.type != SearchIndexEntry.typeService)) {
      await _push(
        FoodScreen(
          highlightProductId:
              e.type == SearchIndexEntry.typeFoodProduct ? e.sourceId : null,
        ),
      );
      return;
    }

    if (e.type == SearchIndexEntry.typeLocalPlace) {
      await _openModule(HomeModulesCatalog.byId('local_taxi'));
      return;
    }

    // Yuk e'loni (har qanday moduleId — eski `yuk_birja` indeks yozuvlari ham)
    // doim shaharlararo doska.
    if (e.type == SearchIndexEntry.typeYukListing ||
        module == 'yuk_intercity') {
      if (!ServiceConfigHolder.isOpenable('yuk_intercity')) {
        _showTezKundaSnack();
        return;
      }
      await _push(
        YukIntercityScreen(
          highlightListingId:
              e.type == SearchIndexEntry.typeYukListing ? e.sourceId : null,
          autoFrom: e.from.isNotEmpty ? e.from : null,
          autoTo: e.to.isNotEmpty ? e.to : null,
        ),
      );
      return;
    }

    switch (module) {
      case 'yuk_local':
      // Eski indeksdagi `yuk_birja` xizmat kartasi — avvalgi default scope (local).
      case 'yuk_birja':
        if (!ServiceConfigHolder.isOpenable('yuk_local')) {
          _showTezKundaSnack();
          return;
        }
        await _push(const YukLocalScreen());
        return;
      case 'milk':
        await _push(const MilkPickupScreen());
        return;
      case 'oil_change':
        await _push(const OilChangeHomeScreen());
        return;
      case 'carpet_wash':
        await _push(const CarpetWashScreen());
        return;
      case 'circles':
        await _push(const RelativesScreen());
        return;
      case 'courier':
        if (!ServiceConfigHolder.isOpenable('courier')) {
          _showTezKundaSnack();
          return;
        }
        await _push(const CourierServicesHubScreen());
        return;
      case 'dating':
        await _openDating();
        return;
      case 'jobs':
        await _push(
          JobsScreen(
            initialTabIndex: e.type == SearchIndexEntry.typeService
                ? JobsTabs.service
                : JobsTabs.ad,
          ),
        );
        return;
      // «СОТИНГ» модули олиб ташланди — унинг мазмуни («Янги эълон»,
      // «Менинг эълонларим», лента) Бозор модулида тўлиқ бор. Эски
      // `search_index/sell` ёзуви прод'дан ўчирилгунча Бозорга олиб
      // борамиз — қидирув натижаси «ўлик» бўлиб қолмасин.
      case 'sell':
        await _openModule(HomeModulesCatalog.byId('cheap_products_home'));
        return;
      default:
        try {
          final m = HomeModulesCatalog.byId(module);
          await _openModule(m);
        } catch (_) {
          _showTezKundaSnack();
        }
    }
  }

  /// Пастки менюнинг табларини қайта ишлаш.
  Future<void> _onNavTap(AvaNavTab tab) async {
    switch (tab) {
      case AvaNavTab.home:
        return;
      case AvaNavTab.avagram:
        await _push(const TvMarketFeedScreen());
      case AvaNavTab.create:
        await _openCreateSheet();
      case AvaNavTab.messages:
        await _push(const NewsHubScreen());
      case AvaNavTab.cabinet:
        // «Буюртмалар» энди алоҳида таб эмас — Кабинет (профил) ичида.
        await _openProfileTab();
    }
  }

  Future<void> _openProfileTab() async {
    await openProfileScreen(context);
    if (!mounted) return;
    await context.read<HomeController>().refreshUser();
    if (mounted) _onHomeResurface();
  }

  /// «＋» — видео / эълон / маҳсулот / хизмат / сотувчи.
  Future<void> _openCreateSheet() async {
    final action = await showAvaCreateSheet(context);
    if (action == null || !mounted) return;

    final phone = canonicalPhoneId(context.read<HomeController>().phone);
    // Барча қўшиш йўллари эгалик телефонига боғланган.
    if (phoneDigits(phone).length < 9) {
      needPhoneForAction(context);
      return;
    }

    switch (action) {
      case AvaCreateAction.video:
        await _push(const TvPublishScreen());
      case AvaCreateAction.ad:
        await _push(
          const JobsScreen(initialTabIndex: JobsTabs.ad, openAddSheet: true),
        );
      case AvaCreateAction.service:
        await _push(
          const JobsScreen(
            initialTabIndex: JobsTabs.service,
            openAddSheet: true,
          ),
        );
      case AvaCreateAction.product:
        await _push(const CreateAdScreen());
      case AvaCreateAction.seller:
        await _push(
          WholesaleMarketScreen(userPhone: phone, initialTabIndex: 1),
        );
    }
  }

  /// Хизмат каталоги учун амаллар — каталог экранга боғланиб қолмасин.
  HomeServiceActions get _serviceActions => HomeServiceActions(
        push: _push,
        openModule: _openModule,
        openYukModule: _openYukModule,
        openPayment: _openPaymentProvider,
        openDating: _openDating,
        showComingSoon: _showTezKundaSnack,
      );

  /// «Барча хизматлар» — кўринадиган модуллар рўйхати.
  Future<void> _openAllServices() async {
    await _push(
      AllServicesScreen(
        items: buildHomeServices(context, a: _serviceActions),
      ),
    );
  }

  Future<void> _openAssistant() async {
    await openAssistantEntry(
      context,
      phone: context.read<HomeController>().phone,
      push: _push,
    );
  }

  /// Фаол буюртма карточкаси босилганда — тегишли кузатиш экрани.
  Future<void> _openActiveOrder(HomeActiveOrder order) async {
    final trip = order.trip;
    switch (order.kind) {
      case ActiveOrderKind.localTaxi:
        if (trip == null) return;
        await _push(
          trip.status == 'searching'
              ? SearchingScreen(
                  from: trip.fromAddr,
                  to: trip.toAddr,
                  taxiType: 'local',
                  tripId: trip.id,
                )
              : LocalTaxiActiveTripScreen(tripId: trip.id),
        );
      case ActiveOrderKind.marshrut:
        if (trip == null) return;
        await _push(MarshrutAcceptedScreen(trip: trip));
      case ActiveOrderKind.intercity:
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await _push(
          IntercityTaxiScreen(
            autoFrom: prefs.getString('last_intercity_from'),
            autoTo: prefs.getString('last_intercity_to'),
          ),
        );
    }
  }

  /// Улгуржи ёки Хитой бозори — телефон Home subtree'дан узатилади
  /// (`WholesaleMarketScreen` `HomeController` ни ўзи ўқий олмайди).
  /// Иккала бозор битта модул калити (`wholesale_market`) остида.
  Future<void> _openWholesale(String market) async {
    if (!ServiceConfigHolder.isOpenable('wholesale_market')) {
      _showTezKundaSnack();
      return;
    }
    await _push(
      WholesaleMarketScreen(
        userPhone: canonicalPhoneId(context.read<HomeController>().phone),
        market: market,
      ),
    );
  }

  /// Бўлимдаги маҳсулот — тўғридан-тўғри тафсилот саҳифаси.
  Future<void> _openWholesaleProduct(WholesaleProduct product) async {
    if (!ServiceConfigHolder.isOpenable('wholesale_market')) {
      _showTezKundaSnack();
      return;
    }
    await _push(WholesaleProductDetailScreen(product: product));
  }

  /// Юқори қатордаги ҳудуд тугмаси.
  Future<void> _openRegionPicker() async {
    final uid = phoneDigits(context.read<HomeController>().phone);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ZoneSelectScreen(
          uid: uid,
          allowCancel: true,
          onDone: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    // Ҳудуд ўзгарган бўлса — бўлимлар янги ҳудуд бўйича қайта тўлади.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final uid = phoneDigits(home.phone);
    final userRepo = context.read<UserRepository>();

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: AvaBottomNav(
        current: AvaNavTab.home,
        onTap: _onNavTap,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeAliveBackground(),
          SafeArea(
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
                      return CustomScrollView(
                    cacheExtent: 320,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                          0,
                          MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                          0,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            [
                              Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AvaTopBar(onPickRegion: _openRegionPicker),
                            _ActiveOrderSlot(onOpen: _openActiveOrder),
                            SizedBox(height: _sectionGap(context, base: 10)),
                            // Ҳамён карточкаси интерфейсдан олиб
                            // ташланди (тавсиф: «Ҳамён коддан
                            // ўчирилмайди, фақат интерфейсда
                            // яширилади»). `WalletScreen` жойида ва
                            // ишлайверади: AVA AI ҳамда EV ичидаги
                            // «тўлдириш» уни тўғридан-тўғри очади.
                            // Қуйидаги `openWalletScreen()` эса ҳозир
                            // чақирилмайди — ҳамён яна кўринадиган
                            // бўлса, тайёр туриши учун қолдирилди.
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
                            SizedBox(height: _sectionGap(context, base: 12)),
                            AvaQuickActions(
                              actions: defaultQuickActions(
                                context,
                                onOpenAll: _openAllServices,
                                onTaxi: () => _openModule(
                                  HomeModulesCatalog.byId('local_taxi'),
                                ),
                                onIntercity: () => _openModule(
                                  HomeModulesCatalog.byId('intercity'),
                                ),
                                onMarket: () => _openModule(
                                  HomeModulesCatalog.byId(
                                      'cheap_products_home'),
                                ),
                                onAssistant: _openAssistant,
                                onAvagram: () =>
                                    _push(const TvMarketFeedScreen()),
                              ),
                            ),
                            const SizedBox(height: 16),
                            HomeGlobalSearchBar(
                              onOpenEntry: _openSearchEntry,
                              onOpenClip: (clip) => _push(
                                TvMarketFeedScreen(initialClip: clip),
                              ),
                            ),
                            if (HomeModuleGate.showInGrid('jobs')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeAdsSection(
                                adType: 'ad',
                                titleKey: 'home_section_ads',
                                onOpenAll: () => _push(
                                  const JobsScreen(
                                    initialTabIndex: JobsTabs.ad,
                                  ),
                                ),
                                onOpenAd: (_) => _push(
                                  const JobsScreen(
                                    initialTabIndex: JobsTabs.ad,
                                  ),
                                ),
                              ),
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeAdsSection(
                                adType: 'service',
                                titleKey: 'home_section_services',
                                onOpenAll: () => _push(
                                  const JobsScreen(
                                    initialTabIndex: JobsTabs.service,
                                  ),
                                ),
                                onOpenAd: (_) => _push(
                                  const JobsScreen(
                                    initialTabIndex: JobsTabs.service,
                                  ),
                                ),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid(
                                'cheap_products_home')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeMarketSection(
                                onOpenAll: () => _openModule(
                                  HomeModulesCatalog.byId(
                                      'cheap_products_home'),
                                ),
                                onOpenAd: (_) => _openModule(
                                  HomeModulesCatalog.byId(
                                      'cheap_products_home'),
                                ),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('intercity')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeIntercitySection(
                                onOpenAll: () => _openModule(
                                  HomeModulesCatalog.byId('intercity'),
                                ),
                                onOpenRide: (ride) => _push(
                                  IntercityTaxiScreen(
                                    autoFrom: ride.fromCity,
                                    autoTo: ride.toCity,
                                  ),
                                ),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('yuk_local')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeYukLocalSection(
                                onOpenAll: () => _openYukModule(
                                  'yuk_local',
                                  const YukLocalScreen(),
                                ),
                                onOpenDriver: (_) => _openYukModule(
                                  'yuk_local',
                                  const YukLocalScreen(),
                                ),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid(
                                'wholesale_market')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeWholesaleSection(
                                market: WholesaleProduct.marketWholesale,
                                titleKey: 'home_module_wholesale',
                                onOpenAll: () => _openWholesale(
                                    WholesaleProduct.marketWholesale),
                                onOpenProduct: _openWholesaleProduct,
                              ),
                              SizedBox(height: AvaSpace.sectionMin),
                              // 8-бўлим: Хитой бозори. Архитектураси
                              // улгуржи билан бир хил (эга қарори) —
                              // ўша коллекция, `market` билан ажралади.
                              HomeWholesaleSection(
                                market: WholesaleProduct.marketChina,
                                titleKey: 'home_module_china',
                                onOpenAll: () =>
                                    _openWholesale(WholesaleProduct.marketChina),
                                onOpenProduct: _openWholesaleProduct,
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('ev_charging')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeEvSection(
                                onOpenMap: () =>
                                    _push(const EvChargingMapScreen()),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('dating')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeDatingSection(
                                viewerUid: uid,
                                viewerBirthDate: user?.birthDate ?? '',
                                viewerGender:
                                    user?.gender ?? home.gender,
                                onOpenAll: _openDating,
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('tv_market')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeAvagramSection(
                                onOpenAll: () =>
                                    _push(const TvMarketFeedScreen()),
                                onOpenClip: (clip) => _push(
                                  TvMarketFeedScreen(initialClip: clip),
                                ),
                              ),
                            ],
                          ],
                        ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            right: 0,
            width: 48,
            height: 48,
            child: const _HomeShareButton(),
          ),
        ],
      ),
    );
  }
}

/// Фаол буюртма карточкаси учун жой.
///
/// Телефонни controller'га боғлайди ва фақат шу қисм қайта қурилади —
/// буюртма ҳолати ўзгарганда бутун бош саҳифа rebuild бўлмайди.
class _ActiveOrderSlot extends StatelessWidget {
  const _ActiveOrderSlot({required this.onOpen});

  final Future<void> Function(HomeActiveOrder order) onOpen;

  @override
  Widget build(BuildContext context) {
    final phone = phoneDigits(context.select<HomeController, String>(
      (c) => c.phone,
    ));
    final orders = context.watch<ActiveOrdersController>();
    // `bind` такрор чақирилса ҳам ичида телефон ўзгармаса ҳеч нарса
    // қилмайди, шунинг учун build'дан чақириш хавфсиз.
    orders.bind(phone);

    final primary = orders.primary;
    if (primary == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ActiveOrderCard(
        order: primary,
        extraCount: orders.extraCount,
        onTap: () => onOpen(primary),
      ),
    );
  }
}

/// Карталар устида 48×48 ⋮ — алоҳида қатор йўқ; touch фақат шу квадрат.
class _HomeShareButton extends StatefulWidget {
  const _HomeShareButton();

  @override
  State<_HomeShareButton> createState() => _HomeShareButtonState();
}

class _HomeShareButtonState extends State<_HomeShareButton> {
  static const _navy = Color(0xFF0A2540);

  Future<void> _openMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx + size.width - 220,
        origin.dy + size.height,
        origin.dx + size.width,
        origin.dy + size.height + 8,
      ),
      items: [
        PopupMenuItem(
          value: 'share',
          // Ёрлиқ узун тилларда (рус) менюга сиғмай оверфлоу берарди —
          // Flexible + 2 қатор ҳар қандай тил/шрифт ўлчамида сиғдиради.
          child: Row(
            children: [
              const Icon(Icons.share_rounded, color: _navy, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(context.tr('app_share_title'), maxLines: 2),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected != 'share') return;
    final ok = await shareAvaApp(context);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('app_share_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openMenu,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.more_vert_rounded,
                color: Color(0xE6FFFFFF),
                size: 38,
              ),
              Icon(
                Icons.more_vert_rounded,
                color: _navy,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Телефон киритилмаган — амални бажариб бўлмайди, профилга юборамиз.
///
/// Илгари бу `_HomeBottomNav` синфининг статик методи эди; пастки меню
/// `AvaBottomNav` билан алмаштирилгач, ёрдамчилар шу ерга кўчди.
void needPhoneForAction(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.tr('need_phone_profile')),
      duration: const Duration(seconds: 3),
    ),
  );
  unawaited(openProfileScreen(context));
}

/// Ҳамён экрани.
///
/// Ҳамён пастки менюдан олиб ташланди (тавсиф талаби — «коддан
/// ўчирилмайди, фақат интерфейсда яширилади»), лекин бу йўл қолди:
/// ҳамён карточкаси, AVA AI ва EV ичидаги «тўлдириш» шуни чақиради.
Future<void> openWalletScreen(BuildContext context) async {
  final phone = phoneDigits(context.read<HomeController>().phone);
  if (phone.length < 9) {
    needPhoneForAction(context);
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => WalletScreen(phone: phone)),
  );
}

/// Кабинет (профил) экрани.
Future<void> openProfileScreen(BuildContext context) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ProfileScreen()),
  );
}
