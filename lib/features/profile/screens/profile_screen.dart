import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/same_origin_nav.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/user_address.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/news_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/trips_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/location_service.dart';
import '../../analytics/screens/monitoring_center_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../courier/screens/courier_screen.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../controllers/profile_controller.dart';
import '../widgets/admin_pin_promote_card.dart';
import '../widgets/wallet_section.dart';
import 'address_edit_screen.dart';
import 'news_screen.dart';
import 'user_info_screen.dart';
import 'wallet_partner_program_screen.dart';

/// Соддалaштирилган профил — 4 та асосий "карта":
///   1. 💳 Кашелёк    (Wallet)
///   2. 🔔 Янгилик ва хабарлар (Admin News)
///   3. 💬 Чат          (Admin Chat)
///   4. 👤 Фойдаланувчи маълумотлари (User info / Address)
///
/// Эски "Сафарлар тарихи" ва "Буюртмалар тарихи" — олиб ташланди.
/// Маълумот сақланиб қолади, лекин шу йерда кўрсатилмайди (профил —
/// "сервислар маркази", тарихни ўз модулдан кўрилади).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileController>(
      create: (ctx) => ProfileController(
        driverRepo: ctx.read<DriverRepository>(),
        tripsRepo: ctx.read<TripsRepository>(),
        ordersRepo: ctx.read<OrdersRepository>(),
        userRepo: ctx.read<UserRepository>(),
        locationService: ctx.read<LocationService>(),
      )..load(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  static const _green = Color(0xFF2E7D32);

  int _unreadNews = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnread());
  }

  Future<void> _loadUnread() async {
    final c = context.read<ProfileController>();
    if (c.phone.isEmpty) {
      // load() ҳали тугамаган бўлиши мумкин — қайтариб уринамиз.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _loadUnread();
      });
      return;
    }
    final uid = phoneDigits(c.phone);
    if (uid.length < 9) return;
    try {
      final userRepo = context.read<UserRepository>();
      final newsRepo = context.read<NewsRepository>();
      final user = await userRepo.getById(uid);
      final audiences = ['all', c.role.isEmpty ? 'user' : c.role];
      final count = await newsRepo.countUnread(
          uid, user?.lastNewsReadAt, audiences);
      if (mounted) setState(() => _unreadNews = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<ProfileController>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final err = c.consumeError();
      if (err != null && mounted) _snack(err, isError: true);
      final ok = c.consumeSuccess();
      if (ok != null && mounted) _snack(ok);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: Text(loc.translate('profile')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'logout') _showLogoutDialog(c, loc);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  const Icon(Icons.logout, size: 18, color: Colors.red),
                  const SizedBox(width: 10),
                  Text(loc.translate('logout'),
                      style: const TextStyle(color: Colors.red)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          _header(c, loc),
          if (!c.hasCompleteAddress) _addressWarning(),
          const AdminPinPromoteCard(),
          _cards(c, loc),
          if (c.role == 'admin' || c.role == 'superadmin') _rolePanelButton(
            label: 'АДМИН ПАНЕЛИ',
            icon: Icons.admin_panel_settings,
            color: const Color(0xFF0D47A1),
            onTap: () {
              // Вебда `/admin/` — тўлиқ панель (main_admin); ички Monitoring
              // билан дубликат бўлмасин.
              if (kIsWeb) {
                navigateSameOriginPath('/admin/');
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MonitoringCenterScreen(),
                ),
              );
            },
          ),
          if (c.role == 'courier') _rolePanelButton(
            label: 'КУРЬЕР ПАНЕЛИ',
            icon: Icons.delivery_dining,
            color: const Color(0xFFE65100),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CourierScreen())),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // HEADER
  // ────────────────────────────────────────────────────────────────────
  Widget _header(ProfileController c, AppLocalizations loc) {
    return Container(
      color: _green,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      child: Center(
        child: Column(children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _showImagePicker(c, loc),
            child: Stack(children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: ClipOval(
                  child: c.imagePath != null
                      ? Image.file(File(c.imagePath!), fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: _green),
                          ),
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.camera_alt, size: 15, color: _green),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text('${_honorific(c, loc)} ${c.name.isEmpty ? '—' : c.name}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_roleLabel(c.role, loc),
                style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _addressWarning() {
    return Transform.translate(
      offset: const Offset(0, -10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Яшаш манзилингиз тўлдирилмаган. Курьер сизга товар олиб бориши учун мажбурий.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _openAddress,
            child: const Text('Тўлдириш'),
          ),
        ]),
      ),
    );
  }

  Future<void> _openAddress() async {
    final c = context.read<ProfileController>();
    final result = await Navigator.push<UserAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressEditScreen(initial: c.structuredAddress),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      c.applyAddress(result);
    } else {
      // Foydalanuvchi back tugmasини босди — лекин Firestore'да аввaлги
      // ҳолат ўзгaрган бўлиши мумкин (бошқа окимдан AddressGate сақлаган).
      await c.reloadAddressFromPrefs();
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 4 КАРТА
  // ────────────────────────────────────────────────────────────────────
  Widget _cards(ProfileController c, AppLocalizations loc) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          // 1. Кашелёк — мавжуд секцияни ишлатaмиз.
          if (phoneDigits(c.phone).length >= 9) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: WalletSection(phone: c.phone),
            ),
            const SizedBox(height: 10),
          ],
          _cardTile(
            icon: Icons.agriculture,
            color: const Color(0xFF6D4C41),
            title: 'Кошелёк ва маҳсулот топшириш',
            subtitle:
                'Сут, тухум, гуруч — қайерда ҳисобланади; балансни қаерда сарфлайсиз',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      WalletPartnerProgramScreen(phone: c.phone),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 2. Янгилик ва хабарлар.
          _cardTile(
            icon: Icons.campaign,
            color: const Color(0xFF1565C0),
            title: 'Янгилик ва хабарлар',
            subtitle: 'Админ томонидан юборилган маълумотлар',
            badge: _unreadNews > 0 ? _unreadNews.toString() : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewsScreen()),
              );
              if (mounted) _loadUnread();
            },
          ),
          const SizedBox(height: 10),

          // 3. Чат — админ билан.
          _cardTile(
            icon: Icons.chat_bubble,
            color: const Color(0xFF7B1FA2),
            title: '💬 Админ билан чат',
            subtitle: 'Савол / шикоят / таклиф ёзинг',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(targetPhone: phoneDigits(c.phone)),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          // 4. Фойдаланувчи маълумотлари + манзил.
          _cardTile(
            icon: Icons.person,
            color: _green,
            title: 'Фойдаланувчи маълумотлари',
            subtitle: c.addressDisplay.isEmpty
                ? 'Манзил киритилмаган'
                : c.addressDisplay,
            onTap: () async {
              // Yangi route — alohida widget tree, shu sababli mavjud
              // `ProfileController` instance'ni qo'lda forward qilamiz, aks holda
              // UserInfoScreen `context.read<ProfileController>()` topa olmaydi.
              final controller = context.read<ProfileController>();
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider<ProfileController>.value(
                    value: controller,
                    child: const UserInfoScreen(),
                  ),
                ),
              );
              if (mounted) controller.load();
            },
          ),
        ]),
      ),
    );
  }

  Widget _cardTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  Widget _rolePanelButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // DIALOGS
  // ────────────────────────────────────────────────────────────────────
  void _showImagePicker(ProfileController c, AppLocalizations loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(loc.translate('photo_source'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_library, color: _green),
            title: Text(loc.translate('gallery')),
            onTap: () {
              Navigator.pop(context);
              c.pickImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: _green),
            title: Text(loc.translate('camera')),
            onTap: () {
              Navigator.pop(context);
              c.pickImage(ImageSource.camera);
            },
          ),
          if (c.imagePath != null)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(loc.translate('delete_photo'),
                  style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                c.deleteImage();
              },
            ),
        ]),
      ),
    );
  }

  void _showLogoutDialog(ProfileController c, AppLocalizations loc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(loc.translate('logout_confirm')),
        content: Text(loc.translate('logout_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await c.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                (_) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.translate('logout'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _honorific(ProfileController c, AppLocalizations loc) =>
      c.gender == 'female'
          ? loc.translate('madam')
          : loc.translate('mister');

  String _roleLabel(String role, AppLocalizations loc) {
    switch (role) {
      case 'driver':
        return loc.translate('driver_role');
      case 'courier':
        return '🛵 Курьер';
      case 'admin':
        return '🔧 Админ';
      default:
        return loc.translate('user_role');
    }
  }
}
