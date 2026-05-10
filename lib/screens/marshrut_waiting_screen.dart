import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_theme.dart';

class MarshrutWaitingScreen extends StatefulWidget {
  final String pickupMfy;
  final String pickupAddr;
  final String dropoffMfy;
  final List<Map<String, dynamic>> drivers;
  final double? userLat;
  final double? userLng;

  const MarshrutWaitingScreen({
    super.key,
    required this.pickupMfy,
    required this.pickupAddr,
    required this.dropoffMfy,
    required this.drivers,
    this.userLat,
    this.userLng,
  });

  @override
  State<MarshrutWaitingScreen> createState() => _MarshrutWaitingScreenState();
}

class _MarshrutWaitingScreenState extends State<MarshrutWaitingScreen> {
  static const _color      = Color(0xFF0288D1);
  static const _timeoutSec = 15;

  final _db = FirebaseFirestore.instance;

  int _currentIndex = 0;
  int _secondsLeft  = _timeoutSec;
  Timer? _timer;
  StreamSubscription<DocumentSnapshot>? _tripSub;
  String? _activeTripId;
  String _userPhone = '';
  String _userAddr  = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone')   ?? '';
    _userAddr  = prefs.getString('user_address') ?? '';
    if (_userPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Профилдан телефон рақамини киритинг')));
        Navigator.pop(context);
      }
      return;
    }
    _sendToDriver(0);
  }

  Future<void> _sendToDriver(int index) async {
    if (!mounted) return;
    if (index >= widget.drivers.length) {
      _onAllRejected();
      return;
    }

    final driver = widget.drivers[index];

    // ✅ Realtime текширувлар
    try {
      final schedDoc = await _db.collection('schedules').doc(driver['id']).get();
      if (!schedDoc.exists) {
        _moveToNext('Жадвал топилмади');
        return;
      }

      final schedData = schedDoc.data()!;
      final seatsLeft = (schedData['seatsLeft'] ?? 0) as int;
      final direction = schedData['direction'] ?? 'forward';
      final stops = List<String>.from(schedData['stops'] ?? []);

      // Бўш ўрин текшируви
      if (seatsLeft <= 0) {
        _moveToNext('Бу ҳайдовчида ўрин қолмаган');
        return;
      }

      // Йўналиш текшируви
      if (stops.isNotEmpty) {
        final fromIdx = stops.indexOf(widget.pickupMfy);
        final toIdx = stops.indexOf(widget.dropoffMfy);

        if (fromIdx == -1 || toIdx == -1) {
          _moveToNext('Манзил топилмади');
          return;
        }

        final isValid = direction == 'forward'
            ? fromIdx < toIdx
            : fromIdx > toIdx;

        if (!isValid) {
          _moveToNext('Йўналиш тўғри келмади');
          return;
        }
      }
    } catch (_) {
      // Текширувда хатолик — давом этамиз
    }

    setState(() {
      _currentIndex = index;
      _secondsLeft  = _timeoutSec;
    });

    try {
      final tripRef = await _db.collection('trips').add({
        'userPhone':       _userPhone,
        'pickupMfy':       widget.pickupMfy,
        'pickupAddr':      _userAddr,
        'dropoffMfy':      widget.dropoffMfy,
        'taxiType':        'marshrut',
        'status':          'pending',
        'targetDriverId':  driver['driverId'] ?? driver['id'],
        'driverName':      driver['driverName'],
        'driverPhone':     driver['driverPhone'],
        'driverCar':       driver['car'],
        'driverPlate':     driver['plate'],
        'scheduleId':      driver['id'],
        'fare':            driver['price'] ?? 0,
        'userLat':         widget.userLat,
        'userLng':         widget.userLng,
        'driverLat':       driver['lat'],
        'driverLng':       driver['lng'],
        'createdAt':       FieldValue.serverTimestamp(),
        'expiresAt':       Timestamp.fromDate(
            DateTime.now().add(const Duration(seconds: _timeoutSec + 3))),
      });

      _activeTripId = tripRef.id;

      _startTimer();

      _tripSub?.cancel();
      _tripSub = _db.collection('trips').doc(tripRef.id)
          .snapshots().listen(_onTripUpdate);

    } catch (e) {
      if (mounted) _showError('Хатолик: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 0) {
        t.cancel();
        _onTimeout();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _onTripUpdate(DocumentSnapshot snap) {
    if (!mounted || !snap.exists) return;
    final data = snap.data() as Map<String, dynamic>?;
    if (data == null) return;

    final status = data['status'] as String? ?? 'pending';

    if (status == 'accepted') {
      _timer?.cancel();
      _tripSub?.cancel();
      _onAccepted(data);
    } else if (status == 'rejected') {
      _timer?.cancel();
      _moveToNext('Ҳайдовчи рад этди');
    } else if (status == 'no_seats') {
      _timer?.cancel();
      _moveToNext('Бу ҳайдовчида ўрин қолмаган');
    }
  }

  void _onTimeout() async {
    if (_activeTripId != null) {
      try {
        await _db.collection('trips').doc(_activeTripId).update({
          'status': 'expired'});
      } catch (_) {}
    }
    _moveToNext('Ҳайдовчи жавоб бермади');
  }

  void _moveToNext(String reason) {
    if (!mounted) return;
    _tripSub?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$reason — навбатдагини қидирмоқда...'),
      backgroundColor: Colors.orange,
      duration: const Duration(milliseconds: 1500),
    ));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _sendToDriver(_currentIndex + 1);
    });
  }

  void _onAccepted(Map<String, dynamic> trip) {
    if (!mounted) return;
    final phone = trip['driverPhone'] as String? ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 28),
          SizedBox(width: 8),
          Text('Қабул қилинди!',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🚐 Ҳайдовчи маълумоти:'),
              const SizedBox(height: 8),
              Text(trip['driverName'] ?? '',
                  style: const TextStyle(
                      fontSize: AppText.titleSmall,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${trip['driverCar']} • ${trip['driverPlate']}',
                  style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _color.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: _color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Манзил тушунмаса, ҳайдовчига қўнғироқ қилишингиз мумкин',
                    style: TextStyle(
                        fontSize: AppText.bodySmall,
                        color: Colors.grey.shade700),
                  )),
                ]),
              ),
            ]),
        actions: [
          TextButton.icon(
            onPressed: phone.isEmpty ? null : () async {
              try {
                await launchUrl(Uri(scheme: 'tel', path: phone),
                    mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            icon: const Icon(Icons.phone, color: Colors.green, size: 18),
            label: const Text('Қўнғироқ',
                style: TextStyle(color: Colors.green,
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _color, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  void _onAllRejected() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text('Ҳайдовчи топилмади',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: const Text(
            'Афсус, ҳозир ҳайдовчилар банд. Бироз вақтдан кейин уриниб кўринг.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('ОК', style: TextStyle(color: _color)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    if (_activeTripId != null) {
      try {
        await _db.collection('trips').doc(_activeTripId).update({
          'status': 'cancelled'});
      } catch (_) {}
    }

    // ✅ Ghost request protection
    final prefs = await SharedPreferences.getInstance();
    final phone = _userPhone.replaceAll(RegExp(r'[^\d]'), '');
    final cancelCount = (prefs.getInt('cancel_marshrut_$phone') ?? 0) + 1;
    await prefs.setInt('cancel_marshrut_$phone', cancelCount);

    if (cancelCount >= 3) {
      await prefs.setInt('blocked_marshrut_until_$phone',
          DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch);
      await prefs.setInt('cancel_marshrut_$phone', 0);
    }

    if (mounted) Navigator.pop(context);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tripSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = _currentIndex < widget.drivers.length
        ? widget.drivers[_currentIndex] : null;

    return Scaffold(
      backgroundColor: const Color(0xFFE1F5FE),
      body: SafeArea(
        child: Column(children: [
          Container(
            color: const Color(0xFF0277BD),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _cancel,
              ),
              const Expanded(child: Text('Ҳайдовчи қидирилмоқда',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: AppText.titleMedium,
                      fontWeight: FontWeight.bold))),
            ]),
          ),

          Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 140, height: 140,
                    child: CircularProgressIndicator(
                      value: _secondsLeft / _timeoutSec,
                      strokeWidth: 8,
                      backgroundColor: _color.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation(_color),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$_secondsLeft',
                        style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: _color)),
                    const Text('сек',
                        style: TextStyle(
                            fontSize: AppText.bodySmall,
                            color: Colors.grey)),
                  ]),
                ]),
                const SizedBox(height: 32),

                if (driver != null) Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  child: Column(children: [
                    const Text('🚐', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(driver['driverName'] ?? '',
                        style: const TextStyle(
                            fontSize: AppText.titleMedium,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${driver['car']} • ${driver['plate']}',
                        style: TextStyle(
                            fontSize: AppText.bodyMedium,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Ҳайдовчи ${_currentIndex + 1} / '
                          '${widget.drivers.length}',
                          style: TextStyle(
                              fontSize: AppText.bodySmall,
                              color: _color,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                Text('${widget.pickupMfy}${widget.pickupAddr.isNotEmpty ? ", ${widget.pickupAddr}" : ""}\n→ ${widget.dropoffMfy}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: AppText.bodyMedium,
                        color: Colors.grey.shade700,
                        height: 1.5)),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _cancel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('БЕКОР ҚИЛИШ',
                        style: TextStyle(
                            fontSize: AppText.bodyLarge,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ))),
        ]),
      ),
    );
  }
}