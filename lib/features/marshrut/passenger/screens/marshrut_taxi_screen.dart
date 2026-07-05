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
import '../models/marshrut_route_pair.dart';
import '../utils/marshrut_popular_routes.dart';
import '../utils/marshrut_filter_hint.dart';
import '../controllers/marshrut_search_controller.dart';
import '../services/marshrut_mfy_history.dart';
import '../services/marshrut_search_reminder_service.dart';
import '../widgets/marshrut_direction_chips.dart';
import '../widgets/marshrut_results_view_toggle.dart';
import '../widgets/marshrut_route_field.dart';
import '../widgets/marshrut_search_map_view.dart';
import '../widgets/mfy_picker_sheet.dart';
import '../widgets/schedule_card.dart';
import '../widgets/schedule_card_skeleton.dart';
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

  Timer? _autoSearchDebounce;
  String? _lastErrorShown;
  bool _directionChanged = false;
  bool _isSubmitting = false;
  List<String> _recentFrom = const [];
  List<String> _recentTo = const [];
  List<MarshrutRoutePair> _recentRoutes = const [];
  MarshrutResultsView _resultsView = MarshrutResultsView.list;
  MarshrutSearchReminder? _pendingReminder;
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
    _loadPendingReminder();
  }

  Future<void> _loadPendingReminder() async {
    final reminder = await MarshrutSearchReminderService.instance.load();
    if (!mounted) return;
    setState(() => _pendingReminder = reminder);
  }

  Future<void> _loadMfyHistory() async {
    final from = await MarshrutMfyHistory.loadFrom();
    final to = await MarshrutMfyHistory.loadTo();
    final routes = await MarshrutMfyHistory.loadRecentRoutes();
    if (!mounted) return;
    setState(() {
      _recentFrom = from;
      _recentTo = to;
      _recentRoutes = routes;
    });
  }

  Future<void> _persistMfyHistory(MarshrutSearchController c) async {
    if (c.fromMfy.isNotEmpty) {
      await MarshrutMfyHistory.addFrom(c.fromMfy);
    }
    if (c.toMfy.isNotEmpty) {
      await MarshrutMfyHistory.addTo(c.toMfy);
    }
    if (c.fromMfy.isNotEmpty && c.toMfy.isNotEmpty) {
      await MarshrutMfyHistory.addRoute(c.fromMfy, c.toMfy);
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
    _autoSearchDebounce?.cancel();
    _acceptedTripSub?.cancel();
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
        ? (c.fromMfy.isNotEmpty ? "$profileAddr (${c.fromMfy})" : profileAddr)
        : c.fromMfy;

    if (!mounted) return;
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

  void _swapDirection(MarshrutSearchController c) {
    final fromVal = c.fromMfy;
    final toVal = c.toMfy;
    c.setFromMfy(toVal);
    c.setToMfy(fromVal);
    setState(() {
      if (c.searched && c.results.isNotEmpty) {
        _directionChanged = true;
      }
    });
    _scheduleAutoSearch(c);
  }

  Future<void> _openFromPicker(MarshrutSearchController c) async {
    final picked = await showMarshrutMfyPickerSheet(
      context,
      title: context.tr('from'),
      recentPlaces: _recentFrom,
      initialQuery: c.fromMfy,
    );
    if (!mounted || picked == null) return;
    c.setFromMfy(picked);
    setState(() {});
    _scheduleAutoSearch(c);
  }

  Future<void> _openToPicker(MarshrutSearchController c) async {
    final picked = await showMarshrutMfyPickerSheet(
      context,
      title: context.tr('to'),
      recentPlaces: _recentTo,
      initialQuery: c.toMfy,
    );
    if (!mounted || picked == null) return;
    c.setToMfy(picked);
    setState(() {});
    _scheduleAutoSearch(c);
  }

  void _applyRoutePair(MarshrutSearchController c, MarshrutRoutePair route) {
    c.setFromMfy(route.from);
    c.setToMfy(route.to);
    setState(() => _directionChanged = false);
    _scheduleAutoSearch(c);
  }

  void _scheduleAutoSearch(MarshrutSearchController c) {
    _autoSearchDebounce?.cancel();
    if (c.fromMfy.isEmpty || c.toMfy.isEmpty || c.isSearching) return;
    if (c.fromMfy == c.toMfy) return;
    _autoSearchDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      final live = context.read<MarshrutSearchController>();
      if (live.fromMfy.isEmpty ||
          live.toMfy.isEmpty ||
          live.isSearching ||
          live.fromMfy == live.toMfy) {
        return;
      }
      setState(() => _directionChanged = false);
      await live.search();
      await _persistMfyHistory(live);
    });
  }

  Future<void> _runSearch(MarshrutSearchController c) async {
    setState(() => _directionChanged = false);
    await c.search();
    await _persistMfyHistory(c);
    if (c.results.isNotEmpty &&
        MarshrutSearchReminderService.instance
            .matchesRoute(_pendingReminder, c.fromMfy, c.toMfy)) {
      await MarshrutSearchReminderService.instance.clear();
      if (mounted) setState(() => _pendingReminder = null);
    }
  }

  Future<void> _scheduleSearchReminder(
    MarshrutSearchController c,
    Duration delay,
  ) async {
    if (c.fromMfy.isEmpty || c.toMfy.isEmpty) return;
    final title = context.tr('marshrut_remind_notification_title');
    final body = context
        .tr('marshrut_remind_notification_body')
        .replaceAll('{from}', c.fromMfy)
        .replaceAll('{to}', c.toMfy);
    await MarshrutSearchReminderService.instance.schedule(
      fromMfy: c.fromMfy,
      toMfy: c.toMfy,
      delay: delay,
      title: title,
      body: body,
    );
    await _loadPendingReminder();
    if (!mounted) return;
    _snack(context.tr('marshrut_remind_scheduled'));
  }

  Future<void> _cancelSearchReminder() async {
    await MarshrutSearchReminderService.instance.clear();
    if (!mounted) return;
    setState(() => _pendingReminder = null);
    _snack(context.tr('marshrut_remind_cancelled'));
  }

  Future<void> _showRemindLaterSheet(MarshrutSearchController c) async {
    final hasActive = MarshrutSearchReminderService.instance
        .matchesRoute(_pendingReminder, c.fromMfy, c.toMfy);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('marshrut_remind_later'),
                style: const TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('marshrut_remind_later_hint'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _scheduleSearchReminder(c, const Duration(minutes: 15));
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(context.tr('marshrut_remind_in_15')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _scheduleSearchReminder(c, const Duration(minutes: 30));
                },
                icon: const Icon(Icons.schedule_outlined),
                label: Text(context.tr('marshrut_remind_in_30')),
              ),
              if (hasActive) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _cancelSearchReminder();
                  },
                  child: Text(context.tr('marshrut_remind_cancel')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _reminderScheduledLabel(MarshrutSearchController c) {
    if (!MarshrutSearchReminderService.instance
        .matchesRoute(_pendingReminder, c.fromMfy, c.toMfy)) {
      return null;
    }
    final at = _pendingReminder!.scheduledAt;
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return context
        .tr('marshrut_remind_scheduled_at')
        .replaceAll('{time}', '$hh:$mm');
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
          if (!mounted) return;
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
        ? (c.fromMfy.isNotEmpty ? "$profileAddr (${c.fromMfy})" : profileAddr)
        : c.fromMfy;

    if (!mounted) return;
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
      body: Column(children: [
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
            fromMfy: c.fromMfy,
            toMfy: c.toMfy,
            recentRoutes: _recentRoutes,
            isSearching: c.isSearching,
            onFromTap: () => _openFromPicker(c),
            onToTap: () => _openToPicker(c),
            onFromClear: () {
              c.setFromMfy('');
              setState(() {});
            },
            onToClear: () {
              c.setToMfy('');
              setState(() {});
            },
            onRouteSelected: (route) => _applyRoutePair(c, route),
            onSwapDirection: () => _swapDirection(c),
            onManualSearch: c.isSearching ? null : () => _runSearch(c),
          ),
          Expanded(child: _buildResults(c)),
        ]),
    );
  }

  Widget _buildResults(MarshrutSearchController c) {
    if (c.isSearching && !c.searched) {
      return const ScheduleCardSkeletonList(count: 3);
    }
    if (!c.searched) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🚐', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(context.tr('marshrut_direction_card_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppText.bodyLarge, color: Colors.grey.shade500)),
        ),
      ]));
    }
    if (c.results.isEmpty) {
      final hint = marshrutHumanFilterHint(context, c.filterStats,
          emptyResults: true);
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('\u{1F614}', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(context.tr('marshrut_no_drivers_match'),
            style: TextStyle(
                fontSize: AppText.bodyLarge, color: Colors.grey.shade600)),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              hint,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ] else ...[
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
        ],
        const SizedBox(height: 8),
        if (_reminderScheduledLabel(c) != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _reminderScheduledLabel(c)!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: c.isSearching ? null : () => _showRemindLaterSheet(c),
            icon: const Icon(Icons.notifications_outlined),
            label: Text(context.tr('marshrut_remind_later')),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '🚐 ${c.results.length} ${context.tr('cars_found')}',
                    style: const TextStyle(
                      fontSize: AppText.bodyLarge,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                MarshrutResultsViewToggle(
                  selected: _resultsView,
                  onChanged: (v) => setState(() => _resultsView = v),
                ),
              ],
            ),
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
            if (marshrutHumanFilterHint(context, c.filterStats,
                    emptyResults: false) !=
                null) ...[
              const SizedBox(height: 4),
              Text(
                marshrutHumanFilterHint(context, c.filterStats,
                    emptyResults: false)!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
      Expanded(
        child: _resultsView == MarshrutResultsView.map
            ? MarshrutSearchMapView(
                userLat: c.userLat,
                userLng: c.userLng,
                results: c.results,
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: c.results.length,
                itemBuilder: (_, i) => ScheduleCard(
                  result: c.results[i],
                  onCall: _onCall,
                ),
              ),
      ),
    ]);
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.fromMfy,
    required this.toMfy,
    required this.recentRoutes,
    required this.isSearching,
    required this.onFromTap,
    required this.onToTap,
    required this.onFromClear,
    required this.onToClear,
    required this.onRouteSelected,
    required this.onSwapDirection,
    this.onManualSearch,
  });

  final String fromMfy;
  final String toMfy;
  final List<MarshrutRoutePair> recentRoutes;
  final bool isSearching;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final VoidCallback onFromClear;
  final VoidCallback onToClear;
  final ValueChanged<MarshrutRoutePair> onRouteSelected;
  final VoidCallback onSwapDirection;
  final VoidCallback? onManualSearch;

  @override
  Widget build(BuildContext context) {
    final canSearch = fromMfy.isNotEmpty && toMfy.isNotEmpty;
    return Container(
      color: _MarshrutTaxiViewState._accent,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 2,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        MarshrutRouteField(
                          hint: context.tr('from'),
                          value: fromMfy,
                          icon: Icons.trip_origin,
                          iconColor: AppColors.primaryMid,
                          onTap: onFromTap,
                          onClear: onFromClear,
                          compact: true,
                        ),
                        Divider(color: Colors.grey.shade300, height: 1),
                        MarshrutRouteField(
                          hint: context.tr('to'),
                          value: toMfy,
                          icon: Icons.location_on,
                          iconColor: Colors.redAccent,
                          onTap: onToTap,
                          onClear: onToClear,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 2),
                    child: Center(
                      child: _SwapDirectionButton(onTap: onSwapDirection),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          MarshrutDirectionChips(
            recentRoutes: recentRoutes,
            popularRoutes: MarshrutPopularRoutes.routes,
            activeFrom: fromMfy.isEmpty ? null : fromMfy,
            activeTo: toMfy.isEmpty ? null : toMfy,
            onRouteSelected: onRouteSelected,
          ),
          if (isSearching) ...[
            const SizedBox(height: 6),
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ] else if (canSearch && onManualSearch != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onManualSearch,
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                label: Text(
                  context.tr('marshrut_search_again'),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Yo'nalish almashtirish — o'ng tomonda, yashil dizayn.
class _SwapDirectionButton extends StatelessWidget {
  const _SwapDirectionButton({required this.onTap});

  static const double _size = 36;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: context.tr('switch_direction'),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Icon(
              Icons.swap_vert,
              color: AppColors.primaryDark,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
