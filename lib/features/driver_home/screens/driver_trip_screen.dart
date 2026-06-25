import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/trip_request.dart';
import '../../../utils/fare_calculator.dart';

/// Ҳайдовчи сафар экрани — йўловчи қабул қилингандан кейин.
/// Харита + бошланғич нарх + манзил танлаш + йўлкира ҳисоби.
class DriverTripScreen extends StatefulWidget {
  const DriverTripScreen({
    super.key,
    required this.ride,
    required this.onFinish,
  });

  final TripRequest ride;

  /// Сафар якунлангач чақирилади — `(fare)` узатилади.
  final void Function(int fare) onFinish;

  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  static const _green = AppColors.primaryDark;

  final _mapController = Completer<GoogleMapController>();

  /// Йўловчи жойлашуви (бошланиш нуқтаси).
  late final LatLng _origin;

  /// Ҳайдовчи танлаган манзил (тугаш нуқтаси).
  LatLng? _destination;

  @override
  void initState() {
    super.initState();
    _origin = LatLng(
      widget.ride.fromLat != 0 ? widget.ride.fromLat : 41.4957,
      widget.ride.fromLng != 0 ? widget.ride.fromLng : 60.5822,
    );
  }

  void _onMapTap(LatLng latLng) {
    setState(() => _destination = latLng);
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

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final passengerName =
        ride.userName.trim().isNotEmpty ? ride.userName.trim() : ride.userPhone;
    final baseFare = FareCalculator.baseFare;

    return Scaffold(
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
                  ] else ...[
                    Row(children: [
                      const Icon(Icons.flag, color: Color(0xFFB71C1C),
                          size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Манзил белгиланди. Йўлкира нархини ҳисоблаш '
                          'кейинги қадамда.',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _destination = null),
                        child: const Text('Ўзгартириш'),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
