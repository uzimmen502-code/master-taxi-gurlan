import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/passenger_cancel_block_rules.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/active_trip.dart';
import '../../../../models/schedule.dart';
import '../../../../repositories/marshrut_block_repository.dart';
import '../../../../repositories/queue_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../services/location_service.dart';
import '../../../../services/settlement_service.dart';
import '../models/marshrut_passenger_route_context.dart';
import 'marshrut_waiting_screen.dart';

/// Marshrut — haydovchi qabul qilgandan keyingi to'liq safar ekrani.
class MarshrutAcceptedScreen extends StatefulWidget {
  const MarshrutAcceptedScreen({
    super.key,
    required this.trip,
    this.routeContext,
  });

  final ActiveTrip trip;
  final MarshrutPassengerRouteContext? routeContext;

  @override
  State<MarshrutAcceptedScreen> createState() => _MarshrutAcceptedScreenState();
}

class _MarshrutAcceptedScreenState extends State<MarshrutAcceptedScreen> {
  static const double _kmPerMinute = 0.4;
  static const double _distanceBuffer = 1.12;
  static const int _gpsRefreshSec = 8;

  Timer? _tickTimer;
  DateTime? _arrivalAt;
  double? _userLat;
  double? _userLng;
  double? _driverLat;
  double? _driverLng;
  int _secondsLeft = 0;
  double? _distanceKmBuffered;
  int _gpsRefreshCounter = 0;
  bool _tripEndHandled = false;
  bool _rerouteInProgress = false;

  @override
  void initState() {
    super.initState();
    _userLat = widget.trip.userLat;
    _userLng = widget.trip.userLng;
    _driverLat = widget.trip.driverLat;
    _driverLng = widget.trip.driverLng;
    _recalcArrival();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    _gpsRefreshCounter++;
    if (_gpsRefreshCounter >= _gpsRefreshSec) {
      _gpsRefreshCounter = 0;
      _refreshPassengerGps();
    }
    if (_arrivalAt != null) {
      final left = _arrivalAt!.difference(DateTime.now()).inSeconds;
      _secondsLeft = left.clamp(0, 86400);
    }
    setState(() {});
  }

  Future<void> _refreshPassengerGps() async {
    try {
      final loc = context.read<LocationService>();
      final c = await loc.getCurrentCoords(
        mediumTimeout: const Duration(seconds: 3),
        highTimeout: const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() {
        _userLat = c.lat;
        _userLng = c.lng;
      });
      _recalcArrival();
    } catch (_) {}
  }

  void _applyDriverCoords(double? lat, double? lng) {
    if (lat == null || lng == null) return;
    if (_driverLat == lat && _driverLng == lng) return;
    _driverLat = lat;
    _driverLng = lng;
    _recalcArrival();
  }

  void _recalcArrival() {
    final uLat = _userLat;
    final uLng = _userLng;
    final dLat = _driverLat;
    final dLng = _driverLng;
    if (uLat == null || uLng == null || dLat == null || dLng == null) {
      _arrivalAt = null;
      _distanceKmBuffered = null;
      _secondsLeft = 0;
      return;
    }
    final rawKm = LocationService.distanceKm(uLat, uLng, dLat, dLng);
    final bufferedKm = rawKm * _distanceBuffer;
    final etaSec =
        (bufferedKm / _kmPerMinute * 60).round().clamp(30, 7200);
    _distanceKmBuffered = bufferedKm;
    _arrivalAt = DateTime.now().add(Duration(seconds: etaSec));
    _secondsLeft = etaSec;
  }

  static List<String> _routeStops(Schedule? schedule, ActiveTrip trip) {
    final pickup = trip.pickupMfy.trim();
    final dropoff = trip.dropoffMfy.trim();
    if (schedule == null || schedule.stops.isEmpty) {
      return [
        if (pickup.isNotEmpty) pickup else schedule?.from ?? '',
        if (dropoff.isNotEmpty) dropoff else schedule?.to ?? '',
      ].where((s) => s.isNotEmpty).toList();
    }
    final stops = schedule.stops;
    final fromIdx = stops.indexOf(pickup);
    final toIdx = stops.indexOf(dropoff);
    if (fromIdx == -1 || toIdx == -1) {
      return [pickup, dropoff].where((s) => s.isNotEmpty).toList();
    }
    if (schedule.direction == 'forward') {
      if (fromIdx >= toIdx) return [pickup, dropoff];
      return stops.sublist(fromIdx, toIdx + 1);
    }
    if (fromIdx <= toIdx) return [pickup, dropoff];
    return stops.sublist(toIdx, fromIdx + 1).reversed.toList();
  }

  Future<void> _callDriver(String phone) async {
    await callPhone(phone);
  }

  String _formatCountdown(BuildContext context) {
    if (_secondsLeft <= 0) {
      return context.tr('marshrut_eta_live_soon');
    }
    final min = _secondsLeft ~/ 60;
    final sec = _secondsLeft % 60;
    if (min <= 0) {
      return context
          .tr('marshrut_eta_live_seconds')
          .replaceAll('{sec}', '$sec');
    }
    return context
        .tr('marshrut_eta_live_min_sec')
        .replaceAll('{min}', '$min')
        .replaceAll('{sec}', '$sec');
  }

  @override
  Widget build(BuildContext context) {
    final schedules = context.read<SchedulesRepository>();
    final rides = context.read<RidesRepository>();
    final scheduleId = widget.trip.scheduleId;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('marshrut_driver_accepted')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<ActiveTrip>(
        stream: rides.watch(widget.trip.id),
        initialData: widget.trip,
        builder: (context, tripSnap) {
          final trip = tripSnap.data ?? widget.trip;
          if (trip.isDriverNoRoomCancel) {
            if (!_tripEndHandled) {
              _tripEndHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleDriverNoRoomReroute(trip);
              });
            }
          } else if (trip.status == 'cancelled') {
            if (!_tripEndHandled) {
              _tripEndHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            }
          } else if (trip.status == 'completed') {
            if (!_tripEndHandled) {
              _tripEndHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleCompleted(trip.id);
              });
            }
          }
          if (trip.userLat != null && trip.userLng != null) {
            _userLat ??= trip.userLat;
            _userLng ??= trip.userLng;
          }
          if (trip.driverLat != null && trip.driverLng != null) {
            _applyDriverCoords(trip.driverLat, trip.driverLng);
          }

          if (scheduleId.isEmpty) {
            return _body(context, trip, null);
          }
          return StreamBuilder<Schedule?>(
            stream: schedules.watchById(scheduleId),
            builder: (context, schedSnap) {
              final sched = schedSnap.data;
              if (sched?.lat != null && sched?.lng != null) {
                _applyDriverCoords(sched!.lat, sched.lng);
              }
              return _body(context, trip, sched);
            },
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, ActiveTrip trip, Schedule? schedule) {
    final routeStops = _routeStops(schedule, trip);
    final distanceStr = _distanceKmBuffered != null
        ? context
            .tr('marshrut_distance_buffered')
            .replaceAll('{km}', _distanceKmBuffered!.toStringAsFixed(1))
        : context.tr('marshrut_distance_unknown');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('🚌', trip.driverName),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: trip.driverPhone.isNotEmpty
                          ? () => _callDriver(trip.driverPhone)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Text('📞', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                trip.driverPhone.isNotEmpty
                                    ? trip.driverPhone
                                    : '—',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: trip.driverPhone.isNotEmpty
                                      ? AppColors.primary
                                      : Colors.grey,
                                  decoration: trip.driverPhone.isNotEmpty
                                      ? TextDecoration.underline
                                      : null,
                                ),
                              ),
                            ),
                            if (trip.driverPhone.isNotEmpty)
                              Icon(Icons.call,
                                  size: 20, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _row('🚗', '${trip.driverCar} · ${trip.driverPlate}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('marshrut_route_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < routeStops.length; i++) ...[
                        if (i > 0)
                          Icon(Icons.arrow_forward,
                              size: 16, color: Colors.grey.shade500),
                        Text(
                          routeStops[i],
                          style: const TextStyle(
                            fontSize: AppText.bodyMedium,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$distanceStr · ${_formatCountdown(context)}',
                    style: TextStyle(
                      fontSize: AppText.bodySmall,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Text(
                  context.tr('marshrut_eta_live_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatCountdown(context),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmCancel(context, trip),
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            label: Text(context.tr('cancel_trip'),
                style: const TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String emoji, String text) => Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16)),
          ),
        ],
      );

  /// Haydovchi "o'rin yo'q" deb bekor qilganda — keyingi haydovchiga qayta dispatch.
  Future<void> _handleDriverNoRoomReroute(ActiveTrip cancelled) async {
    if (_rerouteInProgress || !mounted) return;
    final route = widget.routeContext;
    if (route == null) {
      Navigator.of(context).pop();
      return;
    }

    _rerouteInProgress = true;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('no_seat_title')),
        content: Text(context.tr('no_seat_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('back_short')),
          ),
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
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final excludeId = cancelled.driverId.isNotEmpty
        ? cancelled.driverId
        : cancelled.targetDriverId;
    final drivers = await context.read<QueueRepository>().findNextEligibleMarshrutDrivers(
          pickupMfy: route.pickupMfy,
          dropoffMfy: route.dropoffMfy,
          limit: 7,
          excludeDriverIds:
              excludeId.isNotEmpty ? {excludeId} : const {},
        );
    if (!mounted) {
      _rerouteInProgress = false;
      return;
    }
    if (drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('no_other_driver_now'))),
      );
      _rerouteInProgress = false;
      Navigator.of(context).pop();
      return;
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MarshrutWaitingScreen(
          pickupMfy: route.pickupMfy,
          pickupAddr: route.pickupAddr,
          dropoffMfy: route.dropoffMfy,
          drivers: drivers,
          userLat: route.userLat,
          userLng: route.userLng,
        ),
      ),
    );
    _rerouteInProgress = false;
  }

  /// Safar tugadi — qaytim (settlement) pending bo'lsa tasdiq dialogi, so'ng pop.
  Future<void> _handleCompleted(String tripId) async {
    if (!mounted) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      final settlementId = (data['settlementId'] ?? '').toString();
      final settlementState = (data['settlementState'] ?? '').toString();
      final settlementAmount = (data['settlementAmount'] as num?)?.toInt() ?? 0;
      if (settlementState == 'pending' &&
          settlementId.isNotEmpty &&
          settlementAmount > 0 &&
          mounted) {
        await _showSettlementDialog(settlementId, settlementAmount);
      }
    } catch (e) {
      debugPrint('marshrut completed settlement: $e');
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Settlement Ledger — qaytim hamyonga o'tkazilsinmi (yo'lovchi tasdig'i).
  Future<void> _showSettlementDialog(String settlementId, int amount) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Қайтим — ҳамёнга'),
        content: Text(
          'Ҳайдовчи ${formatPrice(amount)} сўм қайтимни ҳамёнингизга '
          'ўтказмоқчи. Тасдиқлайсизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Нақд керак'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'confirm'),
            child: const Text('Тасдиқлайман'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'confirm') {
        await SettlementService.confirmSettlement(settlementId: settlementId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${formatPrice(amount)} сўм ҳамёнингизга қўшилди'),
          backgroundColor: Colors.green,
        ));
      } else {
        await SettlementService.cancelSettlement(
          settlementId: settlementId,
          reason: 'passenger_wants_cash',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Settlement: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _confirmCancel(BuildContext context, ActiveTrip trip) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = RidesRepository.normalizeMarshrutPhone(
      prefs.getString('user_phone') ?? '',
    );
    final blockState = phone.isNotEmpty
        ? await MarshrutBlockRepository().getState(phone)
        : const MarshrutBlockState();

    if (!context.mounted) return;

    final left = blockState.cancelsUntilBlock;
    final blockMin = '${PassengerCancelBlockRules.blockMinutes}';
    final warning = left <= 1
        ? context
            .tr('marshrut_block_warning_last')
            .replaceAll('{minutes}', blockMin)
        : context
            .tr('marshrut_block_warning')
            .replaceAll('{n}', '$left')
            .replaceAll('{minutes}', blockMin);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('cancel_trip')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('marshrut_cancel_after_accept_confirm')),
            const SizedBox(height: 12),
            Text(
              warning,
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('no')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      final rides = context.read<RidesRepository>();
      await rides.cancelMarshrutByPassenger(
        tripId: trip.id,
        reason: 'passenger_cancel_after_accept',
      );
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
