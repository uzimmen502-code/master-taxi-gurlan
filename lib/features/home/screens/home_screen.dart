import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/same_origin_nav.dart';
import '../../../models/home_module.dart';
import '../../../shared/widgets/no_internet_banner.dart';
import '../../bread/screens/bread_screen.dart';
import '../../food/screens/food_screen.dart';
import '../../intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../../jobs/screens/jobs_screen.dart';
import '../../local_taxi/passenger/screens/local_taxi_screen.dart';
import '../../marshrut/passenger/screens/marshrut_taxi_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../controllers/home_controller.dart';
import '../widgets/home_header.dart';
import '../widgets/module_card.dart';
import '../widgets/space_painter.dart';

/// Бош экран — Provider орқали [HomeController].
///
/// **Мобил** (кенглик 600 px дан кичик): ҳозиргидек — устунли рўйхат.
/// **Десктоп** (`≥ 600`): марказда `maxWidth: 960`, 2 ёки 3 устунли grid, симметрик паддинг.
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

class _HomeViewState extends State<_HomeView> with SingleTickerProviderStateMixin {
  StreamSubscription<String>? _promoSub;

  late AnimationController _spaceCtrl;
  final math.Random _shootRng = math.Random(7);
  final List<ShootingStar> _shootingStars = <ShootingStar>[];
  bool _shootingInited = false;

  /// Windows/macOS/Linux: браузерда ochiladi (`--dart-define=ADMIN_PANEL_URL=...` билан ўзгартирилади).
  static const String _kAdminPanelExternalUrl = String.fromEnvironment(
    'ADMIN_PANEL_URL',
    defaultValue: 'https://master-taxi-gurlan.web.app/admin/',
  );

  /// Кенг экран бўлими — веб/десктоп билан мос.
  static const double _desktopBreakpoint = 600;

  static const List<HomeModule> _modules = [
    HomeModule(
      id: 'bread',
      image: 'assets/images/bread.png',
      label: 'Нон буюртма',
      color1: Color(0xFFE65100),
      color2: Color(0xFFEF6C00),
    ),
    HomeModule(
      id: 'food',
      image: 'assets/images/food.png',
      label: 'Тайёр овқат',
      color1: Color(0xFF2E7D32),
      color2: Color(0xFF43A047),
    ),
    HomeModule(
      id: 'marshrut',
      image: 'assets/images/taxi_marshrut.png',
      label: 'Маршрут такси',
      color1: Color(0xFF00695C),
      color2: Color(0xFF00897B),
    ),
    HomeModule(
      id: 'local_taxi',
      image: 'assets/images/taxi_local.png',
      label: 'Маҳаллий такси',
      color1: Color(0xFF1565C0),
      color2: Color(0xFF1E88E5),
    ),
    HomeModule(
      id: 'intercity',
      image: 'assets/images/taxi_intercity.png',
      label: 'Шаҳарлараро',
      color1: Color(0xFF6A1B9A),
      color2: Color(0xFF8E24AA),
    ),
    HomeModule(
      id: 'jobs',
      image: 'assets/images/ishtop.png',
      label: 'ИШ ТОП',
      color1: Color(0xFF0277BD),
      color2: Color(0xFF0288D1),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _spaceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _spaceCtrl.addListener(_onSpaceTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sz = MediaQuery.sizeOf(context);
      setState(() {
        _shootingStars
          ..clear()
          ..addAll(createInitialShootingStars(sz.width, sz.height));
        _shootingInited = true;
      });
      final c = context.read<HomeController>();
      _promoSub = c.onAgroPromo.listen(_showAgroPromo);
    });
  }

  void _onSpaceTick() {
    if (!mounted) return;
    if (_shootingInited) {
      final sz = MediaQuery.sizeOf(context);
      updateShootingStars(_shootingStars, sz.width, sz.height, _shootRng);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _spaceCtrl.removeListener(_onSpaceTick);
    _spaceCtrl.dispose();
    _promoSub?.cancel();
    super.dispose();
  }

  void _showAgroPromo(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📢 Янгилик'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Тушунарли'),
          ),
        ],
      ),
    );
  }

  /// Веб: `/admin/`; десктоп (Win/macOS/Linux): ташқи браузер.
  VoidCallback? _adminPanelTap() {
    if (kIsWeb) {
      return () => navigateSameOriginPath('/admin/');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        break;
      default:
        return null;
    }
    final uri = Uri.tryParse(_kAdminPanelExternalUrl.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return () async {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    };
  }

  Future<void> _openModule(HomeModule m) async {
    final Widget screen;
    switch (m.id) {
      case 'bread':
        screen = const BreadScreen();
        break;
      case 'food':
        screen = const FoodScreen();
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

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    await context.read<HomeController>().refreshUser();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HomeController>();
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= _desktopBreakpoint;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          RepaintBoundary(
            child: CustomPaint(
              painter: SpacePainter(
                _spaceCtrl.value * 60,
                _shootingStars,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (!c.hasInternet) const NoInternetBanner(),
                Expanded(
                  child: isDesktop
                      ? _DesktopLayout(
                          controller: c,
                          modules: _modules,
                          onProfileTap: () => unawaited(_openProfile()),
                          onModule: _openModule,
                          adminTap: c.isAdminOrSuperadmin
                              ? _adminPanelTap()
                              : null,
                        )
                      : _MobileLayout(
                          controller: c,
                          modules: _modules,
                          onProfileTap: () => unawaited(_openProfile()),
                          onModule: _openModule,
                          adminTap: c.isAdminOrSuperadmin
                              ? _adminPanelTap()
                              : null,
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

// ─── МОБИЛ (< 600) — ҳозиргидек: дуо + устунли карталар ───────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.controller,
    required this.modules,
    required this.onProfileTap,
    required this.onModule,
    required this.adminTap,
  });

  final HomeController controller;
  final List<HomeModule> modules;
  final VoidCallback onProfileTap;
  final void Function(HomeModule) onModule;
  final VoidCallback? adminTap;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: HomeHeader(
            controller: controller,
            onProfileTap: onProfileTap,
            onOpenAdminWeb: adminTap,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ModuleCard(
                  module: modules[i],
                  onTap: () => onModule(modules[i]),
                  isGrid: false,
                ),
              ),
              childCount: modules.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── ДЕСКТОП (≥ 600) — марказлаштирилган + grid ───────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.controller,
    required this.modules,
    required this.onProfileTap,
    required this.onModule,
    required this.adminTap,
  });

  final HomeController controller;
  final List<HomeModule> modules;
  final VoidCallback onProfileTap;
  final void Function(HomeModule) onModule;
  final VoidCallback? adminTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900 ? 3 : 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPad = (constraints.maxWidth * 0.06).clamp(16.0, 48.0);

        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    HomeHeader(
                      controller: controller,
                      onProfileTap: onProfileTap,
                      onOpenAdminWeb: adminTap,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.apps_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Хизматлар',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.85,
                      ),
                      itemCount: modules.length,
                      itemBuilder: (_, i) => ModuleCard(
                        module: modules[i],
                        onTap: () => onModule(modules[i]),
                        isGrid: true,
                      ),
                    ),
                    const SizedBox(height: 28),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 20,
                        ),
                        child: Text(
                          '© 2026 Master Taxi Gurlan · AVA Technology',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
