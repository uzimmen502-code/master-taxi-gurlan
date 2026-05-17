import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/saved_place.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/location_service.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/gurlan_places.dart';
import '../../../map_picker/screens/map_picker_screen.dart';
import '../controllers/local_taxi_controller.dart';
import '../services/driver_app_launcher.dart';
import '../widgets/driver_app_promo_dialog.dart';
import '../widgets/install_driver_app_dialog.dart';
import 'searching_screen.dart';

class LocalTaxiScreen extends StatelessWidget {
  const LocalTaxiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final c = LocalTaxiController(
          locationService: ctx.read<LocationService>(),
          userRepo: ctx.read<UserRepository>(),
        );
        c.init();
        return c;
      },
      child: const _LocalTaxiView(),
    );
  }
}

class _LocalTaxiView extends StatefulWidget {
  const _LocalTaxiView();

  @override
  State<_LocalTaxiView> createState() => _LocalTaxiViewState();
}

class _LocalTaxiViewState extends State<_LocalTaxiView> {
  static const _heroStart = Color(0xFFF57F17);
  static const _heroEnd = Color(0xFFFF8F00);
  static const _green = Color(0xFF2E7D32);

  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();

  List<String> _fromSug = const [];
  List<String> _toSug = const [];
  Timer? _debounce;

  bool _bootstrapped = false;
  LocalTaxiController? _controllerRef;

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) setState(() => _fromSug = const []);
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) setState(() => _toSug = const []);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onGpsTap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _controllerRef = context.read<LocalTaxiController>();
    _controllerRef!.addListener(_handleMessages);
  }

  void _handleMessages() {
    if (!mounted) return;
    final c = context.read<LocalTaxiController>();
    final info = c.infoMessage;
    final err = c.errorMessage;
    if (info != null) {
      _snack(info);
      c.clearMessages();
    } else if (err != null) {
      _snack(err);
      c.clearMessages();
    }
  }

  @override
  void dispose() {
    _controllerRef?.removeListener(_handleMessages);
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─── Autocomplete ─────────────────────────────────────────────────

  void _onFromChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _fromSug = GurlanPlaces.search(q));
    });
  }

  void _onToChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _toSug = GurlanPlaces.search(q));
    });
  }

  // ─── Actions ──────────────────────────────────────────────────────

  Future<void> _onGpsTap() async {
    final addr = await context.read<LocalTaxiController>().getCurrentAddress();
    if (!mounted || addr == null) return;
    setState(() {
      _fromCtrl.text = addr;
      _fromSug = const [];
    });
  }

  Future<void> _pickOnMap({required bool isFrom}) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => const MapPickerScreen(title: 'Манзил танлаш')),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromCtrl.text = result;
      } else {
        _toCtrl.text = result;
      }
    });
  }

  Future<void> _onSearch() async {
    if (_fromCtrl.text.trim().isEmpty) {
      _showGpsDialog();
      return;
    }
    final blocked = await context.read<LocalTaxiController>().checkGhostBlock();
    if (!mounted) return;
    if (blocked != null) {
      _snack(blocked);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchingScreen(
          from: _fromCtrl.text.trim(),
          to: _toCtrl.text.trim(),
          // Канонизaция: маҳaллий такси трип/драйвер ҳужжатидa `taxiType='local'`.
          // Driver app тинглaши учун муҳим эмас (targetDriverId фильтрлaнaди),
          // лекин админ ва аналитикa бўйичa мaшинни ажрaтиш зaрур.
          taxiType: 'local',
        ),
      ),
    );
  }

  void _showGpsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('📍 Жойлашувни аниқланг'),
        content: const Text(
            '"Қаердан" майдони бўш.\nGPS орқали жойлашувингизни аниқланг.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Орқага')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _onGpsTap().then((_) {
                if (_fromCtrl.text.isNotEmpty) _onSearch();
              });
            },
            icon: const Icon(Icons.gps_fixed),
            label: const Text('GPS'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ─── Saved places ─────────────────────────────────────────────────

  Future<void> _onAddPlace() async {
    final addr = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => const MapPickerScreen(title: 'Янги манзил')),
    );
    if (addr == null || !mounted) return;
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Манзил номи'),
        content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Уй, Иш, Дўкон...', border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Бекор')),
          ElevatedButton(
            onPressed: () {
              final t = nameCtrl.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(context, t);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white),
            child: const Text('Сақлаш'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await context
        .read<LocalTaxiController>()
        .addSavedPlace(SavedPlace(name: name, address: addr));
  }

  Future<void> _onDeletePlace(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('"$name" ўчириш'),
        content: const Text('Ушбу манзилни ўчиришни истайсизми?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<LocalTaxiController>().removeSavedPlaceByName(name);
  }

  // ─── Driver app handoff ────────────────────────────────────────────
  //
  // Маҳаллий такси режимини алоҳида `master_taxi_driver` иловаси орқaли
  // юритиш — пассажир ва ҳайдовчи приложенияларининг **интеграцияси**:
  //
  //   1. Профил тўлдирилганлигини текширамиз (`user_phone` 9+ рақам).
  //   2. SharedPreferences'дан мавжуд авто маълумотларини ўқиймиз.
  //   3. Авто маълумотлари тўлиқ эмас бўлса — `_DriverOnboardingDialog`'ни
  //      очамиз ва фойдаланувчидан **русум / ранг / рақам**ни сўраймиз.
  //      Сақласа — SharedPreferences + Firestore'нинг `drivers/{uid}` ҳужжатига
  //      `merge:true` билан ёзамиз (admin web модератор учун).
  //   4. Driver app **ўрнатилганми** текширамиз —
  //      [DriverAppLauncher.isInstalled].
  //        - **Ҳа** → deep link билан очамиз: `mastertaxidriver://onboard?...`.
  //          Driver app параметрларни ўқиб: `drivers/{uid}` Firestore'да бўлсa
  //          auto-login → home; бўлмаса pre-filled register screen.
  //        - **Йўқ** → `showInstallDriverAppDialog` орқaли APK юклaш диалоги.
  //          Юклaш тугмасини боссa — Firebase Hosting'даги APK URL очилaди.
  //   5. "Бекор қилиш" → ҳеч нима бўлмaйди.
  Future<void> _onDriverTap() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);

    if (!mounted) return;
    if (uid.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: const Text(
            'Аввал профилда телефон рақамингизни тўлдиринг'),
      ));
      return;
    }

    var carModel = prefs.getString('car_model') ?? '';
    var carColor = prefs.getString('car_color') ?? '';
    var carPlate = prefs.getString('car_plate') ?? '';

    // Авто маълумотлари тўлиқ эмас бўлса — диалог.
    final hasCarInfo = carModel.isNotEmpty && carPlate.isNotEmpty;
    if (!hasCarInfo) {
      final result = await showDriverAppPromoDialog(
        context,
        initialModel: carModel,
        initialColor: carColor,
        initialPlate: carPlate,
      );
      if (result == null) return; // Бекор қилинди
      carModel = result.model;
      carColor = result.color;
      carPlate = result.plate;

      // Локал кэш — кейинги сафар диалог чиқмаслиги учун.
      await prefs.setString('car_model', carModel);
      await prefs.setString('car_color', carColor);
      await prefs.setString('car_plate', carPlate);
      // Firestore'га ёзиш — driverApprovalMode'га қараб auto ёки manual.
      final name = prefs.getString('user_name') ?? '';
      try {
        if (!mounted) return;
        final driverRepo = context.read<DriverRepository>();
        final car = '$carModel${carColor.isEmpty ? '' : ' · $carColor'}';
        final mode = await driverRepo.getDriverApprovalMode();
        if (!mounted) return;
        if (mode == 'manual') {
          await driverRepo.submitDriverRequest(
            uid: uid,
            name: name,
            phone: phone,
            car: car,
            plate: carPlate,
            taxiType: 'local',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: const Text(
              'Ҳайдовчи аризангиз админ тасдиғига юборилди.',
            ),
          ));
          return;
        }

        await prefs.setString('user_role', 'driver');
        await driverRepo.approveDriverAutomatically(
          uid: uid,
          name: name,
          phone: phone,
          car: car,
          plate: carPlate,
          taxiType: 'local',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'Табриклаймиз, ҳайдовчи режими фаоллашди.',
          ),
        ));
      } catch (_) {
        // Интернет йўқлиги — driver app keyinroq Firestore'дан ўқийди ёки
        // ўз register screen'идан тўлдирилaди. Оқим узилмaйди.
      }
    }

    // Авто маълумотлари аввалдан бор, лекин user_role ҳали driver бўлмаса
    // approval mode'ни шу ерда ҳам текширамиз.
    if ((prefs.getString('user_role') ?? '') != 'driver') {
      final name = prefs.getString('user_name') ?? '';
      final car = '$carModel${carColor.isEmpty ? '' : ' · $carColor'}';
      try {
        if (!mounted) return;
        final driverRepo = context.read<DriverRepository>();
        final mode = await driverRepo.getDriverApprovalMode();
        if (!mounted) return;
        if (mode == 'manual') {
          await driverRepo.submitDriverRequest(
            uid: uid,
            name: name,
            phone: phone,
            car: car,
            plate: carPlate,
            taxiType: 'local',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: const Text(
              'Ҳайдовчи аризангиз админ тасдиғига юборилди.',
            ),
          ));
          return;
        }

        await prefs.setString('user_role', 'driver');
        await driverRepo.approveDriverAutomatically(
          uid: uid,
          name: name,
          phone: phone,
          car: car,
          plate: carPlate,
          taxiType: 'local',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'Табриклаймиз, ҳайдовчи режими фаоллашди.',
          ),
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text('Ҳайдовчи режимига ўтишда хатолик: $e'),
        ));
        return;
      }
    }

    // ─── Driver app launch ─────────────────────────────────────────
    // Vebda deep link ishlamaydi — haydovchi ilovasi faqat mobilda
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: const Text(
            '🚗 Ҳайдовчи режими фақат мобил иловада. Телефонга юклаб олинг.'),
      ));
      return;
    }
    const launcher = DriverAppLauncher();
    final installed = await launcher.isInstalled();
    if (!mounted) return;

    if (installed) {
      final name = prefs.getString('user_name') ?? '';
      final ok = await launcher.launchOnboard(
        phone: phone,
        name: name,
        model: carModel,
        color: carColor,
        plate: carPlate,
        taxiType: 'local',
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
              'Ҳайдовчи иловасини очиб бўлмади. Қайтa уриниб кўринг.'),
        ));
      }
      return;
    }

    // Ўрнатилмаган — APK юклаш диалоги.
    final wantsDownload = await showInstallDriverAppDialog(context);
    if (!mounted || wantsDownload != true) return;
    final downloaded = await launcher.openApkDownload();
    if (!mounted) return;
    if (!downloaded) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: const Text(
            'Браузер очилмади — ҳавола нусхаланди, ёпиб қўлда очинг'),
      ));
    }
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<LocalTaxiController>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(loc.translate('local_taxi')),
        backgroundColor: _heroStart,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _DriverButton(onTap: _onDriverTap),
        ],
      ),
      body: Column(
        children: [
          _HeroCard(
            fromCtrl: _fromCtrl,
            toCtrl: _toCtrl,
            fromFocus: _fromFocus,
            toFocus: _toFocus,
            fromHint: loc.translate('from'),
            toHint: loc.translate('to_optional'),
            mapTooltip: loc.translate('pick_on_map'),
            isGpsLoading: c.isGpsLoading,
            fromSuggestions: _fromSug,
            toSuggestions: _toSug,
            onFromChanged: _onFromChanged,
            onToChanged: _onToChanged,
            onGpsTap: _onGpsTap,
            onMapTap: () => _pickOnMap(isFrom: false),
            onSwap: () {
              final tmp = _fromCtrl.text;
              _fromCtrl.text = _toCtrl.text;
              _toCtrl.text = tmp;
              setState(() {});
            },
            onPickFromSug: (v) {
              _fromCtrl.text = v;
              setState(() => _fromSug = const []);
            },
            onPickToSug: (v) {
              _toCtrl.text = v;
              setState(() => _toSug = const []);
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SavedPlacesSection(
                      places: c.savedPlaces,
                      addLabel: loc.translate('add'),
                      sectionLabel: loc.translate('saved_places'),
                      onAdd: _onAddPlace,
                      onPick: (p) {
                        setState(() => _fromCtrl.text = p.address);
                      },
                      onLongPress: _onDeletePlace,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [_heroStart, _heroEnd]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                  color: _heroStart.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))
                            ],
                          ),
                          child: InkWell(
                            onTap: _onSearch,
                            borderRadius: BorderRadius.circular(14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search,
                                    size: 22, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(loc.translate('search_driver'),
                                    style: const TextStyle(
                                        fontSize: AppText.bodyLarge,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helpers / inline widgets
// ─────────────────────────────────────────────────────────────────────

class _DriverButton extends StatelessWidget {
  const _DriverButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Ҳайдовчи',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF57F17))),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.fromCtrl,
    required this.toCtrl,
    required this.fromFocus,
    required this.toFocus,
    required this.fromHint,
    required this.toHint,
    required this.mapTooltip,
    required this.isGpsLoading,
    required this.fromSuggestions,
    required this.toSuggestions,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onGpsTap,
    required this.onMapTap,
    required this.onSwap,
    required this.onPickFromSug,
    required this.onPickToSug,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final FocusNode fromFocus;
  final FocusNode toFocus;
  final String fromHint;
  final String toHint;
  final String mapTooltip;
  final bool isGpsLoading;
  final List<String> fromSuggestions;
  final List<String> toSuggestions;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final VoidCallback onGpsTap;
  final VoidCallback onMapTap;
  final VoidCallback onSwap;
  final ValueChanged<String> onPickFromSug;
  final ValueChanged<String> onPickToSug;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF57F17), Color(0xFFFF8F00), Color(0xFFFF8F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(children: [
        _addressField(
          ctrl: fromCtrl,
          focus: fromFocus,
          hint: fromHint,
          icon: Icons.circle,
          iconColor: Colors.greenAccent,
          onChange: onFromChanged,
          trailing: isGpsLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.gps_fixed,
                      color: Colors.greenAccent, size: 20),
                  onPressed: onGpsTap,
                  tooltip: 'GPS',
                ),
        ),
        if (fromSuggestions.isNotEmpty)
          _suggestList(fromSuggestions, onPickFromSug),
        const SizedBox(height: 8),
        Row(children: [
          const SizedBox(width: 12),
          Container(width: 2, height: 12, color: Colors.white24),
          const Spacer(),
          GestureDetector(
            onTap: onSwap,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8)),
              child:
                  const Icon(Icons.swap_vert, color: Colors.white, size: 18),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _addressField(
          ctrl: toCtrl,
          focus: toFocus,
          hint: toHint,
          icon: Icons.location_on,
          iconColor: Colors.redAccent,
          onChange: onToChanged,
          trailing: IconButton(
            icon: const Icon(Icons.map_outlined,
                color: Colors.white70, size: 20),
            onPressed: onMapTap,
            tooltip: mapTooltip,
          ),
        ),
        if (toSuggestions.isNotEmpty) _suggestList(toSuggestions, onPickToSug),
      ]),
    );
  }

  Widget _addressField({
    required TextEditingController ctrl,
    required FocusNode focus,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<String> onChange,
    required Widget trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        Icon(icon, size: 10, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            onChanged: onChange,
            style: const TextStyle(
                fontSize: AppText.bodyLarge,
                color: Colors.white,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: AppText.bodyMedium),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        trailing,
      ]),
    );
  }

  Widget _suggestList(List<String> list, ValueChanged<String> onPick) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => ListTile(
          dense: true,
          leading: const Icon(Icons.location_on, size: 16, color: Colors.grey),
          title: Text(list[i],
              style: const TextStyle(fontSize: AppText.bodyMedium)),
          onTap: () => onPick(list[i]),
        ),
      ),
    );
  }
}

class _SavedPlacesSection extends StatelessWidget {
  const _SavedPlacesSection({
    required this.places,
    required this.sectionLabel,
    required this.addLabel,
    required this.onAdd,
    required this.onPick,
    required this.onLongPress,
  });

  final List<SavedPlace> places;
  final String sectionLabel;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<SavedPlace> onPick;
  final ValueChanged<String> onLongPress;

  static const _green = Color(0xFF2E7D32);

  IconData _iconFor(String name) {
    final l = name.toLowerCase();
    if (l.contains('уй')) return Icons.home;
    if (l.contains('иш')) return Icons.work;
    if (l.contains('дўкон') || l.contains('бозор')) return Icons.store;
    if (l.contains('мактаб')) return Icons.school;
    if (l.contains('касалхона') || l.contains('шифо')) {
      return Icons.local_hospital;
    }
    return Icons.place;
  }

  Color _colorFor(String name) {
    final l = name.toLowerCase();
    if (l.contains('уй')) return Colors.blue;
    if (l.contains('иш')) return Colors.orange;
    if (l.contains('дўкон') || l.contains('бозор')) return Colors.purple;
    if (l.contains('мактаб')) return Colors.red;
    if (l.contains('касалхона')) return Colors.teal;
    return Colors.grey.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.bookmark, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(sectionLabel,
            style: TextStyle(
                fontSize: AppText.bodySmall,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500)),
        const Spacer(),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _green.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add, size: 12, color: Color(0xFF2E7D32)),
              const SizedBox(width: 2),
              Text(addLabel,
                  style: const TextStyle(
                      fontSize: AppText.labelSmall,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (places.isEmpty)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(sectionLabel,
                style: TextStyle(
                    fontSize: AppText.bodySmall, color: Colors.grey.shade500)),
          ]),
        )
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: places
              .map((p) => GestureDetector(
                    onTap: () => onPick(p),
                    onLongPress: () => onLongPress(p.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4)
                        ],
                      ),
                      child:
                          Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_iconFor(p.name),
                            size: 13, color: _colorFor(p.name)),
                        const SizedBox(width: 4),
                        Text(p.name,
                            style: const TextStyle(
                                fontSize: AppText.labelSmall,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ))
              .toList(),
        ),
    ]);
  }
}
