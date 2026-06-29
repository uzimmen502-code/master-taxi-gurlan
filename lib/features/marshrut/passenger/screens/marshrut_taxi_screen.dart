import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/active_trip.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../repositories/queue_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../shared/navigation/ensure_car_info_via_profile.dart';
import '../../../../shared/widgets/driver_route_application_dialog.dart';
import '../../../../shared/widgets/driver_application_feedback.dart';
import '../../driver/screens/driver_panel_marshrut_screen.dart';
import '../../driver/screens/driver_register_marshrut_screen.dart';
import '../../../../services/location_service.dart';
import '../../../../services/user_role_sync.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/marshrut_search_filter_stats.dart';
import '../controllers/marshrut_search_controller.dart';
import '../services/marshrut_mfy_history.dart';
import '../widgets/mfy_dropdown.dart';
import '../widgets/schedule_card.dart';
import 'marshrut_waiting_screen.dart';

/// Yo'lovchi marshrut taksi qidirayotgan ekran.
///
/// Ko'rsatadi: MFY tanlash, qidiruv, natijalar (GPS faqat masofa filtri uchun, banner yo'q).
/// natijalar ro'yxati va "ЧАҚИРИШ" tugmasi marshrut waiting flow'iga ulaydi.
class MarshrutTaxiScreen extends StatelessWidget {
  const MarshrutTaxiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MarshrutSearchController>(
      create: (ctx) {
        final c = MarshrutSearchController(
          schedulesRepo: ctx.read<SchedulesRepository>(),
          queueRepo: ctx.read<QueueRepository>(),
          locationService: ctx.read<LocationService>(),
        );
        c.initBlockWatch();
        return c;
      },
      child: const _MarshrutTaxiView(),
    );
  }
}

class _MarshrutTaxiView extends StatefulWidget {
  const _MarshrutTaxiView();

  @override
  State<_MarshrutTaxiView> createState() => _MarshrutTaxiViewState();
}

class _MarshrutTaxiViewState extends State<_MarshrutTaxiView> {
  static const Color _accent = AppColors.primary;

  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  bool _showFromDropdown = false;
  bool _showToDropdown = false;
  Timer? _debounce;
  String? _lastErrorShown;
  bool _directionChanged = false;
  bool _isSubmitting = false;
  List<String> _recentFrom = const [];
  List<String> _recentTo = const [];
  StreamSubscription<ActiveTrip>? _acceptedTripSub;
  bool _rerouteInProgress = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _approvalSub;
  bool _isListening = false;
  int? _pricePerSeat;
  MarshrutSearchController? _searchCtrl;
  static const _prefsSystemCallInfoShown = 'marshrut_system_call_info_shown';

  @override
  void initState() {
    super.initState();
    _searchCtrl = context.read<MarshrutSearchController>();
    _searchCtrl!.addListener(_onSearchBlockUpdate);
    _loadMfyHistory();
  }

  Future<void> _loadMfyHistory() async {
    final from = await MarshrutMfyHistory.loadFrom();
    final to = await MarshrutMfyHistory.loadTo();
    if (!mounted) return;
    setState(() {
      _recentFrom = from;
      _recentTo = to;
    });
  }

  Future<void> _persistMfyHistory(MarshrutSearchController c) async {
    if (c.fromMfy.isNotEmpty) {
      await MarshrutMfyHistory.addFrom(c.fromMfy);
    }
    if (c.toMfy.isNotEmpty) {
      await MarshrutMfyHistory.addTo(c.toMfy);
    }
    await _loadMfyHistory();
  }

  void _onSearchBlockUpdate() {
    if (!mounted) return;
    if (_searchCtrl?.consumeBlockClearedSnack() ?? false) {
      _snack(context.tr('marshrut_block_cleared'));
    }
  }

  void _refreshPrice(MarshrutSearchController c) {
    // Yo'nalish narxi — haydovchi belgilagan flat narx (schedule.price).
    // Navbat tartibidagi birinchi mos reysning narxini ko'rsatamiz.
    int? price;
    for (final r in c.results) {
      final p = r.schedule.price;
      if (p > 0) {
        price = p;
        break;
      }
    }
    if (_pricePerSeat != price && mounted) {
      setState(() => _pricePerSeat = price);
    }
  }

  @override
  void dispose() {
    _searchCtrl?.removeListener(_onSearchBlockUpdate);
    _approvalSub?.cancel();
    _debounce?.cancel();
    _acceptedTripSub?.cancel();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _pushMarshrutDriverPanel(String userId) async {
    final profile =
        await context.read<MarshrutDriverRepository>().getProfile(userId);
    if (!mounted) return;

    if (profile != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPanelMarshrutScreen(
            carModel: profile.carModel,
            plate: profile.plate,
            seats: profile.seats,
            stops: profile.stops,
            driverName: profile.driverName,
            driverPhone: profile.driverPhone,
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

  Future<void> _onDriverApproved(String uid) async {
    await UserRoleSync.forceSyncDriver();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('driver_mode_activated')),
      backgroundColor: AppColors.button,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await _pushMarshrutDriverPanel(canonicalPhoneId(uid));
  }

  void _startApprovalListener(String uid) {
    if (_isListening) return;
    _isListening = true;
    final docId = canonicalPhoneId(uid);
    _approvalSub?.cancel();
    _approvalSub = FirebaseFirestore.instance
        .collection('drivers')
        .doc(docId)
        .snapshots()
        .listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      final isApproved =
          data['approved'] == true || data['approvalStatus'] == 'approved';
      if (isApproved && mounted) {
        _approvalSub?.cancel();
        _isListening = false;
        await _onDriverApproved(docId);
      }
    });
  }

  void _startAcceptedTripMonitor(ActiveTrip trip) {
    _acceptedTripSub?.cancel();
    final rides = context.read<RidesRepository>();
    _acceptedTripSub = rides.watch(trip.id).listen((t) {
      if (!mounted || _rerouteInProgress) return;
      if (t.isDriverNoRoomCancel) {
        _acceptedTripSub?.cancel();
        unawaited(_onDriverNoRoomCancel(t));
      }
    });
  }

  Future<void> _onDriverNoRoomCancel(ActiveTrip cancelled) async {
    if (_rerouteInProgress || !mounted) return;
    _rerouteInProgress = true;
    final c = context.read<MarshrutSearchController>();
    final excludeId = cancelled.driverId.isNotEmpty
        ? cancelled.driverId
        : cancelled.targetDriverId;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('no_seat_title')),
        content: Text(context.tr('no_seat_body')),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.button,
              foregroundColor: Colors.white,
            ),
            child: Text(context.tr('continue')),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) {
      _rerouteInProgress = false;
      return;
    }

    await c.search();
    if (!mounted) {
      _rerouteInProgress = false;
      return;
    }
    final prep = await c.prepareSystemQueueCall(
      excludeDriverIds: {excludeId},
      skipResultsGuard: true,
    );
    if (!mounted) {
      _rerouteInProgress = false;
      return;
    }
    if (!prep.isReady) {
      _snack(context.trMsg(prep.error ?? 'no_other_driver_now'));
      _rerouteInProgress = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final profileAddr = prefs.getString('user_address') ?? '';
    final pickupAddr = profileAddr.trim().isNotEmpty
        ? '${c.fromMfy.isNotEmpty ? "$profileAddr (${c.fromMfy})" : profileAddr}'
        : c.fromMfy;

    final accepted = await Navigator.push<ActiveTrip?>(
      context,
      MaterialPageRoute(
        builder: (_) => MarshrutWaitingScreen(
          pickupMfy: c.fromMfy,
          pickupAddr: pickupAddr,
          dropoffMfy: c.toMfy,
          drivers: prep.drivers,
          userLat: c.userLat,
          userLng: c.userLng,
        ),
      ),
    );
    _rerouteInProgress = false;
    if (!mounted) return;
    if (accepted != null) {
      _startAcceptedTripMonitor(accepted);
      _snack(context
          .tr('marshrut_accepted')
          .replaceAll('{name}', accepted.driverName));
    } else {
      await c.search();
      if (mounted) setState(() => _directionChanged = true);
    }
  }

  void _onFromQueryChanged(String q) {
    setState(() => _showFromDropdown = q.length >= 2 || _recentFrom.isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(
          () => _showFromDropdown = q.length >= 2 || _recentFrom.isNotEmpty);
    });
  }

  void _onToQueryChanged(String q) {
    setState(() => _showToDropdown = q.length >= 2 || _recentTo.isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _showToDropdown = q.length >= 2 || _recentTo.isNotEmpty);
    });
  }

  void _swapDirection(MarshrutSearchController c) {
    final fromVal =
        c.fromMfy.isNotEmpty ? c.fromMfy : _fromCtrl.text.trim();
    final toVal = c.toMfy.isNotEmpty ? c.toMfy : _toCtrl.text.trim();
    c.setFromMfy(toVal);
    c.setToMfy(fromVal);
    _fromCtrl.text = toVal;
    _toCtrl.text = fromVal;
    setState(() {
      _showFromDropdown = false;
      _showToDropdown = false;
      if (c.searched && c.results.isNotEmpty) {
        _directionChanged = true;
      }
    });
  }

  Future<void> _openDriverPanel() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();
    try {
      await _runOpenDriverPanel();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _runOpenDriverPanel() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final userId = phoneDigits(phone);
    if (!mounted) return;

    if (userId.isEmpty) {
      _snack(context.tr('fill_phone_in_profile'));
      return;
    }

    if (!await ensureCarInfoViaProfile(context)) return;
    if (!mounted) return;

    final driverRepo = context.read<DriverRepository>();
    final approved = await driverRepo.isApprovedForTaxi(
      uid: userId,
      taxiType: 'marshrut',
    );
    if (!mounted) return;

    if (!approved) {
      final route = await showDriverRouteApplicationDialog(
        context,
        taxiType: 'marshrut',
      );
      if (route == null || !mounted) return;

      final carUid = canonicalPhoneId(userId);
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

      final name = prefs.getString('user_name') ?? '';
      final car =
          '$carModel${carColor.isEmpty ? '' : ' · $carColor'}';
      try {
        final submitResult = await driverRepo.submitDriverApplication(
          uid: userId,
          name: name,
          phone: phone,
          car: car,
          plate: carPlate,
          taxiType: 'marshrut',
          routeFrom: route.from,
          routeTo: route.to,
          routeStops: route.midStops,
        );
        if (!mounted) return;
        if (submitResult.autoApproved) {
          await UserRoleSync.forceSyncDriver();
          _snack(context.tr('marshrut_driver_mode_activated'));
          await _pushMarshrutDriverPanel(userId);
        } else {
          await showDriverApplicationPendingFeedback(
            context,
            result: submitResult,
            resentMessageKey: 'marshrut_driver_request_sent',
            snackColor: Colors.orange.shade700,
          );
          _startApprovalListener(userId);
        }
      } on FirebaseFunctionsException catch (e) {
        if (!mounted) return;
        if (e.code == 'unauthenticated') {
          _snack(context.tr('auth_required_to_order'), Colors.orange);
        } else {
          _snack(
            '${context.tr('driver_mode_error')}: ${e.message}',
            Colors.red,
          );
        }
      } catch (e) {
        if (!mounted) return;
        _snack(context.tr('driver_mode_error'), Colors.red);
      }
      return;
    }

    await _pushMarshrutDriverPanel(userId);
  }

  Future<bool> _maybeShowSystemCallInfoDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsSystemCallInfoShown) == true) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('marshrut_call_system')),
        content: Text(context.tr('marshrut_call_system_info_dialog')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('ok')),
          ),
        ],
      ),
    );
    await prefs.setBool(_prefsSystemCallInfoShown, true);
    return mounted;
  }

  Future<void> _onCall() async {
    final c = context.read<MarshrutSearchController>();
    if (!await _maybeShowSystemCallInfoDialog()) return;
    if (!mounted) return;
    if (c.isBlockActive) {
      if (!mounted) return;
      final remaining = c.blockMinutesRemaining ?? 1;
      _snack(context.trMsg('retry_after_minutes|$remaining'));
      return;
    }
    final prep = await c.prepareSystemQueueCall();
    if (!mounted) return;
    if (!prep.isReady) {
      if (prep.error == 'no_queue_driver') {
        _snack(context.tr('marshrut_no_driver_now'));
      } else {
        _snack(context.trMsg(prep.error!));
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final profileAddr = prefs.getString('user_address') ?? '';
    final pickupAddr = profileAddr.trim().isNotEmpty
        ? '${c.fromMfy.isNotEmpty ? "$profileAddr (${c.fromMfy})" : profileAddr}'
        : c.fromMfy;

    final accepted = await Navigator.push<ActiveTrip?>(
      context,
      MaterialPageRoute(
        builder: (_) => MarshrutWaitingScreen(
          pickupMfy: c.fromMfy,
          pickupAddr: pickupAddr,
          dropoffMfy: c.toMfy,
          drivers: prep.drivers,
          userLat: c.userLat,
          userLng: c.userLng,
        ),
      ),
    );
    if (!mounted) return;
    if (accepted != null) {
      _startAcceptedTripMonitor(accepted);
      _snack(context
          .tr('marshrut_accepted')
          .replaceAll('{name}', accepted.driverName));
    } else {
      await c.search();
      if (mounted) setState(() => _directionChanged = true);
    }
  }

  void _snack(String msg, [Color? backgroundColor]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: backgroundColor ?? AppColors.button,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MarshrutSearchController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPrice(c));

    if (c.errorMessage != null && c.errorMessage != _lastErrorShown) {
      _lastErrorShown = c.errorMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(context.trMsg(c.errorMessage!));
        c.clearTransient();
        _lastErrorShown = null;
      });
    }

    return Scaffold(
      backgroundColor: AppColors.moduleBg,
      appBar: AppBar(
        title: Text('🚐 ${context.tr('marshrut_taxi')}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Opacity(
              opacity: _isSubmitting ? 0.6 : 1,
              child: GestureDetector(
                onTap: _isSubmitting ? null : _openDriverPanel,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSubmitting) ...[
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                          _isSubmitting
                              ? 'Юкланмоқда...'
                              : context.tr('become_driver'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _showFromDropdown = false;
            _showToDropdown = false;
          });
        },
        child: Column(children: [
          if (c.isBlockActive && c.effectiveCancelCount >= 7)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('marshrut_block_active_banner'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (c.blockMinutesRemaining != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      context
                          .tr('marshrut_block_remaining_time')
                          .replaceAll('{n}', '${c.blockMinutesRemaining}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          _SearchPanel(
            fromCtrl: _fromCtrl,
            toCtrl: _toCtrl,
            fromMfy: c.fromMfy,
            toMfy: c.toMfy,
            recentFrom: _recentFrom,
            recentTo: _recentTo,
            showFromDropdown: _showFromDropdown,
            showToDropdown: _showToDropdown,
            isSearching: c.isSearching,
            onFromQueryChanged: _onFromQueryChanged,
            onToQueryChanged: _onToQueryChanged,
            onFromTap: () => setState(() => _showFromDropdown = true),
            onToTap: () => setState(() => _showToDropdown = true),
            onFromSelected: (v) {
              c.setFromMfy(v);
              _fromCtrl.text = v;
              setState(() => _showFromDropdown = false);
            },
            onToSelected: (v) {
              c.setToMfy(v);
              _toCtrl.text = v;
              setState(() => _showToDropdown = false);
            },
            onSwapDirection: () => _swapDirection(c),
            onSearch: c.isSearching
                ? null
                : () async {
                    setState(() => _directionChanged = false);
                    await c.search();
                    await _persistMfyHistory(c);
                  },
          ),
          Expanded(child: _buildResults(c)),
        ]),
      ),
    );
  }

  Widget _buildResults(MarshrutSearchController c) {
    if (!c.searched) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🚐', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        Text(context.tr('marshrut_select_mfy_and_search'),
            style: TextStyle(
                fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
      ]));
    }
    if (c.results.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('😔', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(context.tr('marshrut_no_drivers_match'),
            style: TextStyle(
                fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            context.tr('marshrut_try_swap_direction'),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        TextButton.icon(
          onPressed: c.isSearching
              ? null
              : () async {
                  final from = c.fromMfy;
                  final to = c.toMfy;
                  c.setFromMfy(to);
                  c.setToMfy(from);
                  _fromCtrl.text = to;
                  _toCtrl.text = from;
                  setState(() => _directionChanged = false);
                  await c.search();
                },
          icon: const Icon(Icons.swap_vert),
          label: Text(context.tr('swap_direction')),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _filterStatsText(context, c.filterStats),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ]));
    }
    return Column(children: [
      if (c.searched && c.results.isNotEmpty && _directionChanged)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.refresh, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('driver_route_may_change'),
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          ]),
        ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🚐 ${c.results.length} ${context.tr('cars_found')}',
                style: const TextStyle(
                    fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
            if (_pricePerSeat != null && _pricePerSeat! > 0) ...[
              const SizedBox(height: 4),
              Text(
                context
                    .tr('marshrut_price_per_seat')
                    .replaceAll('{price}', '$_pricePerSeat'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
            if (c.filterStats.hasHiddenReasons) ...[
              const SizedBox(height: 4),
              Text(
                _filterStatsText(context, c.filterStats),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
      Expanded(
          child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: c.results.length,
        itemBuilder: (_, i) => ScheduleCard(
          result: c.results[i],
          onCall: _onCall,
        ),
      )),
    ]);
  }

  String _filterStatsText(
    BuildContext context,
    MarshrutSearchFilterStats s,
  ) {
    return context.tr('marshrut_search_filter_stats').replaceAll('{total}', '${s.totalActive}').replaceAll('{offline}', '${s.offline}').replaceAll('{full}', '${s.full}').replaceAll('{route}', '${s.routeMismatch}').replaceAll('{eligible}', '${s.notYetEligible}').replaceAll('{far}', '${s.tooFar}');
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.fromCtrl,
    required this.toCtrl,
    required this.fromMfy,
    required this.toMfy,
    required this.recentFrom,
    required this.recentTo,
    required this.showFromDropdown,
    required this.showToDropdown,
    required this.isSearching,
    required this.onFromQueryChanged,
    required this.onToQueryChanged,
    required this.onFromTap,
    required this.onToTap,
    required this.onFromSelected,
    required this.onToSelected,
    required this.onSwapDirection,
    required this.onSearch,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final String fromMfy;
  final String toMfy;
  final List<String> recentFrom;
  final List<String> recentTo;
  final bool showFromDropdown;
  final bool showToDropdown;
  final bool isSearching;
  final ValueChanged<String> onFromQueryChanged;
  final ValueChanged<String> onToQueryChanged;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final ValueChanged<String> onFromSelected;
  final ValueChanged<String> onToSelected;
  final VoidCallback onSwapDirection;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _MarshrutTaxiViewState._accent,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('from'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
          const SizedBox(height: 4),
          MfyDropdown(
            ctrl: fromCtrl,
            hint: context.tr('mfy_select_hint'),
            value: fromMfy,
            show: showFromDropdown,
            icon: Icons.circle_outlined,
            iconColor: AppColors.primaryMid,
            recentPlaces: recentFrom,
            onTap: onFromTap,
            onQueryChanged: onFromQueryChanged,
            onSelected: onFromSelected,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.tr('to'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70)),
                ),
                _SwapDirectionPill(onTap: onSwapDirection),
              ],
            ),
          ),
          const SizedBox(height: 4),
          MfyDropdown(
            ctrl: toCtrl,
            hint: context.tr('mfy_select_hint'),
            value: toMfy,
            show: showToDropdown,
            icon: Icons.location_on,
            iconColor: Colors.redAccent,
            recentPlaces: recentTo,
            onTap: onToTap,
            onQueryChanged: onToQueryChanged,
            onSelected: onToSelected,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: onSearch,
              icon: isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 20),
              label: Text(
                  isSearching
                      ? context.tr('searching')
                      : context.tr('search_driver'),
                  style: const TextStyle(
                      fontSize: AppText.bodyLarge,
                      fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _MarshrutTaxiViewState._accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Qayerdan ↔ Qayerga — gorizontal pill, «Qayerga» qatori markazida.
class _SwapDirectionPill extends StatelessWidget {
  const _SwapDirectionPill({required this.onTap});

  static const Color _swapOrange = Color(0xFFFF8C00);
  static const double _height = 34;
  static const double _minWidth = 72;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _swapOrange,
      elevation: 2,
      shadowColor: _swapOrange.withOpacity(0.4),
      borderRadius: BorderRadius.circular(_height / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_height / 2),
        child: Tooltip(
          message: context.tr('switch_direction'),
          child: const SizedBox(
            height: _height,
            width: _minWidth,
            child: Icon(
              Icons.swap_vert,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
