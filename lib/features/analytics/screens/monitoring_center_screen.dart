import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../repositories/analytics_repository.dart';
import '../../../services/admin_service.dart';
import '../../../services/daily_report_service.dart';
import '../controllers/analytics_controller.dart';
import '../tabs/dashboard_tab.dart';
import '../tabs/drivers_tab.dart';
import '../tabs/finance_tab.dart';
import '../tabs/operations_tab.dart';
import '../tabs/users_tab.dart';
import 'admin_news_compose_screen.dart';
import 'admin_orders_screen.dart';
import 'daily_report_screen.dart';
import '../../../core/theme/app_theme.dart';

/// Monitoring & Analytics Center — эски `AdminScreen` ўрнига.
///
/// `embedded: true` — Web админ панели контексти. AppBar яратилмaйди
/// (sidebar ўрнини босaди), Navigator.pop() ўрнига SnackBar холос.
class MonitoringCenterScreen extends StatelessWidget {
  const MonitoringCenterScreen({super.key, this.embedded = false});

  /// `true` — Web админ shell ичидa жoйлaштирилгaн.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => AnalyticsController(
        repo: ctx.read<AnalyticsRepository>(),
        // main.dart'дa allaqachon yaratilган DailyReportService'ни ishlатаmiз —
        // bu yerda yangi instans yaratish — `ensureToday()` мexanizmini
        // dublikat qилади (Timer'lar дublikat).
        reportService: ctx.read<DailyReportService>(),
      ),
      child: _MonitoringView(embedded: embedded),
    );
  }
}

class _MonitoringView extends StatefulWidget {
  const _MonitoringView({required this.embedded});
  final bool embedded;

  @override
  State<_MonitoringView> createState() => _MonitoringViewState();
}

class _MonitoringViewState extends State<_MonitoringView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _isAdmin = false;
  bool _adminChecked = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _checkAdmin();
  }

  /// **Xavfsiz default — agar tekshiruv muvaffaqiyatsiz bo'lsa, KIRMAYDI.**
  ///
  /// Tekshiruv 2 bosqichда:
  ///   1. SharedPreferences'дa local `user_role == 'admin'` (tezroq UX)
  ///   2. Firestore'даги `users/{uid}.role == 'admin'` (haqiqiy tasdiq)
  ///
  /// Birinchisi false bo'lsa — Firestore'ga ham bormaydi (tezda chiqaradi).
  /// Ikkilamchisi xatolik bersa — false (xavfsiz default).
  Future<void> _checkAdmin() async {
    // Web admin shell: PIN login allaqachon — Firestore role qayta tekshirish
    // Monitoring Center'ni bo'sh qoldiradi (AdminService Phone Auth talab qiladi).
    if (widget.embedded) {
      if (!mounted) return;
      setState(() {
        _isAdmin = true;
        _adminChecked = true;
      });
      return;
    }

    bool isAdmin = false;
    try {
      isAdmin = await context.read<AdminService>().isCurrentUserAdmin();
    } catch (_) {
      isAdmin = false;
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _adminChecked = true;
    });
    if (!isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('⛔ Сизда админ панелга кириш ҳуқуқи йўқ'),
          ),
        );
        // Web admin shell ичида pop() — ишлaмaйди (root экран). Faqat
        // mobile'да pop qilamiz.
        if (!widget.embedded && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked || !_isAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final c = context.watch<AnalyticsController>();
    final actions = [
      IconButton(
        tooltip: 'Буюртмалар',
        icon: const Icon(Icons.receipt_long),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminOrdersScreen()),
        ),
      ),
      IconButton(
        tooltip: 'Янги хабар юбориш',
        icon: const Icon(Icons.campaign),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AdminNewsComposeScreen()),
        ),
      ),
      IconButton(
        tooltip: 'Кундалик ҳисобот',
        icon: const Icon(Icons.assessment_outlined),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: c,
              child: const DailyReportScreen(),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Барча таҳлилни янгилаш',
        icon: const Icon(Icons.refresh),
        onPressed: () => c.refreshAll(),
      ),
    ];

    final tabBar = TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      indicatorColor: widget.embedded ? AppColors.primary : Colors.white,
      indicatorWeight: 3,
      labelColor: widget.embedded ? AppColors.primary : Colors.white,
      unselectedLabelColor:
          widget.embedded ? Colors.grey.shade600 : Colors.white70,
      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      tabs: const [
        Tab(text: '📊 Dashboard'),
        Tab(text: '👥 Фойдаланувчи'),
        Tab(text: '🚖 Ҳайдовчи'),
        Tab(text: '💰 Молия'),
        Tab(text: '⚙️ Операция'),
      ],
    );

    final tabBarView = TabBarView(
      controller: _tabCtrl,
      children: const [
        DashboardTab(),
        UsersTab(),
        DriversTab(),
        FinanceTab(),
        OperationsTab(),
      ],
    );

    if (widget.embedded) {
      // Web shell ичида — AppBar ўрнига кенг кoнтейнер.
      return Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(children: [
            const Text(
              '📊 Monitoring Center',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            ...actions.map((a) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: a,
                )),
          ]),
        ),
        Container(
          color: Colors.white,
          child: tabBar,
        ),
        const Divider(height: 1),
        Expanded(
          child: _ResponsiveContentWrap(child: tabBarView),
        ),
      ]);
    }

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('📊 Monitoring Center',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: actions,
        bottom: tabBar,
      ),
      body: tabBarView,
    );
  }
}

/// Жуда кенг экранлaрдa контентни марказлaштирaди (тaшқaри 1400px-дaн
/// кaттa бўлсa — Center билaн ўрaйди).
class _ResponsiveContentWrap extends StatelessWidget {
  const _ResponsiveContentWrap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      if (constraints.maxWidth <= 1400) return child;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: child,
        ),
      );
    });
  }
}
