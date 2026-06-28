import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/active_trip.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/settlement_service.dart';

/// Mahalliy taksi — haydovchi qabul qilgandan keyin safar ekrani.
class LocalTaxiActiveTripScreen extends StatefulWidget {
  const LocalTaxiActiveTripScreen({
    super.key,
    required this.tripId,
    this.initialTrip,
  });

  final String tripId;
  final ActiveTrip? initialTrip;

  @override
  State<LocalTaxiActiveTripScreen> createState() =>
      _LocalTaxiActiveTripScreenState();
}

class _LocalTaxiActiveTripScreenState extends State<LocalTaxiActiveTripScreen> {
  ActiveTrip? _trip;
  bool _tripEndHandled = false;
  bool _arrivalAlertShown = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverLocationSub;
  String? _listeningDriverId;
  LatLng? _driverLatLng;
  Position? _myPosition;
  final _mapController = Completer<GoogleMapController>();
  final _localNotifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _trip = widget.initialTrip;
    _initPassengerPosition();
    final driverId = _trip?.driverId ?? '';
    if (driverId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDriverLocationListener(driverId);
      });
    }
  }

  Future<void> _initPassengerPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      _myPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _driverLocationSub?.cancel();
    super.dispose();
  }

  void _syncDriverLocationListener(String driverId) {
    if (!mounted || driverId.isEmpty) return;
    if (_listeningDriverId == driverId) return;
    _driverLocationSub?.cancel();
    _listeningDriverId = driverId;
    _driverLocationSub = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen((snap) async {
      final d = snap.data();
      final lat = (d?['lat'] as num?)?.toDouble();
      final lng = (d?['lng'] as num?)?.toDouble();

      if (lat != null && lng != null && mounted) {
        setState(() => _driverLatLng = LatLng(lat, lng));
        _animateCamera();
      }

      if (!_arrivalAlertShown &&
          _myPosition != null &&
          lat != null &&
          lng != null) {
        final dist = Geolocator.distanceBetween(
          _myPosition!.latitude,
          _myPosition!.longitude,
          lat,
          lng,
        );
        if (dist < 100) {
          _arrivalAlertShown = true;
          await _onDriverArrived(d ?? <String, dynamic>{});
        }
      }
    });
  }

  Future<void> _onDriverArrived(Map<String, dynamic> driverData) async {
    if (!mounted) return;
    final arrivedTitle = context.tr('driver_arrived_title');
    final arrivedBody = context.tr('driver_arrived_body');
    final okLabel = context.tr('ok');

    final name = (driverData['name'] as String?)?.trim().isNotEmpty == true
        ? driverData['name'] as String
        : (_trip?.driverName ?? '');
    final car = (driverData['car'] as String?)?.trim().isNotEmpty == true
        ? driverData['car'] as String
        : (_trip?.driverCar ?? '');
    final plate = (driverData['plate'] as String?)?.trim().isNotEmpty == true
        ? driverData['plate'] as String
        : (_trip?.driverPlate ?? '');

    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 300));
    HapticFeedback.heavyImpact();

    FlutterRingtonePlayer().playNotification();

    await _showArrivalLocalNotification(
      title: arrivedTitle,
      body: '$name — $car',
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(arrivedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(arrivedBody),
            const SizedBox(height: 12),
            _infoRow('👤', name),
            _infoRow('🚗', car),
            _infoRow('🔢', plate),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.button),
            onPressed: () => Navigator.pop(context),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showArrivalLocalNotification({
    required String title,
    required String body,
  }) async {
    try {
      await NotificationService.instance.setup();
      await _localNotifications.show(
        9100 + widget.tripId.hashCode.abs() % 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'incoming_ride',
            'Янги буюртма',
            importance: Importance.max,
            priority: Priority.max,
          ),
        ),
      );
    } catch (_) {}
  }

  Widget _infoRow(String emoji, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
      );

  Future<void> _animateCamera() async {
    if (_driverLatLng == null) return;
    final ctrl = await _mapController.future;
    ctrl.animateCamera(CameraUpdate.newLatLng(_driverLatLng!));
  }

  Widget _buildMap(BuildContext context) {
    return SizedBox(
      height: 220,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _driverLatLng ?? const LatLng(41.6, 60.6),
          zoom: 15,
        ),
        onMapCreated: _mapController.complete,
        markers: _driverLatLng == null
            ? {}
            : {
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _driverLatLng!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: InfoWindow(
                    title: context.tr('driver_on_way'),
                  ),
                ),
              },
        myLocationEnabled: true,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    await callPhone(phone);
  }

  Widget _buildCancelButton(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _confirmCancel(context),
      icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
      label: Text(
        context.tr('cancel_trip'),
        style: const TextStyle(color: Colors.red),
      ),
    );
  }

  Future<void> _showRatingDialog(
    BuildContext context,
    Map<String, dynamic> trip,
  ) async {
    int selectedRating = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(context.tr('rate_driver')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trip['driverName'] as String? ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return GestureDetector(
                    onTap: () => setS(() => selectedRating = i + 1),
                    child: Icon(
                      i < selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('skip')),
            ),
            if (selectedRating > 0)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _submitRating(
                    tripId: widget.tripId,
                    driverId: trip['driverId'] as String? ?? '',
                    rating: selectedRating,
                  );
                },
                child: Text(context.tr('submit')),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating({
    required String tripId,
    required String driverId,
    required int rating,
  }) async {
    if (driverId.isEmpty) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateDriverRating')
          .call({
        'driverId': driverId,
        'rating': rating,
        'tripId': tripId,
      });
    } catch (e) {
      debugPrint('rating submit error: $e');
    }
  }

  /// Settlement Ledger — safar tugagach qaytim ҳamyonga o'tkazilsinmi.
  Future<void> _showSettlementDialog(
      BuildContext context, String settlementId, int amount) async {
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

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('cancel_trip_confirm_title')),
        content: Text(context.tr('cancel_trip_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('no')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<RidesRepository>().cancelLocalTripByPassenger(
            widget.tripId,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.trMsg('error_generic|$e')),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('active_trip_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .snapshots(),
        builder: (context, docSnap) {
          if (!docSnap.hasData || !docSnap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final trip = ActiveTrip.fromDoc(docSnap.data!);
          final data = docSnap.data!.data() ?? {};
          final estimatedPrice =
              (data['estimatedPrice'] as num?)?.toInt() ?? 0;

          _trip = trip;

          if (trip.status == 'cancelled') {
            if (!_tripEndHandled) {
              _tripEndHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context).pop();
              });
            }
          } else if (trip.status == 'completed') {
            if (!_tripEndHandled) {
              _tripEndHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                final settlementId = (data['settlementId'] ?? '').toString();
                final settlementState =
                    (data['settlementState'] ?? '').toString();
                final settlementAmount =
                    (data['settlementAmount'] as num?)?.toInt() ?? 0;
                if (settlementState == 'pending' &&
                    settlementId.isNotEmpty &&
                    settlementAmount > 0) {
                  await _showSettlementDialog(
                      context, settlementId, settlementAmount);
                }
                if (!mounted) return;
                await _showRatingDialog(context, data);
                if (mounted) Navigator.of(context).pop();
              });
            }
          }

          if (trip.status == 'accepted' && trip.driverId.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncDriverLocationListener(trip.driverId);
            });
          }

          final completed = trip.status == 'completed';
          final statusText = completed
              ? context.tr('trip_status_completed')
              : context.tr('trip_status_accepted');

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMap(context),
                const SizedBox(height: 12),
                if (estimatedPrice > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('estimated_price'),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${formatPrice(estimatedPrice)} сўм',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '👤 ${trip.driverName}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '🚗 ${trip.driverCar}  ${trip.driverPlate}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 10),
                        Text('📍 ${trip.fromAddr}',
                            style: const TextStyle(fontSize: 14)),
                        if (trip.toAddr.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('🏁 ${trip.toAddr}',
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (trip.driverPhone.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () => _callDriver(trip.driverPhone),
                    icon: const Icon(Icons.phone),
                    label: Text(context.tr('trip_call_driver')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.button,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                if (trip.status == 'accepted') ...[
                  const SizedBox(height: 12),
                  _buildCancelButton(context),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
