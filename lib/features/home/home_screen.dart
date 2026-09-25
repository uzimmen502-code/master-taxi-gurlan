import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../ev_charging/screens/ev_charging_map_screen.dart';
import '../agro_pickup/screens/milk_pickup_screen.dart';
import '../assistant/assistant_entry.dart';
import '../oil_change/screens/oil_change_home_screen.dart';
import '../food/screens/food_screen.dart';
import '../platform_store/screens/platform_store_screen.dart';
import '../wholesale/screens/wholesale_market_screen.dart';
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
import 'widgets/active_order_card.dart';
import 'home_module_gate.dart';
import 'home_modules_catalog.dart';
import '../../models/search_index_entry.dart';
import 'widgets/all_services_screen.dart';
import 'widgets/home_alive_background.dart';
import 'widgets/home_global_search.dart';
import 'widgets/promo_carousel.dart';
import 'widgets/services_spotlight_carousel.dart';
import 'widgets/wallet_card.dart';
import '../tv_market/screens/tv_market_feed_screen.dart';
import '../tv_market/widgets/home_video_stage.dart';

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
  /// Home қайта очилганда ҳамён 11 с яна кўринсин.
  int _walletRevealEpoch = 0;
  bool _walletVisible = true;
  Timer? _walletHideTimer;
  Timer? _deferredBootstrapTimer;
  DateTime? _lastDeferredBootstrapAt;

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
  /// [revealWallet]: фақат профил/буюртма/ҳамён дан қайтганда — хизматдан
  /// қайтганда ҳамён мажбурий очилмайди (сатҳ силжиши йўқ).
  void _onHomeResurface({bool revealWallet = false}) {
    if (!mounted) return;
    if (revealWallet) {
      setState(() {
        _walletRevealEpoch++;
        _walletVisible = true;
      });
      _armWalletHideTimer();
    }
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
    _walletHideTimer?.cancel();
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

  String _displayName(
      BuildContext context, UserModel? user, HomeController home) {
    final name = (user?.name ?? home.name).trim();
    final phone =
        user?.phone.trim().isNotEmpty == true ? user!.phone : home.phone;
    if (name.isEmpty) {
      return phone.isNotEmpty ? phone : context.tr('user_default_name');
    }
    final gender = (user?.gender.trim().isNotEmpty == true
            ? user!.gender
            : home.gender)
        .trim()
        .toLowerCase();
    final key = gender == 'female'
        ? 'home_display_name_opa'
        : 'home_display_name_aka';
    return context.tr(key).replaceAll('{name}', name);
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
        await _openDatingTelegramBot();
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
    if (mounted) _onHomeResurface(revealWallet: true);
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
                                              needPhoneForAction(
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
                                            if (mounted) {
                                              _onHomeResurface(
                                                  revealWallet: true);
                                            }
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
                            Builder(
                              builder: (context) {
                                final spotlightItems = <ServiceSpotlightItem>[
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
                                  moduleId: 'yuk_local',
                                  label: context.tr('home_module_yuk_local'),
                                  imagePath:
                                      'assets/images/services/service_yuk_local.png',
                                  onTap: () => _openYukModule(
                                    'yuk_local',
                                    const YukLocalScreen(),
                                  ),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'yuk_intercity',
                                  label:
                                      context.tr('home_module_yuk_intercity'),
                                  imagePath:
                                      'assets/images/services/service_yuk_birja.png',
                                  onTap: () => _openYukModule(
                                    'yuk_intercity',
                                    const YukIntercityScreen(),
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
                                  moduleId: 'platform_store',
                                  label: context
                                      .tr('home_module_platform_store'),
                                  icon: Icons.storefront_rounded,
                                  iconColor: const Color(0xFF00BCD4),
                                  onTap: () {
                                    if (!ServiceConfigHolder.isOpenable(
                                        'platform_store')) {
                                      _showTezKundaSnack();
                                      return;
                                    }
                                    _push(const PlatformStoreScreen());
                                  },
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'tv_market',
                                  label:
                                      context.tr('home_module_tv_market'),
                                  icon: Icons.play_circle_filled_rounded,
                                  iconColor: const Color(0xFFFF1744),
                                  onTap: () {
                                    if (!ServiceConfigHolder.isOpenable(
                                        'tv_market')) {
                                      _showTezKundaSnack();
                                      return;
                                    }
                                    _push(const TvMarketFeedScreen());
                                  },
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
                                  moduleId: 'chatgpt',
                                  label: context.tr('home_module_chatgpt'),
                                  icon: Icons.auto_awesome_rounded,
                                  iconColor: const Color(0xFF10A37F),
                                  onTap: () => openAssistantEntry(
                                    context,
                                    phone: home.phone,
                                    push: _push,
                                  ),
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
                                      needPhoneForAction(context);
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
                                ServiceSpotlightItem(
                                  moduleId: 'ev_charging',
                                  label: context.tr('home_module_ev_charging'),
                                  imagePath:
                                      'assets/images/services/service_ev_charging.png',
                                  onTap: () =>
                                      _push(const EvChargingMapScreen()),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'pay_click',
                                  label: context.tr('home_module_click'),
                                  svgPath:
                                      'assets/images/services/service_pay_click.svg',
                                  onTap: () => _openPaymentProvider(kClickApp),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'pay_payme',
                                  label: context.tr('home_module_payme'),
                                  svgPath:
                                      'assets/images/services/service_pay_payme.svg',
                                  onTap: () => _openPaymentProvider(kPaymeApp),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'pay_paynet',
                                  label: context.tr('home_module_paynet'),
                                  imagePath:
                                      'assets/images/services/service_pay_paynet.png',
                                  onTap: () =>
                                      _openPaymentProvider(kPaynetApp),
                                ),
                                ServiceSpotlightItem(
                                  moduleId: 'wholesale_market',
                                  label: context.tr('home_module_wholesale'),
                                  icon: Icons.warehouse_outlined,
                                  iconColor: const Color(0xFF6D4C41),
                                  onTap: () {
                                    if (!ServiceConfigHolder.isOpenable(
                                        'wholesale_market')) {
                                      _showTezKundaSnack();
                                      return;
                                    }
                                    _push(WholesaleMarketScreen(
                                      userPhone: canonicalPhoneId(
                                        context.read<HomeController>().phone,
                                      ),
                                    ));
                                  },
                                ),
                                ];
                                return ServicesSpotlightCarousel(
                                  items: spotlightItems,
                                  onTitleTap: () => _push(
                                    AllServicesScreen(items: spotlightItems),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            HomeGlobalSearchBar(
                              onOpenEntry: _openSearchEntry,
                            ),
                          ],
                        ),
                            ],
                          ),
                        ),
                      ),
                      if (HomeModuleGate.showInGrid('tv_market'))
                        const HomeVideoStage(),
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
