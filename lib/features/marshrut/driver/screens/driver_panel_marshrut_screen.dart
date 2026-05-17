import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/active_trip.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../driver_schedule/screens/driver_schedule_screen.dart';
import '../../../../utils/app_theme.dart';
import '../controllers/marshrut_driver_panel_controller.dart';
import '../widgets/online_toggle_tile.dart';
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
  static const Color _color = Color(0xFF00695C);
  static const Color _orange = Color(0xFFE65100);

  String? _lastSnackShown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MarshrutDriverPanelController>().checkPendingTrips();
    }
  }

  void _react(MarshrutDriverPanelController c) {
    final msg = c.errorMessage ?? c.info;
    if (msg != null && msg != _lastSnackShown) {
      _lastSnackShown = msg;
      final isError = c.errorMessage != null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(
            msg,
            isError
                ? Colors.red
                : (c.info!.contains('📵')
                    ? Colors.orange
                    : c.info!.contains('❗')
                        ? _orange
                        : _color));
        c.clearTransient();
        _lastSnackShown = null;
      });
    }

    if (c.pendingDialogTripId != null) {
      final ride = c.rideById(c.pendingDialogTripId!);
      if (ride != null) {
        final id = ride.id;
        c.dialogShown();
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
    if (phone.isEmpty) return;
    final url = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _showRequestDialog(
    ActiveTrip ride, {
    required MarshrutDriverPanelController controller,
    required String tripId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.person_pin, color: _color, size: 26),
          SizedBox(width: 8),
          Text('Янги буюртма!',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('📍 МФЙ:', ride.pickupMfy),
              if (ride.fromAddr.isNotEmpty)
                _infoRow('🏠 Манзил:', ride.fromAddr),
              _infoRow('🏁 Қаерга:', ride.dropoffMfy),
              _infoRow('📞 Телефон:', ride.userPhone),
            ]),
        actions: [
          IconButton(
            onPressed: () => _callUser(ride.userPhone),
            icon: const Icon(Icons.call, color: Colors.green, size: 28),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.rejectRide(tripId);
            },
            child: const Text('РАД',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
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
            child: const Text('ҚАБУЛ'),
          ),
        ],
      ),
    );
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
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(
        title: const Text('🚐 Маршрут панели'),
        backgroundColor: _color,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'edit') {
                Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const DriverRegisterMarshrutScreen()))
                    .then((_) => c.checkTodaySchedule());
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, size: 18, color: Colors.black87),
                  SizedBox(width: 10),
                  Text('Маълумотларни таҳрирлаш'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _DriverInfoCard(
            driverName: c.driverName,
            carModel: c.carModel,
            plate: c.plate,
            seats: c.seats,
          ),
          const SizedBox(height: 16),
          if (!c.hasScheduleToday) ...[
            _StartScheduleTile(
              taxiType: 'marshrut',
              driverName: c.driverName,
              driverPhone: c.driverPhone,
              driverCar: c.carModel,
              driverPlate: c.plate,
              onReturned: c.checkTodaySchedule,
            ),
            const SizedBox(height: 16),
          ],
          if (c.hasScheduleToday) ...[
            RouteCard(
              stops: c.stops,
              direction: c.direction,
              seatsLeft: c.seatsLeft,
              onSwitchDirection: c.finishTrip,
            ),
            const SizedBox(height: 16),
            if (c.isAutoPaused) ...[
              _AutoPausedBanner(
                reason: c.autoPausedReason ?? '',
                onReactivate: c.reactivateFromAutoPause,
              ),
              const SizedBox(height: 16),
            ],
            OnlineToggleTile(
              isOnline: c.isOnline,
              queuePosition: c.queuePosition,
              onTap: c.isAutoPaused
                  ? c.reactivateFromAutoPause
                  : (c.isOnline ? c.goOffline : c.goOnline),
            ),
            const SizedBox(height: 16),
            if (c.hasAcceptedTrips) ...[
              const _AcceptedTripsHeader(),
              const SizedBox(height: 8),
              for (final r in c.acceptedTrips)
                _AcceptedTripCard(
                  ride: r,
                  onCall: () => _callUser(r.userPhone),
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
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Future<void> _confirmCompleteRide(
    MarshrutDriverPanelController controller,
    ActiveTrip ride,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сафарни якунлаш'),
        content: Text(
          '${ride.pickupMfy} → ${ride.dropoffMfy} сафарини completed қилишни тасдиқлайсизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ҳа, якунлаш'),
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
    return const Row(children: [
      Icon(Icons.check_circle_outline, color: Color(0xFF00695C), size: 20),
      SizedBox(width: 8),
      Text(
        'Қабул қилинган сафарлар',
        style:
            TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold),
      ),
    ]);
  }
}

class _AcceptedTripCard extends StatelessWidget {
  const _AcceptedTripCard({
    required this.ride,
    required this.onCall,
    required this.onComplete,
  });

  final ActiveTrip ride;
  final VoidCallback onCall;
  final VoidCallback onComplete;

  static const Color _color = Color(0xFF00695C);

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
        Row(children: [
          OutlinedButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.call, size: 16),
            label: const Text('Қўнғироқ'),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('Якунлаш'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _color,
              foregroundColor: Colors.white,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _AutoPausedBanner extends StatelessWidget {
  const _AutoPausedBanner({
    required this.reason,
    required this.onReactivate,
  });

  final String reason;
  final Future<void> Function() onReactivate;

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
          const Expanded(
            child: Text(
              'Навбатдан вақтинча чиқарилдингиз',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          reason == 'dispatch_timeout_streak'
              ? 'Сиз 3 марта кетма-кет буюртмага жавоб бермадингиз. Навбатни тўсиб қўймаслик учун тизим сизни вақтинча тўхтатди.'
              : 'Тизим сизни вақтинча тўхтатди: $reason',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: onReactivate,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Навбатга қайтиш'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ]),
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  const _DriverInfoCard({
    required this.driverName,
    required this.carModel,
    required this.plate,
    required this.seats,
  });

  final String driverName;
  final String carModel;
  final String plate;
  final int seats;

  static const Color _color = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          child: Text(
            driverName.isNotEmpty ? driverName[0] : 'Д',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(driverName,
              style: const TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text('🚐 $carModel · $plate · 💺$seats',
              style: const TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.white70)),
        ])),
      ]),
    );
  }
}

class _StartScheduleTile extends StatelessWidget {
  const _StartScheduleTile({
    required this.taxiType,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
    required this.onReturned,
  });

  final String taxiType;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;
  final Future<void> Function() onReturned;

  static const Color _color = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DriverScheduleScreen(
                      taxiType: taxiType,
                      driverName: driverName,
                      driverPhone: driverPhone,
                      driverCar: driverCar,
                      driverPlate: driverPlate,
                    )));
        if (result == true) await onReturned();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.play_circle_fill, color: _color, size: 28),
          ),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('ИШНИ БОШЛАШ',
                    style: TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold,
                        color: _color)),
                Text('Тўхташ нуқталарини киритинг',
                    style: TextStyle(
                        fontSize: AppText.labelSmall, color: Colors.grey)),
              ])),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}

class _RequestsHeader extends StatelessWidget {
  const _RequestsHeader({required this.count});

  final int count;

  static const Color _color = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Text('📥 Буюртмалар',
          style: TextStyle(
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
