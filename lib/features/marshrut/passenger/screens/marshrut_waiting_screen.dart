import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/active_trip.dart';
import '../../../../models/marshrut_driver_option.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../utils/app_theme.dart';
import '../controllers/marshrut_waiting_controller.dart';

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
  static const Color _color = Color(0xFF0288D1);
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _react());
  }

  void _react() {
    if (!mounted) return;
    final c = context.read<MarshrutWaitingController>();

    if (c.missingPhoneError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(c.missingPhoneError!)));
      Navigator.pop(context);
      return;
    }
    if (c.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(c.errorMessage!),
          backgroundColor: Colors.red));
      c.clearTransient();
    }
    if (c.skipReason != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${c.skipReason!} — навбатдагини қидирмоқда...'),
        backgroundColor: Colors.orange,
        duration: const Duration(milliseconds: 1500),
      ));
      c.clearTransient();
    }
    if (!_dialogShown && c.acceptedTrip != null) {
      _dialogShown = true;
      final t = c.consumeAcceptedTrip()!;
      _showAcceptedDialog(t);
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

  void _showAcceptedDialog(ActiveTrip t) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 28),
          SizedBox(width: 8),
          Text('Қабул қилинди!',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🚐 Ҳайдовчи маълумоти:'),
            const SizedBox(height: 8),
            Text(t.driverName,
                style: const TextStyle(
                    fontSize: AppText.titleSmall,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${t.driverCar} • ${t.driverPlate}',
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _color.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: _color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  'Манзил тушунмаса, ҳайдовчига қўнғироқ қилишингиз мумкин',
                  style: TextStyle(
                      fontSize: AppText.bodySmall,
                      color: Colors.grey.shade700),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: t.driverPhone.isEmpty
                ? null
                : () async {
                    try {
                      await launchUrl(Uri(scheme: 'tel', path: t.driverPhone),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
            icon: const Icon(Icons.phone, color: Colors.green, size: 18),
            label: const Text('Қўнғироқ',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  void _showAllRejectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text('Ҳайдовчи топилмади',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: const Text(
            'Афсус, ҳозир ҳайдовчилар банд. Бироз вақтдан кейин уриниб кўринг.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('ОК', style: TextStyle(color: _color)),
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
      onPopInvoked: (didPop) async {
        if (!didPop) await _onCancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE1F5FE),
        body: SafeArea(
          child: Column(children: [
            Container(
              color: const Color(0xFF0277BD),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _onCancel,
                ),
                const Expanded(
                    child: Text('Ҳайдовчи қидирилмоқда',
                        style: TextStyle(
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
                        backgroundColor: _color.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation(_color),
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${c.secondsLeft}',
                          style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: _color)),
                      const Text('сек',
                          style: TextStyle(
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
                      '${c.pickupMfy}${c.pickupAddr.isNotEmpty ? ", ${c.pickupAddr}" : ""}\n→ ${c.dropoffMfy}',
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
                      child: const Text('БЕКОР ҚИЛИШ',
                          style: TextStyle(
                              fontSize: AppText.bodyLarge,
                              fontWeight: FontWeight.bold)),
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
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        const Text('🚐', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        Text(driver.driverName,
            style: const TextStyle(
                fontSize: AppText.titleMedium,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${driver.car} • ${driver.plate}',
            style: TextStyle(
                fontSize: AppText.bodyMedium,
                color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('Ҳайдовчи ${currentIndex + 1} / $totalDrivers',
              style: TextStyle(
                  fontSize: AppText.bodySmall,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
