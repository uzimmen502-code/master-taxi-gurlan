import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchingScreen extends StatefulWidget {
  final String from;
  final String to;
  final String taxiType;

  const SearchingScreen({
    super.key,
    required this.from,
    required this.to,
    required this.taxiType,
  });

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen> {
  static const _blue  = Color(0xFF1565C0);
  static const _green = Color(0xFF2E7D32);

  final _db = FirebaseFirestore.instance;

  String _tripId    = '';
  String _userPhone = '';

  // Цикл: 0=3км, 1=5км, 2=7км
  int _cycle   = 0;
  int _seconds = 20;
  Timer? _timer;

  List<Map<String, dynamic>> _drivers = [];
  bool _isSearching = true;
  bool _isCancelled = false;

  double _fromLat = 0;
  double _fromLng = 0;

  StreamSubscription? _tripSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone') ?? '';

    // GPS олиш
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));
      _fromLat = pos.latitude;
      _fromLng = pos.longitude;
    } catch (_) {}

    // Firestore га trip яратиш
    await _createTrip();

    // Қидирувни бошлаш
    _startCycle();
  }

  Future<void> _createTrip() async {
    try {
      final expiresAt = DateTime.now().add(
          const Duration(minutes: 3));
      final ref = await _db.collection('trips').add({
        'status':    'searching',
        'userPhone': _userPhone,
        'fromAddr':  widget.from,
        'toAddr':    widget.to,
        'fromLat':   _fromLat,
        'fromLng':   _fromLng,
        'taxiType':  widget.taxiType,
        'radiusKm':  3.0,
        'driverId':  '',
        'driverName': '',
        'price':     0,
        'cancelCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
      _tripId = ref.id;

      // Trip статусини тинглаш
      _tripSub = _db.collection('trips')
          .doc(_tripId)
          .snapshots()
          .listen((snap) {
        if (!snap.exists || !mounted) return;
        final status = snap.data()?['status'] ?? '';
        if (status == 'accepted') {
          _onDriverAccepted(snap.data()!);
        }
      });
    } catch (e) {
      _showError('Хатолик: $e');
    }
  }

  void _startCycle() {
    _loadDriversInRadius(_cycleRadius);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds <= 0) {
        _nextCycle();
      }
    });
  }

  double get _cycleRadius {
    switch (_cycle) {
      case 0: return 3.0;
      case 1: return 5.0;
      case 2: return 7.0;
      default: return 7.0;
    }
  }

  void _nextCycle() {
    if (_cycle >= 2) {
      // 3 цикл тугади
      _noDriversFound();
      return;
    }
    _cycle++;
    _seconds = 20;

    // Radius кенгайтириш
    _db.collection('trips').doc(_tripId).update({
      'radiusKm': _cycleRadius,
    });

    _loadDriversInRadius(_cycleRadius);
  }

  Future<void> _loadDriversInRadius(double radiusKm) async {
    if (_fromLat == 0 && _fromLng == 0) return;
    try {
      final snap = await _db.collection('drivers')
          .where('isOnline', isEqualTo: true)
          .where('isBusy',   isEqualTo: false)
          .get();

      final nearby = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final lat  = (data['lat'] ?? 0.0) as double;
        final lng  = (data['lng'] ?? 0.0) as double;
        if (lat == 0 && lng == 0) continue;

        final dist = Geolocator.distanceBetween(
            _fromLat, _fromLng, lat, lng) / 1000;

        if (dist <= radiusKm) {
          nearby.add({
            'id':       doc.id,
            'name':     data['name']  ?? '',
            'car':      data['car']   ?? '',
            'plate':    data['plate'] ?? '',
            'distance': dist,
          });
        }
      }

      // Масофа бўйича сорт
      nearby.sort((a, b) =>
          (a['distance'] as double)
              .compareTo(b['distance'] as double));

      if (mounted) setState(() => _drivers = nearby);
    } catch (_) {}
  }

  void _onDriverAccepted(Map<String, dynamic> data) {
    _timer?.cancel();
    _tripSub?.cancel();
    if (!mounted) return;

    // Мижозга ҳайдовчи маълумотлари кўрсатилади
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('🚕 Ҳайдовчи топилди!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('👤 ${data['driverName'] ?? ''}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('🚗 ${data['driverCar'] ?? ''}  ${data['driverPlate'] ?? ''}',
                style: TextStyle(
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('📍 Яқинлашмоқда...',
                style: TextStyle(
                    color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white),
            child: const Text('ТУШУНДИМ'),
          ),
        ],
      ),
    );
  }

  void _noDriversFound() {
    _timer?.cancel();
    if (mounted) setState(() => _isSearching = false);
    _cancelTrip();
  }

  Future<void> _cancelTrip() async {
    try {
      if (_tripId.isNotEmpty) {
        final phone = _userPhone.replaceAll(RegExp(r'[^\d]'), '');

        await _db.runTransaction((tx) async {
          final userRef = _db.collection('users').doc(phone);
          final userDoc = await tx.get(userRef);

          final cancelCount =
              ((userDoc.data()?['cancelCount'] ?? 0) as int) + 1;

          tx.update(_db.collection('trips').doc(_tripId), {
            'status':      'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          });

          if (cancelCount >= 3) {
            tx.set(userRef, {
              'cancelCount':  0,
              'blockedUntil': Timestamp.fromDate(
                  DateTime.now().add(
                      const Duration(minutes: 30))),
            }, SetOptions(merge: true));
          } else {
            tx.set(userRef, {
              'cancelCount': cancelCount,
            }, SetOptions(merge: true));
          }
        });
      }
    } catch (_) {}
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tripSub?.cancel();
    if (!_isCancelled && _tripId.isNotEmpty) {
      _cancelTrip();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Ҳайдовчи қидирилмоқда'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _isCancelled = true;
            _cancelTrip();
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(children: [

        // ── Қидирув анимацияси ──
        Container(
          color: _blue,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(children: [
            if (_isSearching) ...[
              const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 3),
              const SizedBox(height: 12),
              Text(
                'Radius: ${_cycleRadius.toInt()} км · $_seconds сония',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Цикл ${_cycle + 1} / 3',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
            ] else ...[
              const Icon(Icons.sentiment_dissatisfied,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 8),
              const Text(
                'Ҳозир бўш ҳайдовчи топилмади',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Бироздан кейин қайта уриниб кўринг',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _blue),
                child: const Text('Орқага'),
              ),
            ],
          ]),
        ),

        // ── Манзил ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.circle, size: 10,
                color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.from,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
          ]),
        ),
        if (widget.to.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(children: [
              const Icon(Icons.location_on, size: 10,
                  color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.to,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
            ]),
          ),
        const Divider(height: 1),

        // ── Ҳайдовчилар рўйхати ──
        Expanded(
          child: _drivers.isEmpty
              ? Center(
            child: Text(
              _isSearching
                  ? 'Ҳайдовчилар қидирилмоқда...'
                  : 'Ҳайдовчилар топилмади',
              style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: _drivers.length,
            itemBuilder: (_, i) {
              final d = _drivers[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6)],
                ),
                child: Row(children: [
                  const Text('🚕',
                      style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(d['name'],
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      Text(
                        '${d['car']} · ${d['plate']}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  )),
                  Text(
                    '${(d['distance'] as double).toStringAsFixed(1)} км',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}