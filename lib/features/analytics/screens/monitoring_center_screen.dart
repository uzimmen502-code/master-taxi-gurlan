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

/// Monitoring & Analytics Center вЂ” СЌСЃРєРё `AdminScreen` СћСЂРЅРёРіР°.
///
/// `embedded: true` вЂ” Web Р°РґРјРёРЅ РїР°РЅРµР»Рё РєРѕРЅС‚РµРєСЃС‚Рё. AppBar СЏСЂР°С‚РёР»РјaР№РґРё
/// (sidebar СћСЂРЅРёРЅРё Р±РѕСЃaРґРё), Navigator.pop() СћСЂРЅРёРіР° SnackBar С…РѕР»РѕСЃ.
class MonitoringCenterScreen extends StatelessWidget {
  const MonitoringCenterScreen({super.key, this.embedded = false});

  /// `true` вЂ” Web Р°РґРјРёРЅ shell РёС‡РёРґa Р¶oР№Р»aС€С‚РёСЂРёР»РіaРЅ.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => AnalyticsController(
        repo: ctx.read<AnalyticsRepository>(),
        // main.dart'Рґa allaqachon yaratilРіР°РЅ DailyReportService'РЅРё ishlР°С‚Р°miР· вЂ”
        // bu yerda yangi instans yaratish вЂ” `ensureToday()` Рјexanizmini
        // dublikat qРёР»Р°РґРё (Timer'lar Рґublikat).
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

  /// **Xavfsiz default вЂ” agar tekshiruv muvaffaqiyatsiz bo'lsa, KIRMAYDI.**
  ///
  /// Tekshiruv 2 bosqichРґР°:
  ///   1. SharedPreferences'Рґa local `user_role == 'admin'` (tezroq UX)
  ///   2. Firestore'РґР°РіРё `users/{uid}.role == 'admin'` (haqiqiy tasdiq)
  ///
  /// Birinchisi false bo'lsa вЂ” Firestore'ga ham bormaydi (tezda chiqaradi).
  /// Ikkilamchisi xatolik bersa вЂ” false (xavfsiz default).
  Future<void> _checkAdmin() async {
    // Web admin shell: PIN login allaqachon вЂ” Firestore role qayta tekshirish
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
            content: Text('в›” РЎРёР·РґР° Р°РґРјРёРЅ РїР°РЅРµР»РіР° РєРёСЂРёС€ ТіСѓТ›СѓТ›Рё Р№СћТ›'),
          ),
        );
        // Web admin shell РёС‡РёРґР° pop() вЂ” РёС€Р»aРјaР№РґРё (root СЌРєСЂР°РЅ). Faqat
        // mobile'РґР° pop qilamiz.
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
        tooltip: 'Р‘СѓСЋСЂС‚РјР°Р»Р°СЂ',
        icon: const Icon(Icons.receipt_long),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminOrdersScreen()),
        ),
      ),
      IconButton(
        tooltip: 'РЇРЅРіРё С…Р°Р±Р°СЂ СЋР±РѕСЂРёС€',
        icon: const Icon(Icons.campaign),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AdminNewsComposeScreen()),
        ),
      ),
      IconButton(
        tooltip: 'РљСѓРЅРґР°Р»РёРє ТіРёСЃРѕР±РѕС‚',
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
        tooltip: 'Р‘Р°СЂС‡Р° С‚Р°ТіР»РёР»РЅРё СЏРЅРіРёР»Р°С€',
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
        Tab(text: 'рџ“Љ Dashboard'),
        Tab(text: 'рџ‘Ґ Р¤РѕР№РґР°Р»Р°РЅСѓРІС‡Рё'),
        Tab(text: 'рџљ– ТІР°Р№РґРѕРІС‡Рё'),
        Tab(text: 'рџ’° РњРѕР»РёСЏ'),
        Tab(text: 'вљ™пёЏ РћРїРµСЂР°С†РёСЏ'),
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
      // Web shell РёС‡РёРґР° вЂ” AppBar СћСЂРЅРёРіР° РєРµРЅРі РєoРЅС‚РµР№РЅРµСЂ.
      return Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(children: [
            const Text(
              'рџ“Љ Monitoring Center',
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
        title: const Text('рџ“Љ Monitoring Center',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: actions,
        bottom: tabBar,
      ),
      body: tabBarView,
    );
  }
}

/// Р–СѓРґР° РєРµРЅРі СЌРєСЂР°РЅР»aСЂРґa РєРѕРЅС‚РµРЅС‚РЅРё РјР°СЂРєР°Р·Р»aС€С‚РёСЂaРґРё (С‚aС€Т›aСЂРё 1400px-РґaРЅ
/// РєaС‚С‚a Р±СћР»СЃa вЂ” Center Р±РёР»aРЅ СћСЂaР№РґРё).
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
