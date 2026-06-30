import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/user_address.dart';
import '../../../repositories/marshrut_driver_repository.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../services/driver_force_leave_service.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/trips_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/location_service.dart';
import '../../courier/screens/courier_screen.dart';
import '../../marshrut/driver/screens/driver_panel_marshrut_screen.dart';
import '../../marshrut/driver/screens/driver_register_marshrut_screen.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../../../core/utils/driver_car_prefill.dart';
import '../controllers/profile_controller.dart';
import 'address_edit_screen.dart';
import 'user_info_screen.dart';
import '../../../core/theme/app_theme.dart';

/// Профил — аватар, манзил, фойдаланувчи маълумотлари, роль панеллари.
/// Сотиш, хабарлар, чат, кошелёк — бош экран пастида (HomeBottomBar).
///
/// Эски "Сафарлар тарихи" ва "Буюртмалар тарихи" — олиб ташланди.
/// Маълумот сақланиб қолади, лекин шу йерда кўрсатилмайди (профил —
/// "сервислар маркази", тарихни ўз модулдан кўрилади).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.autoOpenCarEdit = false,
    this.returnAfterSave = false,
  });

  final bool autoOpenCarEdit;
  final bool returnAfterSave;

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
      child: _ProfileView(
        autoOpenCarEdit: autoOpenCarEdit,
        returnAfterSave: returnAfterSave,
      ),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView({
    this.autoOpenCarEdit = false,
    this.returnAfterSave = false,
  });

  final bool autoOpenCarEdit;
  final bool returnAfterSave;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  static const _green = AppColors.primaryDark;
  static const String _rolePin = '2024';

  bool _autoOpenHandled = false;
  int _roleTapCount = 0;
  DateTime? _lastRoleTap;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenCarEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenCarEdit());
    }
  }

  Future<void> _maybeAutoOpenCarEdit() async {
    if (_autoOpenHandled || !mounted) return;
    _autoOpenHandled = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final ctrl = context.read<ProfileController>();
    final saved = await _CarInfoSection.showEditDialog(
      context,
      ctrl,
      driverFlow: widget.returnAfterSave,
    );
    if (!mounted || !widget.returnAfterSave) return;
    Navigator.of(context).pop(saved == true);
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

    final scaffold = Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(loc.translate('profile')),
        backgroundColor: AppColors.primary,
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
          if (!c.hasCompleteAddress) _addressWarning(loc),
          _cards(c, loc),
          if (c.role == 'courier') _rolePanelButton(
            label: loc.translate('profile_courier_panel'),
            icon: Icons.delivery_dining,
            color: AppColors.primary,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CourierScreen())),
          ),
          if (c.role == 'driver' || c.hasCarInfo || widget.autoOpenCarEdit) ...[
            const SizedBox(height: 12),
            _CarInfoSection(ctrl: c),
            const SizedBox(height: 8),
          ],
          if (c.role == 'driver') ...[
            _ShiftButton(
              isOnline: c.isDriverOnline,
              onStart: () => _startShift(c, loc),
              onEnd: () => _endShift(c, loc),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.exit_to_app),
                  label: Text(context.tr('leave_driver_permanent')),
                  onPressed: () => _confirmLeaveDriverMode(context),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );

    if (!widget.returnAfterSave) return scaffold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(false);
      },
      child: scaffold,
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
          GestureDetector(
            onTap: _onRoleLabelTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_roleLabel(context, c.role, loc),
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ),
        ]),
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

  Future<void> _startShift(ProfileController c, AppLocalizations loc) async {
    await _openMarshrutPanel(context, c);
    if (!mounted) return;
    await c.load();
  }

  Future<void> _endShift(ProfileController c, AppLocalizations loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('end_shift_confirm_title')),
        content: Text(context.tr('end_shift_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('end_shift')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await c.endShift();
    if (!mounted) return;
    final err = c.consumeError();
    if (err != null) {
      _snack(context.tr(err), isError: true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('shift_ended_success')),
      backgroundColor: Colors.grey.shade700,
    ));
  }

  Future<void> _confirmLeaveDriverMode(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('leave_driver_permanent_title')),
        content: Text(context.tr('leave_driver_permanent_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final ridesRepo = context.read<RidesRepository>();
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      await DriverForceLeaveService(ridesRepo: ridesRepo)
          .forceLeaveMarshrutDriver(userPhone: phone);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('leave_driver_force_success')),
        backgroundColor: Colors.green,
      ));
      await context.read<ProfileController>().load();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('error_generic')),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _openMarshrutPanel(
    BuildContext context,
    ProfileController c,
  ) async {
    final uid = phoneDigits(c.phone);
    if (uid.length < 9) {
      _snack(context.tr('leave_driver_error_phone'), isError: true);
      return;
    }

    final profile = await MarshrutDriverRepository().getProfile(uid);
    if (!context.mounted) return;

    if (profile != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPanelMarshrutScreen(
            carModel: profile.carModel,
            plate: profile.plate,
            seats: profile.seats,
            stops: profile.stops,
            driverName: profile.driverName.isNotEmpty
                ? profile.driverName
                : c.name,
            driverPhone: profile.driverPhone.isNotEmpty
                ? profile.driverPhone
                : c.phone,
            driverId: profile.uid,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DriverRegisterMarshrutScreen(),
        ),
      );
    }
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
      backgroundColor: isError ? Colors.red : Colors.green,
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

class _ShiftButton extends StatelessWidget {
  const _ShiftButton({
    required this.isOnline,
    required this.onStart,
    required this.onEnd,
  });

  final bool isOnline;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    if (isOnline) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onEnd,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(
              context.tr('end_shift'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(
            context.tr('start_shift'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarInfoSection extends StatelessWidget {
  const _CarInfoSection({required this.ctrl});

  final ProfileController ctrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('car_info_title'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                if (ctrl.hasCarInfo)
                  TextButton.icon(
                    onPressed: () => _confirmDeleteCar(context, ctrl),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 16),
                    label: Text(
                      context.tr('delete'),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => showEditDialog(context, ctrl),
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(context.tr('edit')),
                ),
              ],
            ),
            if (ctrl.hasCarInfo) ...[
              const SizedBox(height: 4),
              _labeledRow(context.tr('car_model'), ctrl.carModel),
              _labeledRow(context.tr('car_color'), ctrl.carColor),
              _labeledRow(context.tr('car_plate'), ctrl.carPlate),
              _labeledRow(context.tr('car_seats_label'), '${ctrl.carSeats}'),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr('car_info_not_set'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _labeledRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool?> showEditDialog(
    BuildContext context,
    ProfileController ctrl, {
    bool driverFlow = false,
  }) async {
    final modelCtrl = TextEditingController(text: ctrl.carModel);
    final colorCtrl = TextEditingController(text: ctrl.carColor);
    final plateCtrl = TextEditingController(text: ctrl.carPlate);
    final initialSeats = ctrl.carSeats > 0 ? ctrl.carSeats : 4;
    final seatsCtrl = TextEditingController(text: '$initialSeats');

    InputDecoration fieldDecoration(
      BuildContext ctx, {
      required String labelKey,
      String? hint,
    }) =>
        InputDecoration(
          labelText: ctx.tr(labelKey),
          hintText: hint,
          isDense: driverFlow,
          contentPadding: driverFlow
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : null,
        );

    void clampSeatsToModel(String model) {
      final max = DriverCarPrefill.maxSeatsForModel(model);
      final parsed = int.tryParse(seatsCtrl.text.trim());
      if (parsed == null || parsed < 1) return;
      if (parsed > max) {
        seatsCtrl.text = '$max';
        seatsCtrl.selection = TextSelection.collapsed(
          offset: seatsCtrl.text.length,
        );
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: !driverFlow,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final maxSeats =
              DriverCarPrefill.maxSeatsForModel(modelCtrl.text.trim());
          return AlertDialog(
            insetPadding: driverFlow
                ? const EdgeInsets.symmetric(horizontal: 20, vertical: 24)
                : null,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(ctx.tr('car_info_edit')),
            contentPadding: driverFlow
                ? const EdgeInsets.fromLTRB(20, 12, 20, 0)
                : null,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: modelCtrl,
                    decoration: fieldDecoration(ctx, labelKey: 'car_model'),
                    onChanged: (_) => setLocal(() {
                      clampSeatsToModel(modelCtrl.text.trim());
                    }),
                  ),
                  SizedBox(height: driverFlow ? 6 : 8),
                  TextField(
                    controller: colorCtrl,
                    decoration: fieldDecoration(ctx, labelKey: 'car_color'),
                  ),
                  SizedBox(height: driverFlow ? 6 : 8),
                  TextField(
                    controller: plateCtrl,
                    decoration: fieldDecoration(ctx, labelKey: 'car_plate'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  SizedBox(height: driverFlow ? 6 : 8),
                  TextField(
                    controller: seatsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    decoration: fieldDecoration(
                      ctx,
                      labelKey: 'car_seats_label',
                      hint: '1–$maxSeats',
                    ),
                    onChanged: (_) => setLocal(() {
                      clampSeatsToModel(modelCtrl.text.trim());
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final model = modelCtrl.text.trim();
                  final color = colorCtrl.text.trim();
                  final plate = plateCtrl.text.trim();
                  final max =
                      DriverCarPrefill.maxSeatsForModel(model);
                  final parsed = int.tryParse(seatsCtrl.text.trim()) ?? 0;
                  final chosenSeats = parsed.clamp(1, max);
                  if (model.isEmpty ||
                      color.isEmpty ||
                      plate.isEmpty ||
                      parsed <= 0) {
                    return;
                  }
                  final ok = await ctrl.saveCarInfo(
                    model: model,
                    color: color,
                    plate: plate,
                    seats: chosenSeats,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, ok);
                },
                child: Text(ctx.tr('save')),
              ),
            ],
          );
        },
      ),
    );

    modelCtrl.dispose();
    colorCtrl.dispose();
    plateCtrl.dispose();
    seatsCtrl.dispose();
    return saved;
  }

  Future<void> _confirmDeleteCar(
    BuildContext context,
    ProfileController ctrl,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('car_delete_confirm_title')),
        content: Text(context.tr('car_delete_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ctrl.clearCarInfo();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('car_deleted_success')),
      backgroundColor: Colors.green,
    ));
  }
}
