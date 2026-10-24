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
import '../local_taxi_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/active_trip.dart';
import '../../../../models/map_picker_result.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/settlement_service.dart';
import '../../../map_picker/screens/map_picker_screen.dart';
import '../../services/local_trip_fare_lock_service.dart';
import '../widgets/local_taxi_wallet_panel.dart';
import 'searching_screen.dart';

/// Mahalliy taksi — haydovchi qabul qilgandan keyin safar ekrani.
class LocalTaxiActiveTripScreen extends StatefulWidget {
  const LocalTaxiActiveTripScreen({
    super.key,
    required this.tripId,
    this.initialTrip,
    this.tripStreamFactory,
  });

  final String tripId;
  final ActiveTrip? initialTrip;

  /// Faqat testlar uchun: safar hujjati oqimini Firestore'siz berish
  /// (xato / «Qayta urinish» holatlarini tekshirish).
  final Stream<DocumentSnapshot<Map<String, dynamic>>> Function()?
      tripStreamFactory;

  @override
  State<LocalTaxiActiveTripScreen> createState() =>
      _LocalTaxiActiveTripScreenState();
}

class _LocalTaxiActiveTripScreenState extends State<LocalTaxiActiveTripScreen> {
  ActiveTrip? _trip;
  bool _tripEndHandled = false;
  bool _cancelInProgress = false;
  bool _arrivalAlertShown = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverLocationSub;
  String? _listeningDriverId;
  LatLng? _driverLatLng;
  Position? _myPosition;
  final _mapController = Completer<GoogleMapController>();
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Oqimlar bir marta yaratiladi — `build` ichida yaratilsa, har haydovchi
  // GPS yangilanishidagi setState yangi listener ochardi (ortiqcha read).
  // «Qayta urinish» (`_retryTripStream`) oqimni qayta ochgani uchun `final` emas.
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _tripStream;
  Stream<int>? _balanceStream;

  /// Xarita markazi — na olib ketish nuqtasi, na haydovchi, na yo'lovchi
  /// joylashuvi ma'lum bo'lmaganda (davlat ko'rinishi). Aks holda ekran
  /// spinnerda qolib, qo'ng'iroq va bekor qilish tugmalari ko'rinmasdi.
  static const _fallbackTarget = LatLng(41.3775, 64.5853);
  static const _fallbackZoom = 5.6;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _openTripStream() =>
      widget.tripStreamFactory?.call() ??
      FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .snapshots();

  // Yangi oqim bilan StreamBuilder holati (eski xato ham) tozalansin: `key`
  // o'zgarmasa, `AsyncSnapshot` xatoni saqlab «Qayta urinish» bosilgandan keyin
  // ham birinchi hodisagacha xato ekranini ko'rsatib turardi.
  int _tripStreamGen = 0;

  void _retryTripStream() {
    if (!mounted) return;
    setState(() {
      _tripStream = _openTripStream();
      _tripStreamGen++;
    });
  }

  @override
  void initState() {
    super.initState();
    _tripStream = _openTripStream();
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
      final balance = context.read<UserRepository>().watchBonusBalance(uid);
      setState(() => _balanceStream = balance);
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
      channelName: context.tr('local_arrival_channel'),
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
            _infoRow(Icons.person_outline, name),
            _infoRow(Icons.directions_car_outlined, car),
            _infoRow(Icons.pin_outlined, plate),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: LocalTaxiColors.primary),
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
    required String channelName,
  }) async {
    try {
      await NotificationService.instance.setup();
      await _localNotifications.show(
        9100 + widget.tripId.hashCode.abs() % 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'incoming_ride',
            channelName,
            importance: Importance.max,
            priority: Priority.max,
          ),
        ),
      );
    } catch (_) {}
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 20, color: LocalTaxiColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
      );

  /// Safar hujjatini o'qib bo'lmaganda (xato / oflayn / topilmadi) — chiqish
  /// yo'li bor ekran: «Qayta urinish» va «Orqaga». Oldin bu holatda cheksiz
  /// spinner turardi.
  Widget _tripLoadFailure(
    BuildContext context, {
    required String messageKey,
    required bool canRetry,
  }) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: LocalTaxiColors.textMuted),
              const SizedBox(height: 12),
              Text(
                context.tr(messageKey),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 20),
              if (canRetry)
                FilledButton(
                  onPressed: _retryTripStream,
                  style: FilledButton.styleFrom(
                    backgroundColor: LocalTaxiColors.primary,
                    foregroundColor: LocalTaxiColors.onPrimary,
                    minimumSize: const Size(160, 48),
                  ),
                  child: Text(context.tr('err_retry')),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(minimumSize: const Size(160, 48)),
                child: Text(context.tr('back')),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          const Icon(Icons.phone, color: AppColors.primaryText, size: 20),
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
              backgroundColor: LocalTaxiColors.primary,
              foregroundColor: LocalTaxiColors.onPrimary,
              minimumSize: const Size(0, 48),
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
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.person_outline,
                      size: 20, color: LocalTaxiColors.textMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.driverName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.directions_car_outlined,
                      size: 20, color: LocalTaxiColors.textMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${trip.driverCar}  ${trip.driverPlate}',
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (estimatedPrice > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    trip.hasLockedFare
                        ? context.tr('locked_fare')
                        : context.tr('estimated_price'),
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
              if (!trip.hasLockedFare) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _setDestination(context, trip),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(context.tr('set_destination')),
                ),
              ],
              const SizedBox(height: 10),
              _buildCancelButton(context),
            ],
          ],
        ),
      );

  Future<void> _setDestination(BuildContext context, ActiveTrip trip) async {
    final picked = await Navigator.push<MapPickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          title: context.tr('pick_location'),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.lat.abs() < 1e-6 && picked.lng.abs() < 1e-6) return;
    try {
      await LocalTripFareLockService().lockFare(
        tripId: trip.id,
        toLat: picked.lat,
        toLng: picked.lng,
        toAddr: picked.label,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('locked_fare'))),
      );
    } catch (e) {
      debugPrint('lockLocalTripFare: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.trMsg(LocalTripFareLockService.errorKey(e))),
        ),
      );
    }
  }

  Future<void> _callDriver(String phone) async {
    await callPhone(phone);
  }

  Widget _buildCancelButton(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _confirmCancel(context),
      style: TextButton.styleFrom(
        foregroundColor: LocalTaxiColors.danger,
        minimumSize: const Size(0, 48),
      ),
      icon: const Icon(Icons.cancel_outlined, size: 18),
      label: Text(
        context.tr('cancel_trip'),
        style: const TextStyle(fontWeight: FontWeight.w600),
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
        title: Text(ctx.tr('local_change_to_wallet_title')),
        content: Text(
          ctx.trMsg('local_change_to_wallet_body',
              params: {'amount': formatMoney(amount)}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(ctx.tr('local_change_want_cash')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'confirm'),
            child: Text(ctx.tr('local_change_confirm')),
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
          content: Text(context.trMsg('local_change_added',
              params: {'amount': formatMoney(amount)})),
          backgroundColor: LocalTaxiColors.success,
        ));
      } else {
        await SettlementService.cancelSettlement(
          settlementId: settlementId,
          reason: 'passenger_wants_cash',
        );
      }
    } catch (e) {
      debugPrint('settlement: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('local_change_failed')),
        backgroundColor: LocalTaxiColors.danger,
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
    _cancelInProgress = true;
    try {
      final cancelled =
          await context.read<RidesRepository>().cancelLocalTripByPassenger(
                widget.tripId,
              );
      if (!context.mounted) return;
      if (!cancelled) {
        // Trip shu orada boshqa holatga o'tgan (haydovchi tark etdi /
        // yakunladi) — ekranni yopmaymiz, oqim o'sha holatni o'zi ko'rsatadi
        // (aks holda ikki marta pop → ota ekran ham yopilardi).
        _cancelInProgress = false;
        return;
      }
      _tripEndHandled = true;
      await _showCancelFeedbackThenPop(context);
    } catch (e) {
      debugPrint('cancelLocalTripByPassenger: $e');
      _cancelInProgress = false;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('local_cancel_failed')),
        backgroundColor: LocalTaxiColors.danger,
      ));
    }
  }

  /// CF `localCancelFeedback` (3 soft / 4 hard / 5 block) — қисқа кутиб диалог.
  Future<void> _showCancelFeedbackThenPop(BuildContext context) async {
    Map<String, dynamic>? fb;
    for (var i = 0; i < 8; i++) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .get();
        final raw = snap.data()?['localCancelFeedback'];
        if (raw is Map) {
          fb = Map<String, dynamic>.from(raw);
          break;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!context.mounted) return;
    }
    if (!context.mounted) return;

    final level = (fb?['level'] ?? '').toString();
    if (level == 'soft' || level == 'hard' || level == 'block') {
      final count = (fb?['cancelCount'] as num?)?.toInt() ?? 0;
      final remaining = (fb?['remaining'] as num?)?.toInt();
      final mins = (fb?['blockMinutes'] as num?)?.toInt() ?? 15;
      final titleKey = switch (level) {
        'block' => 'local_taxi_cancel_block_title',
        'hard' => 'local_taxi_cancel_hard_title',
        _ => 'local_taxi_cancel_soft_title',
      };
      final body = switch (level) {
        'block' => context
            .tr('local_taxi_cancel_block_body')
            .replaceAll('{count}', '$count')
            .replaceAll('{minutes}', '$mins'),
        'hard' => context
            .tr('local_taxi_cancel_hard_body')
            .replaceAll('{count}', '$count')
            .replaceAll('{minutes}', '$mins'),
        _ => context
            .tr('local_taxi_cancel_soft_body')
            .replaceAll('{count}', '$count')
            .replaceAll('{remaining}', '${remaining ?? 2}'),
      };
      final isHard = level == 'hard' || level == 'block';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            ctx.tr(titleKey),
            style: TextStyle(
              color: isHard ? Colors.red.shade800 : null,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(body),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isHard ? LocalTaxiColors.danger : LocalTaxiColors.primary,
                foregroundColor:
                    isHard ? Colors.white : LocalTaxiColors.onPrimary,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tr('ok')),
            ),
          ],
        ),
      );
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LocalTaxiColors.bg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey<int>(_tripStreamGen),
        stream: _tripStream,
        builder: (context, docSnap) {
          if (docSnap.hasError) {
            debugPrint('localTrip stream: ${docSnap.error}');
            return _tripLoadFailure(
              context,
              messageKey: 'local_trip_load_failed',
              canRetry: true,
            );
          }
          if (!docSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!docSnap.data!.exists) {
            // Kesh orqali kelgan «yo'q» — aslida oflayn; serverdan kelgani —
            // safar haqiqatan topilmadi (o'chirilgan / ruxsat yo'q).
            final offline = docSnap.data!.metadata.isFromCache;
            return _tripLoadFailure(
              context,
              messageKey:
                  offline ? 'local_trip_load_failed' : 'local_trip_not_found',
              canRetry: offline,
            );
          }

          final trip = ActiveTrip.fromDoc(docSnap.data!);
          final data = docSnap.data!.data() ?? {};
          final displayFare = trip.displayFare;

          _trip = trip;

          if (trip.status == 'cancelled') {
            if (!_tripEndHandled && !_cancelInProgress) {
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
          final balanceStream = _balanceStream;
          // Hamyon faqat server narxli trip'da ishlatiladi (completeLocalTrip).
          if (trip.status == 'accepted' &&
              balanceStream != null &&
              data['fareSource'] == 'server') {
            final fareEst = displayFare;
            walletSection = StreamBuilder<int>(
              stream: balanceStream,
              // Balans kelmaguncha panel yo'q — aks holda saqlangan intent
              // 0 ga qisilib ko'rinardi.
              builder: (context, balSnap) => !balSnap.hasData
                  ? const SizedBox.shrink()
                  : LocalTaxiWalletPanel(
                      tripId: widget.tripId,
                      walletBalance: balSnap.data!,
                      fareEstimate: fareEst,
                      initialIntent: trip.passengerWalletIntent,
                      enabled: true,
                    ),
            );
          }

          // Olib ketish nuqtasi → haydovchi → yo'lovchi joylashuvi → davlat
          // ko'rinishi. Hech biri bo'lmasa ham ekran ochiladi (oldin cheksiz
          // spinner: qo'ng'iroq va bekor qilish tugmalari ko'rinmasdi).
          final LatLng? knownTarget = trip.fromLat != 0 || trip.fromLng != 0
              ? LatLng(trip.fromLat, trip.fromLng)
              : (_driverLatLng ??
                  (_myPosition == null
                      ? null
                      : LatLng(_myPosition!.latitude, _myPosition!.longitude)));
          final initialTarget = knownTarget ?? _fallbackTarget;

          return Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialTarget,
                    zoom: knownTarget == null ? _fallbackZoom : 14,
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
                  // Panellar balandligi ekranning 62 % idan oshmaydi va
                  // ichida aylanadi: kichik ekran / katta shrift / klaviaturada
                  // «Bekor qilish» tugmasi kesilmasin va xarita to'liq yopilmasin.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trip.driverPhone.isNotEmpty) _phonePanel(trip),
                          _tripInfoPanel(
                            context,
                            trip,
                            displayFare,
                            statusText,
                            walletSection: walletSection,
                          ),
                        ],
                      ),
                    ),
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
