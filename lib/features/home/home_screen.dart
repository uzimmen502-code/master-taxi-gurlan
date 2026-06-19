import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import '../../core/utils/wallet_ledger_labels.dart';
import '../../models/home_module.dart';
import '../../models/user_model.dart';
import '../../models/wallet_ledger_entry.dart';
import '../../repositories/intercity_bookings_repository.dart';
import '../../repositories/user_repository.dart';
import '../../shared/widgets/no_internet_banner.dart';
import '../ads/screens/cheap_products_screen.dart';
import '../bread/screens/bread_screen.dart';
import '../chat/screens/chat_screen.dart';
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
import 'widgets/non_promo_card.dart';
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

String _lastTxLabel(WalletLedgerEntry? entry) {
  if (entry == null) return 'Tranzaksiya yo\'q';
  final sub = walletLedgerSubtitle(entry).trim();
  if (sub.isNotEmpty) return sub;
  if (entry.createdAt != null) {
    return DateFormat('dd.MM HH:mm').format(entry.createdAt!);
  }
  return '—';
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _displayName(UserModel? user, HomeController home) {
    final name = (user?.name ?? home.name).trim();
    final phone = user?.phone.trim().isNotEmpty == true
        ? user!.phone
        : home.phone;
    if (name.isEmpty) return phone.isNotEmpty ? phone : 'Foydalanuvchi';
    final gender = user?.gender ?? home.gender;
    return gender == 'female' ? '$name xonim' : '$name boy aka';
  }

  String _initials(UserModel? user, HomeController home) {
    final name = (user?.name ?? home.name).trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
      }
      return name[0].toUpperCase();
    }
    final phone = phoneDigits(user?.phone ?? home.phone);
    if (phone.length >= 2) return phone.substring(phone.length - 2);
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final uid = phoneDigits(home.phone);
    final userRepo = context.read<UserRepository>();

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: _HomeBottomNav(
        onChat: () => _HomeBottomNav.openChat(context),
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
                        ? userRepo.watchWalletLedger(uid, limit: 1)
                        : Stream.value(const []),
                    builder: (context, ledgerSnap) {
                      final lastEntry = (ledgerSnap.data ?? const []).isNotEmpty
                          ? ledgerSnap.data!.first
                          : null;
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          _HomeHeader(
                            displayName: _displayName(user, home),
                            initials: _initials(user, home),
                          ),
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
                                  lastTxLabel: _lastTxLabel(lastEntry),
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
                                    height: _sectionGap(context, base: 12)),
                                _TaxiServicesGrid(
                                  onLocal: () => _openModule(
                                    HomeModulesCatalog.byId('local_taxi'),
                                  ),
                                  onIntercity: () => _openModule(
                                    HomeModulesCatalog.byId('intercity'),
                                  ),
                                  onMarshrut: () => _openModule(
                                    HomeModulesCatalog.byId('marshrut'),
                                  ),
                                ),
                                SizedBox(
                                    height: _sectionGap(context, base: 10)),
                                const Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: _headerBorder,
                                ),
                                SizedBox(
                                    height: _sectionGap(context, base: 10)),
                                _ServicesGrid(
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
                                  onAvtotex: () => _snack('Tez kunda'),
                                  onJobAd: () => _push(
                                    const JobsScreen(
                                      initialTabIndex: JobsTabs.ad,
                                    ),
                                  ),
                                  onOnlineMarket: () => _openModule(
                                    HomeModulesCatalog.byId(
                                        'cheap_products_home'),
                                  ),
                                ),
                                SizedBox(height: _sectionGap(context, base: 8)),
                                NonPromoCard(
                                  onTap: () => _openModule(
                                    HomeModulesCatalog.byId('bread'),
                                  ),
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

// ─── Header ──────────────────────────────────────────────────────────────────
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.displayName,
    required this.initials,
  });

  final String displayName;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _headerBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Assalomu alaykum',
                      style: TextStyle(fontSize: 12, color: _sectionLabel),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: _titleDark,
                      ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: _primaryGreen,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _brandGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Gurlan, Xorazm',
                  style: TextStyle(fontSize: 11, color: _brandGreen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Taxi grid ───────────────────────────────────────────────────────────────
class _TaxiServicesGrid extends StatelessWidget {
  const _TaxiServicesGrid({
    required this.onLocal,
    required this.onIntercity,
    required this.onMarshrut,
  });

  final VoidCallback onLocal;
  final VoidCallback onIntercity;
  final VoidCallback onMarshrut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TaxiCard(
            iconBg: const Color(0xFFE8F5E9),
            icon: const _StrokeIcon(_IconKind.car, color: _primaryGreen),
            label: 'Mahalliy',
            sub: 'TAXI',
            onTap: onLocal,
          ),
        ),
        SizedBox(width: _scaled(context, 8)),
        Expanded(
          child: _TaxiCard(
            iconBg: const Color(0xFFE3F2FD),
            icon: const _StrokeIcon(_IconKind.navigation,
                color: Color(0xFF1565C0)),
            label: 'Shaharlararo',
            sub: 'TAXI',
            onTap: onIntercity,
          ),
        ),
        SizedBox(width: _scaled(context, 8)),
        Expanded(
          child: _TaxiCard(
            iconBg: const Color(0xFFEDE7F6),
            icon: const _StrokeIcon(_IconKind.bus, color: Color(0xFF6A1B9A)),
            label: 'Marshrut',
            sub: 'TAXI',
            onTap: onMarshrut,
          ),
        ),
      ],
    );
  }
}

class _TaxiCard extends StatefulWidget {
  const _TaxiCard({
    required this.iconBg,
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final Color iconBg;
  final Widget icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  State<_TaxiCard> createState() => _TaxiCardState();
}

class _TaxiCardState extends State<_TaxiCard> {
  bool _pressed = false;

  Future<void> _handleTap() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    widget.onTap();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _scaled(context, 42).clamp(36.0, 42.0);
    final labelSize = _scaled(context, 11).clamp(9.5, 11.0);
    final subSize = _scaled(context, 10).clamp(9.0, 10.0);
    final bg = _pressed ? _brandGreen : Colors.white;
    final labelColor = _pressed ? Colors.white : _titleDark;
    final subColor =
        _pressed ? Colors.white.withValues(alpha: 0.85) : _sectionLabel;
    final tileIconBg =
        _pressed ? Colors.white.withValues(alpha: 0.2) : widget.iconBg;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white24,
        highlightColor: Colors.white12,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: _scaled(context, 10),
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed ? _brandGreen : _cardBorder,
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: tileIconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: _pressed
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                        child: widget.icon,
                      )
                    : widget.icon,
              ),
              SizedBox(height: _scaled(context, 6)),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 2),
              if (widget.sub.trim().isNotEmpty)
                Text(
                  widget.sub,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: subSize, color: subColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Services grid ───────────────────────────────────────────────────────────
class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({
    required this.onCourier,
    required this.onSell,
    required this.onAvtotex,
    required this.onJobAd,
    required this.onOnlineMarket,
  });

  final VoidCallback onCourier;
  final VoidCallback onSell;
  final VoidCallback onAvtotex;
  final VoidCallback onJobAd;
  final VoidCallback onOnlineMarket;

  @override
  Widget build(BuildContext context) {
    final gap = _sectionGap(context, base: 8);
    return Column(
      children: [
        // 3 ustun — taksi bo‘limi bilan bir xil ritm (2+2+1 o‘rniga 3+2)
        Row(
          children: [
            Expanded(
              child: _TaxiCard(
                iconBg: const Color(0xFFE8F5E9),
                icon: const _StrokeIcon(_IconKind.package,
                    color: _primaryGreen),
                label: 'Kuryer',
                sub: 'XIZMATI',
                onTap: onCourier,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _TaxiCard(
                iconBg: const Color(0xFFFCE4EC),
                icon: const _StrokeIcon(_IconKind.shoppingBag,
                    color: Color(0xFFAD1457)),
                label: 'Mahsulot sotaman',
                sub: '',
                onTap: onSell,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _TaxiCard(
                iconBg: const Color(0xFFFFF8E1),
                icon: const _StrokeIcon(_IconKind.wrench,
                    color: Color(0xFFF57F17)),
                label: 'AvtoTex Xizmat',
                sub: '',
                onTap: onAvtotex,
              ),
            ),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(
              child: _ServiceCard(
                iconBg: const Color(0xFFE8EAF6),
                icon: const _StrokeIcon(_IconKind.briefcase,
                    color: Color(0xFF3949AB)),
                title: 'Ish e\'lon',
                desc: 'Vakansiya va ishlar',
                onTap: onJobAd,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _ServiceCard(
                iconBg: const Color(0xFFE3F2FD),
                icon: const _StrokeIcon(_IconKind.shoppingCart,
                    color: Color(0xFF1565C0)),
                title: 'Oline BOZOR+',
                onTap: onOnlineMarket,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    required this.iconBg,
    required this.icon,
    required this.title,
    required this.onTap,
    this.desc,
  });

  final Color iconBg;
  final Widget icon;
  final String title;
  final String? desc;
  final VoidCallback onTap;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _pressed = false;

  Future<void> _handleTap() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    widget.onTap();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _scaled(context, 42).clamp(36.0, 42.0);
    final titleSize = _scaled(context, 12).clamp(10.0, 12.0);
    final descSize = _scaled(context, 10).clamp(9.0, 10.0);
    final hasDesc = widget.desc != null && widget.desc!.trim().isNotEmpty;
    final bg = _pressed ? _brandGreen : Colors.white;
    final titleColor = _pressed ? Colors.white : _titleDark;
    final descColor =
        _pressed ? Colors.white.withValues(alpha: 0.85) : _sectionLabel;
    final tileIconBg =
        _pressed ? Colors.white.withValues(alpha: 0.2) : widget.iconBg;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white24,
        highlightColor: Colors.white12,
        child: Container(
          constraints: BoxConstraints(minHeight: _scaled(context, 64)),
          padding: EdgeInsets.all(_scaled(context, 10).clamp(8.0, 10.0)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed ? _brandGreen : _cardBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: tileIconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: _pressed
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                        child: widget.icon,
                      )
                    : widget.icon,
              ),
              SizedBox(width: _scaled(context, 8).clamp(6.0, 8.0)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                        height: 1.15,
                      ),
                    ),
                    if (hasDesc) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.desc!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: descSize,
                          color: descColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom nav ──────────────────────────────────────────────────────────────
class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav({
    required this.onChat,
    required this.onWallet,
    required this.onProfile,
  });

  final VoidCallback onChat;
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

  static void openChat(BuildContext context) {
    final phone = phoneDigits(context.read<HomeController>().phone);
    if (phone.length < 9) {
      needPhone(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(targetPhone: phone),
      ),
    );
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
                icon: _IconKind.message,
                label: 'Chat',
                onTap: onChat,
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
