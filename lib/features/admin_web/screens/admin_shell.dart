// Админ entry — faqat `main_admin.dart` (web) орқали compile бўлади.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/same_origin_nav.dart';
import '../../analytics/screens/admin_orders_screen.dart';
import '../../analytics/screens/monitoring_center_screen.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_news_read_service.dart';
import '../../../repositories/news_repository.dart';
import 'admin_home_ticker_screen.dart';
import 'admin_news_list_screen.dart';
import 'admin_order_news_list_screen.dart';
import 'birthday_bonus_screen.dart';
import 'identity_approvals_screen.dart';
import 'pending_codes_screen.dart';
import 'intercity_admin_screen.dart';
import 'jobs_moderation_screen.dart';
import 'market_moderation_screen.dart';
import 'marshrut_admin_screen.dart';
import 'marshrut_dispatch_history_screen.dart';
import 'chat_support_screen.dart';
import 'dating_moderation_screen.dart';
import 'carpet_wash_admin_screen.dart';
import 'agro_pickup_admin_screen.dart';
import 'courier_admin_screen.dart';
import 'courier_management_screen.dart';
import 'driver_applications_screen.dart';
import 'finance_center_screen.dart';
import 'payout_management_screen.dart';
import 'products_manager_screen.dart';
import 'procurement_prices_screen.dart';
import 'oil_catalog_admin_screen.dart';
import 'taxi_price_screen.dart';
import 'warehouse_stock_screen.dart';
import 'sell_submissions_admin_screen.dart';
import 'risk_review_screen.dart';
import 'anomaly_settings_screen.dart';
import 'service_config_admin_screen.dart';
import 'splash_taglines_screen.dart';
import 'users_devices_screen.dart';

/// Admin Web Panel — асосий навигaция (sidebar + контент).
///
/// Sidebar'дa бўлимлaр (Dashboard, Маҳсулoтлaр, Ҳaйдовчилaр, Молия, Хабaрлaр).
/// Ҳaр бир бўлимни ўз PageView'и сифатида яратaмиз — Phase 7.2-7.7'дa.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  List<Widget?> _pageCache = [];
  final PendingCodeAutoListener _pendingCodeAuto = PendingCodeAutoListener();

  int _visibleIndexFor(int rawIndex, int visibleCount) {
    if (visibleCount <= 0) return 0;
    return rawIndex.clamp(0, visibleCount - 1);
  }

  List<_AdminSection> _visibleSections(AdminAuthService auth) {
    final role = (auth.role ?? '').trim().toLowerCase();
    return _sections.where((s) => s.visibleFor(role)).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _pageCache = List<Widget?>.filled(_sections.length, null);
    _pendingCodeAuto.start();
  }

  @override
  void dispose() {
    _pendingCodeAuto.dispose();
    super.dispose();
  }

  static const _sections = [
    _AdminSection(
      label: 'Monitoring Center',
      icon: Icons.dashboard,
      description: 'KPI ва кенг таҳлил',
    ),
    _AdminSection(
      label: 'Буюртмалар',
      icon: Icons.receipt_long,
      description: 'Нон ва овқат буюртмалари',
      access: _SectionAccess.opsAndFinance,
    ),
    _AdminSection(
      label: 'Gilam yuvish',
      icon: Icons.local_laundry_service_outlined,
      description: 'Gilam yuvish buyurtmalari',
    ),
    _AdminSection(
      label: 'Sut qabul',
      icon: Icons.water_drop_outlined,
      description: 'Sut qabul buyurtmalari',
    ),
    _AdminSection(
      label: 'Курьер',
      icon: Icons.delivery_dining,
      description: 'Reyslar va kuryer boshqaruvi',
    ),
    _AdminSection(
      label: 'Курьерлар',
      icon: Icons.people_alt_outlined,
      description: 'Курьерларни бошқариш',
    ),
    _AdminSection(
      label: 'Иш ва хизмат доскаси',
      icon: Icons.work_history,
      description: 'Иш, хизмат, эълон — модерация',
    ),
    _AdminSection(
      label: 'Онлайн бозор',
      icon: Icons.storefront_outlined,
      description: 'Арзон маҳсулот эълонлари',
    ),
    _AdminSection(
      label: '❤️ Танишув',
      icon: Icons.favorite,
      description: 'Профил модерацияси ва шикоятлар',
    ),
    _AdminSection(
      label: 'Хабарлaр',
      icon: Icons.campaign,
      description: 'Promo va yangilik yuborish',
    ),
    _AdminSection(
      label: 'Бегущая строка',
      icon: Icons.view_stream_outlined,
      description: 'Bosh ekran yuguruvchi matn',
    ),
    _AdminSection(
      label: 'Ҳудудлар ва хизматлар',
      icon: Icons.map_outlined,
      description: 'MFY boʻyicha modul mavjudligi (config-driven)',
    ),
    _AdminSection(
      label: 'Splash soʻzlari',
      icon: Icons.branding_watermark_outlined,
      description: 'Ilova ochilish animatsiyasi matnlari',
    ),
    _AdminSection(
      label: 'Буюртма хабар',
      icon: Icons.sms_outlined,
      description: 'Mijozga ketgan status xabarlari',
    ),
    _AdminSection(
      label: 'Сотиш аризалари',
      icon: Icons.sell_outlined,
      description: 'Фойдаланувчи формасидан таклифлар',
    ),
    _AdminSection(
      label: 'Маҳсулoтлaр',
      icon: Icons.inventory_2,
      description: 'Нон, овқaт, нархлaр',
    ),
    _AdminSection(
      label: 'Мой каталоги',
      icon: Icons.opacity,
      description: 'Мой/фильтр · нарх · расм',
      access: _SectionAccess.opsAndFinance,
    ),
    _AdminSection(
      label: 'Харид нархлари',
      icon: Icons.price_change_outlined,
      description: 'Йиғиб олиш ва тўлов нархлари',
      access: _SectionAccess.opsAndFinance,
    ),
    _AdminSection(
      label: '🚕 Такси нархи',
      icon: Icons.local_taxi,
      description: 'Mahalliy taksi: boshlang\'ich, km, koeffitsient',
    ),
    _AdminSection(
      label: 'Омбор',
      icon: Icons.warehouse_outlined,
      description: 'Йиғилган маҳсулот қолдиқлари',
      access: _SectionAccess.opsAndFinance,
    ),
    _AdminSection(
      label: 'Ҳaйдовчи aризалари',
      icon: Icons.directions_car,
      description: 'Янги aризалaр',
    ),
    _AdminSection(
      label: 'Туғилган кун',
      icon: Icons.cake_outlined,
      description: 'Туғилган кун бонуси ва сўровлар',
    ),
    _AdminSection(
      label: 'Код сўровлари',
      icon: Icons.pin_outlined,
      description: 'Admin kod (fake SMS)',
    ),
    _AdminSection(
      label: 'Маршрут',
      icon: Icons.directions_bus,
      description: 'Ҳайдовчилар ва сафарлар',
    ),
    _AdminSection(
      label: 'Shaharlararo',
      icon: Icons.connecting_airports,
      description: 'Intercity haydovchilar va bronlar',
    ),
    _AdminSection(
      label: 'Фойдаланувчилар',
      icon: Icons.people_alt_outlined,
      description: 'Телефон, туғилган кун, қурилмалар',
      access: _SectionAccess.users,
    ),
    _AdminSection(
      label: 'Risk review',
      icon: Icons.security,
      description: 'Хавфли сигналлар',
      access: _SectionAccess.superOnly,
    ),
    _AdminSection(
      label: 'Аномалия созламалари',
      icon: Icons.settings,
      description: 'Чеги ва чиқим лимитлари',
      access: _SectionAccess.superOnly,
    ),
    _AdminSection(
      label: 'Молия',
      icon: Icons.account_balance_wallet,
      description: 'Payout ва тушум',
      access: _SectionAccess.finance,
    ),
    _AdminSection(
      label: 'Finance Center',
      icon: Icons.account_balance,
      description: 'Settlement Ledger — float, settlement, журнал',
      access: _SectionAccess.finance,
    ),
    _AdminSection(
      label: 'Birthday bonus',
      icon: Icons.card_giftcard,
      description: 'Йиллик туғилган кун бонуси',
    ),
    _AdminSection(
      label: 'Dispatch history',
      icon: Icons.timeline,
      description: 'Маршрут навбат тарихи',
    ),
    _AdminSection(
      label: 'Чат қўллaб-қуввaтлaш',
      icon: Icons.support_agent,
      description: 'Support чатлaри',
    ),
  ];

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Чиқиш'),
        content: const Text('Чиқишни тaсдиқлaйcизми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Чиқиш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AdminAuthService>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthService>();
    final visible = _visibleSections(auth);
    final safeIndex = _visibleIndexFor(_selectedIndex, visible.length);
    if (safeIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedIndex = safeIndex);
      });
    }

    final media = MediaQuery.of(context);
    final isWide = media.size.width > 1100;
    final isMedium = media.size.width > 700;
    // Телефон drawer — тўлиқ матн; планшет rail (701–1100) — compact иконка.
    final sidebarCompact = isMedium && !isWide;

    final sidebar = _Sidebar(
      sections: visible,
      selectedIndex: safeIndex,
      onSelect: (i) {
        setState(() => _selectedIndex = i);
        if (!isMedium && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      onLogout: _logout,
      compact: sidebarCompact,
    );

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      drawer: isMedium ? null : Drawer(child: sidebar),
      body: Row(children: [
        if (isMedium)
          SizedBox(width: isWide ? 240 : 92, child: sidebar),
        Expanded(
          child: _body(visible, safeIndex),
        ),
      ]),
      appBar: isMedium
          ? null
          : AppBar(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              title: Text(visible[safeIndex].label),
              actions: [
                IconButton(
                  icon: const Icon(Icons.home_outlined),
                  tooltip: 'Foydalanuvchi ilovasiga',
                  onPressed: () {
                    html.window.location.href = '/';
                  },
                ),
              ],
            ),
    );
  }

  Widget _body(List<_AdminSection> visible, int index) {
    final section = visible[index];
    final rawIndex = _sections.indexOf(section);
    if (rawIndex < 0) {
      return const Center(child: Text('Bo\'lim topilmadi'));
    }
    final cached = _pageCache[rawIndex];
    if (cached != null) return cached;
    final built = _buildSection(section);
    _pageCache[rawIndex] = built;
    return built;
  }

  Widget _buildSection(_AdminSection section) {
    if (section.label == 'Monitoring Center') {
      return const MonitoringCenterScreen(embedded: true);
    }
    if (section.label == 'Хабарлaр') {
      return const AdminNewsListScreen();
    }
    if (section.label == 'Бегущая строка') {
      return const AdminHomeTickerScreen();
    }
    if (section.label == 'Ҳудудлар ва хизматлар') {
      return const ServiceConfigAdminScreen();
    }
    if (section.label == 'Splash soʻzlari') {
      return const SplashTaglinesScreen();
    }
    if (section.label == 'Буюртма хабар') {
      return const AdminOrderNewsListScreen();
    }
    if (section.label == 'Иш ва хизмат доскаси') {
      return const JobsModerationScreen();
    }
    if (section.label == 'Онлайн бозор') {
      return const MarketModerationScreen();
    }
    if (section.label == '❤️ Танишув') {
      return const DatingModerationScreen();
    }
    if (section.label == 'Сотиш аризалари') {
      return const SellSubmissionsAdminScreen();
    }
    if (section.label == 'Ҳaйдовчи aризалари') {
      return const DriverApplicationsScreen();
    }
    if (section.label == 'Туғилган кун') {
      return const IdentityApprovalsScreen();
    }
    if (section.label == 'Код сўровлари') {
      return const PendingCodesScreen();
    }
    if (section.label == 'Фойдаланувчилар') {
      return const UsersDevicesScreen();
    }
    if (section.label == 'Risk review') {
      return const RiskReviewScreen();
    }
    if (section.label == 'Аномалия созламалари') {
      return const AnomalySettingsScreen();
    }
    if (section.label == 'Маҳсулoтлaр') {
      return const ProductsManagerScreen();
    }
    if (section.label == 'Мой каталоги') {
      return const OilCatalogAdminScreen();
    }
    if (section.label == 'Харид нархлари') {
      return const ProcurementPricesScreen();
    }
    if (section.label == '🚕 Такси нархи') {
      return const TaxiPriceScreen();
    }
    if (section.label == 'Омбор') {
      return const WarehouseStockScreen();
    }
    if (section.label == 'Молия') {
      return const PayoutManagementScreen();
    }
    if (section.label == 'Finance Center') {
      if (!context.read<AdminAuthService>().isFinanceReader) {
        return const Center(
          child: Text(
            'Finance Center faqat finance/auditor/superadmin uchun.\n'
            'Oddiy admin bu bo\'limga kira olmaydi (SoD).',
            textAlign: TextAlign.center,
          ),
        );
      }
      return const FinanceCenterScreen();
    }
    if (section.label == 'Birthday bonus') {
      return const BirthdayBonusScreen();
    }
    if (section.label == 'Маршрут') {
      return const MarshrutAdminScreen();
    }
    if (section.label == 'Dispatch history') {
      return const MarshrutDispatchHistoryScreen();
    }
    if (section.label == 'Shaharlararo') {
      return const IntercityAdminScreen();
    }
    if (section.label == 'Курьер') {
      return const CourierAdminScreen();
    }
    if (section.label == 'Курьерлар') {
      return const CourierManagementScreen();
    }
    if (section.label == 'Буюртмалар') {
      return const AdminOrdersScreen(embedded: true);
    }
    if (section.label == 'Gilam yuvish') {
      return const CarpetWashAdminScreen();
    }
    if (section.label == 'Sut qabul') {
      return const AgroPickupAdminScreen();
    }
    if (section.label == 'Чат қўллaб-қуввaтлaш') {
      return const ChatSupportScreen();
    }
    return _PlaceholderTab(section: section);
  }
}

class _AdminSection {
  const _AdminSection({
    required this.label,
    required this.icon,
    required this.description,
    this.access = _SectionAccess.ops,
  });
  final String label;
  final IconData icon;
  final String description;
  final _SectionAccess access;

  bool visibleFor(String role) {
    final r = role.trim().toLowerCase();
    switch (access) {
      case _SectionAccess.ops:
        return r == 'admin' || r == 'superadmin' || r == 'dispatcher';
      case _SectionAccess.finance:
        return r == 'finance' || r == 'auditor' || r == 'superadmin';
      case _SectionAccess.opsAndFinance:
        return r == 'admin' ||
            r == 'superadmin' ||
            r == 'dispatcher' ||
            r == 'finance' ||
            r == 'auditor';
      case _SectionAccess.users:
        return r == 'admin' || r == 'superadmin';
      case _SectionAccess.superOnly:
        return r == 'superadmin';
    }
  }
}

enum _SectionAccess { ops, finance, opsAndFinance, users, superOnly }

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    required this.compact,
  });

  final List<_AdminSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthService>();
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(2, 0)),
        ],
      ),
      child: Column(children: [
        _header(compact),
        const Divider(color: Colors.white24, height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: List.generate(sections.length, (i) {
              final s = sections[i];
              final selected = i == selectedIndex;
              return KeyedSubtree(
                key: ValueKey('nav_${s.label}'),
                child: _sidebarItem(context, s, selected, () => onSelect(i)),
              );
            }),
          ),
        ),
        if (!compact && sections[selectedIndex].label == 'Код сўровлари')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const PendingCodeAutoModeSwitch(compact: true),
            ),
          ),
        const Divider(color: Colors.white24, height: 1),
        if (kIsWeb) _publicAppLinkTile(context, compact),
        _userTile(auth),
      ]),
    );
  }

  Widget _header(bool compact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Row(children: [
        const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
        if (!compact) ...[
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AVA',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Text('Admin Panel',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  static const _tabAnim = Duration(milliseconds: 280);
  static const _tabCurve = Curves.easeOutCubic;

  Widget _sidebarItem(
    BuildContext context,
    _AdminSection s,
    bool selected,
    VoidCallback onTap,
  ) {
    final badgeStream = _badgeCountStream(context, s.label);
    final iconColor = selected ? Colors.white : Colors.white60;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: _tabAnim,
            curve: _tabCurve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.22),
                        blurRadius: 14,
                        spreadRadius: 0,
                        offset: const Offset(0, 0),
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // Chap → o'ng glow / gradient
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: _tabAnim,
                      curve: _tabCurve,
                      opacity: selected ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.34),
                              Colors.white.withValues(alpha: 0.14),
                              Colors.white.withValues(alpha: 0.04),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.28, 0.62, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Chap chetda yorqin chiziq
                  if (selected)
                    Positioned(
                      left: 0,
                      top: 6,
                      bottom: 6,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.75),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  AnimatedContainer(
                    duration: _tabAnim,
                    curve: _tabCurve,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? (selected ? 6 : 0) : 14,
                      vertical: selected ? 14 : 8,
                    ),
                    child: AnimatedSize(
                      duration: _tabAnim,
                      curve: _tabCurve,
                      alignment: Alignment.topCenter,
                      child: compact
                          ? _compactTabBody(
                              s, selected, iconColor, badgeStream)
                          : _expandedTabBody(
                              s, selected, iconColor, badgeStream),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactTabBody(
    _AdminSection s,
    bool selected,
    Color iconColor,
    Stream<int>? badgeStream,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              duration: _tabAnim,
              curve: _tabCurve,
              scale: selected ? 1.12 : 1.0,
              child: Icon(s.icon, color: iconColor, size: selected ? 24 : 22),
            ),
            if (selected) ...[
              const SizedBox(height: 6),
              Text(
                s.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.55),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (badgeStream != null)
          Positioned(
            right: 0,
            top: -2,
            child: _sidebarBadge(stream: badgeStream),
          ),
      ],
    );
  }

  Widget _expandedTabBody(
    _AdminSection s,
    bool selected,
    Color iconColor,
    Stream<int>? badgeStream,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: selected ? 2 : 0),
          child: AnimatedScale(
            duration: _tabAnim,
            curve: _tabCurve,
            scale: selected ? 1.08 : 1.0,
            child: Icon(s.icon, color: iconColor, size: selected ? 22 : 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: selected ? 14.5 : 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  letterSpacing: selected ? 0.2 : 0,
                  shadows: selected
                      ? [
                          Shadow(
                            color: Colors.white.withValues(alpha: 0.65),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
              if (selected) ...[
                const SizedBox(height: 3),
                Text(
                  s.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (badgeStream != null) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _sidebarBadge(stream: badgeStream),
          ),
        ],
      ],
    );
  }

  Stream<int>? _badgeCountStream(BuildContext context, String label) {
    final db = FirebaseFirestore.instance;
    switch (label) {
      case 'Буюртмалар':
        return db
            .collection('orders')
            .where('status', isEqualTo: 'new')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Gilam yuvish':
        return db
            .collection('carpet_wash_orders')
            .where('status', isEqualTo: 'new')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Sut qabul':
        return db
            .collection('agro_pickup_orders')
            .where('productType', isEqualTo: 'milk')
            .where('status', isEqualTo: 'new')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Курьер':
        return db
            .collection('orders')
            .where('status', isEqualTo: 'ready')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Иш ва хизмат доскаси':
        return db
            .collection('ads')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.where((d) {
                  final t = (d.data()['type'] ?? '') as String;
                  if (t == 'cheap_product') return false;
                  return t.isEmpty ||
                      t == 'work' ||
                      t == 'service' ||
                      t == 'ad' ||
                      t == 'announcement';
                }).length);
      case 'Онлайн бозор':
        return db
            .collection('ads')
            .where('type', isEqualTo: 'cheap_product')
            .where('status', isEqualTo: 'pending')
            .limit(200)
            .snapshots()
            .map((s) => s.docs.length);
      case '❤️ Танишув':
        return db
            .collection('dating_profiles')
            .where('status', isEqualTo: 'pending')
            .limit(200)
            .snapshots()
            .map((s) => s.docs.length);
      case 'Хабарлaр':
        return context.read<NewsRepository>().watchAdminUnreadCount(
              orderOnly: false,
              readListenable: context.read<AdminNewsReadService>(),
              lastSeenAt: () =>
                  context.read<AdminNewsReadService>().lastGeneralSeen,
            );
      case 'Буюртма хабар':
        return context.read<NewsRepository>().watchAdminUnreadCount(
              orderOnly: true,
              readListenable: context.read<AdminNewsReadService>(),
              lastSeenAt: () =>
                  context.read<AdminNewsReadService>().lastOrderSeen,
            );
      case 'Сотиш аризалари':
        return db
            .collection('sell_submissions')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Ҳaйдовчи aризалари':
        return db
            .collection('driver_requests')
            .where('status', isEqualTo: 'pending')
            .limit(500)
            .snapshots()
            .map((s) => s.docs.length);
      case 'Туғилган кун':
        return db
            .collection('birthdate_change_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Код сўровлари':
        return db
            .collection('pending_codes')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Маршрут':
        return db
            .collection('trips')
            .where('taxiType', isEqualTo: 'marshrut')
            .where('status', isEqualTo: 'pending')
            .limit(200)
            .snapshots()
            .map((s) => s.docs.length);
      case 'Shaharlararo':
        return db
            .collection('intercity_orders')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Фойдаланувчилар':
        return db
            .collection('risk_events')
            .where('reviewed', isEqualTo: false)
            .snapshots()
            .map((s) => s.docs.length);
      case 'Risk review':
        return db
            .collection('risk_events')
            .where('reviewed', isEqualTo: false)
            .snapshots()
            .map((s) => s.docs.length);
      case 'Молия':
        return db
            .collection('payout_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.length);
      case 'Dispatch history':
        return db
            .collection('trips')
            .where('taxiType', isEqualTo: 'marshrut')
            .where('status', whereIn: ['pending', 'accepted'])
            .limit(200)
            .snapshots()
            .map((s) => s.docs.length);
      case 'Чат қўллaб-қуввaтлaш':
        return db
            .collection('support_chats')
            .where('lastFromAdmin', isEqualTo: false)
            .snapshots()
            .map((s) => s.docs.length);
      default:
        return null;
    }
  }

  Widget _sidebarBadge({required Stream<int> stream}) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        if (count <= 0) return const SizedBox.shrink();
        final text = count > 99 ? '99+' : '$count';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }

  Widget _userTile(AdminAuthService auth) {
    return InkWell(
      onTap: onLogout,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white24,
            child: Text(
                (auth.displayName?.isNotEmpty == true
                        ? auth.displayName!.substring(0, 1)
                        : '👤')
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.displayName?.isNotEmpty == true
                          ? auth.displayName!
                          : 'Админ',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${auth.roleDisplayLabel}'
                      '${auth.phone != null && auth.phone!.isNotEmpty ? ' · ${auth.phone}' : ''}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
            ),
            const Icon(Icons.logout, color: Colors.white60, size: 18),
          ],
        ]),
      ),
    );
  }

  /// Бир хостда фойдаланувчи web (`/`)га қайтиш.
  Widget _publicAppLinkTile(BuildContext context, bool compact) {
    final tile = InkWell(
      onTap: () {
        final navigated = navigateSameOriginPath('/');
        if (!navigated && context.mounted && kDebugMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 12),
              backgroundColor: Colors.orange.shade900,
              content: const Text(
                'Админ ҳозир "/" да ochilgan (локал debug). Фойдаланувчи '
                'иловасини ochиш учун: \n'
                '• `flutter run ... main_admin.dart --base-href /admin/` '
                '(ёки hosting шаклида `/admin/`):\n'
                '• ёки алоҳида портада user ва '
                '`--dart-define=USER_DEV_URL=...` қўшинг.\n'
                'Тафсилот — терминалда `[navigateSameOriginPath]`.',
              ),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 14, vertical: compact ? 8 : 10),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.home_outlined,
                      color: Colors.white70, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    'Фойдалан.',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                    ),
                  ),
                ],
              )
            : Row(children: [
                const Icon(Icons.home_outlined,
                    color: Colors.white70, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Фойдаланувчи иловаси',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.open_in_new, color: Colors.white38, size: 14),
              ]),
      ),
    );

    return Tooltip(
      message: 'Фойдаланувчи иловасига ўтиш (асосий саҳифа /)',
      preferBelow: false,
      child: Semantics(
        button: true,
        label: 'Фойдаланувчи иловасига ўтиш',
        child: tile,
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.section});
  final _AdminSection section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(section.icon, size: 48, color: Colors.orange.shade600),
          ),
          const SizedBox(height: 20),
          Text(section.label,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(section.description,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '🚧 Кейинги Phase\'дa ясaймиз',
              style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
