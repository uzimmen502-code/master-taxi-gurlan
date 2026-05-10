import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/gurlan_places.dart';
import 'marshrut_waiting_screen.dart';
import 'driver_register_marshrut_screen.dart';
import 'driver_panel_marshrut_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MarshrutTaxiScreen extends StatefulWidget {
  const MarshrutTaxiScreen({super.key});
  @override
  State<MarshrutTaxiScreen> createState() => _MarshrutTaxiScreenState();
}

class _MarshrutTaxiScreenState extends State<MarshrutTaxiScreen> {
  static const _blue  = Color(0xFF0288D1);
  static const _green = Color(0xFF039BE5);

  final _db = FirebaseFirestore.instance;

  // ✅ ТУЗАТИШ 1: Controller — State darajasida
  final _fromCtrl = TextEditingController();
  final _toCtrl   = TextEditingController();

  String _fromMfy = '';
  String _toMfy   = '';
  bool _showFromDropdown = false;
  bool _showToDropdown   = false;

  Timer? _debounce;

  bool _isSearching = false;
  bool _searched    = false;
  bool _gpsUnavailable = false; // ✅ ТУЗАТИШ 3: GPS holatini ko'rsatish uchun

  double? _userLat;
  double? _userLng;

  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    _getGps();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // ✅ ТУЗАТИШ 1: Controller tozalash
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _getGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsUnavailable = true); // ✅ ТУЗАТИШ 3
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8));
      if (mounted) setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _gpsUnavailable = false;
      });
    } catch (_) {
      if (mounted) setState(() => _gpsUnavailable = true); // ✅ ТУЗАТИШ 3
    }
  }

  // ✅ ТУЗАТИШ 2: dart:math dan foydalanish
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) *
            math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double d) => d * math.pi / 180;

  Future<void> _search() async {
    if (_fromMfy.isEmpty) {
      _snack('Қаердан МФЙ ни танланг'); return;
    }
    if (!mounted) return;
    setState(() { _isSearching = true; _drivers = []; });
    try {
      final today   = DateTime.now();
      final dateStr = '${today.year}-'
          '${today.month.toString().padLeft(2,'0')}-'
          '${today.day.toString().padLeft(2,'0')}';
      final now = Timestamp.now();

      final snap = await _db.collection('schedules')
          .where('taxiType', isEqualTo: 'marshrut')
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .get();

      final list = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data      = doc.data();
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (expiresAt != null && expiresAt.compareTo(now) < 0) continue;

        final seatsLeft = (data['seatsLeft'] ?? 0) as int;
        if (seatsLeft <= 0) continue;

        if (_fromMfy.isNotEmpty && _toMfy.isNotEmpty) {
          final stops = List<String>.from(data['stops'] ?? []);
          if (stops.isEmpty) {
            final from = (data['from'] ?? '').toString().toLowerCase();
            final to   = (data['to']   ?? '').toString().toLowerCase();
            if (!from.contains(_fromMfy.toLowerCase()) &&
                !to.contains(_toMfy.toLowerCase())) continue;
          } else {
            if (!stops.contains(_fromMfy)) continue;
            if (!stops.contains(_toMfy))   continue;
            final fromIdx = stops.indexOf(_fromMfy);
            final toIdx   = stops.indexOf(_toMfy);

// ✅ -1 текшируви
            if (fromIdx == -1 || toIdx == -1) continue;

// ✅ Direction фильтри
            final direction = data['direction'] ?? 'forward';
            final isValidRoute = direction == 'forward'
                ? fromIdx < toIdx
                : fromIdx > toIdx;
            if (!isValidRoute) continue;
          }
        } else if (_fromMfy.isNotEmpty) {
          final stops = List<String>.from(data['stops'] ?? []);
          if (stops.isNotEmpty && !stops.contains(_fromMfy)) continue;
        }

        final dLat = (data['lat'] as num?)?.toDouble();
        final dLng = (data['lng'] as num?)?.toDouble();

        // ✅ ТУЗАТИШ 3: GPS yo'q bo'lsa — distance filtrini o'tkazib yuborish
        if (_userLat != null && _userLng != null &&
            dLat != null && dLng != null) {
          final dist = _haversine(_userLat!, _userLng!, dLat, dLng);
          if (dist > 5) continue;
        }

        int etaMin = 3;
        if (_userLat != null && _userLng != null &&
            dLat != null && dLng != null) {
          final dist = _haversine(_userLat!, _userLng!, dLat, dLng);
          etaMin = (dist / 0.4).round().clamp(1, 60);
        }

        list.add({
          'id':          doc.id,
          'driverId':    data['driverId']    ?? '',
          'driverName':  data['driverName']  ?? 'Ҳайдовчи',
          'driverPhone': data['driverPhone'] ?? '',
          'car':         data['car']         ?? '',
          'plate':       data['plate']       ?? '',
          'from':        data['from']        ?? '',
          'to':          data['to']          ?? '',
          'seatsLeft':   seatsLeft,
          'price':       data['price']       ?? 0,
          'startTime':   data['startTime']   ?? '',
          'etaMin':      etaMin,
          'lat':         dLat,
          'lng':         dLng,
          'onlineAt':    data['onlineAt'] ?? data['createdAt'],
        });
      }

      list.sort((a, b) {
        final aT = a['onlineAt'] as Timestamp?;
        final bT = b['onlineAt'] as Timestamp?;
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        return aT.compareTo(bT);
      });

      if (!mounted) return;
      setState(() {
        _drivers     = list;
        _searched    = true;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      _snack('Хатолик: $e');
    }
  }

  Future<void> _call(String driverPhone, Map<String, dynamic> driver) async {
    if (_fromMfy.isEmpty) {
      _snack('Қаердан МФЙ ни танланг'); return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = (prefs.getString('user_phone') ?? '')
          .replaceAll(RegExp(r'[^\d]'), '');

      if (phone.isNotEmpty) {
        final blockedUntil = prefs.getInt('blocked_marshrut_until_$phone') ?? 0;

        if (blockedUntil > DateTime.now().millisecondsSinceEpoch) {
          final remaining =
              (blockedUntil - DateTime.now().millisecondsSinceEpoch) ~/ 60000;
          if (mounted) {
            _snack('⛔ ${remaining + 1} дақиқадан кейин қайта урининг');
          }
          return; // ← Блокланган — чақирувни тўхтатиш
        }
      }
    } catch (_) {
      // Агар текширувда хатолик бўлса, давом этамиз
    }
    final ordered = <Map<String, dynamic>>[driver];
    for (final d in _drivers) {
      if (d['id'] != driver['id']) ordered.add(d);
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MarshrutWaitingScreen(
        pickupMfy:   _fromMfy,
        pickupAddr: '',
        dropoffMfy:  _toMfy,
        drivers:     ordered,
        userLat:     _userLat,
        userLng:     _userLng,
      ),
    ));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: const Color(0xFF0277BD),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ✅ Debounce — mfyDropdown onQueryChanged ga ulangan
  void _onFromChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _showFromDropdown = q.length >= 2;
      });
    });
  }

  void _onToChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _showToDropdown = q.length >= 2;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE1F5FE),
      appBar: AppBar(
        title: const Text('🚐 Маршрут такси',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0277BD),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () async {
                final prefs  = await SharedPreferences.getInstance();
                final phone  = prefs.getString('user_phone') ?? '';
                final userId = phone.replaceAll(RegExp(r'[^\d]'), '');
                if (userId.isEmpty) {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const DriverRegisterMarshrutScreen()));
                  return;
                }
                final doc = await FirebaseFirestore.instance
                    .collection('users').doc(userId)
                    .collection('driverProfiles').doc('marshrut').get();
                if (!mounted) return;
                if (doc.exists) {
                  final data  = doc.data()!;
                  final stops = List<String>.from(data['stops'] ?? []);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DriverPanelMarshrutScreen(
                      carModel:    data['carModel']    ?? '',
                      plate:       data['plate']       ?? '',
                      seats:       (data['seats']      ?? 4) as int,
                      stops:       stops,
                      driverName:  data['driverName']  ?? '',
                      driverPhone: data['driverPhone'] ?? '',
                      driverId:    userId,
                    ),
                  ));
                } else {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const DriverRegisterMarshrutScreen()));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Ҳайдовчи',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0277BD))),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() { _showFromDropdown = false; _showToDropdown = false; });
        },
        child: Column(children: [
          // ✅ ТУЗАТИШ 3: GPS ogohlantirishbanneri
          if (_gpsUnavailable)
            Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: const Text(
                '📍 GPS аниқланмади — ҳамма ҳайдовчилар кўрсатилмоқда',
                style: TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

          // Манзил киритиш
          Container(
            color: _blue,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(children: [
              const Text('Қаердан',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.white70)),
              const SizedBox(height: 4),
              _mfyDropdown(
                ctrl:     _fromCtrl,
                hint:     'МФЙ танланг...',
                value:    _fromMfy,
                show:     _showFromDropdown,
                icon:     Icons.circle_outlined,
                iconColor: Colors.greenAccent,
                onQueryChanged: (q) {
                  setState(() => _showFromDropdown = q.length >= 2);
                  _onFromChanged(q);
                },
                onSelected: (v) => setState(() {
                  _fromMfy = v;
                  _fromCtrl.text = v;
                  _showFromDropdown = false;
                }),
              ),
              const SizedBox(height: 20),
              const Text('Қаерга',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.white70)),
              const SizedBox(height: 4),
              _mfyDropdown(
                ctrl:     _toCtrl,
                hint:     'МФЙ танланг...',
                value:    _toMfy,
                show:     _showToDropdown,
                icon:     Icons.location_on,
                iconColor: Colors.redAccent,
                onQueryChanged: (q) {
                  setState(() => _showToDropdown = q.length >= 2);
                  _onToChanged(q);
                },
                onSelected: (v) => setState(() {
                  _toMfy = v;
                  _toCtrl.text = v;
                  _showToDropdown = false;
                }),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _search,
                  icon: _isSearching
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, size: 20),
                  label: Text(_isSearching
                      ? 'Қидирилмоқда...' : 'ҲАЙДОВЧИ ҚИДИРИШ',
                      style: const TextStyle(
                          fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _blue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),

          Expanded(child: _buildResults()),
        ]),
      ),
    );
  }

  Widget _buildResults() {
    if (!_searched) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🚐', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text('Манзил киритиб қидиринг',
              style: TextStyle(fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
        ],
      ));
    }
    if (_drivers.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('😔', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('Ҳайдовчи топилмади',
              style: TextStyle(fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
          const SizedBox(height: 6),
          Text('Яқин атрофда мавжуд ҳайдовчи йўқ',
              style: TextStyle(fontSize: AppText.bodySmall, color: Colors.grey.shade400)),
        ],
      ));
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Text('🚐 ${_drivers.length} та машина топилди',
              style: const TextStyle(
                  fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
        ]),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: _drivers.length,
        itemBuilder: (_, i) => _driverCard(_drivers[i]),
      )),
    ]);
  }

  Widget _driverCard(Map<String, dynamic> d) {
    final eta      = d['etaMin'] as int;
    final seats    = d['seatsLeft'] as int;
    final price    = d['price'] as int;
    final etaColor = eta <= 3 ? _green : eta <= 7 ? Colors.orange : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20, backgroundColor: _blue.withOpacity(0.1),
            child: Text(d['driverName'].toString().substring(0, 1),
                style: TextStyle(fontSize: AppText.titleMedium,
                    fontWeight: FontWeight.bold, color: _blue)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['driverName'],
                style: const TextStyle(
                    fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
            Text('🚗 ${d['car']} · ${d['plate']}',
                style: TextStyle(fontSize: AppText.bodySmall,
                    color: Colors.grey.shade500)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: etaColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: etaColor.withOpacity(0.3)),
            ),
            child: Column(children: [
              Text('$eta дақ',
                  style: TextStyle(fontSize: AppText.bodyLarge,
                      fontWeight: FontWeight.bold, color: etaColor)),
              Text('ETA', style: TextStyle(
                  fontSize: AppText.labelTiny, color: etaColor)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.route, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(child: Text(
            '${d['from']} → ${d['to']}',
            style: TextStyle(fontSize: AppText.bodySmall, color: Colors.grey.shade600),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: seats > 0
                    ? _green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text('💺 $seats ўрин',
                style: TextStyle(fontSize: AppText.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: seats > 0 ? _green : Colors.red)),
          ),
          const SizedBox(width: 8),
          if (price > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('💰 $price сўм',
                  style: const TextStyle(fontSize: AppText.labelSmall,
                      fontWeight: FontWeight.w600, color: Colors.orange)),
            ),
          const Spacer(),
          GestureDetector(
            onTap: () => _call(d['driverPhone'], d),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: _green, borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.notifications_active, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('ЧАҚИРИШ', style: TextStyle(
                    fontSize: AppText.bodySmall, fontWeight: FontWeight.bold,
                    color: Colors.white)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  // ✅ ТУЗАТИШ 1: ctrl parametr qo'shildi — tashqaridan beriladi
  Widget _mfyDropdown({
    required TextEditingController ctrl,
    required String hint,
    required String value,
    required bool show,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<String> onQueryChanged,
    required ValueChanged<String> onSelected,
  }) {
    final suggestions = GurlanPlaces.search(ctrl.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: TextField(
          controller: ctrl,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: value.isNotEmpty ? value : hint,
            hintStyle: TextStyle(
                color: value.isNotEmpty ? Colors.black87 : Colors.grey.shade400,
                fontSize: AppText.bodyMedium),
            prefixIcon: Icon(icon, color: iconColor, size: 18),
            suffixIcon: value.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
              onPressed: () {
                ctrl.clear();
                onSelected('');
              },
            )
                : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            filled: true, fillColor: Colors.white,
          ),
        ),
      ),
      if (show && suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.1), blurRadius: 6)]),
          child: Column(
            children: suggestions.map((p) => InkWell(
              onTap: () => onSelected(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.location_on, size: 13, color: _blue),
                  const SizedBox(width: 8),
                  Text(p, style: const TextStyle(fontSize: AppText.bodyMedium)),
                ]),
              ),
            )).toList(),
          ),
        ),
    ]);
  }
}