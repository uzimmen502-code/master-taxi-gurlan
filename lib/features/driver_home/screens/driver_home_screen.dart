import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
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
    if (!mounted) return;
    _showSnack(context.tr('drv_passenger_cancelled'), Colors.orange);
  }

  @override
  void dispose() {
    _seatsFullSub?.cancel();
    _passengerCancelSub?.cancel();
    super.dispose();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    // Оч фон (бренд/апельсин) устида тўқ матн, тўқ фонда — оқ.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light
            ? AppColors.onPrimary
            : Colors.white;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: onColor)),
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎉', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(context.tr('drv_seats_full_title'),
              style: const TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(context.tr('drv_seats_full_body'),
              style: const TextStyle(
                  fontSize: AppText.bodyMedium,
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: AppColors.onPrimary,
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
      _showSnack(context.trMsg(result.error!), Colors.orange);
      return;
    }
    _showSnack(context.tr('drv_work_started'), _green);
  }

  Future<void> _onEndWork() async {
    final c = context.read<DriverHomeController>();
    final ok = await c.endWorkDay();
    if (!mounted) return;
    if (!ok) {
      _showSnack(context.tr('drv_finish_or_leave_first'), Colors.orange);
      return;
    }
    _showSnack(context.tr('drv_work_ended'), Colors.grey.shade700);
  }

  Future<void> _onCompleteNonLocalRide() async {
    final c = context.read<DriverHomeController>();
    final result = await showFareCalculatorDialog(context);
    if (!mounted || result == null) return;
    final fare = await c.finishRide(fare: result.fare, cashPaid: result.cashPaid);
    if (!mounted) return;
    _showSnack(
        context.trMsg('drv_trip_done_fare',
            params: {'amount': FareCalculator.format(fare)}),
        _green);
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
      context.trMsg(settlement.userMessage!),
      settlement.status == TripChangeSettlementStatus.deferred
          ? Colors.orange
          : Colors.red,
    );
  }

  /// `true` — safar haqiqatan yakunlandi (xarita holatini tozalash mumkin).
  Future<bool> _onFinishLocalTrip(int fare) async {
    final c = context.read<DriverHomeController>();
    var walletIntent = 0;
    var lockedFare = 0;
    var serverPriced = false;
    final tripId = c.acceptedRide?.id;
    if (tripId != null && tripId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      serverPriced = data['fareSource'] == 'server';
      // Hamyon faqat server narxli trip'da yechiladi (completeLocalTrip).
      walletIntent = serverPriced
          ? (data['passengerWalletIntent'] as num?)?.toInt() ?? 0
          : 0;
      lockedFare = (data['lockedFare'] as num?)?.toInt() ?? 0;
    }
    if (!mounted) return false;
    final effectiveFare = lockedFare > 0 ? lockedFare : fare;
    final result = await showFareCalculatorDialog(
      context,
      initialFare: effectiveFare,
      passengerWalletIntent: walletIntent,
      fareLocked: lockedFare > 0,
    );
    if (!mounted || result == null) return false;
    final int earned;
    try {
      earned = await c.finishRide(
        fare: result.fare,
        cashPaid: result.cashPaid,
      );
    } catch (e) {
      debugPrint('finishRide: $e');
      if (mounted) _showSnack(context.tr('local_finish_failed'), Colors.red);
      return false;
    }
    if (!mounted) return true;
    _showSnack(
        context.trMsg('drv_trip_done_fare',
            params: {'amount': FareCalculator.format(earned)}),
        _green);
    // Server hisoblagan naqd ulush (hamyon balansi intent'dan kam bo'lishi
    // mumkin) — haydovchi kam olgan bo'lsa ogohlantiramiz.
    final done = c.lastLocalComplete;
    if (done != null && done.cashPaid < done.cashDue) {
      _showSnack(
        context.trMsg('local_cash_short', params: {
          'amount': FareCalculator.format(done.cashDue - done.cashPaid),
          'due': FareCalculator.format(done.cashDue),
        }),
        Colors.orange,
      );
    }
    _maybeShowSettlementNotice(c);
    return true;
  }

  /// `true` — safar tark etildi (server tasdiqladi).
  Future<bool> _onAbandonLocalTrip() async {
    final c = context.read<DriverHomeController>();
    final result = await c.abandonRide();
    if (!mounted) return result.success;
    if (!result.success && result.error != null) {
      _showSnack(context.trMsg(result.error!), Colors.orange);
    }
    return result.success;
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
