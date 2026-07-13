import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../repositories/schedules_repository.dart';
import '../../../utils/fare_calculator.dart';
import '../../../services/trip_change_settlement.dart';
import '../controllers/driver_home_controller.dart';
import '../widgets/driver_unified_map_view.dart';
import '../widgets/fare_calculator_dialog.dart';

/// Haydovchi bosh ekrani — bitta xarita (kutish / chaqiruv / safar).
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

  StreamSubscription<void>? _seatsFullSub;
  StreamSubscription<void>? _passengerCancelSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hookEvents());
  }

  void _hookEvents() {
    if (!mounted) return;
    final c = context.read<DriverHomeController>();
    _seatsFullSub = c.onSeatsFull.listen((_) => _showSeatsFullDialog());
    _passengerCancelSub =
        c.onPassengerCancelled.listen((_) => _showPassengerCancelledSnack());
  }

  void _showPassengerCancelledSnack() {
    _showSnack('⚠️ Йўловчи сафарни бекор қилди', Colors.orange);
  }

  @override
  void dispose() {
    _seatsFullSub?.cancel();
    _passengerCancelSub?.cancel();
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

  Future<void> _onCompleteNonLocalRide() async {
    final c = context.read<DriverHomeController>();
    final result = await showFareCalculatorDialog(context);
    if (!mounted || result == null) return;
    final fare = await c.finishRide(fare: result.fare, cashPaid: result.cashPaid);
    if (!mounted) return;
    _showSnack(
        '✅ Сафар якунланди! +${FareCalculator.format(fare)} сўм', _green);
    _maybeShowSettlementNotice(c);
  }

  void _maybeShowSettlementNotice(DriverHomeController c) {
    final settlement = c.lastSettlementOutcome;
    if (settlement == null ||
        settlement.userMessage == null ||
        settlement.status == TripChangeSettlementStatus.skipped ||
        settlement.status == TripChangeSettlementStatus.opened) {
      return;
    }
    _showSnack(
      settlement.userMessage!,
      settlement.status == TripChangeSettlementStatus.deferred
          ? Colors.orange
          : Colors.red,
    );
  }

  Future<void> _onFinishLocalTrip(int fare) async {
    final c = context.read<DriverHomeController>();
    var walletIntent = 0;
    final tripId = c.acceptedRide?.id;
    if (tripId != null && tripId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .get();
      walletIntent =
          (snap.data()?['passengerWalletIntent'] as num?)?.toInt() ?? 0;
    }
    if (!mounted) return;
    final result = await showFareCalculatorDialog(
      context,
      initialFare: fare,
      passengerWalletIntent: walletIntent,
    );
    if (!mounted || result == null) return;
    final earned = await c.finishRide(
      fare: result.fare,
      cashPaid: result.cashPaid,
    );
    if (!mounted) return;
    _showSnack(
        '✅ Сафар якунланди! +${FareCalculator.format(earned)} сўм', _green);
    _maybeShowSettlementNotice(c);
  }

  Future<void> _onAbandonLocalTrip() async {
    final c = context.read<DriverHomeController>();
    await c.abandonRide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: DriverUnifiedMapView(
        onStartWork: _onStartWork,
        onEndWork: _onEndWork,
        onCompleteNonLocalRide: _onCompleteNonLocalRide,
        onFinishLocalTrip: _onFinishLocalTrip,
        onAbandonLocalTrip: _onAbandonLocalTrip,
        onSnack: _showSnack,
      ),
    );
  }
}
