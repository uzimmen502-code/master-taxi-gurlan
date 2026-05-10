import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/app_theme.dart';
import 'driver_schedule_screen.dart';
import 'driver_register_marshrut_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DriverPanelMarshrutScreen extends StatefulWidget {
  final String carModel;
  final String plate;
  final int    seats;
  final String driverName;
  final String driverPhone;
  final String driverId;
  final List<String> stops;

  const DriverPanelMarshrutScreen({
    super.key,
    required this.carModel,
    required this.plate,
    required this.seats,
    required this.stops,
    required this.driverName,
    required this.driverPhone,
    required this.driverId,
  });

  @override
  State<DriverPanelMarshrutScreen> createState() =>
      _DriverPanelMarshrutScreenState();
}

class _DriverPanelMarshrutScreenState
    extends State<DriverPanelMarshrutScreen>
    with WidgetsBindingObserver {
  static const _color  = Color(0xFF00695C);
  static const _red    = Color(0xFFB71C1C);
  static const _orange = Color(0xFFE65100);

  final _db = FirebaseFirestore.instance;

  bool _isOnline         = false;
  bool _hasScheduleToday = false;
  bool _dialogShown      = false;
  String? _activeDialogTripId;
  int  _seatsLeft        = 0;
  int  _seatsTotal       = 0;
  String _direction      = 'forward';
  List<String> _stops    = [];
  String? _scheduleId;
  List<Map<String, dynamic>> _requests = [];

  StreamSubscription<QuerySnapshot>? _tripsSub;
  StreamSubscription<QuerySnapshot>? _queueSub;
  int _queuePosition = 0;
  Timer? _heartbeatTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  @override
  void initState() {
    super.initState();
    _stops = List<String>.from(widget.stops);
    _checkTodaySchedule();
    _setupLocalNotifications();                     // ✅ ЯНГИ
    WidgetsBinding.instance.addObserver(this);      // ✅ ЯНГИ
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);  // ✅ ЯНГИ
    _tripsSub?.cancel();
    _queueSub?.cancel();
    _heartbeatTimer?.cancel();
    _connectSub?.cancel();
    if (_isOnline) {
      FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.driverId)
          .update({'isOnline': false, 'updatedAt': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _checkTodaySchedule() async {
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';

      final snap = await _db
          .collection('schedules')
          .where('driverId', isEqualTo: widget.driverId)
          .where('taxiType', isEqualTo: 'marshrut')
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final schedStops = List<String>.from(data['stops'] ?? []);
        setState(() {
          _hasScheduleToday = true;
          _scheduleId       = snap.docs.first.id;
          _seatsLeft        = (data['seatsLeft'] ?? 0) as int;
          _seatsTotal       = widget.seats;
          _direction        = data['direction'] ?? 'forward';
          _stops = schedStops.isNotEmpty ? schedStops : List<String>.from(widget.stops);
        });
      }
    } catch (_) {}
  }

  Future<void> _goOnline() async {
    try {
      Position? pos;
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied)
          perm = await Geolocator.requestPermission();
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 8));
        }
      } catch (_) {}

      await _db.collection('drivers').doc(widget.driverId).set({
        'isOnline':  true,
        'taxiType':  'marshrut',
        'lat':       pos?.latitude,
        'lng':       pos?.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isOnline = true);
      _listenTrips();
      _listenQueue();
      _startHeartbeat();
      _listenConnectivity();
      _snack('🟢 Онлайн', _color);
    } catch (e) {
      _snack('Хатолик: $e', Colors.red);
    }
  }

  Future<void> _goOffline() async {
    _heartbeatTimer?.cancel();
    _connectSub?.cancel();
    try {
      await _db.collection('drivers').doc(widget.driverId).update({
        'isOnline':  false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _db.collection('queue').doc(widget.driverId)
          .update({'isActive': false});
    } catch (_) {}

    _tripsSub?.cancel();
    _queueSub?.cancel();
    if (mounted) setState(() { _isOnline = false; _requests = []; });
  }

  Future<void> _finishTrip() async {
    if (_requests.isNotEmpty) {
      _snack('❗ Аввал буюртмаларни ҳал қилинг', _orange);
      return;
    }

    try {
      final newDir = _direction == 'forward' ? 'backward' : 'forward';
      await _db.collection('drivers').doc(widget.driverId).update({
        'isBusy': false,
        'seatsLeft': _seatsTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (_scheduleId != null) {
        await _db.collection('schedules').doc(_scheduleId).update({
          'direction': newDir,
          'seatsLeft': _seatsTotal,
        });
      }
      await _db.collection('queue').doc(widget.driverId).update({
        'direction': newDir,
        'seatsLeft': _seatsTotal,
        'isActive':  true,
      });

      if (!mounted) return;
      setState(() {
        _direction = newDir;
        _seatsLeft = _seatsTotal;
      });
      _snack('✅ Йўналиш ўзгарди', _color);
    } catch (e) {
      _snack('Хатолик: $e', Colors.red);
    }
  }

  void _listenTrips() {
    _tripsSub?.cancel();
    _tripsSub = _db
        .collection('trips')
        .where('targetDriverId', isEqualTo: widget.driverId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':         d.id,
          'pickupMfy':  data['pickupMfy']  ?? data['from'] ?? '',
          'dropoffMfy': data['dropoffMfy'] ?? data['to']   ?? '',
          'pickupAddr': data['pickupAddr'] ?? '',
          'userPhone':  data['userPhone']  ?? '',
          'createdAt':  data['createdAt'],
        };
      }).toList();

      setState(() => _requests = list);

      // ✅ ЯХШИЛАНГАН: Trip ID билан текшириш
      if (list.isNotEmpty && !_dialogShown) {
        final firstTrip = list.first;
        if (_activeDialogTripId != firstTrip['id']) {
          _showRequestDialog(firstTrip);
        }
      }
    });
  }

  void _listenQueue() {
    _queueSub?.cancel();
    _queueSub = _db
        .collection('queue')
        .where('taxiType', isEqualTo: 'marshrut')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.toList()
        ..sort((a, b) {
          final at = a.data()['onlineAt'] as Timestamp?;
          final bt = b.data()['onlineAt'] as Timestamp?;
          if (at == null) return 1;
          if (bt == null) return -1;
          return at.compareTo(bt);
        });
      int pos = 0;
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == widget.driverId) { pos = i + 1; break; }
      }
      if (mounted) setState(() => _queuePosition = pos);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isOnline) return;
      try {
        await _db.collection('drivers').doc(widget.driverId).update({
          'isOnline':  true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    });
  }

  void _listenConnectivity() {
    _connectSub?.cancel();
    _connectSub = Connectivity()
        .onConnectivityChanged
        .listen((results) async {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline && _isOnline) {
        if (mounted) setState(() => _isOnline = false);
        _snack('📵 Интернет узилди', Colors.orange);
      } else if (!offline && !_isOnline && _hasScheduleToday) {
        await _goOnline();
        _snack('🟢 Уланиш тикланди', _color);
      }
    });
  }
  // ✅ ЯНГИ МЕТОД 1: Local Notifications созлаш
  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        // Notification босилганда — trip'ни текшириш
        if (mounted) _checkPendingTrips();
      },
    );
  }

  // ✅ ЯНГИ МЕТОД 2: Full Screen Notification кўрсатиш
  Future<void> _showFullScreenNotification(Map<String, dynamic> tripData) async {
    await _localNotifications.show(
      DateTime.now().millisecond,
      '🚐 Янги буюртма!',
      '${tripData['pickupMfy'] ?? ''} → ${tripData['dropoffMfy'] ?? ''}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'incoming_ride',
          'Янги буюртма',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
        ),
      ),
    );
  }

  // ✅ ЯНГИ МЕТОД 3: Lifecycle recovery
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isOnline) {
      _checkPendingTrips();
    }
  }

  // ✅ ЯНГИ МЕТОД 4: Pending trip'ларни текшириш
  Future<void> _checkPendingTrips() async {
    try {
      final snap = await _db.collection('trips')
          .where('targetDriverId', isEqualTo: widget.driverId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (snap.docs.isNotEmpty && !_dialogShown) {
        final data = snap.docs.first.data();
        final tripId = snap.docs.first.id;

        if (_activeDialogTripId != tripId) {
          _showRequestDialog({
            'id': tripId,
            'pickupMfy': data['pickupMfy'] ?? '',
            'dropoffMfy': data['dropoffMfy'] ?? '',
            'userPhone': data['userPhone'] ?? '',
            'pickupAddr': data['pickupAddr'] ?? '',
          });
        }
      }
    } catch (_) {}
  }
  void _showRequestDialog(Map<String, dynamic> ride) {
    if (!mounted) return;
    if (_dialogShown && _activeDialogTripId == ride['id']) return;

    setState(() {
      _dialogShown = true;
      _activeDialogTripId = ride['id'];
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.person_pin, color: Color(0xFF00695C), size: 26),
          SizedBox(width: 8),
          Text('Янги буюртма!',
              style: TextStyle(fontSize: AppText.titleMedium)),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('📍 МФЙ:',    ride['pickupMfy']),
              if ((ride['pickupAddr'] as String).isNotEmpty)
                _infoRow('🏠 Манзил:', ride['pickupAddr']),
              _infoRow('🏁 Қаерга:', ride['dropoffMfy']),
              _infoRow('📞 Телефон:', ride['userPhone']),
            ]),
        actions: [
          IconButton(
            onPressed: () async {
              final url = Uri(scheme: 'tel', path: ride['userPhone']);
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
            icon: const Icon(Icons.call, color: Colors.green, size: 28),
          ),

          // ✅ ТУЗАТИЛГАН РАД ТУГМАСИ
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) setState(() {
                _dialogShown = false;
                _activeDialogTripId = null; // ✅ ТОЗАЛАШ
              });
              _rejectRide(ride['id']);
            },
            child: const Text('РАД',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),

          // ✅ ТУЗАТИЛГАН ҚАБУЛ ТУГМАСИ
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) setState(() {
                _dialogShown = false;
                _activeDialogTripId = null; // ✅ ТОЗАЛАШ
              });
              _acceptRide(ride);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('ҚАБУЛ'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: AppText.bodySmall, color: Colors.grey)),
      const SizedBox(width: 6),
      Flexible(
          child: Text(value,
              style: const TextStyle(
                  fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600))),
    ]),
  );

  bool _isValidRoute(String from, String to) {
    final fromIndex = _stops.indexOf(from);
    final toIndex   = _stops.indexOf(to);
    if (fromIndex == -1 || toIndex == -1) return false;
    return _direction == 'forward'
        ? fromIndex < toIndex
        : fromIndex > toIndex;
  }

  Future<void> _acceptRide(Map<String, dynamic> ride) async {
    try {
      final from = ride['pickupMfy'] as String;
      final to   = ride['dropoffMfy'] as String;

      if (!_isValidRoute(from, to)) {
        _snack('❌ Нотўғри маршрут', Colors.red);
        await _rejectRide(ride['id']);
        return;
      }

      await _db.runTransaction((tx) async {
        final tripRef = _db.collection('trips').doc(ride['id']);
        final tripDoc = await tx.get(tripRef);
        if (!tripDoc.exists) return;

        if ((tripDoc.data()?['status'] ?? '') != 'pending') return;

        if (_scheduleId != null) {
          final schedRef = _db.collection('schedules').doc(_scheduleId);
          final schedDoc = await tx.get(schedRef);
          final seats = (schedDoc.data()?['seatsLeft'] ?? 0) as int;
          if (seats <= 0) {
            tx.update(tripRef, {'status': 'no_seats'});
            return;
          }
          tx.update(schedRef, {'seatsLeft': seats - 1});
        }

        tx.update(tripRef, {
          'status':              'accepted',
          'acceptedDriverId':    widget.driverId,
          'acceptedDriverName':  widget.driverName,
          'acceptedDriverPhone': widget.driverPhone,
          'acceptedDriverCar':   widget.carModel,
          'acceptedDriverPlate': widget.plate,
          'acceptedAt':          FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      setState(() {
        _seatsLeft = (_seatsLeft - 1).clamp(0, _seatsTotal);
        _requests.removeWhere((r) => r['id'] == ride['id']);
      });
      _snack('✅ Қабул қилинди', _color);

      final phone = ride['userPhone'] as String;
      if (mounted && phone.isNotEmpty) {
        final url = Uri(scheme: 'tel', path: phone);
        if (await canLaunchUrl(url)) await launchUrl(url);
      }
    } catch (e) {
      _snack('Хатолик: $e', Colors.red);
    }
  }

  Future<void> _rejectRide(String tripId) async {
    try {
      await _db.collection('trips').doc(tripId).update({
        'status':     'rejected',
        'rejectedBy': widget.driverId,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(
        title: const Text('🚐 Маршрут панели'),
        backgroundColor: _color,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'edit') {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const DriverRegisterMarshrutScreen(),
                )).then((_) => _checkTodaySchedule());
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, size: 18, color: Colors.black87),
                  SizedBox(width: 10),
                  Text('Маълумотларни таҳрирлаш'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // ── Ҳайдовчи карточкаси ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00695C), Color(0xFF00897B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: _color.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )],
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: Text(
                  widget.driverName.isNotEmpty ? widget.driverName[0] : 'Д',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.driverName,
                        style: const TextStyle(
                            fontSize: AppText.titleMedium,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text('🚐 ${widget.carModel} · ${widget.plate} · 💺${widget.seats}',
                        style: const TextStyle(
                            fontSize: AppText.labelSmall, color: Colors.white70)),
                  ])),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Жадвал yo'q — boshlash ──
          if (!_hasScheduleToday) ...[
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DriverScheduleScreen(
                      taxiType:    'marshrut',
                      driverName:  widget.driverName,
                      driverPhone: widget.driverPhone,
                      driverCar:   widget.carModel,
                      driverPlate: widget.plate,
                    )));
                if (result == true) _checkTodaySchedule();
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _color.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: _color.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.play_circle_fill,
                        color: Color(0xFF00695C), size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ИШНИ БОШЛАШ',
                            style: TextStyle(
                                fontSize: AppText.bodyLarge,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00695C))),
                        Text('Тўхташ нуқталарини киритинг',
                            style: TextStyle(
                                fontSize: AppText.labelSmall, color: Colors.grey)),
                      ])),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Бугунги маршрут ──
          if (_hasScheduleToday) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _color.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _direction == 'forward'
                      ? '${_stops.isNotEmpty ? _stops.first : ''} → ${_stops.isNotEmpty ? _stops.last : ''}'
                      : '${_stops.isNotEmpty ? _stops.last : ''} → ${_stops.isNotEmpty ? _stops.first : ''}',
                  style: const TextStyle(
                      fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _stops.map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: _color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(s,
                        style: TextStyle(fontSize: AppText.labelTiny, color: _color)),
                  )).toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  _seatsLeft == 0 ? '🚫 Бўш жой йўқ' : '💺 $_seatsLeft та бўш жой',
                  style: TextStyle(
                      fontSize: AppText.bodyMedium,
                      fontWeight: FontWeight.bold,
                      color: _seatsLeft == 0 ? _red : _color),
                ),
                const SizedBox(height: 10),
                Center(
                  child: GestureDetector(
                    onTap: _finishTrip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz, size: 16, color: Colors.black),
                          SizedBox(width: 6),
                          Text('ЙЎНАЛИШНИ ЎЗГАРТИРИШ',
                              style: TextStyle(
                                  fontSize: AppText.labelSmall,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Онлайн toggle ──
            GestureDetector(
              onTap: () async {
                if (_isOnline) await _goOffline();
                else           await _goOnline();
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isOnline ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _isOnline ? _color.withOpacity(0.4) : Colors.grey.shade300,
                      width: 1.5),
                ),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: (_isOnline ? _color : Colors.grey).withOpacity(0.15),
                        shape: BoxShape.circle),
                    child: Icon(
                        _isOnline ? Icons.wifi : Icons.wifi_off,
                        color: _isOnline ? _color : Colors.grey,
                        size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
                            style: TextStyle(
                                fontSize: AppText.bodyLarge,
                                fontWeight: FontWeight.bold,
                                color: _isOnline ? _color : Colors.grey.shade600)),
                        Text(
                          _isOnline
                              ? 'Навбат: $_queuePosition-ўрин'
                              : 'Буюртмалар тўхтатилган',
                          style: TextStyle(
                              fontSize: AppText.labelSmall,
                              color: Colors.grey.shade500),
                        ),
                      ])),
                  Container(
                    width: 52, height: 28,
                    decoration: BoxDecoration(
                        color: _isOnline ? _color : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(14)),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _isOnline ? Alignment.centerRight : Alignment.centerLeft,
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
            ),
            const SizedBox(height: 16),

            // ── Буюртмалар ──
            if (_requests.isNotEmpty) ...[
              Row(children: [
                const Text('📥 Буюртмалар',
                    style: TextStyle(
                        fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: _color, borderRadius: BorderRadius.circular(10)),
                  child: Text('${_requests.length}',
                      style: const TextStyle(
                          fontSize: AppText.labelSmall,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 8),
              ..._requests.map((r) => _buildRequestCard(r)),
            ],
          ],

          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📍 ${ride['pickupMfy']}',
                  style: const TextStyle(
                      fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
              if ((ride['pickupAddr'] as String).isNotEmpty)
                Text('🏠 ${ride['pickupAddr']}',
                    style: TextStyle(
                        fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
              Text('🏁 ${ride['dropoffMfy']}',
                  style: TextStyle(
                      fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
              Text('📞 ${ride['userPhone']}',
                  style: TextStyle(
                      fontSize: AppText.labelSmall, color: Colors.grey.shade400)),
            ])),
        GestureDetector(
          onTap: () => _showRequestDialog(ride),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: _color, borderRadius: BorderRadius.circular(10)),
            child: const Text('КЎРИШ',
                style: TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}