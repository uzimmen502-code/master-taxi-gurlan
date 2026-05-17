import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/trip_request.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../repositories/schedules_repository.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/fare_calculator.dart';
import '../../driver_schedule/screens/driver_schedule_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../controllers/driver_home_controller.dart';
import '../widgets/active_ride_card.dart';
import '../widgets/driver_hero_card.dart';
import '../widgets/fare_calculator_dialog.dart';
import '../widgets/main_action_buttons.dart';
import '../widgets/online_pulse_toggle.dart';
import '../widgets/queue_card.dart';
import '../widgets/seats_card.dart';
import '../widgets/trip_request_card.dart';
import '../widgets/trip_request_dialog.dart';

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
  static const _blue = Color(0xFF1565C0);
  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFB71C1C);

  StreamSubscription<TripRequest>? _requestSub;
  StreamSubscription<void>? _seatsFullSub;
  bool _isDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hookEvents());
  }

  void _hookEvents() {
    if (!mounted) return;
    final c = context.read<DriverHomeController>();
    _requestSub = c.onNewRequest.listen(_onNewRequest);
    _seatsFullSub = c.onSeatsFull.listen((_) => _showSeatsFullDialog());
  }

  @override
  void dispose() {
    _requestSub?.cancel();
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

  Future<void> _onNewRequest(TripRequest ride) async {
    if (!mounted || _isDialogOpen) return;
    _isDialogOpen = true;
    final action = await showTripRequestDialog(context, ride);
    _isDialogOpen = false;
    if (!mounted) return;
    final c = context.read<DriverHomeController>();
    if (action == 'accept') {
      final result = await c.acceptRide(ride);
      if (result.success) {
        // Қўнғироқ қилишни UI томонда қилмаймиз — диалог ичида тугма бор
      } else if (result.error != null) {
        _showSnack(result.error!, Colors.orange);
      }
    } else if (action == 'reject') {
      await c.rejectRide(ride);
    }
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

  Future<void> _onToggleOnline() async {
    final c = context.read<DriverHomeController>();
    final result = await c.toggleOnline();
    if (!mounted) return;
    if (!result.success && result.error != null) {
      _showSnack(result.error!, Colors.orange);
      return;
    }
    _showSnack(c.isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
        c.isOnline ? _green : Colors.grey.shade700);
  }

  Future<void> _onStartWork() async {
    final c = context.read<DriverHomeController>();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverScheduleScreen(
          taxiType: c.session.taxiType,
          driverName: c.session.name,
          driverPhone: c.session.phone,
          driverCar: c.session.carModel,
          driverPlate: c.session.carPlate,
        ),
      ),
    );
    if (result == true) await c.refreshTodaySchedule();
  }

  Future<void> _onEndWork() async {
    final c = context.read<DriverHomeController>();
    await c.endWorkDay();
    if (!mounted) return;
    _showSnack('✅ Иш тугатилди', _green);
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

  Future<void> _onAddPassenger() async {
    final c = context.read<DriverHomeController>();
    final result = await c.addPassenger();
    if (!mounted || result.error == null) return;
    _showSnack(result.error!, result.success ? _green : Colors.orange);
  }

  Future<void> _onRemovePassenger() async {
    final c = context.read<DriverHomeController>();
    final result = await c.removePassenger();
    if (!mounted || result.error == null) return;
    _showSnack(result.error!, result.success ? _green : Colors.orange);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverHomeController>();
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
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
                DriverHeroCard(
                  session: c.session,
                  onProfileTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProfileScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                if (c.hasScheduleToday) ...[
                  SeatsCard(
                    seatsLeft: c.seatsLeft,
                    totalSeats: c.totalSeats,
                    onAdd: _onAddPassenger,
                    onRemove: _onRemovePassenger,
                  ),
                  const SizedBox(height: 16),
                  OnlinePulseToggle(
                    isOnline: c.isOnline,
                    onTap: _onToggleOnline,
                  ),
                  const SizedBox(height: 16),
                ],
                if (c.isBusy && c.acceptedRide != null) ...[
                  ActiveRideCard(
                      ride: c.acceptedRide!, onComplete: _onCompleteRide),
                  const SizedBox(height: 16),
                ],
                if (c.isOnline && c.queueList.isNotEmpty) ...[
                  QueueCard(
                      queueList: c.queueList,
                      myPosition: c.queuePosition,
                      myDriverId: c.session.driverId),
                  const SizedBox(height: 16),
                ],
                MainActionButtons(
                  hasScheduleToday: c.hasScheduleToday,
                  onStart: _onStartWork,
                  onEnd: _onEndWork,
                ),
                const SizedBox(height: 16),
                if (c.isOnline && !c.isBusy && c.activeRequests.isNotEmpty) ...[
                  _SectionTitle(
                      title: '📥 Буюртмалар',
                      count: c.activeRequests.length),
                  const SizedBox(height: 8),
                  ...c.activeRequests.map((r) => TripRequestCard(
                        ride: r,
                        onTap: () => _onNewRequest(r),
                      )),
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

  static const _blue = Color(0xFF1565C0);

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
