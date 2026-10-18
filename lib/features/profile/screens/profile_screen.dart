import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/app_share.dart';
import '../../../core/geo/geo_names.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/driver_status_chip.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../l10n/app_localizations.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/trips_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/location_service.dart';
import '../../seller/screens/seller_pos_screen.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../../realty/screens/my_realty_listings_screen.dart';
import '../controllers/profile_controller.dart';
import 'address_edit_screen.dart';
import 'user_info_screen.dart';
import '../../../core/theme/app_theme.dart';
// «Талаб ва таклифлар» бўлими (эга қарори, 2026-10-03).
import '../../demand_offer/domain/canonical_id.dart';
import '../../demand_offer/presentation/activity/demand_activity_entry.dart';

/// Профил — аватар, манзил, фойдаланувчи маълумотлари, роль панеллари.
/// Сотиш, хабарлар, чат, кошелёк — бош экран пастида (HomeBottomBar).
///
/// Эски "Сафарлар тарихи" ва "Буюртмалар тарихи" — олиб ташланди.
/// Маълумот сақланиб қолади, лекин шу йерда кўрсатилмайди (профил —
/// "сервислар маркази", тарихни ўз модулдан кўрилади).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Anonim (guest) foydalanuvchida telefon-orqali profil hali mavjud
    // emas — to'liq ProfileController oqimi o'rniga ixtiyoriy ravishda
    // telefon-registratsiyaga (mavjud OnboardingScreen, o'zgarishsiz)
    // o'tkazuvchi qisqa taklif ko'rsatiladi.
    if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
      return const _AnonymousProfileView();
    }
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

class _AnonymousProfileView extends StatelessWidget {
  const _AnonymousProfileView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 64, color: AppColors.primaryText),
              const SizedBox(height: 16),
              Text(
                context.tr('profile_login_cta'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const OnboardingScreen()),
                      (_) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    context.tr('ob_start'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  static const _green = AppColors.primaryText;
  static const String _rolePin = '2024';

  int _roleTapCount = 0;
  DateTime? _lastRoleTap;

  /// Ҳамён қатори учун жонли баланс (бош экрандан ҳамён карточкаси олиб
  /// ташланган, эга қарори 2026-10-18: ҳамёнга кириш — Кабинетнинг биринчи қатори).
  late final Stream<int> _walletBalance = walletBalanceStream();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<ProfileController>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final err = c.consumeError();
      // Рақам алмаштириш хатолари l10n калити (`profile_phone_change_*`),
      // қолганлари — аввалгидек тайёр матн.
      if (err != null && mounted) {
        _snack(
          err.startsWith('profile_phone_change_') ? context.tr(err) : err,
          isError: true,
        );
      }
      final ok = c.consumeSuccess();
      if (ok != null && mounted) _snack(ok);
    });

    final scaffold = Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: Listenable.merge([ServiceConfigHolder.revision, GeoNames.revision]),
          builder: (context, _) {
            final district = BrandLabels.districtContextFor(context.contentLang) ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.translate('profile')),
                if (district.isNotEmpty)
                  Text(
                    '${BrandLabels.brand} · $district',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onPrimary.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            );
          },
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.onPrimary),
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
          if (!c.hasUsableAddress) _addressWarning(loc),
          _cards(c, loc),
          // ТАЛАБ ВА ТАКЛИФЛАР (эга қарори, 2026-10-03).
          //
          // Пастки навигацияга ЯНГИ ТАБ ҚЎШИЛМАЙДИ — бўлим Профиль
          // ичида туради. Ҳар бир фойдаланувчига кўринади: сўров
          // юбориш ҳар кимга тегишли, таклифчи бўлиш эса ихтиёрий
          // (иккинчи бўлим фақат имконият ёққанларга чиқади).
          if (canonicalUserId(c.phone).isNotEmpty)
            _rolePanelButton(
              label: loc.translate('profile_demand_offer_section'),
              icon: Icons.swap_horiz_rounded,
              color: AppColors.primaryMid,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DemandActivityEntry(
                    userId: canonicalUserId(c.phone),
                  ),
                ),
              ),
            ),
          // Курьерлик, кафе-ресторан / уй ошпази, ҳайдовчи (автомобиль, смена,
          // чиқиш) ва дўкон «＋ → Менинг бизнесим» га кўчди (эга, 2026-10-16):
          // Кабинет — бошқариш жойи, бошлаш эмас.
          if (c.role == 'seller' ||
              c.role == 'admin' ||
              c.role == 'superadmin')
            _rolePanelButton(
              label: 'Sotuv paneli',
              icon: Icons.point_of_sale,
              color: AppColors.primaryDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SellerPosScreen()),
              ),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );

    return scaffold;
  }

  // ────────────────────────────────────────────────────────────────────
  // HEADER
  // ────────────────────────────────────────────────────────────────────
  Widget _header(ProfileController c, AppLocalizations loc) {
    return Container(
      color: AppColors.primaryDark,
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
                  child: _headerAvatar(c),
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
                  color: AppColors.onPrimary)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _onRoleLabelTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_roleLabel(context, c.role, loc),
                  style: const TextStyle(fontSize: 12, color: AppColors.onPrimary)),
            ),
          ),
          // Ҳайдовчи индикатори — ҳедерда: карталар 20 px юқорига сурилгани
          // учун ҳедердан пастдаги чип уларнинг остида қолар эди.
          if (canonicalUserId(c.phone).isNotEmpty)
            DriverStatusChip(
              key: ValueKey(canonicalUserId(c.phone)),
              userId: canonicalUserId(c.phone),
              alignment: Alignment.center,
            ),
        ]),
      ),
    );
  }

  Widget _headerAvatar(ProfileController c) {
    if (c.imagePath != null) {
      final f = File(c.imagePath!);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }
    if (c.photoUrl.isNotEmpty) {
      return Image.network(c.photoUrl, fit: BoxFit.cover);
    }
    return Center(
      child: Text(
        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 36, fontWeight: FontWeight.bold, color: _green),
      ),
    );
  }

  Widget _addressWarning(AppLocalizations loc) {
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
          Expanded(
            child: Text(
              loc.translate('profile_address_incomplete_banner'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _openAddress,
            child: Text(loc.translate('profile_fill_address')),
          ),
        ]),
      ),
    );
  }

  Future<void> _openAddress() =>
      AddressGate.edit(context, context.read<ProfileController>());

  // ────────────────────────────────────────────────────────────────────
  // 4 КАРТА
  // ────────────────────────────────────────────────────────────────────
  Widget _cards(ProfileController c, AppLocalizations loc) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          StreamBuilder<int>(
            stream: _walletBalance,
            builder: (context, snap) => _cardTile(
              key: const ValueKey('profile-wallet-tile'),
              icon: Icons.account_balance_wallet_rounded,
              color: _green,
              title: context.tr('wlt_profile_title'),
              // Баланс номаълум (юкланмаган/хато) — ёлғон «0» кўрсатилмайди.
              subtitle: snap.hasData
                  ? formatMoney(snap.data!)
                  : context.tr('wlt_profile_sub'),
              onTap: () => openWalletTopUp(Navigator.of(context)),
            ),
          ),
          const SizedBox(height: 10),
          _cardTile(
            icon: Icons.person,
            color: _green,
            title: loc.translate('profile_user_info_title'),
            subtitle: c.addressDisplay.isEmpty
                ? loc.translate('profile_address_not_entered')
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
          const SizedBox(height: 10),
          // Кўчмас мулк объектлари — фойдаланувчининг ўз контенти,
          // шунинг учун профилда туради (бўлим экранида эмас).
          // Дўкон ва китоб «＋ → Менинг бизнесим» га кўчди (2026-10-16).
          _cardTile(
            icon: Icons.apartment_rounded,
            color: _green,
            title: context.tr('realty_my_title'),
            subtitle: context.tr('realty_my_subtitle'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyRealtyListingsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _cardTile(
            icon: Icons.share_rounded,
            color: _green,
            title: context.tr('app_share_title'),
            subtitle: context.tr('app_share_subtitle'),
            onTap: () async {
              final ok = await shareAvaApp(context);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('app_share_failed'))),
                );
              }
            },
          ),
        ]),
      ),
    );
  }

  Widget _cardTile({
    Key? key,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Material(
      key: key,
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
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
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
            foregroundColor: AppColors.onPrimary,
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

  void _onRoleLabelTap() {
    final now = DateTime.now();
    if (_lastRoleTap != null &&
        now.difference(_lastRoleTap!) > const Duration(seconds: 2)) {
      _roleTapCount = 0;
    }
    _roleTapCount++;
    _lastRoleTap = now;
    if (_roleTapCount >= 7) {
      _roleTapCount = 0;
      _showRolePinDialog();
    }
  }

  Future<void> _showRolePinDialog() async {
    final loc = AppLocalizations.of(context)!;
    final pinController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    final entered = pinController.text;
    pinController.dispose();

    if (!mounted || confirmed != true) return;

    if (entered != _rolePin) {
      _snack('Нотўғри PIN', isError: true);
      return;
    }

    final c = context.read<ProfileController>();
    if (c.role == 'driver') {
      _snack('Haydovchi rolini PIN orqali o\'zgartirib bo\'lmaydi', isError: true);
      return;
    }
    final newRole = c.role == 'courier' ? 'user' : 'courier';
    final ok = await c.quickSaveRole(newRole);
    if (!mounted) return;
    if (!ok && c.errorMessage != null) {
      _snack(c.errorMessage!, isError: true);
      c.consumeError();
      return;
    }
    await c.load();
    if (!mounted) return;
    _snack('Роль ўзгартирилди: ${_roleLabel(context, c.role, loc)}');
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : AvaLight.ok,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _honorific(ProfileController c, AppLocalizations loc) =>
      c.gender == 'female'
          ? loc.translate('madam')
          : loc.translate('mister');

  String _roleLabel(BuildContext context, String role, AppLocalizations loc) {
    switch (role) {
      case 'driver':
        return loc.translate('driver_role');
      case 'courier':
        return context.tr('courier_role');
      case 'admin':
        return context.tr('admin_role');
      default:
        return loc.translate('user_role');
    }
  }
}
