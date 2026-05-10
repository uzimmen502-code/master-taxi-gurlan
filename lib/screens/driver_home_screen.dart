import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../l10n/app_localizations.dart';
import '../utils/fare_calculator.dart';
import '../services/background_gps_service.dart';
import 'profile_screen.dart';
import 'driver_schedule_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with SingleTickerProviderStateMixin {

  static const _blue   = Color(0xFF1565C0);
  static const _green  = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);
  static const _red    = Color(0xFFB71C1C);

  // ── Маълумотлар ──
  String _name     = 'Ҳайдовчи';
  String _gender   = 'male';
  String _phone    = '';
  String _carModel = '';
  String _carPlate = '';
  String _taxiType = 'alone';
  String? _driverId;

  // ── Ҳолат ──
  bool _isOnline         = false;
  bool _isBusy           = false;
  bool _hasInternet      = true;
  bool _hasScheduleToday = false;

  // ── Буюртма ──
  List<Map<String, dynamic>> _activeRequests = [];
  Map<String, dynamic>?      _acceptedRide;

  // ── Иш санаси ──
  int _seatsLeft  = 0;
  int _totalSeats = 0;

  // ── Навбат ──
  int _queuePosition = 0;
  List<Map<String, dynamic>> _queueList = [];
  StreamSubscription<QuerySnapshot>? _queueSub;

  // ── Статистика ──
  int _todayTrips    = 0;
  int _todayEarnings = 0;
  int _totalTrips    = 0;

  // ── Streamлар ──
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  StreamSubscription<QuerySnapshot>?            _tripsListener;
  StreamSubscription<Position>?                 _gpsStream;
  StreamSubscription<Position>?                 _driverLocationStream;

  // ── Анимация ──
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  final _db = FirebaseFirestore.instance;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 6)  return 'Яхши тун';
    if (h < 12) return 'Хайрли тонг';
    if (h < 17) return 'Хайрли кун';
    if (h < 21) return 'Хайрли оқшом';
    return 'Яхши кеч';
  }

  String get _honorificName =>
      _gender == 'female' ? '$_name хоним' : 'жаноб $_name';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(_pulseCtrl);
    _loadUser();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _connectSub?.cancel();
    _tripsListener?.cancel();
    _gpsStream?.cancel();
    _driverLocationStream?.cancel();
    _queueSub?.cancel();
    if (_isOnline) _goOfflineInFirestore();
    super.dispose();
  }

  // ══════════════════════════════════════
  // МАЪЛУМОТЛАРНИ ЮКЛАШ
  // ══════════════════════════════════════
  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    setState(() {
      _name     = prefs.getString('user_name')   ?? 'Ҳайдовчи';
      _gender   = prefs.getString('user_gender') ?? 'male';
      _phone    = prefs.getString('user_phone')  ?? '';
      _carModel = prefs.getString('car_model')   ?? '';
      _carPlate = prefs.getString('car_plate')   ?? '';
      _taxiType = prefs.getString('taxi_type')   ?? 'alone';
      _todayTrips    = prefs.getInt('today_trips')    ?? 0;
      _todayEarnings = prefs.getInt('today_earnings') ?? 0;
      _totalTrips    = prefs.getInt('total_trips')    ?? 0;
    });
    _driverId = _phone.replaceAll(RegExp(r'[^\d]'), '');
    await _closeExpiredSchedules();
    await _checkTodaySchedule();
    if (_carModel.isNotEmpty && _driverId!.isNotEmpty) {
      try {
        await _db.collection('drivers').doc(_driverId).set({
          'car':      _carModel,
          'plate':    _carPlate,
          'taxiType': _taxiType,
          'name':     _name,
          'phone':    _phone,
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  void _listenConnectivity() {
    _connectSub = Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() =>
      _hasInternet = !r.contains(ConnectivityResult.none));
    });
  }

  // ══════════════════════════════════════
  // ИШ САНАСИ
  // ══════════════════════════════════════
  Future<void> _checkTodaySchedule() async {
    if (_driverId == null || _driverId!.isEmpty) return;
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final snap = await _db.collection('schedules')
          .where('driverId', isEqualTo: _driverId)
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .limit(1).get();
      if (mounted && snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        setState(() {
          _hasScheduleToday = true;
          _seatsLeft  = (data['seatsLeft'] ?? 0) as int;
          _totalSeats = (data['seats']     ?? 0) as int;
        });
      } else {
        if (mounted) setState(() {
          _hasScheduleToday = false;
          _seatsLeft  = 0;
          _totalSeats = 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _closeExpiredSchedules() async {
    if (_driverId == null || _driverId!.isEmpty) return;
    try {
      final now  = Timestamp.now();
      final snap = await _db.collection('schedules')
          .where('driverId', isEqualTo: _driverId)
          .where('isActive', isEqualTo: true)
          .get();
      final batch = _db.batch();
      bool hasExpired = false;
      for (final doc in snap.docs) {
        final exp = doc.data()['expiresAt'] as Timestamp?;
        if (exp != null && exp.compareTo(now) < 0) {
          batch.update(doc.reference, {'isActive': false});
          hasExpired = true;
        }
      }
      if (hasExpired) {
        await batch.commit();
        await _db.collection('drivers').doc(_driverId).update({
          'isAvailable': false, 'updatedAt': FieldValue.serverTimestamp()});
        if (mounted) setState(() => _hasScheduleToday = false);
      }
    } catch (_) {}
  }

  Future<bool> _isTodayScheduleValid() async {
    if (_driverId == null || _driverId!.isEmpty) return false;
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final snap = await _db.collection('schedules')
          .where('driverId', isEqualTo: _driverId)
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .limit(1).get();
      return snap.docs.isNotEmpty;
    } catch (_) { return false; }
  }

  // ══════════════════════════════════════
  // НАВБАТ ТИЗИМИ
  // ══════════════════════════════════════
  void _listenQueue() {
    _queueSub?.cancel();
    _queueSub = _db.collection('queue')
        .where('taxiType', isEqualTo: _taxiType)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':         d.id,
          'driverName': data['driverName']  ?? '',
          'car':        data['car']         ?? '',
          'from':       data['from']        ?? '',
          'to':         data['to']          ?? '',
          'seatsLeft':  data['seatsLeft']   ?? 0,
          'onlineAt':   data['onlineAt'],
        };
      }).toList();

      list.sort((a, b) {
        final at = a['onlineAt'] as Timestamp?;
        final bt = b['onlineAt'] as Timestamp?;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });

      int pos = 0;
      for (int i = 0; i < list.length; i++) {
        if (list[i]['id'] == _driverId) { pos = i + 1; break; }
      }

      setState(() { _queueList = list; _queuePosition = pos; });

      if (pos > 0 && _driverId != null) {
        SharedPreferences.getInstance().then((p) =>
            p.setInt('last_queue_pos_$_driverId', pos));
      }
    });
  }

  Future<void> _joinQueue(Position? pos) async {
    if (_driverId == null || _driverId!.isEmpty) return;
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';

      final sched = await _db.collection('schedules')
          .where('driverId', isEqualTo: _driverId)
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .limit(1).get();
      if (sched.docs.isEmpty) return;

      final data  = sched.docs.first.data();
      final prefs = await SharedPreferences.getInstance();

      final lastPos  = prefs.getInt('last_queue_pos_$_driverId') ?? 0;
      final lastDate = prefs.getString('last_queue_date_$_driverId') ?? '';
      final isReEntry = lastDate == dateStr && lastPos > 0;

      Timestamp onlineAt;
      if (isReEntry) {
        final queueSnap = await _db.collection('queue')
            .where('taxiType', isEqualTo: _taxiType)
            .where('isActive', isEqualTo: true)
            .get();
        final list = queueSnap.docs
            .map((d) => d.data()['onlineAt'] as Timestamp?)
            .where((t) => t != null).toList()
          ..sort((a, b) => a!.compareTo(b!));
        if (list.length >= lastPos) {
          final refTime = list[lastPos - 1]!.toDate();
          onlineAt = Timestamp.fromDate(
              refTime.add(const Duration(seconds: 1)));
        } else {
          onlineAt = Timestamp.now();
        }
      } else {
        onlineAt = Timestamp.now();
      }

      await _db.collection('queue').doc(_driverId).set({
        'driverId':    _driverId,
        'driverName':  _name,
        'driverPhone': _phone,
        'car':         _carModel,
        'plate':       _carPlate,
        'taxiType':    _taxiType,
        'from':        data['from'] ?? '',
        'to':          data['to']   ?? '',
        'scheduleId':  sched.docs.first.id,
        'seats':       data['seats']     ?? 4,
        'seatsLeft':   data['seatsLeft'] ?? 4,
        'date':        dateStr,
        'onlineAt':    onlineAt,
        'isActive':    true,
        'lat':         pos?.latitude,
        'lng':         pos?.longitude,
      });

      await prefs.setString('last_queue_date_$_driverId', dateStr);
    } catch (_) {}
  }

  Future<void> _leaveQueue() async {
    if (_driverId == null) return;
    try {
      await _db.collection('queue').doc(_driverId)
          .update({'isActive': false});
    } catch (_) {}
  }

  // ══════════════════════════════════════
  // ОНЛАЙН / ОФФЛАЙН
  // ══════════════════════════════════════
  void _toggleOnline() async {
    try {
      await _closeExpiredSchedules();
      final newStatus = !_isOnline;
      if (newStatus) {
        final hasValid = await _isTodayScheduleValid();
        if (!hasValid) {
          if (!mounted) return;
          _showSnack('⚠️ Аввал "ИШНИ БОШЛАШ" ни босинг!', Colors.orange);
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _isOnline = newStatus;
        if (!newStatus) {
          _activeRequests = [];
          _acceptedRide   = null;
          _isBusy         = false;
          _tripsListener?.cancel();
        }
      });
      if (newStatus) {
        await _goOnlineInFirestore();
        _listenToTrips();
      } else {
        await _goOfflineInFirestore();
      }
      if (!mounted) return;
      _showSnack(newStatus ? '🟢 Онлайн' : '⚫ Оффлайн',
          newStatus ? _green : Colors.grey.shade700);
    } catch (e) {
      if (mounted) _showSnack('Хатолик: $e', Colors.red);
    }
  }

  Future<void> _goOnlineInFirestore() async {
    if (_driverId == null || _driverId!.isEmpty) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      Position? pos;
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        try {
          pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 8));
        } catch (_) {}
      }
      await _db.collection('drivers').doc(_driverId).set({
        'name': _name, 'phone': _phone, 'isOnline': true,
        'taxiType': _taxiType,
        'lat': pos?.latitude, 'lng': pos?.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driver_online', true);
      try { await BackgroundGpsService.start(); } catch (_) {}
      _startDriverLocationStream();
      _listenQueue();
      await _joinQueue(pos);
    } catch (_) {}
  }

  Future<void> _goOfflineInFirestore() async {
    if (_driverId == null || _driverId!.isEmpty) return;
    _driverLocationStream?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driver_online', false);
    try { await BackgroundGpsService.stop(); } catch (_) {}
    await _leaveQueue();
    _queueSub?.cancel();
    try {
      await _db.collection('drivers').doc(_driverId).update({
        'isOnline': false, 'lat': null, 'lng': null,
        'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  void _startDriverLocationStream() {
    _driverLocationStream?.cancel();
    _driverLocationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((pos) async {
      if (_driverId == null || !_isOnline) return;
      try {
        await _db.collection('drivers').doc(_driverId).update({
          'lat': pos.latitude, 'lng': pos.longitude,
          'updatedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    });
  }

  // ══════════════════════════════════════
  // TRIPS LISTENER
  // ══════════════════════════════════════
  void _listenToTrips() {
    _tripsListener?.cancel();
    _tripsListener = _db.collection('trips')
        .where('status', whereIn: ['searching', 'pending'])
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final now  = DateTime.now();
      final list = snap.docs.where((d) {
        final data      = d.data();
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          final age = now.difference(createdAt.toDate());
          if (age.inMinutes >= 3) return false;
        }
        if (data['taxiType'] == 'marshrut') {
          final target = data['targetDriverId'];
          if (target != null && target != _driverId) return false;
        }
        return data['taxiType'] == _taxiType ||
            _taxiType == 'both' ||
            (_taxiType == 'alone'     && data['taxiType'] == 'alone') ||
            (_taxiType == 'marshrut'  && data['taxiType'] == 'marshrut') ||
            (_taxiType == 'intercity' && data['taxiType'] == 'intercity');
      }).map((d) {
        final data      = d.data();
        final createdAt = data['createdAt'];
        int secsLeft = 180;
        if (createdAt is Timestamp) {
          final age = now.difference(createdAt.toDate());
          secsLeft = (180 - age.inSeconds).clamp(0, 180);
        }
        return {
          'id':         d.id,
          'name':       data['userPhone']  ?? 'Йўловчи',
          'from':       data['from']       ?? '',
          'to':         data['to']         ?? '',
          'phone':      data['userPhone']  ?? '',
          'type': data['taxiType'] == 'marshrut'  ? '🚐 Маршрут'
              : data['taxiType'] == 'intercity' ? '🚌 Шаҳарлараро'
              : '🚕 Алоҳида',
          'scheduleId': data['scheduleId'] ?? '',
          'secsLeft':   secsLeft,
        };
      }).toList();
      setState(() => _activeRequests = list);
      if (list.isNotEmpty && !_isBusy && _acceptedRide == null) {
        _showRequestDialog(list.first);
      }
    });
  }

  // ══════════════════════════════════════
  // СЎРОВ ДИАЛОГИ
  // ══════════════════════════════════════
  void _showRequestDialog(Map<String, dynamic> ride) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.person_pin, color: _blue, size: 26),
          const SizedBox(width: 8),
          const Text('Янги буюртма!',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              _infoRow('📍 Қаердан:', ride['from']),
              if ((ride['to'] as String).isNotEmpty)
                _infoRow('🏁 Қаерга:', ride['to']),
              _infoRow('📞 Телефон:', ride['phone']),
              _infoRow('🚕 Тури:', ride['type']),
              const SizedBox(height: 8),
              StreamBuilder<int>(
                stream: Stream.periodic(const Duration(seconds: 1),
                        (i) => (ride['secsLeft'] as int) - i)
                    .cast<int>()
                    .take(ride['secsLeft'] as int),
                builder: (ctx, snap) {
                  final secs  = snap.data ?? (ride['secsLeft'] as int);
                  final color = secs > 60 ? _green : secs > 30 ? _orange : _red;
                  final m = secs ~/ 60;
                  final s = secs % 60;
                  return Row(children: [
                    const Icon(Icons.timer, size: 14),
                    const SizedBox(width: 4),
                    Text('$m:${s.toString().padLeft(2,'0')} қолди',
                        style: TextStyle(
                            fontSize: AppText.bodyMedium,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ]);
                },
              ),
            ]),
        actions: [
          IconButton(
            onPressed: () async {
              final url = Uri(scheme: 'tel', path: ride['phone']);
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
            icon: const Icon(Icons.call, color: _green, size: 28),
            tooltip: 'Қўнғироқ',
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectRide(ride);
            },
            child: const Text('РАД ЭТИШ',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _acceptRide(ride);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('ҚАБУЛ',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: AppText.bodySmall, color: Colors.grey)),
      const SizedBox(width: 6),
      Flexible(child: Text(value, style: const TextStyle(
          fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600))),
    ]),
  );

  void _rejectRide(Map<String, dynamic> ride) async {
    try {
      await _db.collection('trips').doc(ride['id'] as String).update({
        'status':     'rejected',
        'rejectedBy': _driverId,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ══════════════════════════════════════
  // САФАРНИ ҚАБУЛ ҚИЛИШ
  // ══════════════════════════════════════
  void _acceptRide(Map<String, dynamic> ride) async {
    final tripId     = ride['id']         as String;
    final scheduleId = ride['scheduleId'] as String? ?? '';
    final taxiType   = ride['taxiType']   as String? ?? '';

    try {
      await _db.runTransaction((tx) async {
        final tripRef = _db.collection('trips').doc(tripId);
        final tripDoc = await tx.get(tripRef);
        if (!tripDoc.exists) throw Exception('topilmadi');
        final status = tripDoc.data()?['status'] as String? ?? '';
        if (status != 'searching' && status != 'pending') {
          throw Exception('allaqachon');
        }
        if (taxiType == 'marshrut' && scheduleId.isNotEmpty) {
          final schedRef = _db.collection('schedules').doc(scheduleId);
          final schedDoc = await tx.get(schedRef);
          final seatsLeft = (schedDoc.data()?['seatsLeft'] ?? 0) as int;
          if (seatsLeft <= 0) {
            tx.update(tripRef, {'status': 'no_seats'});
            throw Exception('no_seats');
          }
          tx.update(schedRef, {'seatsLeft': seatsLeft - 1});
        }
        tx.update(tripRef, {
          'status':              'accepted',
          'acceptedDriverId':    _driverId,
          'acceptedDriverName':  _name,
          'acceptedDriverPhone': _phone,
          'acceptedDriverCar':   _carModel,
          'acceptedDriverPlate': _carPlate,
          'acceptedAt':          FieldValue.serverTimestamp(),
        });
      });

      if (taxiType != 'marshrut' && scheduleId.isNotEmpty) {
        await _db.collection('schedules').doc(scheduleId)
            .update({'seatsLeft': FieldValue.increment(-1)});
      }
      if (_driverId != null) {
        await _db.collection('drivers').doc(_driverId)
            .update({'seatsLeft': FieldValue.increment(-1)});
      }

      final newSeats = _seatsLeft - 1;
      if (_driverId != null) {
        if (newSeats <= 0) {
          await _db.collection('queue').doc(_driverId)
              .update({'isActive': false});
        } else {
          await _db.collection('queue').doc(_driverId)
              .update({'seatsLeft': FieldValue.increment(-1)});
        }
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('no_seats')) {
        _showSnack('⚠️ Ўрин қолмаган', Colors.orange);
      } else if (msg.contains('allaqachon')) {
        _showSnack('⚠️ Аллақачон қабул қилинган', Colors.orange);
      }
      return;
    }

    final newSeatsLeft = _seatsLeft - 1;
    setState(() {
      _acceptedRide = ride;
      _isBusy       = true;
      _seatsLeft    = newSeatsLeft.clamp(0, _totalSeats);
      _activeRequests.removeWhere((r) => r['id'] == tripId);
    });

    if (newSeatsLeft <= 0 && mounted) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('БЎШ ЖОЙ ҚОЛМАДИ!',
                style: TextStyle(fontSize: AppText.titleMedium,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('ҲАРАКАТНИ БОШЛАШИНГИЗ МУМКИН!',
                style: const TextStyle(fontSize: AppText.bodyMedium,
                    color: _green, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ]),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    final userPhone = ride['phone'] as String;
    if (userPhone.isNotEmpty) {
      final url = Uri(scheme: 'tel', path: userPhone);
      if (await canLaunchUrl(url)) await launchUrl(url);
    }
  }

  // ══════════════════════════════════════
  // САФАРНИ ЯКУНЛАШ
  // ══════════════════════════════════════
  void _completeRide() {
    if (_acceptedRide == null) return;
    _showFareDialog(_acceptedRide!);
  }

  void _showFareDialog(Map<String, dynamic> ride) {
    double distanceKm = 3.0;
    int    waitMins   = 0;
    bool   isNight    = FareCalculator.isNightTime();
    bool   isHoliday  = false;
    bool   isRainy    = false;
    bool   isUrgent   = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final fare = FareCalculator.calculate(
              distanceKm: distanceKm, waitMinutes: waitMins,
              isNight: isNight, isHoliday: isHoliday,
              isRainy: isRainy, isUrgent: isUrgent);
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.calculate, color: _blue, size: 24),
              SizedBox(width: 8),
              Text('Йўлкира ҳисоблаш'),
            ]),
            content: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              const Align(alignment: Alignment.centerLeft,
                  child: Text('📍 Масофа (км)', style: TextStyle(
                      fontSize: AppText.bodySmall,
                      fontWeight: FontWeight.w600))),
              Row(children: [
                Expanded(child: Slider(
                    value: distanceKm, min: 0.5, max: 60,
                    divisions: 119, activeColor: _blue,
                    onChanged: (v) => setS(() => distanceKm =
                        double.parse(v.toStringAsFixed(1))))),
                SizedBox(width: 50,
                    child: Text(distanceKm.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold))),
              ]),
              const Align(alignment: Alignment.centerLeft,
                  child: Text('⏳ Кутиш (дақ)', style: TextStyle(
                      fontSize: AppText.bodySmall,
                      fontWeight: FontWeight.w600))),
              Row(children: [
                Expanded(child: Slider(
                    value: waitMins.toDouble(), min: 0, max: 30,
                    divisions: 30, activeColor: _orange,
                    onChanged: (v) => setS(() => waitMins = v.round()))),
                SizedBox(width: 50,
                    child: Text('$waitMins дақ',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold))),
              ]),
              const Divider(height: 16),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _coefChip('🌙 Тунги',    isNight,   (v) => setS(() => isNight   = v)),
                _coefChip('🚨 Шошилинч', isUrgent,  (v) => setS(() => isUrgent  = v)),
                _coefChip('🎉 Байрам',   isHoliday, (v) => setS(() => isHoliday = v)),
                _coefChip('🌧 Ёмғир',   isRainy,   (v) => setS(() => isRainy   = v)),
              ]),
              const Divider(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _green.withOpacity(0.3))),
                child: Column(children: [
                  const Text('💰 Йўлкира', style: TextStyle(
                      fontSize: AppText.bodyMedium,
                      color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('${FareCalculator.format(fare)} сўм',
                      style: const TextStyle(fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _green)),
                ]),
              ),
            ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Орқага',
                      style: TextStyle(color: Colors.grey))),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _finishRide(ride['id'] as String, fare);
                },
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('ЯКУНЛАШ'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _coefChip(String label, bool selected,
      ValueChanged<bool> onChange) {
    return GestureDetector(
      onTap: () => onChange(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _blue : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(
            fontSize: AppText.labelSmall,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87)),
      ),
    );
  }

  Future<void> _finishRide(String tripId, int fare) async {
    _gpsStream?.cancel();
    try {
      await _db.collection('trips').doc(tripId).update({
        'status': 'completed', 'fare': fare,
        'completedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
    setState(() {
      _todayTrips++;
      _totalTrips++;
      _todayEarnings += fare;
      _acceptedRide  = null;
      _isBusy        = false;
    });
    _saveStats();
    _showSnack(
        '✅ Сафар якунланди! +${FareCalculator.format(fare)} сўм',
        _green);
  }

  void _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_trips',    _todayTrips);
    await prefs.setInt('today_earnings', _todayEarnings);
    await prefs.setInt('total_trips',    _totalTrips);
  }

  // ══════════════════════════════════════
  // БЎШ ЎРИН БОШҚАРУВИ
  // ══════════════════════════════════════
  Future<void> _addPassenger() async {
    if (_driverId == null || _driverId!.isEmpty) return;
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final snap = await _db.collection('schedules')
          .where('driverId', isEqualTo: _driverId)
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .limit(1).get();
      if (snap.docs.isEmpty) return;
      final seatsLeft = (snap.docs.first.data()['seatsLeft'] ?? 1) as int;
      if (seatsLeft <= 0) {
        _showSnack('⚠️ Бўш ўрин йўқ', _orange); return;
      }
      await snap.docs.first.reference.update(
          {'seatsLeft': FieldValue.increment(-1)});
      await _db.collection('drivers').doc(_driverId)
          .update({'seatsLeft': FieldValue.increment(-1)});

      final newSeats = seatsLeft - 1;
      if (newSeats <= 0) {
        await _db.collection('queue').doc(_driverId)
            .update({'isActive': false});
      } else {
        await _db.collection('queue').doc(_driverId)
            .update({'seatsLeft': FieldValue.increment(-1)});
      }

      setState(() => _seatsLeft = (seatsLeft - 1).clamp(0, _totalSeats));
      _showSnack(
          '✅ +1 кўча йўловчи (қолди: ${seatsLeft - 1})', _green);
    } catch (_) {}
  }

  Future<void> _removePassenger() async {
    if (_driverId == null) return;
    if (_seatsLeft >= _totalSeats) {
      _showSnack('Барча ўринлар бўш', _orange); return;
    }
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final snap = await _db.collection('schedules')
          .where('driverId', isEqualTo: _driverId)
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .limit(1).get();
      if (snap.docs.isEmpty) return;
      await snap.docs.first.reference.update(
          {'seatsLeft': FieldValue.increment(1)});
      await _db.collection('drivers').doc(_driverId)
          .update({'seatsLeft': FieldValue.increment(1)});
      await _db.collection('queue').doc(_driverId).set({
        'seatsLeft': FieldValue.increment(1),
        'isActive':  true,
      }, SetOptions(merge: true));
      setState(() => _seatsLeft = (_seatsLeft + 1).clamp(0, _totalSeats));
      _showSnack('✅ Йўловчи камайтирилди', _green);
    } catch (_) {}
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ══════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Column(children: [
          if (!_hasInternet)
            Container(
              color: _red,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: const Row(children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Интернет уланиши йўқ',
                    style: TextStyle(color: Colors.white,
                        fontSize: AppText.bodyMedium)),
              ]),
            ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _buildDriverCard(),
              const SizedBox(height: 16),
              if (_hasScheduleToday) _buildSeatsCard(),
              if (_hasScheduleToday) const SizedBox(height: 16),
              if (_hasScheduleToday) _buildOnlineToggle(),
              if (_hasScheduleToday) const SizedBox(height: 16),
              if (_isBusy && _acceptedRide != null) ...[
                _buildActiveRide(),
                const SizedBox(height: 16),
              ],
              if (_isOnline && _queueList.isNotEmpty) ...[
                _buildQueueCard(),
                const SizedBox(height: 16),
              ],
              _buildMainButtons(),
              const SizedBox(height: 16),
              if (_isOnline && !_isBusy &&
                  _activeRequests.isNotEmpty) ...[
                _buildSectionTitle(
                    '📥 Буюртмалар', _activeRequests.length),
                const SizedBox(height: 8),
                ..._activeRequests.map((r) => _buildRequestCard(r)),
              ],
              const SizedBox(height: 80),
            ]),
          )),
        ]),
      ),
    );
  }

  // ── ҲАЙДОВЧИ КАРТОЧКАСИ ──
  Widget _buildDriverCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _green.withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white.withOpacity(0.2),
          child: Text(
            _name.isNotEmpty ? _name[0] : 'Д',
            style: const TextStyle(fontSize: 24,
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_greeting,', style: const TextStyle(
              fontSize: AppText.labelSmall, color: Colors.white70)),
          Text(_honorificName, style: const TextStyle(
              fontSize: AppText.titleMedium,
              fontWeight: FontWeight.bold, color: Colors.white)),
          if (_carModel.isNotEmpty)
            Text('🚗 $_carModel · $_carPlate',
                style: const TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.white70)),
        ])),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => const ProfileScreen())),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.person,
                color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── БЎШ ЎРИНЛАР ──
  Widget _buildSeatsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _seatsLeft == 0
            ? _red.withOpacity(0.4) : _green.withOpacity(0.3)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Text(_seatsLeft == 0 ? '🚫' : '💺',
            style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _seatsLeft == 0
                ? 'БЎШ ЖОЙ ҚОЛМАДИ — ҲАРАКАТ БОШЛАНГ!'
                : '$_seatsLeft та жой бўш',
            style: TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.bold,
                color: _seatsLeft == 0 ? _red : _green),
          ),
          Text('Жами: $_totalSeats та ўрин',
              style: TextStyle(
                  fontSize: AppText.labelSmall,
                  color: Colors.grey.shade500)),
        ])),
        if (_seatsLeft < _totalSeats)
          GestureDetector(
            onTap: _removePassenger,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Icon(Icons.remove,
                  size: 18, color: Colors.grey),
            ),
          ),
        if (_seatsLeft > 0)
          GestureDetector(
            onTap: _addPassenger,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0xFF2E7D32), Color(0xFF43A047)]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(
                    color: _green.withOpacity(0.3),
                    blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text('+1', style: TextStyle(
                        fontSize: AppText.bodyMedium,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                  ]),
            ),
          ),
      ]),
    );
  }

  // ── ОНЛАЙН TOGGLE ──
  Widget _buildOnlineToggle() {
    return GestureDetector(
      onTap: _toggleOnline,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _isOnline
              ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _isOnline
                  ? _green.withOpacity(0.4) : Colors.grey.shade300,
              width: 1.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: (_isOnline ? _green : Colors.grey)
                      .withOpacity(
                      _isOnline ? _pulseAnim.value * 0.3 : 0.1),
                  shape: BoxShape.circle),
              child: Center(child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: _isOnline ? _green : Colors.grey,
                    shape: BoxShape.circle),
                child: Icon(
                    _isOnline ? Icons.wifi : Icons.wifi_off,
                    color: Colors.white, size: 14),
              )),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
                style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold,
                    color: _isOnline
                        ? _green : Colors.grey.shade600)),
            Text(_isOnline
                ? 'Буюртмалар қабул қилинмоқда'
                : 'Буюртмалар тўхтатилган',
                style: TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.grey.shade500)),
          ])),
          Container(
            width: 52, height: 28,
            decoration: BoxDecoration(
                color: _isOnline ? _green : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(14)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: _isOnline
                  ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(4),
                width: 20, height: 20,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── АСОСИЙ ТУГМАЛАР ──
  Widget _buildMainButtons() {
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: () async {
          final result = await Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => DriverScheduleScreen(
                    taxiType:    _taxiType,
                    driverName:  _name,
                    driverPhone: _phone,
                    driverCar:   _carModel,
                    driverPlate: _carPlate,
                  )));
          if (result == true) await _checkTodaySchedule();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: _green.withOpacity(0.35),
                blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: const Column(children: [
            Icon(Icons.play_circle_fill,
                color: Colors.white, size: 28),
            SizedBox(height: 6),
            Text('ИШНИ БОШЛАШ', style: TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
          ]),
        ),
      )),
      const SizedBox(width: 12),
      Expanded(child: GestureDetector(
        onTap: _hasScheduleToday ? () async {
          if (_driverId == null) return;
          final today   = DateTime.now();
          final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
          final snap = await _db.collection('schedules')
              .where('driverId', isEqualTo: _driverId)
              .where('date',     isEqualTo: dateStr)
              .where('isActive', isEqualTo: true)
              .get();
          final batch = _db.batch();
          for (final doc in snap.docs) {
            batch.update(doc.reference, {'isActive': false});
          }
          await batch.commit();
          await _db.collection('drivers').doc(_driverId).update({
            'isAvailable': false,
            'updatedAt':   FieldValue.serverTimestamp()});
          if (_isOnline) {
            setState(() => _isOnline = false);
            await _goOfflineInFirestore();
          }
          final prefs2 = await SharedPreferences.getInstance();
          await prefs2.setInt('last_queue_pos_$_driverId', 0);
          await prefs2.setString('last_queue_date_$_driverId', '');
          await _checkTodaySchedule();
          _showSnack('✅ Иш тугатилди', _green);
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: _hasScheduleToday
                ? const LinearGradient(colors: [
              Color(0xFF7F0000), Color(0xFFB71C1C)])
                : LinearGradient(colors: [
              Colors.grey.shade300, Colors.grey.shade400]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _hasScheduleToday ? [BoxShadow(
                color: _red.withOpacity(0.35),
                blurRadius: 10, offset: const Offset(0, 4))] : null,
          ),
          child: Column(children: [
            Icon(Icons.stop_circle,
                color: _hasScheduleToday
                    ? Colors.white : Colors.grey.shade600,
                size: 28),
            const SizedBox(height: 6),
            Text('ИШНИ ТУГАТИШ', style: TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.bold,
                color: _hasScheduleToday
                    ? Colors.white : Colors.grey.shade600)),
          ]),
        ),
      )),
    ]);
  }

  // ── НАВБАТ КАРТОЧКАСИ ──
  Widget _buildQueueCard() {
    final myPos = _queuePosition;
    String nextRoute = '';
    if (_queueList.isNotEmpty) {
      final first = _queueList.first;
      final from  = first['from'] as String;
      final to    = first['to']   as String;
      if (to.isNotEmpty) nextRoute = '$to → $from';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withOpacity(0.2)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.queue, color: _blue, size: 18),
                const SizedBox(width: 8),
                const Text('📋 Навбат тизими', style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold)),
                const Spacer(),
                if (myPos > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: myPos == 1 ? _green : _blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      myPos == 1 ? '🥇 Сиз биринчисиз!'
                          : '${myPos}-навбат',
                      style: const TextStyle(
                          fontSize: AppText.labelSmall,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ]),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _queueList.length,
              itemBuilder: (_, i) {
                final q     = _queueList[i];
                final isMe  = q['id'] == _driverId;
                final seats = q['seatsLeft'] as int;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? _green.withOpacity(0.06) : Colors.transparent,
                    border: i < _queueList.length - 1
                        ? Border(bottom: BorderSide(
                        color: Colors.grey.shade100)) : null,
                  ),
                  child: Row(children: [
                    Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: i == 0 ? _green
                            : isMe ? _blue : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: AppText.labelSmall,
                              fontWeight: FontWeight.bold,
                              color: (i == 0 || isMe)
                                  ? Colors.white
                                  : Colors.grey.shade600))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '${q['driverName']} (Сиз)'
                                : q['driverName'],
                            style: TextStyle(
                                fontSize: AppText.bodyMedium,
                                fontWeight: isMe
                                    ? FontWeight.bold : FontWeight.normal,
                                color: isMe ? _green : Colors.black87),
                          ),
                          Text('${q['from']} → ${q['to']}',
                              style: TextStyle(
                                  fontSize: AppText.labelSmall,
                                  color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: seats > 0
                            ? _green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('💺 $seats', style: TextStyle(
                          fontSize: AppText.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: seats > 0 ? _green : Colors.red)),
                    ),
                  ]),
                );
              },
            ),
            if (nextRoute.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Row(children: [
                  const Icon(Icons.swap_horiz, color: _orange, size: 16),
                  const SizedBox(width: 6),
                  Text('Кейинги маршрут: $nextRoute',
                      style: const TextStyle(
                          fontSize: AppText.bodySmall,
                          color: _orange,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
    );
  }

  // ── ФАОЛ САФАР ──
  Widget _buildActiveRide() {
    final ride = _acceptedRide!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _green.withOpacity(0.4), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.directions_car, color: _green, size: 20),
              SizedBox(width: 8),
              Text('Фаол сафар', style: TextStyle(
                  fontSize: AppText.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: _green)),
            ]),
            const SizedBox(height: 10),
            Text('📞 ${ride['phone']}', style: const TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.w600)),
            Text('📍 ${ride['from']} → ${ride['to']}',
                style: TextStyle(
                    fontSize: AppText.bodySmall,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _completeRide,
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('САФАРНИ ЯКУНЛАШ'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ]),
    );
  }

  // ── БУЮРТМА КАРТОЧКАСИ ──
  Widget _buildRequestCard(Map<String, dynamic> ride) {
    final secsLeft = ride['secsLeft'] as int? ?? 180;
    final m     = secsLeft ~/ 60;
    final s     = secsLeft % 60;
    final color = secsLeft > 60 ? _green
        : secsLeft > 30 ? _orange : _red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: secsLeft <= 30
            ? Border.all(
            color: _red.withOpacity(0.4), width: 1.5) : null,
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ride['from'], style: const TextStyle(
              fontSize: AppText.bodyMedium,
              fontWeight: FontWeight.bold)),
          if ((ride['to'] as String).isNotEmpty)
            Text('→ ${ride['to']}', style: TextStyle(
                fontSize: AppText.labelSmall,
                color: Colors.grey.shade500)),
          Text(ride['phone'], style: TextStyle(
              fontSize: AppText.labelSmall,
              color: Colors.grey.shade400)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: color.withOpacity(0.3))),
          child: Column(children: [
            Text('$m:${s.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const Text('⏱',
                style: TextStyle(
                    fontSize: AppText.labelTiny)),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _showRequestDialog(ride),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(10)),
            child: const Text('КЎРИШ', style: TextStyle(
                fontSize: AppText.labelSmall,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(children: [
      Text(title, style: const TextStyle(
          fontSize: AppText.bodyLarge,
          fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: _blue,
            borderRadius: BorderRadius.circular(10)),
        child: Text('$count', style: const TextStyle(
            fontSize: AppText.labelSmall,
            color: Colors.white,
            fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}