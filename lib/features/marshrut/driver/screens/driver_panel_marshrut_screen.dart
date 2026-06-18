import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/active_trip.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../driver_schedule/screens/driver_schedule_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/marshrut_driver_panel_controller.dart';
import '../../../../shared/navigation/ensure_car_info_via_profile.dart';
import '../services/marshrut_panel_status_sounds.dart';
import '../widgets/marshrut_panel_bottom_bar.dart';
import '../widgets/marshrut_smena_info_sheet.dart';
import '../widgets/ride_request_card.dart';
import '../widgets/route_card.dart';
import 'driver_register_marshrut_screen.dart';

/// Marshrut haydovchi paneli — bugungi reys, online toggle, buyurtmalar oqimi.
class DriverPanelMarshrutScreen extends StatelessWidget {
  const DriverPanelMarshrutScreen({
    super.key,
    required this.carModel,
    required this.plate,
    required this.seats,
    required this.stops,
    required this.driverName,
    required this.driverPhone,
    required this.driverId,
  });

  final String carModel;
  final String plate;
  final int seats;
  final String driverName;
  final String driverPhone;
  final String driverId;
  final List<String> stops;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MarshrutDriverPanelController>(
      create: (ctx) => MarshrutDriverPanelController(
        driverId: driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        carModel: carModel,
        plate: plate,
        seats: seats,
        initialStops: stops,
        marshrutRepo: ctx.read<MarshrutDriverRepository>(),
        schedulesRepo: ctx.read<SchedulesRepository>(),
        ridesRepo: ctx.read<RidesRepository>(),
      )..init(),
      child: const _DriverPanelMarshrutView(),
    );
  }
}

class _DriverPanelMarshrutView extends StatefulWidget {
  const _DriverPanelMarshrutView();

  @override
  State<_DriverPanelMarshrutView> createState() =>
      _DriverPanelMarshrutViewState();
}

class _DriverPanelMarshrutViewState extends State<_DriverPanelMarshrutView>
    with WidgetsBindingObserver {
  static const Color _color = AppColors.button;
  static const Color _orange = AppColors.primary;

  String? _lastSnackShown;
  String? _openRequestDialogTripId;
  String? _lastPassengerCancelSnackTripId;
  VoidCallback? _closeRequestDialog;
  final FlutterRingtonePlayer _ringtonePlayer = FlutterRingtonePlayer();
  bool _shiftEnded = false;
  bool _autoScheduleOpened = false;
  MarshrutDriverPanelController? _panelCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ctrl = context.read<MarshrutDriverPanelController>();
    _panelCtrl = ctrl;
    ctrl.addListener(_onPanelControllerUpdate);
    ctrl.onStopRingtone = _stopRingtone;
    ctrl.onPassengerOrderCancelled = _onPassengerOrderCancelled;
    ctrl.onEndStopApproaching = () {
      if (mounted) _showEndStopDialog();
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingTripFromPush();
      _onPanelControllerUpdate();
    });
  }

  void _onPanelControllerUpdate() {
    final ctrl = _panelCtrl;
    if (ctrl == null || !mounted || _autoScheduleOpened || _shiftEnded) return;
    if (!ctrl.initDone || ctrl.hasScheduleToday) return;
    _autoScheduleOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openStartSchedule(ctrl));
    });
  }

  Future<void> _checkPendingTripFromPush() async {
    final prefs = await SharedPreferences.getInstance();
    final tripId = prefs.getString('pending_marshrut_trip_id');
    if (tripId == null || tripId.isEmpty) return;
    await prefs.remove('pending_marshrut_trip_id');
    if (!mounted) return;
    await context.read<MarshrutDriverPanelController>().setPendingDialogTripId(
          tripId,
        );
  }

  @override
  void dispose() {
    _panelCtrl?.removeListener(_onPanelControllerUpdate);
    final ctrl = context.read<MarshrutDriverPanelController>();
    ctrl.onStopRingtone = null;
    ctrl.onPassengerOrderCancelled = null;
    ctrl.onEndStopApproaching = null;
    _stopRingtone();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final ctrl = context.read<MarshrutDriverPanelController>();
      ctrl.checkPendingTrips();
      unawaited(ctrl.refreshProfileInfo());
      unawaited(ctrl.probeNetworkNow());
    }
  }

  void _startRingtone() {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _ringtonePlayer.playRingtone(
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    }
  }

  void _stopRingtone() {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _ringtonePlayer.stop();
    }
  }

  Future<void> _showEndStopDialog() async {
    _startRingtone();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('end_stop_approaching')),
        content: Text(context.tr('return_trip_question')),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('no')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.button),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    );
    _stopRingtone();

    if (!mounted) return;
    final ctrl = context.read<MarshrutDriverPanelController>();
    ctrl.markEndStopDialogClosed();
    if (ok == true) {
      await ctrl.forceEndAndSwitch();
    } else {
      await ctrl.forceEndAndGoOffline();
    }
  }

  void _react(MarshrutDriverPanelController c) {
    final msg = c.errorMessage ?? c.info;
    if (msg != null && msg != _lastSnackShown) {
      _lastSnackShown = msg;
      if (msg == 'no_schedule_today') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _snack(context.tr('no_schedule_today'), Colors.orange.shade800);
          c.clearTransient();
          _lastSnackShown = null;
        });
      } else {
        final isError = c.errorMessage != null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final infoKey = c.info;
          _snack(
              context.trMsg(msg),
              isError
                  ? Colors.red
                  : (infoKey == 'internet_disconnected_offline'
                      ? Colors.orange
                      : infoKey == 'finish_accepted_trip_first' ||
                              infoKey == 'resolve_orders_first'
                          ? _orange
                          : _color));
          c.clearTransient();
          _lastSnackShown = null;
        });
      }
    }

    if (c.pendingDialogTripId != null && !c.isDialogOpen) {
      final ride = c.rideById(c.pendingDialogTripId!);
      if (ride != null) {
        final id = ride.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showRequestDialog(ride, controller: c, tripId: id);
        });
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _callUser(String phone) async {
    if (phone.isEmpty || phoneDigits(phone).length < 9) return;
    final url = Uri.parse('tel:${phoneForCall(phone)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _onPassengerOrderCancelled(String tripId) {
    _handlePassengerCancelledOrder(tripId);
  }

  void _handlePassengerCancelledOrder(String tripId) {
    _stopRingtone();
    if (_openRequestDialogTripId == tripId) {
      _closeRequestDialog?.call();
    }
    if (!mounted) return;
    if (_lastPassengerCancelSnackTripId == tripId) return;
    _lastPassengerCancelSnackTripId = tripId;
    _snack(context.tr('marshrut_passenger_cancelled_order'), Colors.orange);
    Future.delayed(const Duration(seconds: 3), () {
      if (_lastPassengerCancelSnackTripId == tripId) {
        _lastPassengerCancelSnackTripId = null;
      }
    });
  }

  Future<void> _showRequestDialog(
    ActiveTrip ride, {
    required MarshrutDriverPanelController controller,
    required String tripId,
  }) async {
    controller.isDialogOpen = true;
    _startRingtone();
    _openRequestDialogTripId = tripId;
    StreamSubscription<ActiveTrip>? tripSub;
    tripSub = context.read<RidesRepository>().watch(tripId).listen((trip) {
      if (!trip.isPassengerCancelled) return;
      tripSub?.cancel();
      _handlePassengerCancelledOrder(tripId);
    });
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          _closeRequestDialog = () {
            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
          };
          return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.person_pin, color: _color, size: 26),
            const SizedBox(width: 8),
            Text(context.tr('new_order_alert'),
                style: const TextStyle(fontSize: AppText.titleMedium)),
          ]),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(context.tr('label_mfy'), ride.pickupMfy),
                if (ride.fromAddr.isNotEmpty)
                  _infoRow(context.tr('label_address'), ride.fromAddr),
                _infoRow(context.tr('label_destination'), ride.dropoffMfy),
                _infoRow(context.tr('label_phone'), ride.userPhone),
              ]),
          actions: [
            IconButton(
              onPressed: () => _callUser(ride.userPhone),
              icon: const Icon(Icons.call, color: AppColors.primary, size: 28),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                controller.rejectRide(tripId);
              },
              child: Text(context.tr('reject'),
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final ok = await controller.acceptRide(tripId);
                if (!mounted) return;
                if (ok && ride.userPhone.isNotEmpty) {
                  await _callUser(ride.userPhone);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(context.tr('accept')),
            ),
          ],
        );
        },
      );
    } finally {
      await tripSub?.cancel();
      _closeRequestDialog = null;
      _openRequestDialogTripId = null;
      _stopRingtone();
    }
    controller.isDialogOpen = false;
    controller.dialogShown();
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppText.bodySmall, color: Colors.grey)),
          const SizedBox(width: 6),
          Flexible(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: AppText.bodyMedium,
                      fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MarshrutDriverPanelController>();
    _react(c);

    return Scaffold(
      backgroundColor: AppColors.moduleBg,
      appBar: AppBar(
        title: Text(context.tr('marshrut_panel_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (c.hasScheduleToday) ...[
                  RouteCard(
                    stops: c.stops,
                    direction: c.direction,
                    seatsLeft: c.seatsLeft,
                    isOnline: c.isOnline,
                    onSwitchDirection: c.switchDirection,
                  ),
                  const SizedBox(height: 16),
                  if (c.isAutoPaused) ...[
                    _AutoPausedBanner(reason: c.autoPausedReason ?? ''),
                    const SizedBox(height: 16),
                  ],
                  if (c.hasAcceptedTrips) ...[
                    const _AcceptedTripsHeader(),
                    const SizedBox(height: 8),
                    for (final r in c.acceptedTrips)
                      _AcceptedTripCard(
                        ride: r,
                        onCall: () => _callUser(r.userPhone),
                        onCancelNoRoom: () => _confirmCancelNoRoom(c, r),
                        onComplete: () => _confirmCompleteRide(c, r),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (c.hasRequests) ...[
                    _RequestsHeader(count: c.requests.length),
                    const SizedBox(height: 8),
                    for (final r in c.requests)
                      RideRequestCard(
                        ride: r,
                        onView: () =>
                            _showRequestDialog(r, controller: c, tripId: r.id),
                      ),
                  ],
                ] else if (!_shiftEnded) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange.shade800, size: 28),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('no_schedule_today'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppText.bodyMedium,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('start_work_subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppText.bodySmall,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
          ),
          MarshrutPanelBottomBar(
            barState: resolveMarshrutPanelBarState(
              shiftEnded: _shiftEnded,
              hasScheduleToday: c.hasScheduleToday,
              isOnline: c.isOnline,
            ),
            onOnlineTap: () => _onBottomBarOnline(c),
            onTanaffusTap: () => _onBottomBarTanaffus(c),
            onSmenaStartedTap: () => _openStartSchedule(c),
            onSmenaEndedTap: () => _showEndShiftDialog(context),
            onSmenaInfoTap: () => _openSmenaInfo(c),
          ),
        ],
      ),
    );
  }

  Future<void> _openStartSchedule(MarshrutDriverPanelController c) async {
    await c.refreshProfileInfo();
    if (!context.mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverScheduleScreen(
          taxiType: 'marshrut',
          driverName: c.driverName,
          driverPhone: c.driverPhone,
          driverCar: c.carModel,
          driverPlate: c.plate,
          initialSeats: c.seats,
        ),
      ),
    );
    if (result == true) await c.checkTodaySchedule();
  }

  Future<void> _openSmenaInfo(MarshrutDriverPanelController c) async {
    await c.refreshProfileInfo();
    if (!context.mounted) return;
    await showMarshrutSmenaInfoSheet(
      context,
      controller: c,
      onEditProfile: () async {
        if (!await ensureCarInfoViaProfile(context)) return;
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DriverRegisterMarshrutScreen(),
          ),
        );
        if (!context.mounted) return;
        await c.checkTodaySchedule();
        await c.refreshProfileInfo();
      },
    );
  }

  Future<void> _onBottomBarOnline(MarshrutDriverPanelController c) async {
    if (c.isAutoPaused) {
      await c.reactivateFromAutoPause();
    } else if (!c.isOnline) {
      await c.goOnline();
    }
    if (c.isOnline) {
      await MarshrutPanelStatusSounds.playOnline();
    }
  }

  Future<void> _onBottomBarTanaffus(MarshrutDriverPanelController c) async {
    if (!c.isAutoPaused && !c.isOnline) return;
    final wasActive = c.isOnline || c.isAutoPaused;
    if (wasActive) await c.goOffline();
    if (wasActive && !c.isOnline) {
      await MarshrutPanelStatusSounds.playOffline();
    }
  }

  Future<void> _showEndShiftDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('end_shift_confirm_title')),
        content: Text(context.tr('end_shift_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('end_shift')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ctrl = context.read<MarshrutDriverPanelController>();
    await ctrl.goOffline();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmCancelNoRoom(
    MarshrutDriverPanelController controller,
    ActiveTrip ride,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('no_seat_title')),
        content: Text(ctx.tr('no_room_dialog_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('no')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            child: Text(ctx.tr('cancel_booking')),
          ),
        ],
      ),
    );
    if (ok == true) await controller.cancelAcceptedNoRoom(ride.id);
  }

  Future<void> _confirmCompleteRide(
    MarshrutDriverPanelController controller,
    ActiveTrip ride,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('complete_trip_title')),
        content: Text(
          ctx.tr('complete_trip_confirm').replaceAll('{from}', ride.pickupMfy).replaceAll('{to}', ride.dropoffMfy),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('no')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _color,
              foregroundColor: Colors.white,
            ),
            child: Text(ctx.tr('complete_trip_confirm_btn')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.completeRide(ride.id);
    }
  }
}

class _AcceptedTripsHeader extends StatelessWidget {
  const _AcceptedTripsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.check_circle_outline, color: AppColors.primaryDark, size: 20),
      const SizedBox(width: 8),
      Text(
        context.tr('accepted_trips_title'),
        style: const TextStyle(
            fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold),
      ),
    ]);
  }
}

class _AcceptedTripCard extends StatelessWidget {
  const _AcceptedTripCard({
    required this.ride,
    required this.onCall,
    required this.onCancelNoRoom,
    required this.onComplete,
  });

  final ActiveTrip ride;
  final VoidCallback onCall;
  final VoidCallback onCancelNoRoom;
  final VoidCallback onComplete;

  static const Color _color = AppColors.button;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${ride.pickupMfy} → ${ride.dropoffMfy}',
          style: const TextStyle(
            fontSize: AppText.bodyMedium,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (ride.fromAddr.isNotEmpty)
          Text(
            '🏠 ${ride.fromAddr}',
            style: TextStyle(
                fontSize: AppText.labelSmall, color: Colors.grey.shade600),
          ),
        Text(
          '📞 ${ride.userPhone}',
          style: TextStyle(
              fontSize: AppText.labelSmall, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.call, size: 16),
              label: Text(context.tr('call')),
            ),
            OutlinedButton.icon(
              onPressed: onCancelNoRoom,
              icon: const Icon(Icons.event_busy, size: 16),
              label: Text(context.tr('no_room_short')),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
            ),
            ElevatedButton.icon(
              onPressed: onComplete,
              icon: const Icon(Icons.done_all, size: 16),
              label: Text(context.tr('complete_short')),
              style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

class _AutoPausedBanner extends StatelessWidget {
  const _AutoPausedBanner({
    required this.reason,
  });

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.pause_circle_outline, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('auto_paused_banner_title'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          reason == 'dispatch_timeout_streak'
              ? context.tr('auto_paused_timeout_body')
              : context.tr('auto_paused_generic_body')
                  .replaceAll('{reason}', reason),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
        ),
      ]),
    );
  }
}

class _RequestsHeader extends StatelessWidget {
  const _RequestsHeader({required this.count});

  final int count;

  static const Color _color = AppColors.button;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(context.tr('orders_incoming'),
          style: const TextStyle(
              fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: _color, borderRadius: BorderRadius.circular(10)),
        child: Text('$count',
            style: const TextStyle(
                fontSize: AppText.labelSmall,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}
