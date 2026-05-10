import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CourierScreen extends StatefulWidget {
  const CourierScreen({super.key});
  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  static const _blue   = Color(0xFF1565C0);
  static const _green  = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);

  final _db = FirebaseFirestore.instance;

  String _courierPhone = '';
  String _courierName  = '';
  bool   _isOnline     = false;

  // Маршрут
  Map<String, dynamic>? _activeRoute;
  List<Map<String, dynamic>> _routeOrders = [];
  int _currentOrderIndex = 0;

  // GPS
  StreamSubscription<Position>? _gpsStream;
  LatLng? _currentPos;
  GoogleMapController? _mapCtrl;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _loadCourier();
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadCourier() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _courierPhone = prefs.getString('user_phone') ?? '';
      _courierName  = prefs.getString('user_name')  ?? 'Курьер';
    });
    await _loadActiveRoute();
  }

  Future<void> _loadActiveRoute() async {
    try {
      final uid  = _courierPhone.replaceAll(RegExp(r'[^\d]'), '');
      final snap = await _db.collection('delivery_routes')
          .where('courierId', isEqualTo: uid)
          .where('status',    isEqualTo: 'active')
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        // Кутаётган маршрутлар
        final waiting = await _db.collection('delivery_routes')
            .where('status', isEqualTo: 'ready')
            .limit(1)
            .get();
        if (waiting.docs.isNotEmpty) {
          setState(() => _activeRoute = {
            'id': waiting.docs.first.id,
            ...waiting.docs.first.data(),
          });
        }
        return;
      }

      final route = {'id': snap.docs.first.id, ...snap.docs.first.data()};
      final orderIds = (route['orders'] as List?)?.cast<String>() ?? [];
      final orders   = <Map<String, dynamic>>[];

      for (final orderId in orderIds) {
        final oDoc = await _db.collection('orders').doc(orderId).get();
        if (oDoc.exists) {
          orders.add({'id': orderId, ...oDoc.data()!});
        }
      }

      setState(() {
        _activeRoute       = route;
        _routeOrders       = orders;
        _currentOrderIndex = (route['currentIndex'] as int?) ?? 0;
      });

      _buildMarkers();
    } catch (e) {
      _snack('Хатолик: $e');
    }
  }

  void _buildMarkers() {
    final markers = <Marker>{};
    for (int i = 0; i < _routeOrders.length; i++) {
      final order = _routeOrders[i];
      final lat   = (order['lat'] as num?)?.toDouble();
      final lng   = (order['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final isDone    = i < _currentOrderIndex;
      final isCurrent = i == _currentOrderIndex;

      markers.add(Marker(
        markerId: MarkerId(order['id']),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isDone    ? BitmapDescriptor.hueGreen
              : isCurrent ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueYellow,
        ),
        infoWindow: InfoWindow(
          title: '${i + 1}. ${order['userName'] ?? ''}',
          snippet: order['address'] ?? '',
        ),
      ));
    }
    if (mounted) setState(() => _markers = markers);
  }

  Future<void> _toggleOnline() async {
    final uid = _courierPhone.replaceAll(RegExp(r'[^\d]'), '');
    final newStatus = !_isOnline;
    setState(() => _isOnline = newStatus);

    if (newStatus) {
      // GPS бошлаш
      _gpsStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 20),
      ).listen((pos) async {
        setState(() => _currentPos = LatLng(pos.latitude, pos.longitude));
        try {
          await _db.collection('couriers').doc(uid).set({
            'lat':       pos.latitude,
            'lng':       pos.longitude,
            'isOnline':  true,
            'name':      _courierName,
            'phone':     _courierPhone,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      });

      // Маршрутни олиш
      if (_activeRoute == null) await _loadActiveRoute();

      // Маршрутни ACTIVE қилиш
      if (_activeRoute != null &&
          _activeRoute!['status'] == 'ready') {
        await _db.collection('delivery_routes')
            .doc(_activeRoute!['id']).update({
          'status':    'active',
          'courierId': uid,
          'startedAt': FieldValue.serverTimestamp(),
        });
        await _loadActiveRoute();
      }
    } else {
      _gpsStream?.cancel();
      try {
        await _db.collection('couriers').doc(uid).update({
          'isOnline': false, 'updatedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }

    _snack(newStatus ? '🟢 Онлайн' : '⚫ Оффлайн');
  }

  Future<void> _markDelivered(String orderId) async {
    try {
      await _db.collection('orders').doc(orderId).update({
        'status':      'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
        'courierId':   _courierPhone.replaceAll(RegExp(r'[^\d]'), ''),
      });

      final nextIndex = _currentOrderIndex + 1;
      await _db.collection('delivery_routes')
          .doc(_activeRoute!['id']).update({
        'currentIndex': nextIndex,
      });

      if (nextIndex >= _routeOrders.length) {
        // Барча буюртмалар етказилди
        await _db.collection('delivery_routes')
            .doc(_activeRoute!['id']).update({
          'status':      'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
        setState(() {
          _activeRoute       = null;
          _routeOrders       = [];
          _currentOrderIndex = 0;
        });
        _snack('🎉 Маршрут якунланди!');
      } else {
        setState(() {
          _currentOrderIndex = nextIndex;
          _routeOrders[_routeOrders.indexWhere((o) => o['id'] == orderId)]
          ['status'] = 'delivered';
        });
        _buildMarkers();
        _snack('✅ Етказилди!');
      }
    } catch (e) {
      _snack('Хатолик: $e');
    }
  }

  Future<void> _navigateTo(Map<String, dynamic> order) async {
    final lat = (order['lat'] as num?)?.toDouble();
    final lng = (order['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('🛵 Курьер панели'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Онлайн toggle
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _toggleOnline,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _activeRoute == null
          ? _buildNoRoute()
          : Column(children: [
        // Харита
        SizedBox(
          height: 220,
          child: _currentPos == null
              ? Container(
              color: Colors.grey.shade200,
              child: const Center(
                  child: CircularProgressIndicator()))
              : GoogleMap(
            initialCameraPosition: CameraPosition(
                target: _currentPos!, zoom: 14),
            onMapCreated: (c) => _mapCtrl = c,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
        ),

        // Буюртмалар рўйхати
        Expanded(child: _buildOrdersList()),
      ]),
    );
  }

  Widget _buildNoRoute() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🛵', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        Text(_isOnline
            ? 'Маршрут кутилмоқда...'
            : 'Онлайн бўлинг',
            style: TextStyle(fontSize: 16,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 24),
        if (!_isOnline)
          ElevatedButton.icon(
            onPressed: _toggleOnline,
            icon: const Icon(Icons.play_arrow),
            label: const Text('ИШНИ БОШЛАШ'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          )
        else
          ElevatedButton.icon(
            onPressed: _loadActiveRoute,
            icon: const Icon(Icons.refresh),
            label: const Text('ЯНГИЛАШ'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
      ],
    ));
  }

  Widget _buildOrdersList() {
    return Column(children: [
      // Прогресс
      Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(children: [
          Text('📦 Жами: ${_routeOrders.length} та буюртма',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('✅ ${_currentOrderIndex}/${_routeOrders.length}',
              style: const TextStyle(
                  fontSize: 13, color: _green,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      LinearProgressIndicator(
        value: _routeOrders.isEmpty ? 0
            : _currentOrderIndex / _routeOrders.length,
        backgroundColor: Colors.grey.shade200,
        valueColor: const AlwaysStoppedAnimation<Color>(_green),
      ),

      // Буюртмалар
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _routeOrders.length,
        itemBuilder: (_, i) => _orderCard(i),
      )),
    ]);
  }

  Widget _orderCard(int i) {
    final order    = _routeOrders[i];
    final isDone   = i < _currentOrderIndex;
    final isCurrent = i == _currentOrderIndex;
    final status   = order['status'] as String? ?? 'ready';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDone
            ? Colors.grey.shade50
            : isCurrent ? Colors.white : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone ? Colors.grey.shade200
              : isCurrent ? _green : Colors.grey.shade200,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent ? [BoxShadow(
            color: _green.withOpacity(0.15),
            blurRadius: 8, offset: const Offset(0, 2))] : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 1-қатор: номер + исм + статус
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: isDone ? Colors.grey.shade300
                    : isCurrent ? _green : Colors.orange.shade100,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text('${i+1}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold,
                      color: isDone ? Colors.grey
                          : isCurrent ? Colors.white : _orange))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order['userName'] ?? order['userPhone'] ?? '',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold,
                      color: isDone ? Colors.grey.shade400 : Colors.black87)),
              Text(order['address'] ?? '',
                  style: TextStyle(fontSize: 11,
                      color: Colors.grey.shade500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (isDone)
              const Icon(Icons.check_circle, color: _green, size: 20)
            else if (isCurrent)
              const Icon(Icons.navigation, color: _green, size: 20),
          ]),

          // Маҳсулотлар
          const SizedBox(height: 6),
          Text(
            (order['items'] as List?)
                ?.take(2).map((e) => '${e['name']} ×${e['count']}').join(', ')
                ?? '',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Тугмалар — фақат жорий буюртма учун
          if (isCurrent) Row(children: [
            // Қўнғироқ
            GestureDetector(
              onTap: () async {
                final phone = order['userPhone'] as String? ?? '';
                if (phone.isEmpty) return;
                final url = Uri(scheme: 'tel', path: phone);
                await launchUrl(url,
                    mode: LaunchMode.externalApplication);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: _blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _blue.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.call, color: _blue, size: 14),
                  SizedBox(width: 4),
                  Text('Қўнғироқ', style: TextStyle(
                      fontSize: 11, color: _blue,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            // Навигация
            GestureDetector(
              onTap: () => _navigateTo(order),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: _orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _orange.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.navigation, color: _orange, size: 14),
                  SizedBox(width: 4),
                  Text('Навигация', style: TextStyle(
                      fontSize: 11, color: _orange,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const Spacer(),
            // ЕТКАЗИЛДИ
            ElevatedButton(
              onPressed: () => _markDelivered(order['id']),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
              child: const Text('ЕТКАЗИЛДИ ✅'),
            ),
          ]),
        ]),
      ),
    );
  }
}