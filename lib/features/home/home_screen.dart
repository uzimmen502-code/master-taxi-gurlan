import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../models/home_module.dart';
import '../../models/user_model.dart';
import '../../models/wallet_ledger_entry.dart';
import '../../repositories/intercity_bookings_repository.dart';
import '../../repositories/user_repository.dart';
import '../../shared/widgets/no_internet_banner.dart';
import '../ads/screens/cheap_products_screen.dart';
import '../bread/screens/bread_screen.dart';
import '../food/screens/food_screen.dart';
import '../courier_order/screens/courier_order_screen.dart';
import '../intercity_taxi/driver/intercity_driver_resume.dart';
import '../intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../jobs/jobs_tabs.dart';
import '../jobs/screens/jobs_screen.dart';
import '../local_taxi/passenger/screens/local_taxi_screen.dart';
import '../marshrut/passenger/screens/marshrut_taxi_screen.dart';
import '../profile/screens/profile_screen.dart';
import '../profile/screens/wallet_screen.dart';
import '../sell/screens/sell_offer_screen.dart';
import 'controllers/home_controller.dart';
import 'home_modules_catalog.dart';
import 'widgets/featured_products_section.dart';
import 'widgets/product_feed_section.dart';
import 'widgets/promo_carousel.dart';
import 'widgets/seller_cta_banner.dart';
import 'widgets/wallet_card.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
const _bg = Color(0xFFF6FAF2);
const _cardBorder = Color(0xFFC8DDB8);
const _sectionLabel = Color(0xFF7A9070);
const _headerBorder = Color(0xFFD4E8C4);
const _titleDark = Color(0xFF1A3A20);
const _primaryGreen = Color(0xFF2E7D32);
const _brandGreen = Color(0xFF36A63A);
const _inactiveTab = Color(0xFF9AB090);

/// Kichik ekranlar uchun matn/shrift masshtabini moslashtirish.
double _homeUiScale(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 340) return 0.86;
  if (w < 380) return 0.92;
  return 1.0;
}

double _scaled(BuildContext context, double size) =>
    size * _homeUiScale(context);

/// Bo‘limlar orasidagi vertikal masofa — ekran balandligi/kengligiga qarab.
double _sectionGap(BuildContext context, {required double base}) {
  final h = MediaQuery.sizeOf(context).height;
  final scale = _homeUiScale(context);
  final heightFactor = h < 640 ? 0.72 : h < 720 ? 0.82 : h < 800 ? 0.9 : 1.0;
  return (base * scale * heightFactor).clamp(6.0, base);
}

String _formatBalance(int balance) =>
    '${NumberFormat('#,###').format(balance)} so\'m';

String _lastTxAmount(WalletLedgerEntry? entry) {
  if (entry == null) return '—';
  final sign = entry.amount >= 0 ? '+' : '−';
  return '$sign${NumberFormat('#,###').format(entry.amount.abs())} so\'m';
}

String _todayText() {
  final now = DateTime.now();
  final d = now.day.toString().padLeft(2, '0');
  final m = now.month.toString().padLeft(2, '0');
  return '$d.$m.${now.year} yil';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkActiveIntercityBooking();
      final c = context.read<HomeController>();
      _promoSub = c.onAgroPromo.listen(_showAgroPromo);
      unawaited(IntercityDriverResume.tryResumeOnAppLaunch(context));
    });
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

  @override
  void dispose() {
    _promoSub?.cancel();
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
  }

  Future<void> _openModule(HomeModule m) async {
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
          builder: (_) => SellOfferScreen(
            phone: phone,
            defaultToPlatform: true,
            defaultToPublic: true,
          ),
        ),
      );
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

  String _displayName(UserModel? user, HomeController home) {
    final name = (user?.name ?? home.name).trim();
    final phone = user?.phone.trim().isNotEmpty == true
        ? user!.phone
        : home.phone;
    if (name.isEmpty) return phone.isNotEmpty ? phone : 'Foydalanuvchi';
    return '$name aka';
  }

  void _showTezKundaSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tez kunda'),
        duration: Duration(seconds: 2),
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
        onOrders: _showTezKundaSnack,
        onWallet: () => _HomeBottomNav.openWallet(context),
        onProfile: () async {
          await _HomeBottomNav.openProfile(context);
          if (!context.mounted) return;
          await context.read<HomeController>().refreshUser();
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
                  return StreamBuilder<List<WalletLedgerEntry>>(
                    stream: uid.length >= 9
                        ? userRepo.watchWalletLedger(uid, limit: 10)
                        : Stream.value(const []),
                    builder: (context, ledgerSnap) {
                      // Balansga ta'sir qilmaydigan qaydlar tranzaksiya emas:
                      // order_payment_cash/card — amount: 0 (to'lov tasdig'i);
                      // order_payment_product — amount musbat, lekin bu mahsulot
                      // bilan to'lov qaydi (meta.debitCredit: none), kirim emas.
                      // Kartada faqat balansni o'zgartirgan oxirgi yozuvni
                      // ko'rsatamiz (change_accrued, purchase_debit, payout, ...).
                      const skipTypes = {
                        'order_payment_cash',
                        'order_payment_card',
                        'order_payment_product',
                      };
                      final entries = ledgerSnap.data ?? const <WalletLedgerEntry>[];
                      WalletLedgerEntry? lastEntry;
                      for (final e in entries) {
                        if (e.amount != 0 && !skipTypes.contains(e.type)) {
                          lastEntry = e;
                          break;
                        }
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  MediaQuery.sizeOf(context).width < 360
                                      ? 12
                                      : 16,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    height: _sectionGap(context, base: 10)),
                                WalletCard(
                                  balance: _formatBalance(
                                      user?.bonusBalance ?? 0),
                                  lastTxAmount: _lastTxAmount(lastEntry),
                                  displayName: _displayName(user, home),
                                  dateText: _todayText(),
                                  locationText: 'Gurlan, Xorazm',
                                  lastTxIsCredit: lastEntry == null
                                      ? null
                                      : lastEntry.amount >= 0,
                                  onHistoryTap: () {
                                    if (uid.length < 9) {
                                      _HomeBottomNav.needPhone(context);
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            WalletScreen(phone: home.phone),
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(
                                    height: _sectionGap(context, base: 10)),
                                _HomeSearchBar(onTap: _showTezKundaSnack),
                                SizedBox(
                                    height: _sectionGap(context, base: 12)),
                                PromoCarousel(
                                  onNonTap: () => _openModule(
                                    HomeModulesCatalog.byId('bread'),
                                  ),
                                  onTaomTap: () => _openModule(
                                    HomeModulesCatalog.byId('food'),
                                  ),
                                  onBozorTap: () => _openModule(
                                    HomeModulesCatalog.byId(
                                        'cheap_products_home'),
                                  ),
                                  onLocalTaxiTap: () => _openModule(
                                    HomeModulesCatalog.byId('local_taxi'),
                                  ),
                                  onIntercityTap: () => _openModule(
                                    HomeModulesCatalog.byId('intercity'),
                                  ),
                                  onMarshrutTap: () => _openModule(
                                    HomeModulesCatalog.byId('marshrut'),
                                  ),
                                ),
                                SizedBox(
                                    height: _sectionGap(context, base: 12)),
                                _UnifiedServicesGrid(
                                  onLocal: () => _openModule(
                                    HomeModulesCatalog.byId('local_taxi'),
                                  ),
                                  onIntercity: () => _openModule(
                                    HomeModulesCatalog.byId('intercity'),
                                  ),
                                  onMarshrut: () => _openModule(
                                    HomeModulesCatalog.byId('marshrut'),
                                  ),
                                  onCourier: () async {
                                    final phone = phoneDigits(
                                      context.read<HomeController>().phone,
                                    );
                                    if (phone.length < 9) {
                                      _HomeBottomNav.needPhone(context);
                                      return;
                                    }
                                    await _push(const CourierOrderScreen());
                                  },
                                  onSell: () => _openModule(
                                    HomeModulesCatalog.byId('sell'),
                                  ),
                                  onFood: () => _openModule(
                                    HomeModulesCatalog.byId('food'),
                                  ),
                                  onJobAd: () => _push(
                                    const JobsScreen(
                                      initialTabIndex: JobsTabs.ad,
                                    ),
                                  ),
                                  onOnlineMarket: () => _openModule(
                                    HomeModulesCatalog.byId(
                                        'cheap_products_home'),
                                  ),
                                  onNon: () => _openModule(
                                    HomeModulesCatalog.byId('bread'),
                                  ),
                                  onCarWash: _showTezKundaSnack,
                                  onTire: _showTezKundaSnack,
                                  onOilChange: _showTezKundaSnack,
                                ),
                                const SizedBox(height: 16),
                                FeaturedProductsSection(
                                  onProductTap: (source) {
                                    final moduleId = switch (source) {
                                      'bread' => 'bread',
                                      'food' => 'food',
                                      'market' => 'cheap_products_home',
                                      _ => null,
                                    };
                                    if (moduleId == null) return;
                                    _openModule(
                                      HomeModulesCatalog.byId(moduleId),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                SellerCtaBanner(
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('sell'),
                                  ),
                                ),
                                const SizedBox(height: 16),
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

// ─── Search bar (placeholder) ────────────────────────────────────────────────
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({required this.onTap});

  final VoidCallback onTap;

  static const _fill = Color(0xFFE8EAEC);
  static const _hint = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(27),
        child: Ink(
          height: 53,
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(27),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const _StrokeIcon(_IconKind.search, color: _hint, size: 20),
              const SizedBox(width: 10),
              Text(
                'Taksi, taom, buyumlar qidirish...',
                style: TextStyle(
                  fontSize: 14,
                  color: _hint.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Taxi grid ───────────────────────────────────────────────────────────────
// ─── Unified services grid (4 ustun x 3 qator, PNG rasmlar) ──────────────────
class _UnifiedServicesGrid extends StatelessWidget {
  const _UnifiedServicesGrid({
    required this.onLocal,
    required this.onIntercity,
    required this.onMarshrut,
    required this.onCourier,
    required this.onSell,
    required this.onFood,
    required this.onJobAd,
    required this.onOnlineMarket,
    required this.onNon,
    required this.onCarWash,
    required this.onTire,
    required this.onOilChange,
  });

  final VoidCallback onLocal;
  final VoidCallback onIntercity;
  final VoidCallback onMarshrut;
  final VoidCallback onCourier;
  final VoidCallback onSell;
  final VoidCallback onFood;
  final VoidCallback onJobAd;
  final VoidCallback onOnlineMarket;
  final VoidCallback onNon;
  final VoidCallback onCarWash;
  final VoidCallback onTire;
  final VoidCallback onOilChange;

  @override
  Widget build(BuildContext context) {
    final items = <_GridItemData>[
      _GridItemData('assets/images/services/service_taxi_local.png',
          'Mahalliy TAKSI', onLocal),
      _GridItemData('assets/images/services/service_taxi_intercity.png',
          'Shaharlararo TAKSI', onIntercity),
      _GridItemData('assets/images/services/service_marshrut.png',
          'Marshrut TAKSI', onMarshrut),
      _GridItemData('assets/images/services/service_courier.png',
          'Kuryer xizmati', onCourier),
      _GridItemData('assets/images/services/service_sell.png',
          'Mahsulot sotaman', onSell),
      _GridItemData('assets/images/services/service_food.png',
          'Taom buyurtma', onFood),
      _GridItemData('assets/images/services/service_jobs.png',
          'Ish va E\'lon', onJobAd),
      _GridItemData('assets/images/services/service_market.png',
          'Onlayn BOZOR', onOnlineMarket),
      _GridItemData('assets/images/services/service_bread.png',
          'Non buyurtma', onNon),
      _GridItemData('assets/images/services/service_car_wash.png',
          'Avto yuvish', onCarWash),
      _GridItemData('assets/images/services/service_tire.png',
          'Avto Shina', onTire),
      _GridItemData('assets/images/services/service_oil_change.png',
          'Moy almashtirish', onOilChange),
    ];

    final colGap = _scaled(context, 13).clamp(10.0, 13.0);
    const rowGap = 2.0;

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: rowGap,
      crossAxisSpacing: colGap,
      childAspectRatio: 0.80,
      children: items.map((d) => _GridTile(data: d)).toList(),
    );
  }
}

class _GridItemData {
  const _GridItemData(this.image, this.label, this.onTap);
  final String image;
  final String label;
  final VoidCallback onTap;
}

class _GridTile extends StatefulWidget {
  const _GridTile({required this.data});
  final _GridItemData data;

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  bool _pressed = false;

  Future<void> _handleTap() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    widget.data.onTap();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _scaled(context, 52).clamp(44.0, 56.0);
    final labelSize = _scaled(context, 10.5).clamp(9.5, 10.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: _brandGreen.withValues(alpha: 0.15),
        highlightColor: _brandGreen.withValues(alpha: 0.08),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: Image.asset(
                  widget.data.image,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.data.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: FontWeight.w500,
                  color: _titleDark,
                  height: 1.15,
                ),
              ),
            ],
          ),
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
                label: 'Bosh sahifa',
                active: true,
                onTap: () {},
              ),
              _NavItem(
                icon: _IconKind.package,
                label: 'Buyurtmalar',
                onTap: onOrders,
              ),
              _NavItem(
                icon: _IconKind.wallet,
                label: 'Hamyon',
                onTap: onWallet,
              ),
              _NavItem(
                icon: _IconKind.user,
                label: 'Profil',
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
      RRect.fromRectAndRadius(const Rect.fromLTWH(3, 4, 18, 14), const Radius.circular(3)),
      p,
    );
    c.drawPath(Path()..moveTo(8, 18)..lineTo(10, 21)..lineTo(12, 18), p);
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
      RRect.fromRectAndRadius(const Rect.fromLTWH(4, 5, 16, 14), const Radius.circular(2)),
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
