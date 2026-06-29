import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../models/active_trip.dart';
import '../../../../models/marshrut_driver_option.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/marshrut_waiting_controller.dart';
import 'marshrut_accepted_screen.dart';

/// Marshrut taksi haydovchilarni ketma-ket chaqirayotgan vaqtda
/// foydalanuvchiga ko'rsatiladigan screen.
class MarshrutWaitingScreen extends StatelessWidget {
  const MarshrutWaitingScreen({
    super.key,
    required this.pickupMfy,
    required this.pickupAddr,
    required this.dropoffMfy,
    required this.drivers,
    this.userLat,
    this.userLng,
  });

  final String pickupMfy;
  final String pickupAddr;
  final String dropoffMfy;
  final List<MarshrutDriverOption> drivers;
  final double? userLat;
  final double? userLng;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MarshrutWaitingController>(
      create: (ctx) => MarshrutWaitingController(
        ridesRepo: ctx.read<RidesRepository>(),
        schedulesRepo: ctx.read<SchedulesRepository>(),
        pickupMfy: pickupMfy,
        pickupAddr: pickupAddr,
        dropoffMfy: dropoffMfy,
        drivers: drivers,
        userLat: userLat,
        userLng: userLng,
      )..start(),
      child: const _MarshrutWaitingView(),
    );
  }
}

class _MarshrutWaitingView extends StatefulWidget {
  const _MarshrutWaitingView();

  @override
  State<_MarshrutWaitingView> createState() => _MarshrutWaitingViewState();
}

class _MarshrutWaitingViewState extends State<_MarshrutWaitingView> {
  static const Color _color = AppColors.primary;
  bool _dialogShown = false;
  bool _cancelAfterAcceptShown = false;

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<MarshrutWaitingController>();
    ctrl.onCancelWarning = (remaining) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('marshrut_cancel_warning')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: context.tr('understood'),
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _react());
  }

  void _react() {
    if (!mounted) return;
    final c = context.read<MarshrutWaitingController>();

    if (c.missingPhoneError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.trMsg(c.missingPhoneError!))));
      Navigator.pop(context);
      return;
    }
    if (c.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.trMsg(c.errorMessage!)),
          backgroundColor: Colors.red));
      c.clearTransient();
    }
    if (c.skipReason != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${context.trMsg(c.skipReason!)} вЂ” ${context.tr('searching_next_in_queue')}'),
        backgroundColor: Colors.orange,
        duration: const Duration(milliseconds: 1500),
      ));
      c.clearTransient();
    }
    if (!_cancelAfterAcceptShown && c.acceptedTrip != null) {
      _cancelAfterAcceptShown = true;
      final t = c.consumeAcceptedTrip()!;
      _showAcceptedWithCancelDialog(t);
      return;
    }
    if (!_dialogShown && c.allRejected) {
      _dialogShown = true;
      _showAllRejectedDialog();
    }
  }

  Future<void> _onCancel() async {
    final c = context.read<MarshrutWaitingController>();
    await c.cancelByUser();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showAcceptedWithCancelDialog(ActiveTrip trip) async {
    final c = context.read<MarshrutWaitingController>();

    final cancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('marshrut_driver_accepted')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('рџљЊ ${trip.driverName}'),
            Text('рџ“ћ ${trip.driverPhone}'),
            Text('рџљ— ${trip.driverCar}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('cancel_trip'),
                style: const TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('ok')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (cancel == true) {
      await c.cancelAfterAccept(trip.id);
      if (mounted) Navigator.of(context).pop();
    } else {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MarshrutAcceptedScreen(trip: trip),
          ),
        );
      }
    }
  }

  void _showAllRejectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ctx.tr('marshrut_all_drivers_no_response_title'),
              style: const TextStyle(fontSize: AppText.titleMedium),
            ),
          ),
        ]),
        content: Text(ctx.tr('marshrut_all_drivers_no_response_body')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(ctx.tr('ok'), style: const TextStyle(color: _color)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: _color),
            child: Text(ctx.tr('marshrut_search_again')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MarshrutWaitingController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _react());

    final driver = c.currentDriver;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.moduleBg,
        body: SafeArea(
          child: Column(children: [
            Container(
              color: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _onCancel,
                ),
                Expanded(
                    child: Text(context.tr('marshrut_offer_pending_title'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppText.titleMedium,
                            fontWeight: FontWeight.bold))),
              ]),
            ),
            Expanded(
                child: Center(
                    child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: c.secondsLeft / c.timeoutSec,
                        strokeWidth: 8,
                        backgroundColor: _color.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(_color),
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${c.secondsLeft}',
                          style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: _color)),
                      Text(context.tr('sec_short'),
                          style: const TextStyle(
                              fontSize: AppText.bodySmall,
                              color: Colors.grey)),
                    ]),
                  ]),
                  const SizedBox(height: 32),
                  if (driver != null)
                    _DriverCard(
                      driver: driver,
                      currentIndex: c.currentIndex,
                      totalDrivers: c.totalDrivers,
                      color: _color,
                    ),
                  const SizedBox(height: 24),
                  Text(
                      '${c.pickupMfy}${c.pickupAddr.isNotEmpty ? ", ${c.pickupAddr}" : ""}\nв†’ ${c.dropoffMfy}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: AppText.bodyMedium,
                          color: Colors.grey.shade700,
                          height: 1.5)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onCancel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(context.tr('marshrut_cancel_waiting'),
                          style: const TextStyle(
                              fontSize: AppText.bodyLarge,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('marshrut_cancel_waiting_hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppText.bodySmall,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ))),
          ]),
        ),
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.driver,
    required this.currentIndex,
    required this.totalDrivers,
    required this.color,
  });

  final MarshrutDriverOption driver;
  final int currentIndex;
  final int totalDrivers;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        const Text('рџљђ', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        Text(driver.driverName,
            style: const TextStyle(
                fontSize: AppText.titleMedium,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${driver.car} вЂў ${driver.plate}',
            style: TextStyle(
                fontSize: AppText.bodyMedium,
                color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
              context.tr('driver_n_of_m').replaceAll('{current}', '${currentIndex + 1}').replaceAll('{total}', '$totalDrivers'),
              style: TextStyle(
                  fontSize: AppText.bodySmall,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
