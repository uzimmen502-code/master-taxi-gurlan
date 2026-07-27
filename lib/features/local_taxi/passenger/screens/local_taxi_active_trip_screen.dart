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
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/active_trip.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/settlement_service.dart';
import '../widgets/local_taxi_wallet_panel.dart';
import 'searching_screen.dart';

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
  String? _passengerUid;

  @override
  void initState() {
    super.initState();
    _trip = widget.initialTrip;
    _loadPassengerUid();
    _initPassengerPosition();
    final driverId = _trip?.driverId ?? '';
    if (driverId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDriverLocationListener(driverId);
      });
    }
  }

  Future<void> _loadPassengerUid() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = canonicalPhoneId(phone);
    if (mounted && uid.isNotEmpty) {
      setState(() => _passengerUid = uid);
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
    final trip = _trip;
    if (trip != null && trip.fromLat != 0 && trip.fromLng != 0) {
      final pickup = LatLng(trip.fromLat, trip.fromLng);
      final bounds = LatLngBounds(
        southwest: LatLng(
          pickup.latitude < _driverLatLng!.latitude
              ? pickup.latitude
              : _driverLatLng!.latitude,
          pickup.longitude < _driverLatLng!.longitude
              ? pickup.longitude
              : _driverLatLng!.longitude,
        ),
        northeast: LatLng(
          pickup.latitude > _driverLatLng!.latitude
              ? pickup.latitude
              : _driverLatLng!.latitude,
          pickup.longitude > _driverLatLng!.longitude
              ? pickup.longitude
              : _driverLatLng!.longitude,
        ),
      );
      await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
      return;
    }
    await ctrl.animateCamera(CameraUpdate.newLatLng(_driverLatLng!));
  }

  Set<Marker> _buildMarkers(ActiveTrip trip) {
    final markers = <Marker>{};
    if (trip.fromLat != 0 || trip.fromLng != 0) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(trip.fromLat, trip.fromLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: context.tr('passenger_map_you')),
      ));
    }
    if (_driverLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: context.tr('driver_on_way')),
      ));
    }
    return markers;
  }

  Widget _phonePanel(ActiveTrip trip) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.phone, color: AppColors.primaryDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              trip.driverPhone.isNotEmpty ? trip.driverPhone : '—',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton.icon(
            onPressed: trip.driverPhone.isEmpty
                ? null
                : () => _callDriver(trip.driverPhone),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.call, size: 18),
            label: Text(context.tr('trip_call_driver')),
          ),
        ]),
      );

  Widget _tripInfoPanel(
    BuildContext context,
    ActiveTrip trip,
    int estimatedPrice,
    String statusText, {
    Widget? walletSection,
  }) =>
      Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              statusText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '👤 ${trip.driverName}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '🚗 ${trip.driverCar}  ${trip.driverPlate}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if (estimatedPrice > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('estimated_price'),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  Text(
                    '${formatMoney(estimatedPrice)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            if (walletSection != null) ...[
              const SizedBox(height: 10),
              walletSection,
            ],
            if (trip.status == 'accepted') ...[
              const SizedBox(height: 10),
              _buildCancelButton(context),
            ],
          ],
        ),
      );

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
          'Ҳайдовчи ${formatMoney(amount)} қайтимни ҳамёнингизга '
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
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'confirm') {
        await SettlementService.confirmSettlement(settlementId: settlementId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${formatMoney(amount)} ҳамёнингизга қўшилди'),
          backgroundColor: Colors.green,
        ));
      } else {
        await SettlementService.cancelSettlement(
          settlementId: settlementId,
          reason: 'passenger_wants_cash',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
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
          } else if (trip.status == 'searching') {
            if (!_tripEndHandled) {
              _tripEndHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                final nav = Navigator.of(context);
                final title = context.tr('local_driver_abandoned_title');
                final body = context.tr('local_driver_abandoned_body');
                final okLabel = context.tr('ok');
                await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => AlertDialog(
                    title: Text(title),
                    content: Text(body),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(okLabel),
                      ),
                    ],
                  ),
                );
                if (!mounted) return;
                nav.pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => SearchingScreen(
                      from: trip.fromAddr,
                      to: trip.toAddr,
                      taxiType: 'local',
                      tripId: widget.tripId,
                    ),
                  ),
                );
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
                if (!context.mounted) return;
                await _showRatingDialog(context, data);
                if (context.mounted) Navigator.of(context).pop();
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

          Widget? walletSection;
          if (trip.status == 'accepted' &&
              _passengerUid != null &&
              _passengerUid!.isNotEmpty) {
            final fareEst = estimatedPrice > 0
                ? estimatedPrice
                : trip.estimatedPrice;
            walletSection = StreamBuilder<int>(
              stream: context
                  .read<UserRepository>()
                  .watchBonusBalance(_passengerUid!),
              builder: (context, balSnap) => LocalTaxiWalletPanel(
                tripId: widget.tripId,
                walletBalance: balSnap.data ?? 0,
                fareEstimate: fareEst,
                initialIntent: trip.passengerWalletIntent,
                enabled: true,
              ),
            );
          }

          final LatLng? initialTarget = trip.fromLat != 0 || trip.fromLng != 0
              ? LatLng(trip.fromLat, trip.fromLng)
              : _driverLatLng;

          if (initialTarget == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialTarget,
                    zoom: 14,
                  ),
                  onMapCreated: _mapController.complete,
                  markers: _buildMarkers(trip),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8),
                        ],
                      ),
                      child: Text(
                        context.tr('active_trip_title'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trip.driverPhone.isNotEmpty) _phonePanel(trip),
                      _tripInfoPanel(
                        context,
                        trip,
                        estimatedPrice,
                        statusText,
                        walletSection: walletSection,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
