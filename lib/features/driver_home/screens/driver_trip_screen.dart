import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/route_candidate.dart';
import '../../../models/route_stop.dart';
import '../../../models/trip_request.dart';
import '../../../services/google_directions_service.dart';
import '../../../services/polyline_decoder.dart';
import '../../../utils/fare_calculator.dart';

/// Ҳайдовчи сафар экрани — йўловчи қабул қилингандан кейин.
///
/// РРєРєРё фаза:
///   1. [_Phase.pick]      — манзилни харитада белгилаш + маршрут масофаси.
///   2. [_Phase.navigating] — жонли GPS кузатув, босиб ўтилган масофага қараб
///      йўлкира ва "қолган масофа" реал вақтда янгиланади.
enum _Phase { pick, navigating }

class DriverTripScreen extends StatefulWidget {
  const DriverTripScreen({
    super.key,
    required this.ride,
    required this.onFinish,
    required this.onCancel,
  });

  final TripRequest ride;

  /// Сафар якунлангач чақирилади — `(fare)` узатилади.
  final void Function(int fare) onFinish;

  /// Сафар тугатилмасдан чиқилганда — бандликни бекор қилиш учун.
  final VoidCallback onCancel;

  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  static const _green = AppColors.primaryDark;

  final _mapController = Completer<GoogleMapController>();
  final _directionsService = GoogleDirectionsService();
  final _polylineDecoder = const PolylineDecoder();

  /// Йўловчи жойлашуви (бошланиш нуқтаси).
  late final LatLng _origin;

  /// Ҳайдовчи танлаган манзил (тугаш нуқтаси).
  LatLng? _destination;

  /// Маршрут чизиғи (Google Directions polyline).
  final Set<Polyline> _polylines = {};

  /// Google маршрут масофаси (км) — навигация бошланганда қотирилади.
  double? _routeKm;
  bool _calculating = false;
  String? _calcError;

  _Phase _phase = _Phase.pick;

  /// Жонли кузатув.
  StreamSubscription<Position>? _posSub;
  LatLng? _lastPos;
  double _drivenKm = 0;
  int _liveFare = 0;
  bool _arrived = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _origin = LatLng(
      widget.ride.fromLat != 0 ? widget.ride.fromLat : 41.4957,
      widget.ride.fromLng != 0 ? widget.ride.fromLng : 60.5822,
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    if (_mapController.isCompleted) {
      _mapController.future.then((c) => c.dispose());
    }
    super.dispose();
  }

  // ─────────────────── 1-фаза: манзил танлаш ───────────────────
  void _onMapTap(LatLng latLng) {
    if (_phase != _Phase.pick) return;
    setState(() {
      _destination = latLng;
      _polylines.clear();
      _routeKm = null;
      _calcError = null;
    });
    _calculateRoute();
  }

  /// Йўловчи → манзил: Google Directions орқали йўл масофаси ва чизиғи.
  Future<void> _calculateRoute() async {
    final dest = _destination;
    if (dest == null) return;
    setState(() {
      _calculating = true;
      _calcError = null;
    });
    try {
      final candidate = RouteCandidate(
        id: 'trip',
        startLat: _origin.latitude,
        startLng: _origin.longitude,
        directionLabel: '',
        directionDegrees: 0,
        distanceKm: 0,
        durationMin: 0,
        stops: [
          RouteStop(
            orderId: 'dest',
            sequence: 0,
            lat: dest.latitude,
            lng: dest.longitude,
          ),
        ],
      );
      final result = await _directionsService.fetchDirections(candidate);
      if (!mounted) return;

      final points = _polylineDecoder.decode(result.polyline);
      setState(() {
        _routeKm = result.distanceKm;
        _polylines
          ..clear()
          ..add(Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: AppColors.primaryDark,
            width: 5,
          ));
        _calculating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calculating = false;
        _calcError = 'Масофани ҳисоблаб бўлмади. Қайта уриниб кўринг.';
      });
    }
  }

  // ─────────────────── 2-фаза: навигация ───────────────────
  Future<void> _startNavigation() async {
    if (_routeKm == null) return;
    setState(() {
      _phase = _Phase.navigating;
      _drivenKm = 0;
      _lastPos = null;
      _arrived = false;
      _liveFare = FareCalculator.calculate(distanceKm: 0);
    });
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position p) {
    final cur = LatLng(p.latitude, p.longitude);
    if (_lastPos != null) {
      final d = Geolocator.distanceBetween(
            _lastPos!.latitude,
            _lastPos!.longitude,
            cur.latitude,
            cur.longitude,
          ) /
          1000;
      if (d.isFinite && d > 0) _drivenKm += d;
    }
    _lastPos = cur;

    final dest = _destination;
    double? distToDestM;
    if (dest != null) {
      distToDestM = Geolocator.distanceBetween(
        cur.latitude,
        cur.longitude,
        dest.latitude,
        dest.longitude,
      );
    }
    final remaining =
        _routeKm == null ? 0.0 : (_routeKm! - _drivenKm).clamp(0.0, _routeKm!);
    final arrived =
        (distToDestM != null && distToDestM <= 60) || remaining <= 0.15;

    if (!mounted) return;
    setState(() {
      _liveFare = FareCalculator.calculate(distanceKm: _drivenKm);
      _arrived = arrived;
    });
  }

  Set<Marker> _markers() {
    final set = <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position: _origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Йўловчи'),
      ),
    };
    if (_destination != null) {
      set.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destination!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Манзил'),
      ));
    }
    return set;
  }

  Future<void> _onFinishTrip() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      widget.onFinish(_liveFare);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final passengerName =
        ride.userName.trim().isNotEmpty ? ride.userName.trim() : ride.userPhone;
    final baseFare = FareCalculator.baseFare;
    final navigating = _phase == _Phase.navigating;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave != true || !context.mounted) return;
        widget.onCancel();
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: Text(passengerName),
        ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _origin, zoom: 14),
              markers: _markers(),
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (c) {
                if (!_mapController.isCompleted) _mapController.complete(c);
              },
              onTap: _onMapTap,
            ),

            // ─── Бошланғич нарх белгиси — фақат 1-фазада ───
            if (!navigating)
              Positioned(
                left: 16,
                bottom: 120,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Бошланғич',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('${formatPrice(baseFare)} сўм',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),

            // ─── Пастки панель ───
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: navigating ? _buildNavPanel() : _buildPickPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1-фаза пастки панели.
  Widget _buildPickPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_destination == null) ...[
          Row(children: [
            const Icon(Icons.touch_app, color: _green, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Йўловчи борадиган манзилни харитада белгиланг',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
          ]),
        ] else if (_calculating) ...[
          const Row(children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Масофа ҳисобланмоқда...'),
          ]),
        ] else if (_calcError != null) ...[
          Row(children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_calcError!,
                  style: TextStyle(color: Colors.red.shade700)),
            ),
            TextButton(
                onPressed: _calculateRoute, child: const Text('Қайта')),
          ]),
        ] else if (_routeKm != null) ...[
          Row(
            children: [
              const Icon(Icons.navigation, color: _green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Манзилга — ${_routeKm!.toStringAsFixed(1)} км',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _destination = null;
                  _polylines.clear();
                  _routeKm = null;
                }),
                child: const Text('Ўзгартириш'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startNavigation,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.navigation),
              label: const Text('Навигацияни бошлаш'),
            ),
          ),
        ],
      ],
    );
  }

  // 2-фаза пастки панели.
  Widget _buildNavPanel() {
    final remaining =
        _routeKm == null ? 0.0 : (_routeKm! - _drivenKm).clamp(0.0, _routeKm!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(_arrived ? Icons.flag : Icons.navigation,
              color: _green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _arrived
                  ? 'Етиб келдингиз'
                  : 'Манзилга — ${remaining.toStringAsFixed(1)} км қолди',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Жорий йўлкира (${_drivenKm.toStringAsFixed(1)} км)',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                  Text('${formatPrice(_liveFare)} сўм',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _green)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _finishing ? null : _onFinishTrip,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
              child: _finishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Якунлаш',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool?> _confirmLeave() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сафардан чиқиш'),
        content: const Text(
            'Сафар ҳали якунланмади. Чиқсангиз, буюртма бекор қилинади. '
            'Чиқишни хоҳлайсизми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа, чиқиш',
                style: TextStyle(color: Color(0xFFB71C1C))),
          ),
        ],
      ),
    );
  }
}
