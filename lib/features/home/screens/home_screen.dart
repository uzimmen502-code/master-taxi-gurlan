import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/home_module.dart';
import '../../../shared/widgets/no_internet_banner.dart';
import '../../ads/screens/cheap_products_screen.dart';
import '../../bread/screens/bread_screen.dart';
import '../../intercity_taxi/driver/intercity_driver_resume.dart';
import '../../intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../../jobs/screens/jobs_screen.dart';
import '../../local_taxi/passenger/screens/local_taxi_screen.dart';
import '../../marshrut/passenger/screens/marshrut_taxi_screen.dart';
import '../../sell/screens/sell_offer_screen.dart';
import '../../../models/home_ticker_ad.dart';
import '../../../repositories/home_ticker_repository.dart';
import '../../../repositories/intercity_bookings_repository.dart';
import '../controllers/home_controller.dart';
import '../controllers/home_label_animator.dart';
import '../home_grid_layout.dart';
import '../home_modules_catalog.dart';
import '../widgets/home_bottom_bar.dart';
import '../widgets/home_dua_section.dart';
import '../widgets/home_green_background.dart';
import '../widgets/home_modules_grid.dart';
import '../widgets/home_ticker_shell.dart';
import '../../../core/theme/app_theme.dart';

/// Бош экран — 2+3 yashil dizayn (duo, ticker, modullar).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeController()),
        ChangeNotifierProvider(
          create: (_) {
            final a = HomeLabelAnimator();
            a.start();
            return a;
          },
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

  late final HomeScreenLayout _layout =
      HomeGridLayout.buildLayout(HomeModulesCatalog.modules);

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
      // Skip if already navigated by driver resume
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
          builder: (_) => IntercityTaxiScreen(
            autoFrom: from,
            autoTo: to,
          ),
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

  Future<void> _openModule(HomeModule m) async {
    if (m.id == 'sell') {
      final phone = phoneDigits(context.read<HomeController>().phone);
      if (phone.length < 9) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('fill_phone_first')),
          ),
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
    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => screen,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HomeController>();

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      bottomNavigationBar: const HomeBottomBar(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeGreenBackground(),
          SafeArea(
            child: Column(
              children: [
                if (!c.hasInternet) const NoInternetBanner(),
                const HomeDuaSection(),
                StreamBuilder<List<HomeTickerAd>>(
                  stream: context
                      .read<HomeTickerRepository>()
                      .watchForRole(c.role),
                  builder: (context, snap) {
                    final ads = snap.data ?? const [];
                    return HomeTickerShell(ads: ads);
                  },
                ),
                SizedBox(height: HomeGridLayout.cardsGapBelowTicker),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: HomeGridLayout.maxWidth,
                      ),
                      child: HomeModulesGrid(
                        layout: _layout,
                        onModuleTap: _openModule,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
