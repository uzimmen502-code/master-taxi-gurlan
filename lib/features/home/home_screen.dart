import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_share.dart';
import '../../core/geo/geo_context.dart';
import '../../core/geo/geo_selector.dart';
import '../../core/geo/geo_suggest_banner.dart';
import '../../core/geo/location_area_service.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/payment_provider_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/home_module.dart';
import '../../models/user_model.dart';
import '../../models/home_ticker_ad.dart';
import '../../models/platform_product.dart';
import '../../repositories/platform_products_repository.dart';
import '../../repositories/rides_repository.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/news_repository.dart';
import '../../repositories/home_ticker_repository.dart';
import '../../shared/widgets/no_internet_banner.dart';
import '../customer_confirm/widgets/customer_confirm_banner.dart';
import 'widgets/home_info_ticker.dart';
import '../../core/widgets/zone_gate.dart';
import '../ads/models/ad_model.dart';
import '../ads/screens/ad_details_screen.dart';
import '../ads/screens/cheap_products_screen.dart';
import '../ads/screens/create_ad_screen.dart';
import '../profile/screens/news_hub_screen.dart';
import '../tv_market/screens/tv_publish_screen.dart';
import 'widgets/ava_bottom_nav.dart';
import 'widgets/ava_top_bar.dart';
import '../bread/screens/bread_screen.dart';
import '../carpet_wash/screens/carpet_wash_screen.dart';
import '../dating/dating_telegram_bot.dart';
import '../ev_charging/screens/ev_charging_map_screen.dart';
import '../agro_pickup/screens/milk_pickup_screen.dart';
import '../oil_change/screens/oil_change_home_screen.dart';
import '../restaurants/data/restaurants_repository.dart';
import '../restaurants/screens/restaurant_screen.dart';
import '../restaurants/screens/restaurants_list_screen.dart';
import '../ads/widgets/platform_market_card.dart' show openPlatformProductDetail;
import '../wholesale/models/wholesale_product.dart';
import '../wholesale/screens/wholesale_market_screen.dart';
import '../wholesale/screens/wholesale_product_detail_screen.dart';
import 'screens/courier_services_hub_screen.dart';
import '../yuk_intercity/screens/yuk_intercity_screen.dart';
import '../yuk_local/screens/yuk_local_screen.dart';
import '../../models/driver_roles.dart';
import 'widgets/active_roles_strip.dart';
import '../courier/screens/courier_screen.dart';
import '../../repositories/courier_capability_repository.dart';
import '../courier/widgets/courier_apply_flow.dart';
import 'widgets/work_roles_sheet.dart';
import '../../services/user_audience.dart';
import '../driver_hub/driver_hub_actions.dart';
import '../driver_hub/screens/driver_hub_screen.dart';
import '../../shared/car/car_edit_dialog.dart';
import '../assistant/assistant_entry.dart';
import '../book/screens/ava_book_screen.dart';
import '../restaurants/merchant/restaurant_entry_flow.dart';
import '../../shared/widgets/taxi_agreement_sheet.dart';
import '../../repositories/driver_repository.dart';
import '../intercity_taxi/driver/intercity_driver_onboarding.dart';
import '../intercity_taxi/driver/intercity_driver_resume.dart';
import '../intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../../models/job_ad.dart';
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
import 'controllers/home_unread_badge.dart';
import 'home_services_catalog.dart';
import 'widgets/home_services_olx_row.dart';
import 'widgets/active_order_card.dart';
import 'home_module_gate.dart';
import 'home_modules_catalog.dart';
import '../../models/search_index_entry.dart';
import 'widgets/all_services_screen.dart';
import 'widgets/home_alive_background.dart';
import 'widgets/home_global_search.dart';
import '../realty/screens/realty_detail_screen.dart';
import '../realty/screens/realty_map_screen.dart';
import '../realty/screens/realty_screen.dart';
import '../tv_market/screens/tv_market_feed_screen.dart';
import 'widgets/home_ads_section.dart';
import 'widgets/home_restaurants_section.dart';
import 'widgets/home_avagram_section.dart';
import 'widgets/home_dating_section.dart';
import 'widgets/home_ev_section.dart';
import 'widgets/home_intercity_section.dart';
import 'widgets/home_market_section.dart';
import 'widgets/home_realty_section.dart';
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

  /// «Хабарлар» таби белгиси (ўқилмаган хабарлар). Телефон кечроқ тайёр
  /// бўлади, шунинг учун оқим `build`да телефон пайдо бўлганда уланади.
  late final HomeUnreadBadge _unread;
  String _unreadPhone = '';

  /// Тортиб янгилаш ҳисоблагичи: ошса, бўлимлар қайта яратилади ва ўз
  /// маълумотини қайта сўрайди (қаранг: [_refreshHome]).
  int _refreshEpoch = 0;

  @override
  void initState() {
    super.initState();
    final news = context.read<NewsRepository>();
    _unread = HomeUnreadBadge(
      watch: ({required userId, required audiences}) =>
          news.watchUnreadTotal(userId: userId, audiences: audiences),
      audience: UserAudience.current,
    );
    _configListener = () {
      if (mounted) setState(() {});
    };
    ServiceConfigHolder.revision.addListener(_configListener!);
    GeoContext.revision.addListener(_configListener!);
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
      unawaited(_checkLocationSuggestion());
      unawaited(_refreshDriverRoles());
    });
  }

  /// Home яна кўринганда.
  void _onHomeResurface() {
    if (!mounted) return;
    // Config sync — fade тугагач, фақат керак бўлса; ортиқча rebuild йўқ.
    _scheduleDeferredConfigBootstrap();
    unawaited(_checkLocationSuggestion());
    unawaited(_refreshDriverRoles());
    unawaited(_syncUnread());
  }

  /// Бўлим калити: тортиб янгилашда ўзгаради → бўлим қайта яратилади.
  Key _sectionKey(String base) => ValueKey('${base}_$_refreshEpoch');

  /// Хабарлар белгисини ҳозирги телефон/аудиторияга мослайди.
  Future<void> _syncUnread() =>
      _unread.sync(context.read<HomeController>().phone);

  /// Тортиб янгилаш: конфиг, ҳудуд таклифи, ҳайдовчи ҳолати, белги қайта
  /// ўқилади ва ҳар бўлим қайта яратилиб ўз маълумотини қайта сўрайди.
  ///
  /// Индикатор камида ярим сония кўринади — бўлимлар ўзи мустақил юклангани
  /// учун ҳисоб-китоб кутилмайди, лекин «ҳеч нарса бўлмади» таассуроти
  /// қолмасин.
  Future<void> _refreshHome() async {
    if (!mounted) return;
    final home = context.read<HomeController>();
    setState(() => _refreshEpoch++);
    _lastLocationCheckAt = null;
    _lastDeferredBootstrapAt = null;
    await Future.wait<void>([
      ServiceConfigHolder.bootstrap(),
      home.refreshUser(),
      _checkLocationSuggestion(),
      _refreshDriverRoles(),
      _syncUnread(),
      Future<void>.delayed(const Duration(milliseconds: 500)),
    ].map((f) => f.catchError((Object _) {})));
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


  /// Ҳудудга боғлиқ бўлимлар калити: туман ўзгарса бўлим ҚАЙТА ЯРАТИЛАДИ
  /// ва янги сўров очади. Аввал бўлимлар туманни фақат `initState`да
  /// ўқирди — ҳудуд алмашгач эски туман эълонлари қоларди (geo аудит).
  ///
  /// Фаол ҳудуд (D-GEO-1) — яшаш жойи ёки танланган/локация ҳудуди.
  String get _geoKey =>
      '${GeoContext.active.regionId}:${GeoContext.active.districtId}';

  /// Локациядан аниқланган туман (1б, D-GEO-12/13) — ҳудуд ойнасида
  /// «Ҳозирги жойим» пункти; `null` — аниқланмаган.
  GeoArea? _locationArea;

  /// Кўрсатиладиган локация таклифи (D-GEO-12) — `null` бўлса йўқ.
  GeoArea? _suggestArea;
  DateTime? _lastLocationCheckAt;

  /// Жорий туманни аниқлаш (рухсат СЎРАМАЙДИ, 10 дақиқада бир марта).
  Future<void> _checkLocationSuggestion() async {
    final now = DateTime.now();
    if (_lastLocationCheckAt != null &&
        now.difference(_lastLocationCheckAt!) < const Duration(minutes: 10)) {
      return;
    }
    _lastLocationCheckAt = now;
    final area = await LocationAreaService().detect();
    if (!mounted) return;
    final dismissed =
        area == null ? null : await suggestionDismissedAt(area.districtId);
    if (!mounted) return;
    setState(() {
      _locationArea = area;
      _suggestArea = shouldSuggestLocation(
        detected: area,
        active: GeoContext.active,
        dismissedAt: dismissed,
        now: DateTime.now(),
      )
          ? area
          : null;
    });
  }

  Future<void> _acceptLocationSuggestion() async {
    final a = _suggestArea;
    if (a == null) return;
    setState(() => _suggestArea = null);
    await GeoContext.setActive(a, GeoAreaSource.location);
  }

  Future<void> _declineLocationSuggestion() async {
    final a = _suggestArea;
    if (a == null) return;
    setState(() => _suggestArea = null);
    await dismissSuggestion(a.districtId, DateTime.now());
  }

  @override
  void dispose() {
    _deferredBootstrapTimer?.cancel();
    _promoSub?.cancel();
    _unread.dispose();
    if (_configListener != null) {
      ServiceConfigHolder.revision.removeListener(_configListener!);
      GeoContext.revision.removeListener(_configListener!);
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

  /// Танишув — ТАШҚИ Telegram бот (@bilish_tanish_bot).
  ///
  /// Эга қарори (2026-09-26, аввалги талабга қайтиш): бўлим фойдаланувчини
  /// тўғридан-тўғри ботга олиб боради. Сабаби ўлчовдан аниқ: ботда 18 744
  /// ойлик фойдаланувчи бор, иловадаги `dating_profiles` коллекцияси эса
  /// БЎШ (0 профил) — яъни илова ичидаги экран фойдаланувчини бўш рўйхатга
  /// олиб борарди.
  ///
  /// [DatingHomeScreen] ва унинг CF'лари РЕПОДА ҚОЛАДИ (ўчирилмайди) —
  /// келажакда бот билан синхронлаш қилинса, улар тайёр туради. Ҳозир
  /// уларга ҳеч қаердан йўл йўқ.
  Future<void> _openDating() async {
    if (!ServiceConfigHolder.isOpenable('dating')) {
      _showTezKundaSnack();
      return;
    }
    if (!mounted) return;
    await openDatingTelegramBot(context);
  }

  /// «Кафе-Ресторан» (D-REST-6): модул «Тез кунда» бўлса ҳам INTERNAL
  /// синовчи киради (сервер `testerIds`, logistics намунаси, 42-банд).
  Future<void> _openRestaurants({double? lat, double? lng}) async {
    final openable = HomeModuleGate.canOpen('restaurants');
    if (!openable && !await RestaurantsRepository().hasAccess()) {
      if (mounted) HomeModuleGate.onTapBlocked(context, 'restaurants');
      return;
    }
    if (!mounted) return;
    await _push(RestaurantsListScreen(userLat: lat, userLng: lng));
  }

  Future<void> _openModule(HomeModule m) async {
    if (m.id == 'restaurants') {
      await _openRestaurants();
      return;
    }
    if (!HomeModuleGate.canOpen(m.id)) {
      HomeModuleGate.onTapBlocked(context, m.id);
      return;
    }
    final Widget screen;
    switch (m.id) {
      case 'bread':
        screen = const BreadScreen();
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

    // AVA товари / эски «AVA дўкони» хизмат картаси — алоҳида дўкон экрани
    // йўқ (2026-10-07): товар — ўзининг тафсилоти, хизмат — Улгуржи бозор.
    // `wholesale_market` — қидирув индексидаги янги хизмат картаси.
    if (e.type == SearchIndexEntry.typePlatformProduct) {
      final p = e.sourceId.isEmpty
          ? null
          : await PlatformProductsRepository()
              .getById(e.sourceId)
              .catchError((Object _) => null);
      if (!mounted) return;
      if (p != null && p.active) {
        await _openPlatformProduct(p, const []);
      } else {
        await _openWholesale(WholesaleProduct.marketWholesale);
      }
      return;
    }
    if (module == 'platform' || module == 'wholesale_market') {
      await _openWholesale(WholesaleProduct.marketWholesale);
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

    // «Овқат» модули олиб ташланди (2026-10-11), ўрнига кафе-ресторанлар.
    // Эски `search_index` food ёзувлари прод'дан ўчирилгунча ресторанларга
    // олиб борамиз — қидирув натижаси «ўлик» бўлиб қолмасин.
    if (e.type == SearchIndexEntry.typeFoodProduct || module == 'food') {
      await _openRestaurants();
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
            kind: e.type == SearchIndexEntry.typeService
                ? AdKind.service
                : AdKind.ad,
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

  /// «＋» менюси учун ҳайдовчи ҳолати (кэш): индикатор ва «Ҳайдовчи панели».
  DriverRoles _driverRoles = DriverRoles.none;
  bool _driverRolesLoaded = false;
  bool _driverRolesLoading = false;

  Future<void> _refreshDriverRoles() async {
    final uid = phoneDigits(context.read<HomeController>().phone);
    if (uid.length < 9) return;
    final roles = await context.read<DriverRepository>().driverRoles(uid);
    // Аудитория белгиси (янгиликлар, тасма, push) — ҳуқуқдан; фақат ҳолат
    // ҳақиқатан ўқилганда (узилишда "ҳайдовчи эмас" деб ёзиб юбормаймиз).
    // `await`: аудитория белгиси ёзилиб бўлгач Хабарлар белгиси уни ўқийди
    // (ҳайдовчи ҳуқуқи келса аудитория `user` → `driver` бўлади).
    if (roles.known) await UserAudience.saveTaxiDriver(roles.isDriver);
    if (!mounted) return;
    setState(() {
      _driverRoles = roles;
      _driverRolesLoaded = true;
    });
    unawaited(_syncUnread());
  }

  /// «＋» — «Менинг бизнесим»: видео · эълон · хизмат · онлайн дўкон · дўкон ·
  /// ҳайдовчи · курьер · уй ошпази · кафе · юк ташувчи · китоб · AVA AI.
  Future<void> _openCreateSheet() async {
    // Совуқ ишга туширишда телефон кечроқ тайёр бўлади — ҳолат ҳали юкланмаган
    // бўлса, менюни кўрсатишдан олдин қисқа муддат кутамиз.
    if (!_driverRolesLoaded) {
      await _refreshDriverRoles()
          .timeout(const Duration(milliseconds: 1500), onTimeout: () {});
      if (!mounted) return;
    } else {
      unawaited(_refreshDriverRoles());
    }
    final action = await showAvaCreateSheet(
      context,
      driverRoles: _driverRoles,
      // Кафе-ресторан модули яширин бўлса — «Уй ошпази» ва «Кафе» ҳам йўқ.
      hidden: {
        if (!ServiceConfigHolder.isVisible('restaurants')) ...{
          AvaCreateAction.homeCook,
          AvaCreateAction.cafe,
        },
        if (!ServiceConfigHolder.isVisible('yuk_local')) AvaCreateAction.cargo,
      },
    );
    if (action == null || !mounted) return;

    // Китоб ва AVA AI телефонсиз ҳам очилади (AI ўзи рўйхатдан ўтишни таклиф қилади).
    if (action == AvaCreateAction.book) {
      await _push(const AvaBookScreen());
      return;
    }
    if (action == AvaCreateAction.assistant) {
      await openAssistantEntry(
        context,
        phone: context.read<HomeController>().phone,
        push: _push,
      );
      return;
    }

    final phone = canonicalPhoneId(context.read<HomeController>().phone);
    // Қолган барча йўллар эгалик телефонига боғланган.
    if (phoneDigits(phone).length < 9) {
      needPhoneForAction(context);
      return;
    }

    switch (action) {
      case AvaCreateAction.video:
        await _push(const TvPublishScreen());
      case AvaCreateAction.ad:
        await _push(
          const JobsScreen(kind: AdKind.ad, openAddSheet: true),
        );
      case AvaCreateAction.service:
        await _push(
          const JobsScreen(
            kind: AdKind.service,
            openAddSheet: true,
          ),
        );
      case AvaCreateAction.shopOnline:
        final target = await showAvaShopTargetSheet(context);
        if (target == null || !mounted) return;
        switch (target) {
          case AvaShopTarget.retail:
            await _push(const CreateAdScreen());
          case AvaShopTarget.wholesale:
            await _push(
              WholesaleMarketScreen(userPhone: phone, initialTabIndex: 1),
            );
        }
      case AvaCreateAction.driver:
        await _openWork();
      case AvaCreateAction.courier:
        await _openCourierWork();
      case AvaCreateAction.homeCook:
        await openRestaurantBusiness(context, ownerUid: phone, homeCook: true);
      case AvaCreateAction.cafe:
        await openRestaurantBusiness(context, ownerUid: phone, homeCook: false);
      case AvaCreateAction.cargo:
        await _openYukModule('yuk_local', const YukLocalScreen());
      case AvaCreateAction.book:
      case AvaCreateAction.assistant:
        break; // юқорида ҳал қилинган
    }
  }

  /// «＋» → «Ҳайдовчи бўлиш»: «Иш панели» (автомобиль, учта йўналиш, текширув,
  /// ҳамён). Курьер алоҳида банд (эга, 2026-10-16) — бу ерда йўқ. Амаллар мавжуд
  /// оқимларни чақиради — [_runWorkChoice] ва ҳ.к.
  Future<void> _openWork() async {
    final choices = <WorkChoice>[
      if (HomeModuleGate.canOpen('intercity')) WorkChoice.intercity,
      if (HomeModuleGate.canOpen('local_taxi')) WorkChoice.local,
      if (HomeModuleGate.canOpen('marshrut')) WorkChoice.marshrut,
    ];
    final uid = phoneDigits(context.read<HomeController>().phone);
    final driverRepo = context.read<DriverRepository>();
    await _push(DriverHubScreen(
      choices: choices,
      loadRoles: () => driverRepo.driverRoles(uid),
      loadCar: () => UserRepository().getCarInfo(canonicalPhoneId(uid)),
      onAction: _runWorkChoice,
      onEditCar: () async {
        await showCarEditDialog(context, uid: uid);
      },
      onDeleteCar: () => confirmAndDeleteCar(context, uid: canonicalPhoneId(uid)),
      onEndShift: () => endDriverShiftWithConfirm(
        context,
        uid: canonicalPhoneId(uid),
        driverRepo: driverRepo,
      ),
      onLeaveType: (choice) async {
        await leaveDriverTypeWithConfirm(
          context,
          uid: canonicalPhoneId(uid),
          taxiType: choice.name,
        );
      },
      onSubmitVerification: _submitTaxiVerification,
      onOpenWallet: () => openWalletScreen(context),
    ));
    if (mounted) unawaited(_refreshDriverRoles());
  }

  /// «Текширувга юбориш»: сервер ҳал қилади (`requestCapability`) — келишув
  /// керак бўлса варақ тақдим қилинади, қабул қилингач админ текшируви
  /// кутилади. Янги ҳолат (`verified` ва ҳ.к.) фақат админ/тизим томонидан.
  Future<HubSubmitResult> _submitTaxiVerification() async {
    try {
      final res = await context.read<DriverRepository>().requestTaxiCapability();
      if ((res['accountId'] ?? '').toString().isEmpty) return HubSubmitResult.failed;
      if (res['agreementRequired'] != true) return HubSubmitResult.alreadySent;
      if (!mounted) return HubSubmitResult.cancelled;
      final ok = await showTaxiAgreementSheet(
        context,
        version: (res['agreementVersion'] as int?) ?? 1,
        primaryColor: AppColors.primary,
      );
      return ok ? HubSubmitResult.sent : HubSubmitResult.cancelled;
    } catch (_) {
      return HubSubmitResult.failed;
    }
  }

  /// Иш панелидаги тур амали: ҳали ҳайдовчи бўлмаган тур — аввал тасдиқ
  /// (бекор қилиш ҳеч нарса ёзмайди), кейин мавжуд оқим.
  Future<void> _runWorkChoice(WorkChoice picked, DriverRoles roles) async {
    if (picked != WorkChoice.courier && !roles.types.contains(picked.name)) {
      if (!await confirmBecomeDriver(context, picked) || !mounted) return;
    }
    switch (picked) {
      case WorkChoice.intercity:
        await IntercityDriverOnboarding.run(context);
      case WorkChoice.local:
        await _push(const LocalTaxiScreen(startDriverOnOpen: true));
      case WorkChoice.marshrut:
        await _push(const MarshrutTaxiScreen(startDriverOnOpen: true));
      case WorkChoice.courier:
        await _openCourierWork();
    }
    if (mounted) unawaited(_refreshDriverRoles());
  }

  /// Курьер: панели бор — панел; ариза кўриб чиқилмоқда — хабар; акс ҳолда
  /// профилдаги билан БИР ХИЛ ариза оқими ([runCourierApplyFlow]).
  Future<void> _openCourierWork() async {
    var status = _driverRoles.courierStatus;
    if (status.isEmpty) {
      final uid = phoneDigits(context.read<HomeController>().phone);
      try {
        status = await CourierCapabilityRepository().fetchStatus(uid);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('courier_apply_failed'))),
          );
        }
        return;
      }
      if (!mounted) return;
    }
    if (CourierCapabilityRepository.panelStatuses.contains(status) ||
        CourierCapabilityRepository.finishOnlyStatuses.contains(status)) {
      await _push(const CourierScreen());
      return;
    }
    if (status == CourierCapabilityRepository.applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('courier_apply_pending'))),
      );
      return;
    }
    await runCourierApplyFlow(context);
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

  // `_openAssistant` олиб ташланди: у фақат эски `AvaQuickActions`
  // катагида ишлатиларди. AVA ёрдамчиси ҳамон очилади — хизматлар
  // рўйхатидаги `chatgpt` банди айнан шу `openAssistantEntry` ни
  // чақиради (`home_services_catalog.dart`).

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
  /// Ҳар бозор ЎЗ дарвозаси билан (2026-10-07): аввал Хитой бўлимининг
  /// «Ҳаммаси» тугмаси ҳам `wholesale_market` ни текширарди — Улгуржи
  /// ёпилса, ёқиқ Хитой бозори ҳам «Тез кунда» дерди.
  Future<void> _openWholesale(String market) async {
    if (!ServiceConfigHolder.isOpenable(WholesaleProduct.moduleIdFor(market))) {
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

  /// Аҳоли бозори бўлимидаги қатор — АЙНАН ўша эълоннинг тафсилоти.
  ///
  /// Илгари бу ерда эълон объекти `(_)` билан ташлаб юбориларди ва
  /// модулнинг умумий рўйхати очиларди — фойдаланувчи босган эълонини
  /// рўйхатдан қайтадан қидиришга мажбур эди.
  Future<void> _openMarketAd(AdModel ad) async {
    if (!ServiceConfigHolder.isOpenable('cheap_products_home')) {
      _showTezKundaSnack();
      return;
    }
    await _push(AdDetailsScreen(ad: ad));
  }

  /// Бўлимдаги маҳсулот — тўғридан-тўғри тафсилот саҳифаси.
  Future<void> _openWholesaleProduct(
    WholesaleProduct product,
    List<WholesaleProduct> shelf,
  ) async {
    if (!ServiceConfigHolder.isOpenable(
        WholesaleProduct.moduleIdFor(product.market))) {
      _showTezKundaSnack();
      return;
    }
    await _push(WholesaleProductDetailScreen(product: product, catalog: shelf));
  }

  /// AVA товари — Улгуржи бозорнинг бир қисми, шунинг учун Улгуржи
  /// дарвозаси (алоҳида «AVA дўкони» модули 2026-10-07 дан йўқ).
  Future<void> _openPlatformProduct(
    PlatformProduct product,
    List<PlatformProduct> shelf,
  ) async {
    if (!ServiceConfigHolder.isOpenable(
        WholesaleProduct.moduleIdFor(WholesaleProduct.marketWholesale))) {
      _showTezKundaSnack();
      return;
    }
    await openPlatformProductDetail(context, product, shelf);
  }

  /// Юқори қатордаги ҳудуд тугмаси (D-GEO-1, 1-такомиллаштириш): ФАОЛ
  /// ҳудудни танлайди — профил (яшаш жойи) ЎЗГАРМАЙДИ. Аввал бу тугма
  /// `ZoneSelectScreen` орқали профилни қайта ёзарди (geo аудит).
  Future<void> _openRegionPicker() async {
    await showGeoSelectorSheet(
      context,
      current: _locationArea,
      onChangeHome: _openHomeZonePicker,
    );
  }

  /// Яшаш жойини ўзгартириш — профилга ёзилади (эски йўл).
  Future<void> _openHomeZonePicker() async {
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final uid = phoneDigits(home.phone);
    final userRepo = context.read<UserRepository>();

    // Совуқ ишга туширишда телефон кечроқ тайёр бўлади — тайёр бўлганда
    // ҳайдовчи/курьер ҳолати бир марта юкланади.
    if (!_driverRolesLoaded && !_driverRolesLoading && uid.length >= 9) {
      _driverRolesLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshDriverRoles().whenComplete(() => _driverRolesLoading = false);
      });
    }
    // Телефон тайёр бўлгач (ёки алмашгач) ўқилмаганлар оқимини улаш.
    if (uid.length >= 9 && _unreadPhone != uid) {
      _unreadPhone = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_syncUnread());
      });
    }

    return Scaffold(
      backgroundColor: _bg,
      // Белги ўзгарганда фақат меню қайта чизилади, бутун саҳифа эмас.
      bottomNavigationBar: ListenableBuilder(
        listenable: _unread,
        builder: (context, _) => AvaBottomNav(
          current: AvaNavTab.home,
          onTap: _onNavTap,
          messagesBadge: _unread.total,
        ),
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
                      return RefreshIndicator(
                        color: context.ava.brandText,
                        onRefresh: _refreshHome,
                        child: CustomScrollView(
                    // Бўлим кам бўлса ҳам тортиб янгилаш ишлайверсин.
                    physics: const AlwaysScrollableScrollPhysics(),
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
                            // Фаол ҳайдовчилик/курьерлик ёзуви — локация матнининг айнан
                            // тагида (эга, 2026-10-15).
                            AvaTopBar(
                              onPickRegion: _openRegionPicker,
                              subline: _driverRoles.hasAnyActiveRole
                                  ? ActiveRolesStrip(
                                      roles: _driverRoles,
                                      onTap: _openProfileTab,
                                    )
                                  : null,
                            ),
                            if (_suggestArea != null &&
                                !_suggestArea!.sameAs(GeoContext.active))
                              GeoSuggestBanner(
                                area: _suggestArea!,
                                onYes: _acceptLocationSuggestion,
                                onNo: _declineLocationSuggestion,
                              ),
                            // Мижоз тасдиғи (D2/D7): курьер «олдим/етказдим»
                            // деганидан кейин мижоз ўз қурилмасида тасдиқлайди.
                            // Бўш бўлса ёки сервер жавобермаса — жой эгалламайди.
                            const CustomerConfirmBanner(),
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
                                  .watchForModuleCurrentRole('home_search'),
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
                            // Карусель ва «Барча хизматлар» сарлавҳаси орасидаги масофа 2 px (эга, 2026-10-15).
                            const SizedBox(height: 2),
                            // Хизматлар — OLX бош экранидаги жойлашув:
                            // 2 қатор, ёнга скролл, ранг доира ичида расм
                            // (қаранг: [HomeServicesOlxRow] — ўлчамлар
                            // olx.uz дан жонли олинган). Аввал бу ерда
                            // 6 та иконкали квадрат тугма (`AvaQuickActions`)
                            // турарди — эга қарори, 2026-09-26.
                            HomeServicesOlxRow(
                              items: buildHomeServices(
                                context,
                                a: _serviceActions,
                              ),
                              onTitleTap: _openAllServices,
                            ),
                            // Қидирув майдончаси юқоридаги бўлимга 2 px яқин (эга, 2026-10-15).
                            const SizedBox(height: 2),
                            HomeGlobalSearchBar(
                              onOpenEntry: _openSearchEntry,
                              onOpenClip: (clip) => _push(
                                TvMarketFeedScreen(initialClip: clip),
                              ),
                            ),
                            if (HomeModuleGate.showInGrid('dating')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeDatingSection(
                                key: _sectionKey('dating'),
                                viewerUid: uid,
                                viewerBirthDate: user?.birthDate ?? '',
                                viewerGender:
                                    user?.gender ?? home.gender,
                                onOpenAll: _openDating,
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('jobs')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeAdsSection(
                                key: _sectionKey(
                                    'ads_ad_${GeoContext.scopeFor('jobs').key}'),
                                adType: 'ad',
                                titleKey: 'home_section_ads',
                                onOpenAll: () => _push(
                                  const JobsScreen(kind: AdKind.ad),
                                ),
                                // АЙНАН босилган эълон тепага чиқади ва
                                // ажратиб кўрсатилади.
                                onOpenAd: (ad) => _push(
                                  JobsScreen(
                                    kind: AdKind.ad,
                                    highlightAdId: ad.id,
                                  ),
                                ),
                              ),
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeAdsSection(
                                key: _sectionKey(
                                    'ads_service_${GeoContext.scopeFor('jobs').key}'),
                                adType: 'service',
                                titleKey: 'home_section_services',
                                onOpenAll: () => _push(
                                  const JobsScreen(kind: AdKind.service),
                                ),
                                onOpenAd: (ad) => _push(
                                  JobsScreen(
                                    kind: AdKind.service,
                                    highlightAdId: ad.id,
                                  ),
                                ),
                              ),
                            ],
                            // Кафе-ресторанлар — «Яқиндаги хизматлар»дан
                            // кейин (эга қарори D-REST-6, 2026-10-08).
                            // Кўриниш дарвозаси виджетнинг ўзида
                            // (очиқ / синовчи / яширин).
                            HomeRestaurantsSection(
                              key: _sectionKey('restaurants'),
                              userLat: user?.address.lat,
                              userLng: user?.address.lng,
                              onOpenAll: () => _openRestaurants(
                                lat: user?.address.lat,
                                lng: user?.address.lng,
                              ),
                              onOpenRestaurant: (r) => _push(
                                RestaurantScreen(
                                  restaurant: r,
                                  userLat: user?.address.lat,
                                  userLng: user?.address.lng,
                                ),
                              ),
                            ),
                            // Кўчмас мулк — эълонлар оиласининг давоми
                            // (эга қарори, 2026-09-28): «Яқинингиздаги
                            // эълонлар» ва «Хизмат таклифлари»дан кейин,
                            // транспортдан олдин. Сабаби: бу ҳам эълон
                            // доскаси, бозор бўлимлари эса маҳсулот савдоси.
                            if (HomeModuleGate.showInGrid('realty')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeRealtySection(
                                key: _sectionKey(
                                    'realty_${GeoContext.scopeFor('realty').key}'),
                                onOpenAll: () => _push(const RealtyScreen()),
                                onOpenMap: () =>
                                    _push(const RealtyMapScreen()),
                                onOpenListing: (listing) => _push(
                                  RealtyDetailScreen(listing: listing),
                                ),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('intercity')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeIntercitySection(
                                key: _sectionKey('intercity_$_geoKey'),
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
                                key: _sectionKey(
                                    'yuk_local_${GeoContext.scopeFor('yuk_local').key}'),
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
                            // Бозор учлиги: Аҳоли бозори → Улгуржи бозори →
                            // Хитой бозори — эга қарори бўйича кетма-кет.
                            if (HomeModuleGate.showInGrid(
                                'cheap_products_home')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeMarketSection(
                                key: _sectionKey(
                                    'market_${GeoContext.scopeFor('cheap_products_home').key}'),
                                onOpenAll: () => _openModule(
                                  HomeModulesCatalog.byId(
                                      'cheap_products_home'),
                                ),
                                // АЙНАН босилган эълон очилади (умумий
                                // рўйхат эмас) — тафсилот экрани бор.
                                onOpenAd: _openMarketAd,
                              ),
                            ],
                            if (HomeModuleGate.showInGrid(
                                'wholesale_market')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeWholesaleSection(
                                key: _sectionKey('wholesale'),
                                market: WholesaleProduct.marketWholesale,
                                titleKey: 'home_module_wholesale',
                                onOpenAll: () => _openWholesale(
                                    WholesaleProduct.marketWholesale),
                                onOpenProduct: _openWholesaleProduct,
                                // AVA товарлари ҳам шу бўлимда (эга қарори
                                // 2026-10-07: AVA дўкони — Улгуржи бозор).
                                onOpenPlatformProduct: _openPlatformProduct,
                              ),
                            ],
                            // Хитой бозори. Архитектураси улгуржи билан
                            // бир хил (эга қарори) — ўша коллекция,
                            // `market` билан ажралади. Лекин ДАРВОЗАСИ
                            // алоҳида (эга қарори, 2026-09-28): аввал
                            // `wholesale_market` га боғланган эди ва
                            // админ панелда мустақил ёқиб бўлмасди.
                            if (HomeModuleGate.showInGrid(
                                'china_market')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeWholesaleSection(
                                key: _sectionKey('china'),
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
                                key: _sectionKey('ev'),
                                userLat: user?.address.lat,
                                userLng: user?.address.lng,
                                onOpenMap: () =>
                                    _push(const EvChargingMapScreen()),
                              ),
                            ],
                            if (HomeModuleGate.showInGrid('tv_market')) ...[
                              SizedBox(height: AvaSpace.sectionMin),
                              HomeAvagramSection(
                                key: _sectionKey(
                                    'avagram_${GeoContext.scopeFor('tv_market').key}'),
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
                        ),
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
