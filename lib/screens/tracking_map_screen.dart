import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

import '../core/utils/formatters.dart';

class TrackingMapScreen extends StatefulWidget {
  final Map<String, dynamic> driver;
  final String from;

  const TrackingMapScreen({
    super.key,
    required this.driver,
    required this.from,
  });

  @override
  State<TrackingMapScreen> createState() => _TrackingMapScreenState();
}

class _TrackingMapScreenState extends State<TrackingMapScreen> {
  GoogleMapController? _mapController;
  Timer? _trackingTimer;
  bool _driverArrived = false;
  int _arrivalMinutes = 2;

  // Позициялар
  LatLng _driverPosition = const LatLng(41.3111, 69.2797);
  LatLng _userPosition = const LatLng(41.3211, 69.2697);

  // Маркерлар
  Set<Marker> _markers = {};

  // Полилайнлар
  Set<Polyline> _polylines = {};

  // Маршрут нуқталари
  List<LatLng> _routePoints = [];
  int _currentRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _arrivalMinutes = widget.driver['time'] ?? 2;
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _userPosition = LatLng(position.latitude, position.longitude);
        // Ҳайдовчи позицияси (1 км узоқда)
        _driverPosition = LatLng(
          position.latitude + 0.01,
          position.longitude + 0.01,
        );
        _updateMarkers();
      });

      await _loadRoute();
      _startTracking();
    } catch (e) {
      // Fallback
      setState(() {
        _userPosition = const LatLng(41.3211, 69.2697);
        _driverPosition = const LatLng(41.3111, 69.2797);
        _updateMarkers();
      });
      await _loadRoute();
      _startTracking();
    }
  }

  void _updateMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('user'),
        position: _userPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Сиз'),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: _driverPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: widget.driver['name'] ?? 'Ҳайдовчи'),
      ),
    };
  }

  // Маршрутни юклаш
  Future<void> _loadRoute() async {
    final url = 'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${_driverPosition.latitude},${_driverPosition.longitude}'
        '&destination=${_userPosition.latitude},${_userPosition.longitude}'
        '&key=AIzaSyDVUJcqRLQdKJJXjgMwGzKipPudwKFWMfE';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'].isNotEmpty) {
          final points = data['routes'][0]['overview_polyline']['points'];
          final decoded = _decodePolyline(points);

          // Маршрут нуқталарини сақлаш
          _routePoints = decoded;
          _currentRouteIndex = 0;

          // Ҳайдовчини биринчи нуқтага қўйиш
          if (_routePoints.isNotEmpty) {
            _driverPosition = _routePoints[0];
            _updateMarkers();
          }

          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: decoded,
                color: Colors.blue,
                width: 5,
              ),
            };
          });
        }
      }
    } catch (e) {
      // Маршрут юклаб бўлмади
    }
  }

  // Полилайн декодлаш
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  void _startTracking() {
    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_driverArrived) {
        timer.cancel();
        return;
      }

      // Агар маршрут нуқталари йўқ бўлса, тўғри чизиқ бўйлаб ҳаракат
      if (_routePoints.isEmpty) {
        setState(() {
          final latDiff = (_userPosition.latitude - _driverPosition.latitude) / 20;
          final lngDiff = (_userPosition.longitude - _driverPosition.longitude) / 20;
          _driverPosition = LatLng(
            _driverPosition.latitude + latDiff,
            _driverPosition.longitude + lngDiff,
          );
          _updateMarkers();
        });
      } else {
        // Маршрут бўйлаб ҳаракат
        setState(() {
          if (_currentRouteIndex < _routePoints.length - 1) {
            _currentRouteIndex += 1;
            _driverPosition = _routePoints[_currentRouteIndex];
            _updateMarkers();
          }
        });
      }

      // Етиб келдими?
      final distance = _calculateDistance(_driverPosition, _userPosition);
      if (distance < 50) {
        _driverArrived = true;
        timer.cancel();
        _onDriverArrived();
      }
    });
  }

  double _calculateDistance(LatLng a, LatLng b) {
    final latDiff = (a.latitude - b.latitude) * 111000;
    final lngDiff = (a.longitude - b.longitude) * 111000 * 0.8;
    return (latDiff * latDiff + lngDiff * lngDiff);
  }

  Future<void> _callDriver(String phone) async {
    final url = Uri.parse('tel:${phoneForCall(phone)}');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _cancelRide() {
    _trackingTimer?.cancel();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Буюртмани бекор қилиш'),
        content: const Text('Ишончингиз комилми?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
  }

  void _onDriverArrived() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('✅ ҲАЙДОВЧИ ЕТИБ КЕЛДИ!'),
        content: Text('${widget.driver['name']} етиб келди.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _cancelRide),
        title: const Text('🚕 Ҳайдовчи келмоқда...'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Харита
          Expanded(
            flex: 3,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _driverPosition,
                zoom: 15,
              ),
              onMapCreated: (controller) => _mapController = controller,
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: false,
              zoomControlsEnabled: true,
            ),
          ),
          // Ҳайдовчи маълумотлари
          Container(height: 2, color: Colors.grey[300]),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.local_taxi, size: 28, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.driver['car'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('👤 ${widget.driver['name']}', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(12)),
                      child: Text('⭐ ${widget.driver['rating']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const Divider(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _infoItem(Icons.numbers, widget.driver['plate'] ?? '?', 'Дав. рақами'),
                    _infoItem(Icons.phone, widget.driver['phone'] ?? '?', 'Телефон'),
                    _infoItem(Icons.info, '✅ қабул қилди', 'Ҳолат'),
                  ]),
                  const Spacer(),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _cancelRide, icon: const Icon(Icons.close, size: 18), label: const Text('БЕКОР ҚИЛИШ'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)))),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton.icon(onPressed: () => _callDriver(widget.driver['phone'] ?? ''), icon: const Icon(Icons.call, size: 18), label: const Text('ҚЎНҒИРОҚ'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)))),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String value, String label) {
    return Column(children: [
      Icon(icon, size: 22, color: Colors.grey[600]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ]);
  }
}