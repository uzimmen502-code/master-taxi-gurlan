// Админ entry — faqat `main_admin.dart` (web) орқали compile бўлади.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/same_origin_nav.dart';
import '../../analytics/screens/admin_orders_screen.dart';
import '../../analytics/screens/monitoring_center_screen.dart';
import '../services/admin_auth_service.dart';
import 'admin_news_list_screen.dart';
import 'birthday_bonus_screen.dart';
import 'identity_approvals_screen.dart';
import 'intercity_admin_screen.dart';
import 'jobs_moderation_screen.dart';
import 'marshrut_admin_screen.dart';
import 'marshrut_dispatch_history_screen.dart';
import 'chat_support_screen.dart';
import 'courier_admin_screen.dart';
import 'driver_applications_screen.dart';
import 'payout_management_screen.dart';
import 'products_manager_screen.dart';
import 'risk_review_screen.dart';
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

  static const _sections = [
    _AdminSection(
      label: 'Monitoring Center',
      icon: Icons.dashboard,
      description: 'KPI ва кенг таҳлил',
    ),
    _AdminSection(
      label: 'Маҳсулoтлaр',
      icon: Icons.inventory_2,
      description: 'Нон, овқaт, нархлaр',
    ),
    _AdminSection(
      label: 'Ҳaйдовчи aризалари',
      icon: Icons.directions_car,
      description: 'Янги aризалaр',
    ),
    _AdminSection(
      label: 'Тасдиқлар',
      icon: Icons.verified_user_outlined,
      description: 'Рақам ва profile сўровлари',
    ),
    _AdminSection(
      label: 'Фойдаланувчилар',
      icon: Icons.people_alt_outlined,
      description: 'Телефон, туғилган кун, қурилмалар',
    ),
    _AdminSection(
      label: 'Risk review',
      icon: Icons.security,
      description: 'Хавфли сигналлар',
    ),
    _AdminSection(
      label: 'Молия',
      icon: Icons.account_balance_wallet,
      description: 'Payout ва тушум',
    ),
    _AdminSection(
      label: 'Birthday bonus',
      icon: Icons.card_giftcard,
      description: 'Йиллик туғилган кун бонуси',
    ),
    _AdminSection(
      label: 'Хабарлaр',
      icon: Icons.campaign,
      description: 'Фойдaлaнувчилaргa юбoриш',
    ),
    _AdminSection(
      label: 'Иш топ',
      icon: Icons.work_history,
      description: 'Эълонларни тасдиқлаш',
    ),
    _AdminSection(
      label: 'Маршрут',
      icon: Icons.directions_bus,
      description: 'Ҳайдовчилар ва сафарлар',
    ),
    _AdminSection(
      label: 'Dispatch history',
      icon: Icons.timeline,
      description: 'Маршрут навбат тарихи',
    ),
    _AdminSection(
      label: 'Shaharlararo',
      icon: Icons.connecting_airports,
      description: 'Intercity haydovchilar va bronlar',
    ),
    _AdminSection(
      label: 'Курьер',
      icon: Icons.delivery_dining,
      description: 'Reyslar va kuryer boshqaruvi',
    ),
    _AdminSection(
      label: 'Буюртмалар',
      icon: Icons.receipt_long,
      description: 'Нон ва овқат буюртмалари',
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
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 1100;
    final isMedium = media.size.width > 700;

    final sidebar = _Sidebar(
      sections: _sections,
      selectedIndex: _selectedIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      onLogout: _logout,
      compact: !isWide,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: isMedium ? null : Drawer(child: sidebar),
      body: Row(children: [
        // Tor panel: icon + қисқа ном бор — 76px етарсиз.
        if (isMedium) SizedBox(width: isWide ? 240 : 92, child: sidebar),
        Expanded(
          child: _body(),
        ),
      ]),
      appBar: isMedium
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              title: Text(_sections[_selectedIndex].label),
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

  Widget _body() {
    final section = _sections[_selectedIndex];
    if (section.label == 'Monitoring Center') {
      return const MonitoringCenterScreen(embedded: true);
    }
    if (section.label == 'Хабарлaр') {
      return const AdminNewsListScreen();
    }
    if (section.label == 'Иш топ') {
      return const JobsModerationScreen();
    }
    if (section.label == 'Ҳaйдовчи aризалари') {
      return const DriverApplicationsScreen();
    }
    if (section.label == 'Тасдиқлар') {
      return const IdentityApprovalsScreen();
    }
    if (section.label == 'Фойдаланувчилар') {
      return const UsersDevicesScreen();
    }
    if (section.label == 'Risk review') {
      return const RiskReviewScreen();
    }
    if (section.label == 'Маҳсулoтлaр') {
      return const ProductsManagerScreen();
    }
    if (section.label == 'Молия') {
      return const PayoutManagementScreen();
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
    if (section.label == 'Буюртмалар') {
      return const AdminOrdersScreen();
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
  });
  final String label;
  final IconData icon;
  final String description;
}

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
        color: Color(0xFF0D47A1),
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
              return _sidebarItem(s, selected, () => onSelect(i));
            }),
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
                Text('Master Taxi',
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

  Widget _sidebarItem(_AdminSection s, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 14, vertical: compact ? 12 : 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: compact
            ? Center(
                child: Icon(s.icon,
                    color: selected ? Colors.white : Colors.white70, size: 22),
              )
            : Row(children: [
                Icon(s.icon,
                    color: selected ? Colors.white : Colors.white70, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(s.label,
                                style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w500)),
                          ),
                        ]),
                        Text(s.description,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10)),
                      ]),
                ),
              ]),
      ),
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
                    Text(auth.phone ?? '',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
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
                  color: Color(0xFFE65100), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
