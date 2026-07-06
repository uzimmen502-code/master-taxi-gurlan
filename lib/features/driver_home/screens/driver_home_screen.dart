import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/trip_request.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../repositories/schedules_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/fare_calculator.dart';
import '../controllers/driver_home_controller.dart';
import 'driver_trip_screen.dart';
import '../widgets/active_ride_card.dart';
import '../widgets/fare_calculator_dialog.dart';
import '../widgets/main_action_buttons.dart';
import '../widgets/trip_request_card.dart';

/// Ҳайдовчи бош экрани — Provider орқали [DriverHomeController].
class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => DriverHomeController(
        driverRepo: ctx.read<DriverRepository>(),
        schedulesRepo: ctx.read<SchedulesRepository>(),
        ridesRepo: ctx.read<RidesRepository>(),
        queueRepo: ctx.read<QueueRepository>(),
      ),
      child: const _DriverHomeView(),
    );
  }
}

class _DriverHomeView extends StatefulWidget {
  const _DriverHomeView();

  @override
  State<_DriverHomeView> createState() => _DriverHomeViewState();
}

class _DriverHomeViewState extends State<_DriverHomeView> {
  static const _green = AppColors.primaryDark;
  static const _red = Color(0xFFB71C1C);

  StreamSubscription<void>? _seatsFullSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hookEvents());
  }

  void _hookEvents() {
    if (!mounted) return;
    final c = context.read<DriverHomeController>();
    _seatsFullSub = c.onSeatsFull.listen((_) => _showSeatsFullDialog());
  }

  @override
  void dispose() {
    _seatsFullSub?.cancel();
    super.dispose();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// "Қабул" босилди — трипни банд қилади, дайлерни очади, 10 сония таймер.
  Future<void> _onAcceptRequest(TripRequest ride) async {
    final c = context.read<DriverHomeController>();
    final result = await c.reserveRide(ride);
    if (!mounted) return;
    if (!result.success) {
      if (result.error != null) _showSnack(result.error!, Colors.orange);
      return;
    }
    // Дайлерни очамиз — ҳайдовчи қўнғироқ қилади.
    await callPhone(ride.userPhone);
  }

  /// Банд қилинган трипни ЯКУНИЙ қабул қилиш.
  Future<void> _onConfirmReserved() async {
    final c = context.read<DriverHomeController>();
    final ride = c.reservingRide;
    final result = await c.confirmReservedRide();
    if (!mounted) return;
    if (!result.success) {
      if (result.error != null) _showSnack(result.error!, Colors.orange);
      return;
    }
    _openTripScreen(ride);
  }

  /// Local taxi сафар экранини очади (marshrut учун эмас).
  void _openTripScreen(TripRequest? ride) {
    if (ride == null) return;
    if (ride.taxiType != 'local' && ride.taxiType != 'alone') return;
    final c = context.read<DriverHomeController>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DriverTripScreen(
        ride: ride,
        onFinish: (fare) async {
          if (!mounted) return;
          final result = await showFareCalculatorDialog(
            context,
            initialFare: fare,
          );
          if (!mounted || result == null) return;
          final earned = await c.finishRide(
            fare: result.fare,
            cashPaid: result.cashPaid,
          );
          if (!mounted) return;
          _showSnack(
              '✅ Сафар якунланди! +${FareCalculator.format(earned)} сўм',
              _green);
        },
        onCancel: () async {
          await c.abandonRide();
        },
      ),
    ));
  }

  /// Бандликни бекор қилиш (Рад).
  Future<void> _onCancelReserved() async {
    final c = context.read<DriverHomeController>();
    await c.cancelReservation();
  }

  void _onRejectRequest(TripRequest ride) {
    final c = context.read<DriverHomeController>();
    c.dismissRequest(ride);
  }

  void _showSeatsFullDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: const [
          Text('🎉', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text('БЎШ ЖОЙ ҚОЛМАДИ!',
              style: TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('ҲАРАКАТНИ БОШЛАШИНГИЗ МУМКИН!',
              style: TextStyle(
                  fontSize: AppText.bodyMedium,
                  color: _green,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onStartWork() async {
    final c = context.read<DriverHomeController>();
    final result = await c.startLocalWork();
    if (!mounted) return;
    if (!result.success && result.error != null) {
      _showSnack(result.error!, Colors.orange);
      return;
    }
    _showSnack('🟢 Иш бошланди — онлайн', _green);
  }

  Future<void> _onEndWork() async {
    final c = context.read<DriverHomeController>();
    await c.endWorkDay();
    if (!mounted) return;
    _showSnack('⚫ Иш тугатилди — оффлайн', Colors.grey.shade700);
  }

  Future<void> _onCompleteRide() async {
    final c = context.read<DriverHomeController>();
    final result = await showFareCalculatorDialog(context);
    if (!mounted || result == null) return;
    final fare = await c.finishRide(fare: result.fare, cashPaid: result.cashPaid);
    if (!mounted) return;
    _showSnack(
        '✅ Сафар якунланди! +${FareCalculator.format(fare)} сўм', _green);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverHomeController>();
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(children: [
          if (!c.hasInternet)
            Container(
              color: _red,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Интернет уланиши йўқ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: AppText.bodyMedium)),
                ),
              ]),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (c.isBusy &&
                    c.acceptedRide != null &&
                    c.acceptedRide!.taxiType != 'local' &&
                    c.acceptedRide!.taxiType != 'alone') ...[
                  ActiveRideCard(
                      ride: c.acceptedRide!, onComplete: _onCompleteRide),
                  const SizedBox(height: 16),
                ],
                MainActionButtons(
                  hasScheduleToday: c.hasScheduleToday,
                  isOnline: c.isOnline,
                  onStart: _onStartWork,
                  onEnd: _onEndWork,
                ),
                const SizedBox(height: 16),
                if (c.isOnline && !c.isBusy && c.activeRequests.isEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 28, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      const Text('⏳', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 10),
                      Text('Йўловчи кутилмоқда...',
                          style: TextStyle(
                              fontSize: AppText.bodyMedium,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                if (c.isOnline && !c.isBusy && c.activeRequests.isNotEmpty) ...[
                  _SectionTitle(
                      title: '📥 Буюртмалар',
                      count: c.activeRequests.length),
                  const SizedBox(height: 8),
                  ...c.activeRequests.map((r) {
                    final myId = c.session.driverId;
                    final reservingId = c.reservingRide?.id;
                    // Ҳолат аниқлаш:
                    if (reservingId == r.id) {
                      // Бу ҳайдовчи банд қилган — Қабул/Рад + таймер.
                      return TripRequestCard(
                        ride: r,
                        mode: TripCardMode.reserving,
                        reserveSecsLeft: c.reserveSecsLeft,
                        onAccept: _onConfirmReserved,
                        onReject: _onCancelReserved,
                      );
                    }
                    final reservedByOther =
                        r.reservedBy.isNotEmpty && r.reservedBy != myId;
                    if (reservedByOther || c.reservingRide != null) {
                      // Бошқа ҳайдовчи банд қилган ЁКИ бу ҳайдовчи бошқа трипни
                      // банд қилган — "Кутиб туринг" (пассив).
                      return TripRequestCard(
                        ride: r,
                        mode: TripCardMode.waiting,
                        onAccept: () {},
                        onReject: () {},
                      );
                    }
                    // Оддий — Қабул/Рад фаол.
                    return TripRequestCard(
                      ride: r,
                      mode: TripCardMode.normal,
                      disabled: c.isBusy,
                      onAccept: () => _onAcceptRequest(r),
                      onReject: () => _onRejectRequest(r),
                    );
                  }),
                ],
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  static const _blue = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title,
          style: const TextStyle(
              fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: _blue, borderRadius: BorderRadius.circular(10)),
        child: Text('$count',
            style: const TextStyle(
                fontSize: AppText.labelSmall,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}
