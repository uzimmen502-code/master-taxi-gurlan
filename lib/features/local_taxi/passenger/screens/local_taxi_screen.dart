import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/saved_place.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../utils/gurlan_places.dart';
import '../../../map_picker/screens/map_picker_screen.dart';
import '../controllers/local_taxi_controller.dart';
import '../../../driver_home/screens/driver_home_screen.dart';
import '../../../../shared/navigation/ensure_car_info_via_profile.dart';
import '../../../../shared/widgets/driver_application_feedback.dart';
import 'local_taxi_active_trip_screen.dart';
import 'searching_screen.dart';

class LocalTaxiScreen extends StatelessWidget {
  const LocalTaxiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final c = LocalTaxiController(
          locationService: ctx.read<LocationService>(),
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
  static const _heroStart = AppColors.primaryMid;
  static const _heroEnd = AppColors.primary;
  static const _green = AppColors.primaryDark;

  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();

  List<String> _fromSug = const [];
  List<String> _toSug = const [];
  Timer? _debounce;

  bool _bootstrapped = false;
  bool _isSearching = false;
  bool _isSubmitting = false;
  String? _estimatedPriceText;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onGpsTap();
      _tryResumeActiveTrip();
      _loadEstimatedPrice();
    });
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
      _snack(context.trMsg(info));
      c.clearMessages();
    } else if (err != null) {
      _snack(context.trMsg(err));
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

  void _snack(String msg, [Color? backgroundColor]) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: backgroundColor,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]} ',
        );
  }

  Future<void> _loadEstimatedPrice() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('prices')
          .get();
      final base =
          (snap.data()?['local_base'] as num?)?.toInt() ?? 5000;
      final perKm =
          (snap.data()?['local_per_km'] as num?)?.toInt() ?? 1500;
      final est = base + (perKm * 3);
      if (mounted) {
        setState(() {
          _estimatedPriceText = '${_formatPrice(est)}+ сўм';
        });
      }
    } catch (_) {}
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
          builder: (_) => MapPickerScreen(title: context.tr('pick_location'))),
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

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _latestActiveLocalTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    if (phone.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('trips')
          .where('userPhone', isEqualTo: phone)
          .where('taxiType', isEqualTo: 'local')
          .where('status', whereIn: ['searching', 'accepted'])
          .get();
      if (snap.docs.isEmpty) return null;
      final docs = snap.docs.toList();
      docs.sort((a, b) {
        final ta = a.data()['createdAt'] as Timestamp?;
        final tb = b.data()['createdAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return docs.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasActiveTripSearch() async =>
      (await _latestActiveLocalTrip()) != null;

  Future<void> _tryResumeActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final resumeId = prefs.getString('resume_local_trip_id') ?? '';
    if (resumeId.isNotEmpty) {
      await prefs.remove('resume_local_trip_id');
      try {
        final doc = await FirebaseFirestore.instance
            .collection('trips')
            .doc(resumeId)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data() ?? {};
          final status = data['status'] as String? ?? '';
          if (status == 'accepted') {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LocalTaxiActiveTripScreen(tripId: doc.id),
              ),
            );
            return;
          }
          if (status == 'searching') {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchingScreen(
                  from: (data['fromAddr'] ?? '') as String,
                  to: (data['toAddr'] ?? '') as String,
                  taxiType: 'local',
                  tripId: doc.id,
                ),
              ),
            );
            return;
          }
        }
      } catch (_) {}
    }

    final trip = await _latestActiveLocalTrip();
    if (trip == null || !mounted) return;
    final data = trip.data();
    final status = data['status'] as String? ?? '';
    if (status == 'accepted') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocalTaxiActiveTripScreen(tripId: trip.id),
        ),
      );
    } else if (status == 'searching') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchingScreen(
            from: (data['fromAddr'] ?? '') as String,
            to: (data['toAddr'] ?? '') as String,
            taxiType: 'local',
            tripId: trip.id,
          ),
        ),
      );
    }
  }

  Future<void> _onSearch() async {
    if (_isSearching) return;
    setState(() => _isSearching = true);
    try {
      if (_fromCtrl.text.trim().isEmpty) {
        _showGpsDialog();
        return;
      }
      if (await _hasActiveTripSearch()) {
        if (!mounted) return;
        _snack(context.tr('local_trip_already_active'));
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchingScreen(
            from: _fromCtrl.text.trim(),
            to: _toCtrl.text.trim(),
            taxiType: 'local',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _showGpsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('location_detect_title')),
        content: Text(context.tr('location_detect_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('back_short'))),
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
          builder: (_) => MapPickerScreen(title: context.tr('new_location_title'))),
    );
    if (addr == null || !mounted) return;
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('location_name_title')),
        content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
                hintText: context.tr('location_name_hint'),
                border: const OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel'))),
          ElevatedButton(
            onPressed: () {
              final t = nameCtrl.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(context, t);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white),
            child: Text(context.tr('save')),
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
        title: Text(context.tr('delete_location_title').replaceAll('{name}', name)),
        content: Text(context.tr('delete_location_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('no'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<LocalTaxiController>().removeSavedPlaceByName(name);
  }

  // ─── Ҳайдовчи режими (ИЧКИ панель) ─────────────────────────────────
  //
  // Маҳаллий такси ҳайдовчи режими шу илованинг ўзида юритилади (ташқи
  // `master_taxi_driver` иловаси кераксиз):
  //
  //   1. Профил тўлдирилганлигини текширамиз (`user_phone` 9+ рақам).
  //   2. Авто маълумотларини профилдан оламиз (модель / ранг / рақам).
  //   3. Ҳайдовчи тасдиқланмаган бўлса — ариза юборамиз / авто-тасдиқ.
  //   4. Тасдиқлангандан сўнг ички `DriverHomeScreen`'ни очамиз
  //      (веб — қўлланмайди, фақат мобил).
  Future<void> _onDriverTap() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();
    try {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);

    if (!mounted) return;
    if (uid.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(context.tr('fill_phone_in_profile')),
      ));
      return;
    }

    if (uid.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(context.tr('fill_phone_in_profile')),
      ));
      return;
    }

    if (!await ensureCarInfoViaProfile(context)) return;
    if (!mounted) return;

    final carUid = canonicalPhoneId(uid);
    final carFromProfile = await UserRepository().getCarInfo(carUid);
    if (carFromProfile == null || !mounted) return;
    final carModel = carFromProfile['carModel'] ?? '';
    final carColor = carFromProfile['carColor'] ?? '';
    final carPlate = carFromProfile['carPlate'] ?? '';
    await prefs.setString('car_model', carModel);
    await prefs.setString('car_color', carColor);
    await prefs.setString('car_plate', carPlate);
    final carSeats = int.tryParse(carFromProfile['carSeats'] ?? '') ?? 0;
    if (carSeats > 0) await prefs.setInt('car_seats', carSeats);

    final driverRepo = context.read<DriverRepository>();
    final approved = await driverRepo.isApprovedForTaxi(
      uid: uid,
      taxiType: 'local',
    );
    if (!mounted) return;

    if ((prefs.getString('user_role') ?? '') != 'driver') {
      final name = prefs.getString('user_name') ?? '';
      final car = '$carModel${carColor.isEmpty ? '' : ' · $carColor'}';
      try {
        if (!mounted) return;
        if (!approved) {
          final submitResult = await driverRepo.submitDriverApplication(
            uid: uid,
            name: name,
            phone: phone,
            car: car,
            plate: carPlate,
            taxiType: 'local',
          );
          if (!mounted) return;
          if (submitResult.autoApproved) {
            await prefs.setString('user_role', 'driver');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.button,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              content: Text(
                context.tr('driver_mode_activated'),
              ),
            ));
          } else {
            await showDriverApplicationPendingFeedback(
              context,
              result: submitResult,
              snackColor: Colors.orange.shade700,
            );
          }
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
          backgroundColor: AppColors.button,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            context.tr('driver_mode_activated'),
          ),
        ));
      } catch (e) {
        rethrow;
      }
    }

    // ─── Ҳайдовчи панели (ИЧКИ) ─────────────────────────────────────
    // Веб GPS/реал-вақтни тўлиқ қўлламайди — фақат мобилда.
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          context.tr('driver_mobile_only')),
      ));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('invalid_phone_format')
          ? context.tr('invalid_phone_format')
          : context.tr('driver_mode_error');
      _snack(msg, Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<LocalTaxiController>();

    return Scaffold(
      backgroundColor: AppColors.moduleBg,
      appBar: AppBar(
        title: Text(loc.translate('local_taxi')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _DriverButton(
            onTap: _isSubmitting ? null : _onDriverTap,
            loading: _isSubmitting,
          ),
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
                    if (_estimatedPriceText != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${context.tr('estimated_price')}: '
                          '$_estimatedPriceText',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
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
  const _DriverButton({this.onTap, this.loading = false});
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: loading ? 0.6 : 1,
        child: GestureDetector(
          onTap: loading ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryMid,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(loading ? 'Юкланмоқда...' : context.tr('become_driver'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryMid)),
              ],
            ),
          ),
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
          colors: [AppColors.primaryMid, AppColors.primary, AppColors.primary],
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
          iconColor: AppColors.primaryMid,
          onChange: onFromChanged,
          trailing: isGpsLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.gps_fixed,
                      color: AppColors.primaryMid, size: 20),
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
              child: const Icon(Icons.swap_vert, color: Colors.white, size: 18),
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
            icon:
                const Icon(Icons.map_outlined, color: Colors.white70, size: 20),
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

  static const _green = AppColors.primaryDark;

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
              const Icon(Icons.add, size: 12, color: AppColors.primary),
              const SizedBox(width: 2),
              Text(addLabel,
                  style: const TextStyle(
                      fontSize: AppText.labelSmall,
                      color: AppColors.primary,
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
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
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
