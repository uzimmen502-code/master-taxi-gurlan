import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import '../utils/gurlan_places.dart';

class DriverScheduleScreen extends StatefulWidget {
  final String taxiType;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  const DriverScheduleScreen({
    super.key,
    required this.taxiType,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
  });

  @override
  State<DriverScheduleScreen> createState() => _DriverScheduleScreenState();
}

class _DriverScheduleScreenState extends State<DriverScheduleScreen> {
  static const _green = AppColors.success;
  static const _blue  = AppColors.marshrut;

  final _db = FirebaseFirestore.instance;
  bool _isSaving = false;

  String _fromMfy     = '';
  String _fromQuery   = '';
  bool   _showFromSug = false;
  final  _fromSearchCtrl = TextEditingController();

  List<String> _midStops  = [];
  String _midQuery        = '';
  bool   _showMidSug      = false;
  final  _midSearchCtrl   = TextEditingController();

  String _toMfy     = '';
  String _toQuery   = '';
  bool   _showToSug = false;
  final  _toSearchCtrl = TextEditingController();

  String _direction = 'forward';

  final _fromCtrl  = TextEditingController();
  final _toCtrl    = TextEditingController();
  final _priceCtrl = TextEditingController();
  List<String> _fromSug = [];
  List<String> _toSug   = [];
  Timer? _debounce;

  TimeOfDay _startTime = const TimeOfDay(hour: 8,  minute: 0);
  TimeOfDay _endTime   = const TimeOfDay(hour: 18, minute: 0);

  int get _maxSeats =>
      widget.driverCar.toLowerCase().contains('damas') ||
          widget.driverCar.toLowerCase().contains('дамас') ? 6 : 4;
  int _seats = 4;

  @override
  void initState() {
    super.initState();
    _seats = _maxSeats;
    _loadSavedRoute();
    if (widget.taxiType == 'marshrut') _loadStopsFromProfile();
  }

  Future<void> _loadSavedRoute() async {
    if (widget.taxiType == 'marshrut') return;
    final prefs = await SharedPreferences.getInstance();
    final f = prefs.getString('route_from_${widget.taxiType}') ?? '';
    final t = prefs.getString('route_to_${widget.taxiType}')   ?? '';
    if (!mounted) return;
    if (f.isNotEmpty) _fromCtrl.text = f;
    if (t.isNotEmpty) _toCtrl.text   = t;
  }

  Future<void> _loadStopsFromProfile() async {
    final prefs  = await SharedPreferences.getInstance();
    final phone  = prefs.getString('user_phone') ?? '';
    final userId = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (userId.isEmpty) return;
    try {
      final doc = await _db
          .collection('users').doc(userId)
          .collection('driverProfiles').doc('marshrut').get();
      if (!mounted) return;
      if (doc.exists) {
        final stops = List<String>.from(doc.data()?['stops'] ?? []);
        if (stops.length >= 2) {
          setState(() {
            _fromMfy = stops.first;
            _fromSearchCtrl.text = stops.first;
            _toMfy = stops.last;
            _toSearchCtrl.text = stops.last;
            if (stops.length > 2) {
              _midStops = stops.sublist(1, stops.length - 1);
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveRoute() async {
    if (widget.taxiType == 'marshrut') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('route_from_${widget.taxiType}', _fromCtrl.text.trim());
    await prefs.setString('route_to_${widget.taxiType}',   _toCtrl.text.trim());
  }

  @override
  void dispose() {
    _fromSearchCtrl.dispose();
    _midSearchCtrl.dispose();
    _toSearchCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _priceCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String get _dateStr {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _blue)),
        child: child!,
      ),
    );
    if (picked != null) setState(() {
      if (isStart) _startTime = picked;
      else         _endTime   = picked;
    });
  }

  void _onFromChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _fromSug = GurlanPlaces.search(q));
    });
  }

  void _onToChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _toSug = GurlanPlaces.search(q));
    });
  }

  List<String> get _allStops => [
    if (_fromMfy.isNotEmpty) _fromMfy,
    ..._midStops,
    if (_toMfy.isNotEmpty) _toMfy,
  ];

  Future<void> _confirm() async {
    if (widget.taxiType == 'marshrut') {
      if (_fromMfy.isEmpty) { _showError('Бошлангич нуқтани танланг'); return; }
      if (_toMfy.isEmpty)   { _showError('Охирги нуқтани танланг'); return; }
      if (_fromMfy == _toMfy) { _showError('Бошлангич ва охирги нуқта бир хил бўлмасин'); return; }
    } else {
      if (_fromCtrl.text.trim().isEmpty) { _showError('Қаердан манзилини киритинг'); return; }
      if (widget.taxiType != 'alone' && _toCtrl.text.trim().isEmpty) {
        _showError('Қаерга манзилини киритинг'); return;
      }
    }
    if (widget.taxiType == 'intercity' && _priceCtrl.text.trim().isEmpty) {
      _showError('Нархни киритинг'); return;
    }
    if (widget.taxiType == 'alone') {
      final startMin = _startTime.hour * 60 + _startTime.minute;
      final endMin   = _endTime.hour   * 60 + _endTime.minute;
      if (endMin <= startMin) {
        _showError('Тугаш вақти бошланишдан кейин бўлиши керак');
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid   = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (uid.isEmpty) { _showError('Телефон рақами топилмади'); return; }

    // Эски жадвални ўчириш
    try {
      final oldSnap = await _db.collection('schedules')
          .where('driverId', isEqualTo: uid)
          .where('taxiType', isEqualTo: widget.taxiType)
          .where('date',     isEqualTo: _dateStr)
          .where('isActive', isEqualTo: true)
          .get();
      for (final d in oldSnap.docs) {
        await d.reference.update({'isActive': false});
      }
    } catch (_) {}

    setState(() => _isSaving = true);
    try {
      final today    = DateTime.now();
      final midnight = DateTime(today.year, today.month, today.day, 23, 59, 59);
      final stops    = _allStops;

      final Map<String, dynamic> data = {
        'driverId':    uid,
        'driverName':  widget.driverName,
        'driverPhone': widget.driverPhone,
        'car':         widget.driverCar,
        'plate':       widget.driverPlate,
        'taxiType':    widget.taxiType,
        'date':        _dateStr,
        'from': widget.taxiType == 'marshrut' ? _fromMfy : _fromCtrl.text.trim(),
        'to':   widget.taxiType == 'marshrut' ? _toMfy   : _toCtrl.text.trim(),
        'stops':     widget.taxiType == 'marshrut' ? stops : [],
        'direction': widget.taxiType == 'marshrut' ? _direction : '',
        'seats':     _seats,
        'seatsLeft': _seats,
        'isActive':  true,
        'expiresAt': Timestamp.fromDate(midnight),
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (widget.taxiType == 'alone') {
        data['startTime'] = _fmt(_startTime);
        data['endTime']   = _fmt(_endTime);
      }
      if (widget.taxiType == 'intercity') {
        data['price'] = int.tryParse(_priceCtrl.text.trim().replaceAll(' ', '')) ?? 0;
      }

      await _saveRoute();
      final schedRef = await _db.collection('schedules').add(data);

      await _db.collection('queue').doc(uid).set({
        'driverId':    uid,
        'driverName':  widget.driverName,
        'driverPhone': widget.driverPhone,
        'car':         widget.driverCar,
        'plate':       widget.driverPlate,
        'taxiType':    widget.taxiType,
        'from':  widget.taxiType == 'marshrut' ? _fromMfy : _fromCtrl.text.trim(),
        'to':    widget.taxiType == 'marshrut' ? _toMfy   : _toCtrl.text.trim(),
        'stops': widget.taxiType == 'marshrut' ? stops    : [],
        'scheduleId': schedRef.id,
        'seats':      _seats,
        'seatsLeft':  _seats,
        'date':       _dateStr,
        'onlineAt':   FieldValue.serverTimestamp(),
        'isActive':   true,
        'expiresAt':  Timestamp.fromDate(midnight),
      });

      await _db.collection('drivers').doc(uid).update({
        'isAvailable': true,
        'todayFrom':   data['from'],
        'todayTo':     data['to'],
        'seatsLeft':   _seats,
        'updatedAt':   FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Хатолик: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Ишга чиқиш'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _fromSug = []; _toSug = [];
            _showFromSug = false; _showToSug = false; _showMidSug = false;
          });
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _blue.withOpacity(0.2)),
                ),
                child: Row(children: [
                  Text(_taxiEmoji(), style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_taxiLabel(), style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold, color: _blue)),
                    Text('${widget.driverCar} · ${widget.driverPlate}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),

              Row(children: [
                const Icon(Icons.route, color: AppColors.marshrut, size: 20),
                const SizedBox(width: 8),
                Text('ЙЎНАЛИШ', style: TextStyle(
                    fontSize: AppText.titleSmall,
                    fontWeight: FontWeight.bold,
                    color: AppColors.marshrut, letterSpacing: 1.2)),
              ]),
              const SizedBox(height: 12),

              if (widget.taxiType == 'marshrut') ...[
                _buildMarshrutStops(),
                const SizedBox(height: 20),
              ] else ...[
                _addressField(ctrl: _fromCtrl,
                    hint: 'ҚАЕРДАН — МФЙ, бозор, маҳалла...',
                    icon: Icons.circle_outlined, iconColor: Colors.green,
                    onChanged: _onFromChanged),
                if (_fromSug.isNotEmpty) _suggestList(_fromSug, _fromCtrl,
                        () => setState(() => _fromSug = [])),
                const SizedBox(height: 8),
                Center(child: GestureDetector(
                  onTap: () {
                    final tmp = _fromCtrl.text;
                    _fromCtrl.text = _toCtrl.text;
                    _toCtrl.text = tmp;
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.marshrut.withOpacity(0.1), shape: BoxShape.circle,
                      border: Border.all(color: AppColors.marshrut.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.swap_vert, color: AppColors.marshrut, size: 22),
                  ),
                )),
                const SizedBox(height: 8),
                _addressField(ctrl: _toCtrl,
                    hint: 'ҚАЕРГА — МФЙ, бозор, маҳалла...',
                    icon: Icons.location_on, iconColor: Colors.red,
                    onChanged: _onToChanged),
                if (_toSug.isNotEmpty) _suggestList(_toSug, _toCtrl,
                        () => setState(() => _toSug = [])),
                const SizedBox(height: 20),
              ],

              if (widget.taxiType == 'intercity') ...[
                _sectionTitle('💰 Йўлкира нархи (сўм)'),
                const SizedBox(height: 8),
                _textField(ctrl: _priceCtrl, hint: 'Масалан: 150000',
                    icon: Icons.monetization_on_outlined,
                    inputType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly]),
                const SizedBox(height: 20),
              ],

              if (widget.taxiType == 'alone') ...[
                _sectionTitle('🕐 Иш вақти'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _timeCard('Бошланиш', _fmt(_startTime), () => _pickTime(true))),
                  const SizedBox(width: 12),
                  Expanded(child: _timeCard('Тугаш', _fmt(_endTime), () => _pickTime(false))),
                ]),
                const SizedBox(height: 20),
              ],

              _buildSeatsSelector(),
              const SizedBox(height: 24),

              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _confirm,
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 22),
                  label: Text(
                    _isSaving ? 'Сақланмоқда...' : 'ИШГА ЧИҚИШНИ ТАСДИҚЛАЙМАН',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text('Иш санаси ярим тунда автоматик ёпилади',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarshrutStops() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stopLabel('📍 Бошлангич нуқта', required: true),
      const SizedBox(height: 6),
      _mfySearchField(
        ctrl: _fromSearchCtrl, hint: 'МФЙ танланг...', iconColor: Colors.green,
        showSug: _showFromSug, query: _fromQuery,
        onChanged: (q) => setState(() { _fromQuery = q; _showFromSug = q.length >= 2; }),
        onSelected: (v) => setState(() { _fromMfy = v; _fromSearchCtrl.text = v; _showFromSug = false; }),
        onClear: () => setState(() { _fromMfy = ''; _fromSearchCtrl.clear(); _showFromSug = false; }),
      ),
      const SizedBox(height: 16),

      Row(children: [
        _stopLabel('🔵 Оралиқ тўхташ нуқталари', required: false),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
          child: Text('ИХТИЁРИЙ', style: TextStyle(
              fontSize: AppText.labelTiny, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),

      ..._midStops.asMap().entries.map((e) {
        final i = e.key; final stop = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _blue.withOpacity(0.2))),
          child: Row(children: [
            const Icon(Icons.radio_button_unchecked, color: Colors.blueGrey, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(stop, style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w500))),
            GestureDetector(onTap: () => setState(() => _midStops.removeAt(i)),
                child: Icon(Icons.close, size: 16, color: Colors.grey.shade400)),
          ]),
        );
      }),

      _mfySearchField(
        ctrl: _midSearchCtrl, hint: '+ Оралиқ нуқта қўшиш...', iconColor: Colors.blueGrey,
        showSug: _showMidSug, query: _midQuery,
        onChanged: (q) => setState(() { _midQuery = q; _showMidSug = q.length >= 2; }),
        onSelected: (v) {
          if (_midStops.contains(v) || v == _fromMfy || v == _toMfy) {
            _showError('Бу нуқта аллақачон қўшилган'); return;
          }
          setState(() { _midStops.add(v); _midSearchCtrl.clear(); _midQuery = ''; _showMidSug = false; });
        },
        onClear: () => setState(() { _midSearchCtrl.clear(); _midQuery = ''; _showMidSug = false; }),
      ),
      const SizedBox(height: 16),

      _stopLabel('🏁 Охирги нуқта', required: true),
      const SizedBox(height: 6),
      _mfySearchField(
        ctrl: _toSearchCtrl, hint: 'МФЙ танланг...', iconColor: Colors.red,
        showSug: _showToSug, query: _toQuery,
        onChanged: (q) => setState(() { _toQuery = q; _showToSug = q.length >= 2; }),
        onSelected: (v) => setState(() { _toMfy = v; _toSearchCtrl.text = v; _showToSug = false; }),
        onClear: () => setState(() { _toMfy = ''; _toSearchCtrl.clear(); _showToSug = false; }),
      ),

      if (_fromMfy.isNotEmpty && _toMfy.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.06), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _blue.withOpacity(0.15)),
          ),
          child: Row(children: [
            const Icon(Icons.route, color: AppColors.marshrut, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_allStops.join(' → '),
                style: const TextStyle(fontSize: AppText.labelSmall, color: AppColors.marshrut, fontWeight: FontWeight.w600))),
          ]),
        ),
      ],
    ]);
  }

  Widget _stopLabel(String text, {required bool required}) {
    return Row(children: [
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      if (required) ...[const SizedBox(width: 4), const Text('*', style: TextStyle(color: Colors.red, fontSize: 14))],
    ]);
  }

  Widget _mfySearchField({
    required TextEditingController ctrl,
    required String hint, required Color iconColor,
    required bool showSug, required String query,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
    required VoidCallback onClear,
  }) {
    final suggestions = GurlanPlaces.search(query);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ctrl.text.isNotEmpty ? iconColor.withOpacity(0.4) : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: TextField(
          controller: ctrl, onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
            prefixIcon: Icon(Icons.location_on, color: iconColor, size: 18),
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.grey), onPressed: onClear)
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true, fillColor: Colors.white,
          ),
        ),
      ),
      if (showSug && suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6)]),
          child: Column(children: suggestions.map((p) => InkWell(
            onTap: () => onSelected(p),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.location_on, size: 13, color: iconColor),
                  const SizedBox(width: 8),
                  Text(p, style: const TextStyle(fontSize: AppText.bodyMedium)),
                ])),
          )).toList()),
        ),
    ]);
  }

  Widget _addressField({required TextEditingController ctrl,
    required String hint, required IconData icon,
    required Color iconColor, required ValueChanged<String> onChanged}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: TextField(controller: ctrl, onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: iconColor, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.marshrut, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          filled: true, fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _suggestList(List<String> items, TextEditingController ctrl, VoidCallback onDismiss) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: items.map((p) => InkWell(
        onTap: () { ctrl.text = p; onDismiss(); FocusScope.of(context).unfocus(); },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.location_on, size: 14, color: AppColors.marshrut),
              const SizedBox(width: 8),
              Text(p, style: const TextStyle(fontSize: 13)),
            ])),
      )).toList()),
    );
  }

  Widget _buildSeatsSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('💺 Бўш ўринлар сони (максимум $_maxSeats)'),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(
            onTap: () { if (_seats > 1) setState(() => _seats--); },
            child: Container(width: 44, height: 44,
              decoration: BoxDecoration(
                color: _seats > 1 ? const Color(0xFFE3F2FD) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _seats > 1 ? _blue : Colors.grey.shade300),
              ),
              child: Icon(Icons.remove, color: _seats > 1 ? _blue : Colors.grey, size: 20),
            ),
          ),
          const SizedBox(width: 24),
          Column(children: [
            Text('$_seats', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.marshrut)),
            Text('ўрин', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () { if (_seats < _maxSeats) setState(() => _seats++); },
            child: Container(width: 44, height: 44,
              decoration: BoxDecoration(
                color: _seats < _maxSeats ? const Color(0xFFE3F2FD) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _seats < _maxSeats ? _blue : Colors.grey.shade300),
              ),
              child: Icon(Icons.add, color: _seats < _maxSeats ? _blue : Colors.grey, size: 20),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_maxSeats, (i) => i + 1).map((n) {
              final sel = _seats == n;
              return GestureDetector(
                onTap: () => setState(() => _seats = n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: sel ? _blue : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? _blue : Colors.grey.shade300),
                  ),
                  child: Center(child: Text('$n', style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: sel ? Colors.white : Colors.grey.shade600))),
                ),
              );
            }).toList()),
      ]),
    );
  }

  Widget _timeCard(String label, String time, VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: Row(children: [
          const Icon(Icons.access_time, color: AppColors.marshrut, size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            Text(time, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.marshrut)),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
        ]),
      ),
    );
  }

  Widget _textField({required TextEditingController ctrl, required String hint,
    required IconData icon, TextInputType inputType = TextInputType.text,
    List<TextInputFormatter> formatters = const []}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: TextField(controller: ctrl, keyboardType: inputType, inputFormatters: formatters,
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: _blue, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.marshrut, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          filled: true, fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));

  String _taxiEmoji() {
    switch (widget.taxiType) {
      case 'marshrut':  return '🚐';
      case 'intercity': return '🚌';
      default:          return '🚕';
    }
  }

  String _taxiLabel() {
    switch (widget.taxiType) {
      case 'marshrut':  return 'Маршрут такси';
      case 'intercity': return 'Шаҳарлараро такси';
      default:          return 'Маҳаллий такси';
    }
  }
}