import 'dart:async';
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
import '../../orders/screens/orders_screen.dart';
import '../../seller/screens/seller_pos_screen.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../../realty/screens/my_realty_listings_screen.dart';
import '../controllers/profile_controller.dart';
import '../widgets/cabinet_ui.dart';
import 'address_edit_screen.dart';
import 'delete_account_screen.dart';
import 'user_info_screen.dart';
import '../../../core/theme/app_theme.dart';
// «Талаб ва таклифлар» бўлими (эга қарори, 2026-10-03).
import '../../demand_offer/domain/canonical_id.dart';
import '../../demand_offer/presentation/activity/demand_activity_entry.dart';

/// Профил — аватар, манзил, фойдаланувчи маълумотлари, роль панеллари.
/// Сотиш, хабарлар, чат, кошелёк — бош экран пастида (HomeBottomBar).
///
/// Эски "Сафарлар тарихи" — олиб ташланди (тарих ўз модулидан кўрилади).
/// «Буюртмалар» (OrdersScreen) 2026-10-22 дан «Фаолият» бўлимида қайта уланди.
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

    final c0 = context.ava;
    final demandUid = canonicalUserId(c.phone);

    return Scaffold(
      backgroundColor: c0.bg,
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: Listenable.merge([ServiceConfigHolder.revision, GeoNames.revision]),
          builder: (context, _) {
            final district = BrandLabels.districtContextFor(context.contentLang) ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.translate('home_nav_cabinet')),
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
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      // Pull-to-refresh: ism/манзил/расм сервердан қайта ўқилади.
      body: RefreshIndicator(
        color: c0.brandText,
        onRefresh: c.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(children: [
            CabinetHeader(
              avatar: _headerAvatar(c),
              title: '${_honorific(c, loc)} ${c.name.isEmpty ? '—' : c.name}',
              phone: c.phone,
              roleLabel: _roleLabel(context, c.role, loc),
              changePhotoLabel: loc.translate('profile_photo'),
              onAvatarTap: () => _showImagePicker(c, loc),
              onRoleTap: _onRoleLabelTap,
              // Чиқиш — ўнг юқори бурчакда ихчам стрелка (эга, 2026-10-24).
              actionIcon: Icons.logout_rounded,
              actionLabel: loc.translate('logout'),
              onAction: () => _showLogoutDialog(c, loc),
              // Ҳайдовчи индикатори — ҳедер ичида (фақат ҳайдовчида кўринади).
              footer: demandUid.isEmpty
                  ? null
                  : DriverStatusChip(
                      key: ValueKey(demandUid),
                      userId: demandUid,
                      alignment: Alignment.center,
                    ),
            ),
            // Ҳамён — Кабинетнинг биринчи қатори (эга қарори, 2026-10-18).
            StreamBuilder<int>(
              stream: _walletBalance,
              builder: (context, snap) => KeyedSubtree(
                key: const ValueKey('profile-wallet-tile'),
                child: CabinetWalletCard(
                  title: context.tr('wlt_profile_title'),
                  // Баланс номаълум (юкланмаган/хато) — ёлғон «0» кўрсатилмайди.
                  balanceText: snap.hasData ? formatMoney(snap.data!) : null,
                  hint: context.tr('wlt_profile_sub'),
                  actionLabel: context.tr('cab_topup'),
                  onTap: () => openWalletTopUp(Navigator.of(context)),
                ),
              ),
            ),
            if (c.deletionPending)
              CabinetNotice(
                key: const ValueKey('profile-deletion-pending'),
                text: context.tr('acct_del_pending_body').replaceAll('{date}', _fmtDate(c.deletionScheduledFor)),
                actionLabel: context.tr('acct_del_cancel_btn'),
                onAction: () => _openDeleteAccount(c),
              ),
            if (!c.hasUsableAddress)
              CabinetNotice(
                text: loc.translate('profile_address_incomplete_banner'),
                actionLabel: loc.translate('profile_fill_address'),
                onAction: _openAddress,
              ),
            CabinetSection(
              title: context.tr('cab_sec_account'),
              children: [
                CabinetRow(
                  icon: Icons.person_rounded,
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
              ],
            ),
            // Курьерлик, кафе-ресторан / уй ошпази, ҳайдовчи (автомобиль, смена,
            // чиқиш) ва дўкон «＋ → Менинг бизнесим» га кўчди (эга, 2026-10-16):
            // Кабинет — бошқариш жойи, бошлаш эмас.
            CabinetSection(
              title: context.tr('cab_sec_activity'),
              children: [
                // Мижознинг буюртмалари (нон, таом, гилам, сут) — Фаол/Тугаган.
                // Экран тайёр эди, лекин ҳеч қаердан очилмасди (2026-10-22
                // аудит); эга уланишини сўради. Номи — мавжуд `bottom_orders`.
                CabinetRow(
                  icon: Icons.receipt_long_rounded,
                  title: context.tr('bottom_orders'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                  ),
                ),
                // ТАЛАБ ВА ТАКЛИФЛАР (эга қарори, 2026-10-03): пастки
                // навигацияга янги таб қўшилмайди — бўлим шу ерда туради.
                if (demandUid.isNotEmpty)
                  CabinetRow(
                    icon: Icons.swap_horiz_rounded,
                    title: loc.translate('profile_demand_offer_section'),
                    subtitle: context.tr('profile_demand_offer_hint'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DemandActivityEntry(userId: demandUid),
                      ),
                    ),
                  ),
                // Кўчмас мулк объектлари — фойдаланувчининг ўз контенти,
                // шунинг учун профилда туради (бўлим экранида эмас).
                CabinetRow(
                  icon: Icons.apartment_rounded,
                  title: context.tr('realty_my_title'),
                  subtitle: context.tr('realty_my_subtitle'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyRealtyListingsScreen()),
                  ),
                ),
                if (c.role == 'seller' || c.role == 'admin' || c.role == 'superadmin')
                  CabinetRow(
                    icon: Icons.point_of_sale_rounded,
                    title: context.tr('cab_seller_panel'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SellerPosScreen()),
                    ),
                  ),
              ],
            ),
            CabinetSection(
              title: context.tr('cab_sec_app'),
              children: [
                CabinetRow(
                  icon: Icons.ios_share_rounded,
                  title: context.tr('app_share_title'),
                  subtitle: context.tr('app_share_subtitle'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final failedText = context.tr('app_share_failed');
                    final ok = await shareAvaApp(context);
                    if (!ok && mounted) {
                      messenger.showSnackBar(SnackBar(content: Text(failedText)));
                    }
                  },
                ),
                // «Чиқиш» қатори бу ерда йўқ: у ҳедернинг ўнг юқори бурчагидаги
                // ихчам стрелкага кўчди (эга, 2026-10-24).
                CabinetRow(
                  key: const ValueKey('profile-delete-account'),
                  icon: Icons.delete_forever_rounded,
                  title: context.tr('acct_del_row_title'),
                  subtitle: context.tr('acct_del_row_sub'),
                  danger: true,
                  onTap: () => _openDeleteAccount(c),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // HEADER YORDAMCHILARI
  // ────────────────────────────────────────────────────────────────────
  Widget _headerAvatar(ProfileController c) {
    final initial = Center(
      child: Text(
        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 38, fontWeight: FontWeight.bold, color: _green),
      ),
    );
    if (c.imagePath != null) {
      final f = File(c.imagePath!);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }
    if (c.photoUrl.isNotEmpty) {
      // Тармоқ расми юкланмаса — синиқ белги эмас, бош ҳарф.
      return Image.network(
        c.photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initial,
      );
    }
    return initial;
  }

  Future<void> _openAddress() =>
      AddressGate.edit(context, context.read<ProfileController>());

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

  String _fmtDate(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// «Ҳисобни ўчириш» экрани. Сўров қабул қилингач: тушунтириш ойнаси → сессия тозаланади → кириш экрани
  /// (ўчириш ижроси серверда; шу вақтгача қайта кириб бекор қилиш мумкин).
  Future<void> _openDeleteAccount(ProfileController c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeleteAccountScreen(
          onRequested: (screenCtx, days) async {
            await showDialog<void>(
              context: screenCtx,
              barrierDismissible: false,
              builder: (dialogCtx) => AlertDialog(
                title: Text(dialogCtx.tr('acct_del_done_title')),
                content: Text(dialogCtx.tr('acct_del_done_body').replaceAll('{days}', '$days')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: Text(dialogCtx.tr('understand')),
                  ),
                ],
              ),
            );
            await c.logout();
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              (_) => false,
            );
          },
        ),
      ),
    );
    if (mounted) unawaited(c.load());
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
