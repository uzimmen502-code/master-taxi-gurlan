import 'dart:async';

import 'package:flutter/material.dart';
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
/// Харита + бошланғич нарх + манзил танлаш + йўлкира ҳисоби.
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

  /// Йўл масофаси (км) ва ҳисобланган йўлкира.
  double? _distanceKm;
  int? _fare;
  bool _calculating = false;
  String? _calcError;
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
    if (_mapController.isCompleted) {
      _mapController.future.then((c) => c.dispose());
    }
    super.dispose();
  }

  void _onMapTap(LatLng latLng) {
    setState(() {
      _destination = latLng;
      _polylines.clear();
      _distanceKm = null;
      _fare = null;
      _calcError = null;
    });
    _calculateRoute();
  }

  /// Йўловчи → манзил: Google Directions орқали йўл масофаси, маршрут
  /// чизиғи ва йўлкира нархини ҳисоблайди.
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

      final km = result.distanceKm;
      final fare = FareCalculator.calculate(distanceKm: km);

      // Маршрут чизиғи.
      final points = _polylineDecoder.decode(result.polyline);

      setState(() {
        _distanceKm = km;
        _fare = fare;
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

  Set<Marker> _markers() {
    final set = <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position: _origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
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

  /// "Тўловни олдим" — сафарни якунлайди ва ҳайдовчи экранига қайтади.
  Future<void> _onFinishTrip() async {
    final fare = _fare;
    if (fare == null || _finishing) return;
    setState(() => _finishing = true);
    try {
      widget.onFinish(fare);
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave == true && mounted) {
          // Сафарни тугатмасдан чиқиш — бандликни бекор қилиб қайтамиз.
          widget.onCancel();
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: Text(passengerName),
        ),
        body: Stack(
          children: [
            // ─── Харита ───
            GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _origin, zoom: 14),
            markers: _markers(),
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (c) {
              if (!_mapController.isCompleted) _mapController.complete(c);
            },
            onTap: _onMapTap,
          ),

          // ─── Бошланғич нарх (чап паст бурчак, катта ёзув) ───
          Positioned(
            left: 16,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2), blurRadius: 8),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Бошланғич',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('${formatPrice(baseFare)} сўм',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // ─── Пастки панель: манзил танлаш йўриқномаси ───
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Column(
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
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade700),
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
                      Text('Масофа ва нарх ҳисобланмоқда...'),
                    ]),
                  ] else if (_calcError != null) ...[
                    Row(children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_calcError!,
                            style: TextStyle(color: Colors.red.shade700)),
                      ),
                      TextButton(
                          onPressed: _calculateRoute,
                          child: const Text('Қайта')),
                    ]),
                  ] else if (_fare != null) ...[
                    // ─── Йўлкира нархи (катта ёзув) ───
                    if (_distanceKm != null)
                      Text('Масофа: ${_distanceKm!.toStringAsFixed(1)} км',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Йўлкира нархи',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600)),
                              Text('${formatPrice(_fare!)} сўм',
                                  style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: _green)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _finishing
                              ? null
                              : () => setState(() {
                                    _destination = null;
                                    _polylines.clear();
                                    _fare = null;
                                    _distanceKm = null;
                                  }),
                          child: const Text('Ўзгартириш'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _finishing ? null : _onFinishTrip,
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _finishing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle),
                        label: Text(_finishing
                            ? 'Якунланмоқда...'
                            : 'Тўловни олдим — сафарни якунлаш'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Сафарни тугатмасдан чиқишни тасдиқлаш.
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
