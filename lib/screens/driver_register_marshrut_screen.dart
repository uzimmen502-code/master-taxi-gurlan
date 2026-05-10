import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import '../utils/gurlan_places.dart';
import 'driver_panel_marshrut_screen.dart';

class DriverRegisterMarshrutScreen extends StatefulWidget {
  const DriverRegisterMarshrutScreen({super.key});
  @override
  State<DriverRegisterMarshrutScreen> createState() =>
      _DriverRegisterMarshrutScreenState();
}

class _DriverRegisterMarshrutScreenState
    extends State<DriverRegisterMarshrutScreen> {
  static const _color = Color(0xFF00695C);
  final _db = FirebaseFirestore.instance;

  final _carModelCtrl = TextEditingController();
  final _plateCtrl    = TextEditingController();

  // Stops
  String _fromMfy    = '';
  String _fromQuery  = '';
  bool   _showFromSug = false;
  final _fromCtrl    = TextEditingController();

  List<String> _midStops = [];
  String _midQuery       = '';
  bool   _showMidSug     = false;
  final _midCtrl         = TextEditingController();

  String _toMfy    = '';
  String _toQuery  = '';
  bool   _showToSug = false;
  final _toCtrl    = TextEditingController();

  int  _seats    = 4;
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isRegistered = false;

  String _userId    = '';
  String _userName  = '';
  String _userPhone = '';

  String get _dateStr {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _carModelCtrl.dispose();
    _plateCtrl.dispose();
    _fromCtrl.dispose();
    _midCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  int get _maxSeats =>
      _carModelCtrl.text.toLowerCase().contains('damas') ||
          _carModelCtrl.text.toLowerCase().contains('дамас') ? 6 : 4;

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId    = prefs.getString('userId')     ?? '';
    _userName  = prefs.getString('user_name')  ?? '';
    _userPhone = prefs.getString('user_phone') ?? '';

    if (_userId.isEmpty && _userPhone.isNotEmpty) {
      _userId = _userPhone.replaceAll(RegExp(r'[^\d]'), '');
    }

    if (_userId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Аввал профилдан телефон рақамини киритинг'),
          backgroundColor: Colors.red,
        ));
        Navigator.pop(context);
      }
      return;
    }

    // Мавжуд профилни юклаш
    try {
      final doc = await _db
          .collection('users')
          .doc(_userId)
          .collection('driverProfiles')
          .doc('marshrut')
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        final stops = List<String>.from(data['stops'] ?? []);

        setState(() {
          _isRegistered = true;
          _carModelCtrl.text = data['carModel'] ?? '';
          _plateCtrl.text    = data['plate']    ?? '';
          _seats             = (data['seats']   ?? 4) as int;

          if (stops.isNotEmpty) {
            _fromMfy = stops.first;
            _fromCtrl.text = stops.first;
            if (stops.length > 1) {
              _toMfy = stops.last;
              _toCtrl.text = stops.last;
              if (stops.length > 2) {
                _midStops = stops.sublist(1, stops.length - 1);
              }
            }
          }
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  List<String> get _allStops => [
    if (_fromMfy.isNotEmpty) _fromMfy,
    ..._midStops,
    if (_toMfy.isNotEmpty) _toMfy,
  ];

  Future<void> _saveAndStart() async {
    if (_carModelCtrl.text.trim().isEmpty) {
      _snack('Машина маркасини киритинг'); return;
    }
    if (_plateCtrl.text.trim().isEmpty) {
      _snack('Давлат рақамини киритинг'); return;
    }
    if (_fromMfy.isEmpty) {
      _snack('Бошлангич нуқтани танланг'); return;
    }
    if (_toMfy.isEmpty) {
      _snack('Охирги нуқтани танланг'); return;
    }
    if (_fromMfy == _toMfy) {
      _snack('Бошлангич ва охирги нуқта бир хил бўлмасин'); return;
    }

    setState(() => _isSaving = true);
    try {
      final stops = _allStops;
      final dateStr = _dateStr;
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final scheduleId = _db.collection('schedules').doc().id;
      // ─────────────────────────────────────────────────────────
      // 1. ЭСКИ ЖАДВАЛНИ ЎЧИРИШ
      // ─────────────────────────────────────────────────────────
      final oldSnap = await _db.collection('schedules')
          .where('driverId', isEqualTo: _userId)
          .where('date',     isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .get();

      final batch = _db.batch();
      for (final doc in oldSnap.docs) {
        batch.update(doc.reference, {'isActive': false});
      }

      // ─────────────────────────────────────────────────────────
      // 2. DRIVER ПРОФИЛИНИ САҚЛАШ (stops билан)
      // ─────────────────────────────────────────────────────────
      final profileData = {
        'carModel':    _carModelCtrl.text.trim(),
        'plate':       _plateCtrl.text.trim().toUpperCase(),
        'seats':       _seats,
        'stops':       stops,
        'driverName':  _userName,
        'driverPhone': _userPhone,
        'updatedAt':   FieldValue.serverTimestamp(),
      };

      final profRef = _db
          .collection('users')
          .doc(_userId)
          .collection('driverProfiles')
          .doc('marshrut');
      batch.set(profRef, profileData);

      // ─────────────────────────────────────────────────────────
      // 3. DRIVERS КОЛЛЕКЦИЯСИГА САҚЛАШ
      // ─────────────────────────────────────────────────────────
      final driverData = {
        'name':     _userName,
        'phone':    _userPhone,
        'car':      _carModelCtrl.text.trim(),
        'plate':    _plateCtrl.text.trim().toUpperCase(),
        'taxiType': 'marshrut',
        'seats':    _seats,
        'stops':    stops,
        'isOnline': false,
      };

      final driverRef = _db.collection('drivers').doc(_userId);
      batch.set(driverRef, driverData, SetOptions(merge: true));

      // ─────────────────────────────────────────────────────────
      // 4. SCHEDULE (ЖАДВАЛ) ЯРАТИШ ВА АКТИВЛАШТИРИШ
      // ─────────────────────────────────────────────────────────
      final scheduleData = {
        'driverId':    _userId,
        'driverName':  _userName,
        'driverPhone': _userPhone,
        'car':         _carModelCtrl.text.trim(),
        'plate':       _plateCtrl.text.trim().toUpperCase(),
        'taxiType':    'marshrut',
        'date':        dateStr,
        'from':        stops.isNotEmpty ? stops.first : '',
        'to':          stops.isNotEmpty ? stops.last : '',
        'stops':       stops,
        'direction':   'forward',
        'seats':       _seats,
        'seatsLeft':   _seats,
        'isActive':    true,
        'expiresAt':   Timestamp.fromDate(midnight),
        'createdAt':   FieldValue.serverTimestamp(),
      };


      batch.set(_db.collection('schedules').doc(scheduleId), scheduleData);

      // ─────────────────────────────────────────────────────────
      // 5. QUEUE (НАВБАТ) ГА ҚЎШИШ — АВТОМАТИК ОНЛАЙН
      // ─────────────────────────────────────────────────────────
      final queueData = {
        'driverId':    _userId,
        'driverName':  _userName,
        'driverPhone': _userPhone,
        'car':         _carModelCtrl.text.trim(),
        'plate':       _plateCtrl.text.trim().toUpperCase(),
        'taxiType':    'marshrut',
        'from':        stops.isNotEmpty ? stops.first : '',
        'to':          stops.isNotEmpty ? stops.last : '',
        'stops':       stops,
        'direction':   'forward',
        'seats':       _seats,
        'seatsLeft':   _seats,
        'scheduleId':  scheduleId,
        'date':        dateStr,
        'onlineAt':    FieldValue.serverTimestamp(),
        'isActive':    true,
        'expiresAt':   Timestamp.fromDate(midnight),
      };

      final queueRef = _db.collection('queue').doc(_userId);
      batch.set(queueRef, queueData);

      // ─────────────────────────────────────────────────────────
      // 6. ДРИВЕРДА ИШГА ТАЙЁРЛИКНИ БЕЛГИЛАШ
      // ─────────────────────────────────────────────────────────
      batch.update(driverRef, {
        'isAvailable': true,
        'todayFrom':   stops.isNotEmpty ? stops.first : '',
        'todayTo':     stops.isNotEmpty ? stops.last : '',
        'seatsLeft':   _seats,
        'updatedAt':   FieldValue.serverTimestamp(),
      });

      // BATCH COMMIT — ҳаммаси ёки ҳеч бири
      await batch.commit();

      if (!mounted) return;

      // ─────────────────────────────────────────────────────────
      // 7. ТЎҒРИДАН-ТЎҒРИ МАРШРУТ ПАНЕЛИГА ЎТИШ
      // ─────────────────────────────────────────────────────────
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => DriverPanelMarshrutScreen(
          carModel:    _carModelCtrl.text.trim(),
          plate:       _plateCtrl.text.trim().toUpperCase(),
          seats:       _seats,
          stops:       stops,
          driverName:  _userName,
          driverPhone: _userPhone,
          driverId:    _userId,
        ),
      ));

    } catch (e) {
      setState(() => _isSaving = false);
      _snack('Хатолик: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(
        title: Text(_isRegistered
            ? '🚐 Маршрут профили' : '🚐 Маршрут ҳайдовчиси'),
        backgroundColor: _color,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _showFromSug = false;
            _showMidSug  = false;
            _showToSug   = false;
          });
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // Баннер
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00695C), Color(0xFF00897B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    const Text('🚐', style: TextStyle(fontSize: 32)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Маршрут такси ҳайдовчиси',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          Text(
                            _isRegistered
                                ? 'Маълумотларингизни янгиланг'
                                : 'Бир марта киритинг — доим сақланади',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.85)),
                          ),
                        ])),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Машина маълумотлари ──
                _sectionTitle('🚗 Машина маълумотлари'),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Машина'),
                          const SizedBox(height: 6),
                          _field(
                            _carModelCtrl,
                            'Cobalt',
                            onChanged: (_) => setState(() {
                              if (_seats > _maxSeats) _seats = _maxSeats;
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Рақам'),
                          const SizedBox(height: 6),
                          _field(_plateCtrl, '01A123BC'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _label('💺 Ўрин сони (максимум $_maxSeats)'),
                const SizedBox(height: 10),
                _buildSeats(),
                const SizedBox(height: 24),

                // ── Маршрут нуқталари ──
                _sectionTitle('📍 Маршрут нуқталари'),
                const SizedBox(height: 4),
                Text('Бошлангич ва охирги нуқта мажбурий',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 12),

                // Бошлангич нуқта
                _stopLabel('📍 Бошлангич нуқта', required: true),
                const SizedBox(height: 6),
                _mfyField(
                  ctrl:       _fromCtrl,
                  hint:       'МФЙ танланг...',
                  iconColor:  Colors.green,
                  showSug:    _showFromSug,
                  onChanged:  (q) => setState(() {
                    _fromQuery = q; _showFromSug = q.length >= 2;
                  }),
                  onSelected: (v) {
                    setState(() {
                      _fromMfy = v;
                      _fromCtrl.text = v;
                      _showFromSug = false;
                    });
                  },
                  onClear: () {
                    setState(() {
                      _fromMfy = '';
                      _fromCtrl.clear();
                      _showFromSug = false;
                    });
                  },
                  query: _fromQuery,
                ),
                const SizedBox(height: 16),

                // Оралиқ нуқталар
                Row(children: [
                  _stopLabel('🔵 Оралиқ тўхташ нуқталари',
                      required: false),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('ИХТИЁРИЙ',
                        style: TextStyle(
                            fontSize: AppText.labelTiny,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 8),

                // Мавжуд оралиқ нуқталар
                ..._midStops.asMap().entries.map((e) {
                  final i    = e.key;
                  final stop = e.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _color.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.radio_button_unchecked,
                          color: Colors.blueGrey, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(stop,
                          style: const TextStyle(
                              fontSize: AppText.bodyMedium,
                              fontWeight: FontWeight.w500))),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _midStops.removeAt(i)),
                        child: Icon(Icons.close,
                            size: 16,
                            color: Colors.grey.shade400),
                      ),
                    ]),
                  );
                }),

                // Оралиқ нуқта қўшиш
                _mfyField(
                  ctrl:       _midCtrl,
                  hint:       '+ Оралиқ нуқта қўшиш...',
                  iconColor:  Colors.blueGrey,
                  showSug:    _showMidSug,
                  onChanged:  (q) => setState(() {
                    _midQuery = q; _showMidSug = q.length >= 2;
                  }),
                  onSelected: (v) {
                    if (_midStops.contains(v) ||
                        v == _fromMfy || v == _toMfy) {
                      _snack('Бу нуқта аллақачон қўшилган');
                      return;
                    }
                    setState(() {
                      _midStops.add(v);
                      _midCtrl.clear();
                      _midQuery   = '';
                      _showMidSug = false;
                    });
                  },
                  onClear: () => setState(() {
                    _midCtrl.clear();
                    _midQuery   = '';
                    _showMidSug = false;
                  }),
                  query: _midQuery,
                ),
                const SizedBox(height: 16),

                // Охирги нуқта
                _stopLabel('🏁 Охирги нуқта', required: true),
                const SizedBox(height: 6),
                _mfyField(
                  ctrl:       _toCtrl,
                  hint:       'МФЙ танланг...',
                  iconColor:  Colors.red,
                  showSug:    _showToSug,
                  onChanged:  (q) => setState(() {
                    _toQuery = q; _showToSug = q.length >= 2;
                  }),
                  onSelected: (v) {
                    setState(() {
                      _toMfy = v;
                      _toCtrl.text = v;
                      _showToSug = false;
                    });
                  },
                  onClear: () {
                    setState(() {
                      _toMfy = '';
                      _toCtrl.clear();
                      _showToSug = false;
                    });
                  },
                  query: _toQuery,
                ),

                // Маршрут кўриниши
                if (_fromMfy.isNotEmpty && _toMfy.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _color.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.route,
                          color: _color, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        _allStops.join(' → '),
                        style: const TextStyle(
                            fontSize: AppText.labelSmall,
                            color: _color,
                            fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                ],
                const SizedBox(height: 32),

                // ── САҚЛАШ ВА БОШЛАШ ТУГМАСИ (БИРЛАШТИРИЛГАН) ──
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAndStart,
                    icon: _isSaving
                        ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                        : const Icon(Icons.check_circle, size: 22),
                    label: Text(
                      _isSaving
                          ? 'Сақланмоқда...'
                          : _isRegistered
                          ? 'ЯНГИЛАШ ВА БОШЛАШ'
                          : 'САҚЛАШ ВА БОШЛАШ',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ]),
        ),
      ),
    );
  }

  Widget _mfyField({
    required TextEditingController ctrl,
    required String hint,
    required Color iconColor,
    required bool showSug,
    required String query,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
    required VoidCallback onClear,
  }) {
    final suggestions = GurlanPlaces.search(query);
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: ctrl.text.isNotEmpty
                      ? iconColor.withOpacity(0.4)
                      : Colors.grey.shade200),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6)],
            ),
            child: TextField(
              controller: ctrl,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: AppText.bodyMedium),
                prefixIcon: Icon(Icons.location_on,
                    color: iconColor, size: 18),
                suffixIcon: ctrl.text.isNotEmpty
                    ? IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: Colors.grey),
                    onPressed: onClear)
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
          if (showSug && suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6)],
              ),
              child: Column(
                children: suggestions.map((p) => InkWell(
                  onTap: () => onSelected(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.location_on,
                          size: 13, color: iconColor),
                      const SizedBox(width: 8),
                      Text(p, style: const TextStyle(
                          fontSize: AppText.bodyMedium)),
                    ]),
                  ),
                )).toList(),
              ),
            ),
        ]);
  }

  Widget _buildSeats() {
    final max = _maxSeats;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(max, (i) => i + 1).map((n) {
        final sel = _seats == n;
        return GestureDetector(
          onTap: () => setState(() => _seats = n),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: sel ? _color : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: sel ? _color : Colors.grey.shade300),
            ),
            child: Center(child: Text('$n',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: sel
                        ? Colors.white
                        : Colors.grey.shade600))),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800));

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600));

  Widget _stopLabel(String text, {required bool required}) {
    return Row(children: [
      Text(text, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700)),
      if (required) ...[
        const SizedBox(width: 4),
        const Text('*',
            style: TextStyle(color: Colors.red, fontSize: 14)),
      ],
    ]);
  }

  Widget _field(TextEditingController ctrl, String hint,
      {ValueChanged<String>? onChanged}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6)],
      ),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.grey.shade400, fontSize: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 13),
          filled: true, fillColor: Colors.white,
        ),
      ),
    );
  }
}