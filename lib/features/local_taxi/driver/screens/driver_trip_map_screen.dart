import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/price_service.dart';

class DriverTripMapScreen extends StatefulWidget {
  const DriverTripMapScreen({super.key});

  @override
  State<DriverTripMapScreen> createState() => _DriverTripMapScreenState();
}

class _DriverTripMapScreenState extends State<DriverTripMapScreen> {
  GoogleMapController? _mapController;

  bool _isMapMode = true;

  double _distanceKm = 0;
  Position? _lastPos;
  StreamSubscription<Position>? _stream;

  LatLng? _currentLatLng;

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────
  // GPS PERMISSION + START
  // ─────────────────────────────────────
  Future<void> _initGps() async {
    var perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _startTracking();
  }

  // ─────────────────────────────────────
  // TRACKING
  // ─────────────────────────────────────
  void _startTracking() {
    _stream = Geolocator.getPositionStream().listen((pos) {
      final newLatLng = LatLng(pos.latitude, pos.longitude);

      if (_lastPos != null) {
        _distanceKm += Geolocator.distanceBetween(
          _lastPos!.latitude,
          _lastPos!.longitude,
          pos.latitude,
          pos.longitude,
        ) / 1000;
      }

      _lastPos = pos;
      _currentLatLng = newLatLng;

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(newLatLng),
      );

      setState(() {});
    });
  }

  // ─────────────────────────────────────
  // FINISH
  // ─────────────────────────────────────
  void _finishTrip() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final price = PriceService.calculate(distanceKm: _distanceKm);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поездка'),
        actions: [
          IconButton(
            icon: Icon(_isMapMode ? Icons.map : Icons.route),
            onPressed: () {
              setState(() => _isMapMode = !_isMapMode);
            },
          )
        ],
      ),
      body: _currentLatLng == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          // ───────── MAP MODE ─────────
          if (_isMapMode)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentLatLng!,
                zoom: 16,
              ),
              onMapCreated: (c) => _mapController = c,
              myLocationEnabled: true,
              markers: {
                Marker(
                  markerId: const MarkerId('car'),
                  position: _currentLatLng!,
                )
              },
            ),

          // ───────── SIMPLE MODE ─────────
          if (!_isMapMode)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_distanceKm.toStringAsFixed(2)} км',
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${price.toStringAsFixed(0)} сўм',
                    style: const TextStyle(
                        fontSize: 28,
                        color: Colors.green),
                  ),
                ],
              ),
            ),

          // ───────── BOTTOM PANEL ─────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Масофа: ${_distanceKm.toStringAsFixed(2)} км'),
                  Text('Нарх: ${price.toStringAsFixed(0)} сўм'),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _finishTrip,
                      child: const Text('ЯКУНЛАШ'),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}