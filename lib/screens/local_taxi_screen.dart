import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import '../l10n/app_localizations.dart';
import 'map_picker_screen.dart';
import 'searching_screen.dart';
import 'driver_schedule_screen.dart';

class LocalTaxiScreen extends StatefulWidget {
  const LocalTaxiScreen({super.key});

  @override
  State<LocalTaxiScreen> createState() => _LocalTaxiScreenState();
}

class _LocalTaxiScreenState extends State<LocalTaxiScreen> {
  static const _blue1  = Color(0xFFF57F17);
  static const _blue2  = Color(0xFFFF8F00);
  static const _blue3  = Color(0xFFFF8F00);
  static const _green  = Color(0xFF2E7D32);

  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl   = TextEditingController();
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus   = FocusNode();

  List<String> _fromSug = [];
  List<String> _toSug   = [];
  Timer? _debounce;

  String? _taxiType;      // 'alone' | 'marshrut'
  bool _isGpsLoading = false;
  List<Map<String, String>> _savedPlaces = [];

  // ── МФЙ рўйхати: кирилл + лотин жуфт ──
  static const List<Map<String, String>> _mfyList = [
    {"cyrl": "Ёрмиш МФЙ",        "latn": "Yormish MFY"},
    {"cyrl": "Обод МФЙ",          "latn": "Obod MFY"},
    {"cyrl": "Ишонч МФЙ",         "latn": "Ishonch MFY"},
    {"cyrl": "Дўстлик МФЙ",       "latn": "Dostlik MFY"},
    {"cyrl": "Навбаҳор МФЙ",      "latn": "Navbahor MFY"},
    {"cyrl": "Чинобод МФЙ",       "latn": "Chinobod MFY"},
    {"cyrl": "Боғишамол МФЙ",     "latn": "Bogishamol MFY"},
    {"cyrl": "Маърифат МФЙ",      "latn": "Marifat MFY"},
    {"cyrl": "Мевазор МФЙ",       "latn": "Mevazor MFY"},
    {"cyrl": "Дўсимбий МФЙ",      "latn": "Dosimbiy MFY"},
    {"cyrl": "Фидокор МФЙ",       "latn": "Fidokor MFY"},
    {"cyrl": "Навбир-ёп МФЙ",     "latn": "Navbir-yop MFY"},
    {"cyrl": "Нукус МФЙ",         "latn": "Nukus MFY"},
    {"cyrl": "Нурафшон МФЙ",      "latn": "Nurafshon MFY"},
    {"cyrl": "Қатариқ МФЙ",       "latn": "Qatariq MFY"},
    {"cyrl": "Чаккалар МФЙ",      "latn": "Chakkalar MFY"},
    {"cyrl": "Зиёкор МФЙ",        "latn": "Ziyokor MFY"},
    {"cyrl": "Сахтиён МФЙ",       "latn": "Saxtiyon MFY"},
    {"cyrl": "Янги боғ МФЙ",      "latn": "Yangi bog MFY"},
    {"cyrl": "Эсабий МФЙ",        "latn": "Esabiy MFY"},
    {"cyrl": "Қангли МФЙ",        "latn": "Qangli MFY"},
    {"cyrl": "Ватанпарвар МФЙ",   "latn": "Vatanparvar MFY"},
    {"cyrl": "Марбугат МФЙ",      "latn": "Marbugat MFY"},
    {"cyrl": "Бирлашган МФЙ",     "latn": "Birlashgan MFY"},
    {"cyrl": "Гулшан МФЙ",        "latn": "Gulshan MFY"},
    {"cyrl": "Бўзқалъа МФЙ",      "latn": "Bozqala MFY"},
    {"cyrl": "Олчин МФЙ",         "latn": "Olchin MFY"},
    {"cyrl": "Ўйилма МФЙ",        "latn": "Oyilma MFY"},
    {"cyrl": "Деҳқонобод МФЙ",    "latn": "Dehqonobod MFY"},
    {"cyrl": "Тахтакўпир МФЙ",    "latn": "Taxtakopir MFY"},
    {"cyrl": "Мойли МФЙ",         "latn": "Moyli MFY"},
    {"cyrl": "Шанғи МФЙ",         "latn": "Shangi MFY"},
    {"cyrl": "Олға МФЙ",          "latn": "Olga MFY"},
    {"cyrl": "Янги аср МФЙ",      "latn": "Yangi asr MFY"},
    {"cyrl": "Болдоқли МФЙ",      "latn": "Boldoqli MFY"},
    {"cyrl": "Шодлик МФЙ",        "latn": "Shodlik MFY"},
    {"cyrl": "Эшимжирон МФЙ",     "latn": "Eshimjiron MFY"},
    {"cyrl": "Жалойир МФЙ",       "latn": "Jaloyir MFY"},
    {"cyrl": "Пахтачи МФЙ",       "latn": "Paxtachi MFY"},
    {"cyrl": "Нурли йўл МФЙ",     "latn": "Nurli yol MFY"},
    {"cyrl": "Совунчи МФЙ",       "latn": "Sovunchi MFY"},
    {"cyrl": "Пахтакор МФЙ",      "latn": "Paxtakor MFY"},
    {"cyrl": "Деҳқон МФЙ",        "latn": "Dehqon MFY"},
    {"cyrl": "Беш уй МФЙ",        "latn": "Besh uy MFY"},
    {"cyrl": "Боғистон МФЙ",      "latn": "Bogiston MFY"},
    {"cyrl": "Оққум МФЙ",         "latn": "Oqqum MFY"},
    {"cyrl": "Нуробод МФЙ",       "latn": "Nurobod MFY"},
    {"cyrl": "Дўстлик боғи МФЙ",  "latn": "Dostlik bogi MFY"},
  ];

  // ── Қўшимча жойлар (бозор, вокзал...) ──
  static const List<String> _extraPlaces = [
    'Гурлан бозори',
    'Гурлан вокзали',
    'Гурлан туман ҳокимияти',
    'Гурлан туман касалхонаси',
    'Гурлан туман мактаби',
    'Гурлан маркази',
    'Хива', 'Урганч', 'Хонқа', 'Шовот',
    'Янгиариқ', 'Қўшкўпир', 'Боғот', 'Ҳазорасп',
  ];

  // ── Транслитерация: лотин → кирилл (қидирув учун) ──
  static String _toLower(String s) => s.toLowerCase();

  static bool _matches(Map<String, String> mfy, String query) {
    final q = _toLower(query);
    return _toLower(mfy['cyrl']!).contains(q) ||
        _toLower(mfy['latn']!).contains(q) ||
        _toLower(_latinToCyrl(query)).contains(_toLower(mfy['cyrl']!).substring(0, q.length.clamp(0, mfy['cyrl']!.length)));
  }

  // Лотин ҳарфларини кирилл эквивалентига ўхшатиш
  static String _latinToCyrl(String s) {
    return s
        .replaceAll('sh', 'ш').replaceAll('ch', 'ч').replaceAll('yo', 'ё')
        .replaceAll('yu', 'ю').replaceAll('ya', 'я')
        .replaceAll('q', 'қ').replaceAll('x', 'х')
        .replaceAll('a', 'а').replaceAll('b', 'б')
        .replaceAll('d', 'д').replaceAll('e', 'е').replaceAll('f', 'ф')
        .replaceAll('g', 'г').replaceAll('i', 'и').replaceAll('j', 'ж')
        .replaceAll('k', 'к').replaceAll('l', 'л').replaceAll('m', 'м')
        .replaceAll('n', 'н').replaceAll('o', 'о').replaceAll('p', 'п')
        .replaceAll('r', 'р').replaceAll('s', 'с').replaceAll('t', 'т')
        .replaceAll('u', 'у').replaceAll('v', 'в').replaceAll('y', 'й')
        .replaceAll('z', 'з');
  }

  // ── Қидирув ──
  List<String> _search(String query) {
    if (query.length < 2) return [];
    final q = query.toLowerCase();
    final results = <String>[];

    // МФЙлар — кирилл ёки лотинда қидириш
    for (final mfy in _mfyList) {
      final cyrl = mfy['cyrl']!;
      final latn = mfy['latn']!;
      if (cyrl.toLowerCase().contains(q) || latn.toLowerCase().contains(q)) {
        results.add(cyrl); // Ҳамиша кириллда кўрсатилади
      }
    }

    // Қўшимча жойлар
    for (final place in _extraPlaces) {
      if (place.toLowerCase().contains(q)) {
        results.add(place);
      }
    }

    return results.take(8).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
    _fromFocus.addListener(() { if (!_fromFocus.hasFocus) setState(() => _fromSug = []); });
    _toFocus.addListener(()   { if (!_toFocus.hasFocus)   setState(() => _toSug   = []); });
    // Кириш билан GPS автоматик аниқлаш
    WidgetsBinding.instance.addPostFrameCallback((_) => _getGps());
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Сақланган манзиллар ──
  Future<void> _loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_places');
    if (saved != null) {
      final List decoded = jsonDecode(saved);
      setState(() => _savedPlaces = decoded.map((e) => Map<String, String>.from(e)).toList());
    }
  }

  Future<void> _savePlaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_places', jsonEncode(_savedPlaces));
  }

  // ── Автокомплит ──
  void _onFromChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() => _fromSug = _search(q));
    });
  }

  void _onToChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() => _toSug = _search(q));
    });
  }

  // ── GPS ──
  Future<void> _getGps() async {
    if (!mounted) return;
    setState(() => _isGpsLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        _snack('GPS рухсати берилмади');
        setState(() => _isGpsLoading = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));
      final marks = await placemarkFromCoordinates(
          pos.latitude, pos.longitude);
      final addr = marks.isNotEmpty
          ? '${marks.first.street ?? ''} ${marks.first.subLocality ?? ''}, ${marks.first.locality ?? ''}'.trim()
          : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      if (!mounted) return;
      setState(() {
        _fromCtrl.text = addr;
        _fromSug       = [];
        _isGpsLoading  = false;
      });
      _snack('📍 Жойлашув аниқланди');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isGpsLoading = false);
      _snack('GPS аниқланмади');
    }
  }

  // ── Харитадан танлаш ──
  Future<void> _pickOnMap(bool isFrom) async {
    final result = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const MapPickerScreen(title: 'Манзил танлаш')));
    if (result != null) setState(() { isFrom ? _fromCtrl.text = result : _toCtrl.text = result; });
  }

  // ── Қидириш ──
  void _onSearch() async {
    if (_fromCtrl.text.trim().isEmpty) { _showGpsDialog(); return; }

    // Ghost protection текшириш
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = (prefs.getString('user_phone') ?? '')
          .replaceAll(RegExp(r'[^\d]'), '');

      if (phone.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(phone).get();
        final blockedUntil =
        userDoc.data()?['blockedUntil'] as Timestamp?;

        if (blockedUntil != null &&
            blockedUntil.toDate().isAfter(DateTime.now())) {
          final remaining = blockedUntil.toDate()
              .difference(DateTime.now());
          _snack('⛔ ${remaining.inMinutes} дақиқадан кейин '
              'қайта уриниб кўринг');
          return;
        }
      }
    } catch (_) {}

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SearchingScreen(
        from:     _fromCtrl.text.trim(),
        to:       _toCtrl.text.trim(),
        taxiType: 'alone',
      ),
    ));
  }

  void _showGpsDialog() {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('📍 Жойлашувни аниқланг'),
      content: const Text('"Қаердан" майдони бўш.\nGPS орқали жойлашувингизни аниқланг.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Орқага')),
        ElevatedButton.icon(
          onPressed: () { Navigator.pop(context); _getGps().then((_) { if (_fromCtrl.text.isNotEmpty) _onSearch(); }); },
          icon: const Icon(Icons.gps_fixed),
          label: const Text('GPS'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
        ),
      ],
    ));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Сақланган манзил қўшиш ──
  void _addPlace() {
    if (_savedPlaces.length >= 6) { _snack('Максимум 6 та манзил'); return; }
    Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const MapPickerScreen(title: 'Янги манзил'))).then((addr) {
      if (addr == null) return;
      final ctrl = TextEditingController();
      showDialog(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Манзил номи'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: 'Уй, Иш, Дўкон...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _savedPlaces.add({'name': ctrl.text.trim(), 'address': addr}));
                _savePlaces();
                Navigator.pop(context);
                _snack('${ctrl.text.trim()} сақланди');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
            child: const Text('Сақлаш'),
          ),
        ],
      ));
    });
  }

  void _deletePlace(String name) {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('"$name" ўчириш'),
      content: const Text('Ушбу манзилни ўчиришни истайсизми?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Йўқ')),
        ElevatedButton(
          onPressed: () {
            setState(() => _savedPlaces.removeWhere((p) => p['name'] == name));
            _savePlaces(); Navigator.pop(context); _snack('$name ўчирилди');
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Ҳа'),
        ),
      ],
    ));
  }

  IconData _placeIcon(String n) {
    final l = n.toLowerCase();
    if (l.contains('уй'))     return Icons.home;
    if (l.contains('иш'))     return Icons.work;
    if (l.contains('дўкон') || l.contains('бозор')) return Icons.store;
    if (l.contains('мактаб')) return Icons.school;
    if (l.contains('касалхона') || l.contains('шифо')) return Icons.local_hospital;
    return Icons.place;
  }

  Color _placeColor(String n) {
    final l = n.toLowerCase();
    if (l.contains('уй'))     return Colors.blue;
    if (l.contains('иш'))     return Colors.orange;
    if (l.contains('дўкон') || l.contains('бозор')) return Colors.purple;
    if (l.contains('мактаб')) return Colors.red;
    if (l.contains('касалхона')) return Colors.teal;
    return Colors.grey.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(loc.translate('local_taxi')),
        backgroundColor: const Color(0xFFF57F17),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _driverButton(context, 'alone'),
        ],
      ),
      body: Column(
        children: [
          // ── Тепа баннер ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_blue1, _blue2, _blue3],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(children: [
              // Қаердан
              _addressField(
                ctrl: _fromCtrl, focus: _fromFocus,
                hint: loc.translate('from'), icon: Icons.circle,
                iconColor: Colors.greenAccent,
                onChange: _onFromChanged,
                trailing: _isGpsLoading
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : IconButton(
                  icon: const Icon(Icons.gps_fixed, color: Colors.greenAccent, size: 20),
                  onPressed: _getGps,
                  tooltip: 'GPS',
                ),
              ),
              if (_fromSug.isNotEmpty) _suggestList(_fromSug, _fromCtrl, () => setState(() => _fromSug = [])),
              const SizedBox(height: 8),

              // Алмаштириш + чизиқ
              Row(children: [
                const SizedBox(width: 12),
                Container(width: 2, height: 12, color: Colors.white24),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    final tmp = _fromCtrl.text;
                    _fromCtrl.text = _toCtrl.text;
                    _toCtrl.text = tmp;
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.swap_vert, color: Colors.white, size: 18),
                  ),
                ),
              ]),
              const SizedBox(height: 8),

              // Қаерга
              _addressField(
                ctrl: _toCtrl, focus: _toFocus,
                hint: loc.translate('to_optional'),
                icon: Icons.location_on, iconColor: Colors.redAccent,
                onChange: _onToChanged,
                trailing: IconButton(
                  icon: const Icon(Icons.map_outlined, color: Colors.white70, size: 20),
                  onPressed: () => _pickOnMap(false),
                  tooltip: loc.translate('pick_on_map'),
                ),
              ),
              if (_toSug.isNotEmpty) _suggestList(_toSug, _toCtrl, () => setState(() => _toSug = [])),
            ]),
          ),

          // ── Мазмун ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

                // Сақланган манзиллар
                if (_savedPlaces.isNotEmpty || true) ...[
                  Row(children: [
                    const Icon(Icons.bookmark, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(loc.translate('saved_places'),
                        style: TextStyle(fontSize: AppText.bodySmall, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _addPlace,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _green.withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.add, size: 12, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 2),
                          Text(loc.translate('add'), style: const TextStyle(fontSize: AppText.labelSmall, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (_savedPlaces.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text(loc.translate('saved_places'),
                            style: TextStyle(fontSize: AppText.bodySmall, color: Colors.grey.shade500)),
                      ]),
                    )
                  else
                    Wrap(spacing: 6, runSpacing: 6,
                      children: _savedPlaces.map((p) => GestureDetector(
                        onTap: () => setState(() => _fromCtrl.text = p['address'] ?? ''),
                        onLongPress: () => _deletePlace(p['name'] ?? ''),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_placeIcon(p['name'] ?? ''), size: 13, color: _placeColor(p['name'] ?? '')),
                            const SizedBox(width: 4),
                            Text(p['name'] ?? '', style: const TextStyle(fontSize: AppText.labelSmall, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      )).toList(),
                    ),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 24),

                // Қидириш тугмаси — ДОИМ АКТИВ
                SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFF57F17), Color(0xFFFF8F00)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                            color: const Color(0xFFF57F17).withOpacity(0.4),
                            blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: InkWell(
                        onTap: _onSearch,
                        borderRadius: BorderRadius.circular(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search, size: 22, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(loc.translate('search_driver'),
                                style: const TextStyle(
                                    fontSize: AppText.bodyLarge,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Манзил майдони ──
  Widget _addressField({
    required TextEditingController ctrl,
    required FocusNode focus,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<String> onChange,
    required Widget trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        Icon(icon, size: 10, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl, focusNode: focus,
            onChanged: onChange,
            style: const TextStyle(fontSize: AppText.bodyLarge, color: Colors.white, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: AppText.bodyMedium),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        trailing,
      ]),
    );
  }

  // ── Таклифлар рўйхати ──
  Widget _suggestList(List<String> list, TextEditingController ctrl, VoidCallback onDone) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => ListTile(
          dense: true,
          leading: const Icon(Icons.location_on, size: 16, color: Colors.grey),
          title: Text(list[i], style: const TextStyle(fontSize: AppText.bodyMedium)),
          onTap: () { ctrl.text = list[i]; onDone(); },
        ),
      ),
    );
  }

  Widget _driverButton(BuildContext context, String taxiType) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () async {
          final prefs  = await SharedPreferences.getInstance();
          final phone  = prefs.getString('user_phone') ?? '';
          final name   = prefs.getString('user_name')  ?? '';
          final userId = phone.replaceAll(RegExp(r'[^\d]'), '');
          if (userId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Аввал профилдан телефон рақамини киритинг')));
            return;
          }
          _showCarInfoDialog(context, userId, phone, name, taxiType);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Ҳайдовчи',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF57F17))),
        ),
      ),
    );
  }

  void _showCarInfoDialog(BuildContext context, String userId,
      String phone, String name, String taxiType) {
    final carCtrl   = TextEditingController();
    final plateCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🚗 Машина маълумотлари'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: carCtrl,
              decoration: const InputDecoration(hintText: 'Машина маркаси',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: plateCtrl,
              decoration: const InputDecoration(hintText: 'Давлат рақами',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Бекор')),
          ElevatedButton(
            onPressed: () {
              if (carCtrl.text.isEmpty || plateCtrl.text.isEmpty) return;
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => DriverScheduleScreen(
                  taxiType:    taxiType,
                  driverName:  name,
                  driverPhone: phone,
                  driverCar:   carCtrl.text.trim(),
                  driverPlate: plateCtrl.text.trim(),
                ),
              ));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF57F17)),
            child: const Text('ДАВОМ ЭТИШ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Такси карточкаси ──
  Widget _taxiCard({
    required String type, required String emoji,
    required String title, required String sub,
    required Color color,
  }) {
    final sel = _taxiType == type;
    return GestureDetector(
      onTap: () => setState(() => _taxiType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? color : Colors.grey.shade200, width: sel ? 2 : 1),
          boxShadow: [BoxShadow(
            color: sel ? color.withOpacity(0.25) : Colors.black.withOpacity(0.04),
            blurRadius: sel ? 10 : 6, offset: const Offset(0, 3),
          )],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
              fontSize: AppText.titleSmall, fontWeight: FontWeight.bold,
              color: sel ? Colors.white : Colors.black87,
            )),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(
              fontSize: AppText.bodySmall,
              color: sel ? Colors.white70 : Colors.grey.shade500,
            )),
          ])),
          if (sel)
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            ),
        ]),
      ),
    );
  }
}