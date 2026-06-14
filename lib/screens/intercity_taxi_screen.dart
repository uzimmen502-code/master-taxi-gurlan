import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';

// ========== РАНГЛАР ==========
class IntercityColors {
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color darkBlue = Color(0xFF0D47A1);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF1A1A1A);
  static const Color gray = Color(0xFF757575);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color green = Color(0xFF4CAF50);
  static const Color red = Color(0xFFF44336);
  static const Color gold = Color(0xFFFFD700);
  static const Color phoneRed = Color(0xFFD32F2F);
}

// ========== РЕЙС МОДЕЛИ ==========
class IntercityRideModel {
  final String id;
  final String driverName;
  final double rating;
  final String carNumber;
  final String phoneNumber;
  final bool acceptsParcel;
  final int price;
  final int availableSeats;
  final String fromCity;
  final String toCity;
  final String district;
  final DateTime departureTime;

  IntercityRideModel({
    required this.id,
    required this.driverName,
    required this.rating,
    required this.carNumber,
    required this.phoneNumber,
    required this.acceptsParcel,
    required this.price,
    required this.availableSeats,
    required this.fromCity,
    required this.toCity,
    required this.district,
    required this.departureTime,
  });
}

// ========== АСОСИЙ ЭКРАН ==========
class IntercityTaxiScreen extends StatefulWidget {
  const IntercityTaxiScreen({super.key});

  @override
  State<IntercityTaxiScreen> createState() => _IntercityTaxiScreenState();
}

class _IntercityTaxiScreenState extends State<IntercityTaxiScreen> {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();

  String? _selectedFromLocation;
  String? _selectedToLocation;
  String? _selectedDistrict;
  bool _isToday = true;
  int _passengers = 1;

  List<IntercityRideModel> _rides = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  List<String> _fromSuggestions = [];
  List<String> _toSuggestions = [];
  bool _showFromSuggestions = false;
  bool _showToSuggestions = false;

  final List<String> _tashkentDistricts = [
    'Чилонзор', 'Юнусобод', 'Миробод', 'Шайхонтоҳур', 'Олмазор',
    'Сергели', 'Учтепа', 'Яшнобод', 'Бектемир', 'Яккасарой',
  ];

  final List<String> _allLocations = [
    'Тошкент ш.', 'Самарқанд ш.', 'Бухоро ш.', 'Наманган ш.', 'Андижон ш.',
    'Фарғона ш.', 'Қарши ш.', 'Термиз ш.', 'Жиззах ш.', 'Гулистон ш.',
    'Навоий ш.', 'Урганч ш.', 'Нукус ш.',
    'Тошкент ш. • Чилонзор', 'Тошкент ш. • Юнусобод', 'Тошкент ш. • Миробод',
    'Тошкент ш. • Шайхонтоҳур', 'Тошкент ш. • Олмазор', 'Тошкент ш. • Сергели',
    'Тошкент ш. • Учтепа', 'Тошкент ш. • Яшнобод', 'Тошкент ш. • Бектемир',
    'Тошкент ш. • Яккасарой',
    'Гурлан • Хоразм', 'Хива', 'Қўшкўпир • Хоразм', 'Шовот • Хоразм',
    'Янгиариқ • Хоразм', 'Янгибозор • Хоразм', 'Боғот • Хоразм', 'Ҳазорасп • Хоразм',
    'Хонқа • Хоразм', 'Тупрокқалъа • Хоразм',
    'Ангрен', 'Олмалиқ', 'Чирчиқ', 'Бекобод', 'Қўқон', 'Марғилон',
  ];

  @override
  void initState() {
    super.initState();
    _fromController.addListener(_onFromChanged);
    _toController.addListener(_onToChanged);
    _fromFocusNode.addListener(_onFromFocusChanged);
    _toFocusNode.addListener(_onToFocusChanged);
  }

  void _onFromChanged() {
    final q = _fromController.text.toLowerCase();
    setState(() {
      _fromSuggestions = q.isEmpty ? [] : _allLocations.where((l) => l.toLowerCase().contains(q)).toList();
      _showFromSuggestions = _fromSuggestions.isNotEmpty;
    });
  }

  void _onToChanged() {
    final q = _toController.text.toLowerCase();
    setState(() {
      _toSuggestions = q.isEmpty ? [] : _allLocations.where((l) => l.toLowerCase().contains(q)).toList();
      _showToSuggestions = _toSuggestions.isNotEmpty;
    });
  }

  void _onFromFocusChanged() {
    if (!_fromFocusNode.hasFocus) setState(() => _showFromSuggestions = false);
    else if (_fromController.text.isNotEmpty) setState(() => _showFromSuggestions = _fromSuggestions.isNotEmpty);
  }

  void _onToFocusChanged() {
    if (!_toFocusNode.hasFocus) setState(() => _showToSuggestions = false);
    else if (_toController.text.isNotEmpty) setState(() => _showToSuggestions = _toSuggestions.isNotEmpty);
  }

  void _selectFromLocation(String loc) {
    _fromController.text = loc;
    _selectedFromLocation = loc;
    _showFromSuggestions = false;
    _fromFocusNode.unfocus();
  }

  void _selectToLocation(String loc) {
    _toController.text = loc;
    _selectedToLocation = loc;
    _showToSuggestions = false;
    _selectedDistrict = loc.contains('•') ? loc.split('•')[1].trim() : null;
    _toFocusNode.unfocus();
    if (loc == 'Тошкент ш.') _showDistrictPicker();
  }

  void _showDistrictPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.45,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Тошкент туманини танланг', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tashkentDistricts.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(_tashkentDistricts[i]),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: IntercityColors.primaryBlue),
                  onTap: () {
                    setState(() {
                      _selectedDistrict = _tashkentDistricts[i];
                      _toController.text = 'Тошкент ш. • ${_tashkentDistricts[i]}';
                      _selectedToLocation = _toController.text;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    super.dispose();
  }

  // ========== FIREBASE'ДАН ЎҚИШ ==========
  Future<List<IntercityRideModel>> _fetchRidesFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('intercity_drivers')
          .where('isActive', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) return [];

      final now = DateTime.now();
      final today = _isToday ? now : now.add(const Duration(days: 1));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return IntercityRideModel(
          id: doc.id,
          driverName: data['name'] ?? '',
          rating: (data['rating'] ?? 4.0).toDouble(),
          carNumber: data['plate'] ?? '',
          phoneNumber: data['phone'] ?? '',
          acceptsParcel: data['parcel'] ?? false,
          price: data['price'] ?? 0,
          availableSeats: data['seats'] ?? 4,
          fromCity: _extractCity(_selectedFromLocation ?? ''),
          toCity: _extractCity(_selectedToLocation ?? ''),
          district: _selectedDistrict ?? '',
          departureTime: DateTime(today.year, today.month, today.day, data['hour'] ?? 8, 0),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ========== DEMO МАЪЛУМОТЛАР (FIREBASE ИШЛАМАСА) ==========
  List<IntercityRideModel> _generateDemoRides() {
    final now = DateTime.now();
    final today = _isToday ? now : now.add(const Duration(days: 1));
    return [
      IntercityRideModel(id: '1', driverName: 'Сардор', rating: 4.8, carNumber: '01A123AA', phoneNumber: '+998901234567', acceptsParcel: true, price: 150000, availableSeats: 1, fromCity: _extractCity(_selectedFromLocation ?? ''), toCity: _extractCity(_selectedToLocation ?? ''), district: _selectedDistrict ?? 'Чилонзор', departureTime: DateTime(today.year, today.month, today.day, 8, 0)),
      IntercityRideModel(id: '2', driverName: 'Баҳодир', rating: 4.9, carNumber: '01B456BB', phoneNumber: '+998934567890', acceptsParcel: false, price: 180000, availableSeats: 2, fromCity: _extractCity(_selectedFromLocation ?? ''), toCity: _extractCity(_selectedToLocation ?? ''), district: _selectedDistrict ?? 'Чилонзор', departureTime: DateTime(today.year, today.month, today.day, 14, 0)),
      IntercityRideModel(id: '3', driverName: 'Акмал', rating: 4.7, carNumber: '01C789CC', phoneNumber: '+998977889900', acceptsParcel: true, price: 120000, availableSeats: 3, fromCity: _extractCity(_selectedFromLocation ?? ''), toCity: _extractCity(_selectedToLocation ?? ''), district: _selectedDistrict ?? 'Сергели', departureTime: DateTime(today.year, today.month, today.day, 10, 30)),
      IntercityRideModel(id: '4', driverName: 'Дилшод', rating: 4.6, carNumber: '01D456DD', phoneNumber: '+998945612378', acceptsParcel: true, price: 130000, availableSeats: 4, fromCity: 'Урганч', toCity: _extractCity(_selectedToLocation ?? ''), district: _selectedDistrict ?? 'Юнусобод', departureTime: DateTime(today.year, today.month, today.day, 16, 0)),
      IntercityRideModel(id: '5', driverName: 'Элёр', rating: 4.9, carNumber: '01E789EE', phoneNumber: '+998945612379', acceptsParcel: false, price: 140000, availableSeats: 2, fromCity: 'Хива', toCity: _extractCity(_selectedToLocation ?? ''), district: _selectedDistrict ?? 'Миробод', departureTime: DateTime(today.year, today.month, today.day, 12, 0)),
    ];
  }

  // ========== ҚИДИРИШ ==========
  void _searchRides() {
    if (_selectedFromLocation == null || _selectedToLocation == null) {
      _showError('Илтимос, йўналишни танланг');
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    _fetchRidesFromFirestore().then((rides) {
      if (!mounted) return;
      setState(() {
        if (rides.isEmpty) {
          _rides = _generateDemoRides();
        } else {
          _rides = rides;
        }
        _rides.sort((a, b) => a.availableSeats.compareTo(b.availableSeats));
        _isLoading = false;
      });
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _rides = _generateDemoRides();
        _rides.sort((a, b) => a.availableSeats.compareTo(b.availableSeats));
        _isLoading = false;
      });
    });
  }

  String _extractCity(String loc) {
    if (loc.contains('•')) return loc.split('•')[0].trim();
    if (loc.endsWith(' ш.')) return loc.substring(0, loc.length - 3);
    return loc;
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Хатолик'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    final url = Uri.parse('tel:${phoneForCall(phone)}');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _bookRide(IntercityRideModel ride) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('✅ БРОН ҚАБУЛ ҚИЛИНДИ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ҳайдовчи: ${ride.driverName}'),
            Text('Телефон: ${ride.phoneNumber}'),
            Text('Йўлкира: ${_formatPrice(ride.price)} сўм'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() { _hasSearched = false; _rides = []; });
            },
            style: ElevatedButton.styleFrom(backgroundColor: IntercityColors.primaryBlue, foregroundColor: Colors.white),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int p) => p.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  // ========== BUILD ==========
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    return Scaffold(
      backgroundColor: IntercityColors.lightGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: IntercityColors.black, size: 20), onPressed: () => _hasSearched ? setState(() => _hasSearched = false) : Navigator.pop(context)),
        title: Text(_hasSearched ? 'Топилган рейслар' : 'Шаҳарлараро такси', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: IntercityColors.black)),
        centerTitle: true,
      ),
      body: _hasSearched ? _buildResultsView() : _buildSearchForm(today, tomorrow),
    );
  }

  Widget _buildSearchForm(DateTime today, DateTime tomorrow) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('📍 Қаердан'),
          const SizedBox(height: 8),
          _locationField(_fromController, _fromFocusNode, 'Шаҳар ёки туман'),
          if (_showFromSuggestions && _fromSuggestions.isNotEmpty) _suggestionsList(_fromSuggestions, _selectFromLocation),
          const SizedBox(height: 20),
          _sectionTitle('📍 Қаерга'),
          const SizedBox(height: 8),
          _locationField(_toController, _toFocusNode, 'Шаҳар ёки туман'),
          if (_showToSuggestions && _toSuggestions.isNotEmpty) _suggestionsList(_toSuggestions, _selectToLocation),
          const SizedBox(height: 24),
          _sectionTitle('📅 Қачонга'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _dateCard('БУГУН', '${today.day}.${today.month}', _isToday, () => setState(() => _isToday = true))),
            const SizedBox(width: 12),
            Expanded(child: _dateCard('ЭРТАГА', '${tomorrow.day}.${tomorrow.month}', !_isToday, () => setState(() => _isToday = false))),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('👤 Йўловчилар'),
          const SizedBox(height: 8),
          _passengerCounter(),
          const SizedBox(height: 36),
          _searchButton(),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(children: [
            Icon(Icons.search, color: IntercityColors.primaryBlue),
            const SizedBox(width: 8),
            Text('${_rides.length} та рейс топилди', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ]),
        ),
        Expanded(
          child: _rides.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_off, size: 64, color: Colors.grey.shade400), const SizedBox(height: 16), const Text('Рейслар топилмади'), TextButton(onPressed: () => setState(() => _hasSearched = false), child: const Text('Қайта қидириш'))]))
              : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _rides.length, itemBuilder: (_, i) => _rideCard(_rides[i], i + 1)),
        ),
      ],
    );
  }

  // ========== 2 ҚАТОРЛИ КАРТОЧКА ==========
  Widget _rideCard(IntercityRideModel ride, int number) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Text('$number.', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 3),
                Text('👤${ride.driverName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text('⭐${ride.rating}', style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                _buildSeatWidget(ride.availableSeats),
                const SizedBox(width: 4),
                Text(ride.acceptsParcel ? '📦Жўнатма' : '📦❌', style: const TextStyle(fontSize: 10)),
                const Spacer(),
                Text('🚗${ride.carNumber}', style: const TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('📞${ride.phoneNumber}', style: const TextStyle(fontSize: 10)),
                const Spacer(),
                Text('💰${_formatPrice(ride.price)} сўм', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: () => _bookRide(ride),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    child: const Text('БРОН'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatWidget(int seats) {
    if (seats == 1) return _SeatPulseFast(seats: seats);
    if (seats == 2 || seats == 3) return _SeatPulseSlow(seats: seats);
    return Text('💺Бўш ўрин:$seats', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500));
  }

  // ========== ВИДЖЕТЛАР ==========
  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));

  Widget _locationField(TextEditingController ctrl, FocusNode fn, String hint) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]),
      child: TextField(
        controller: ctrl, focusNode: fn,
        decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(fontSize: 15, color: Colors.grey.shade400), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          suffixIcon: ctrl.text.isNotEmpty ? IconButton(icon: Icon(Icons.clear_rounded, size: 20, color: Colors.grey.shade500), onPressed: () { ctrl.clear(); setState(() { if (ctrl == _fromController) { _selectedFromLocation = null; _fromSuggestions = []; _showFromSuggestions = false; } else { _selectedToLocation = null; _selectedDistrict = null; _toSuggestions = []; _showToSuggestions = false; } }); }) : null,
        ),
      ),
    );
  }

  Widget _suggestionsList(List<String> list, Function(String) onTap) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12)]),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true, itemCount: list.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (_, i) => ListTile(leading: Icon(Icons.location_on, color: IntercityColors.primaryBlue, size: 18), title: Text(list[i], style: const TextStyle(fontSize: 15)), onTap: () => onTap(list[i])),
      ),
    );
  }

  Widget _dateCard(String title, String date, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          gradient: sel ? const LinearGradient(colors: [IntercityColors.primaryBlue, IntercityColors.darkBlue]) : null,
          color: sel ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: sel ? [BoxShadow(color: IntercityColors.primaryBlue.withOpacity(0.25), blurRadius: 6)] : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: sel ? Colors.white : IntercityColors.black)),
          const SizedBox(height: 2),
          Text(date, style: TextStyle(fontSize: 10, color: sel ? Colors.white70 : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _passengerCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Йўловчилар', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        Row(children: [
          _counterBtn(Icons.remove, () => setState(() { if (_passengers > 1) _passengers--; }), Colors.grey.shade200, Colors.grey.shade600),
          const SizedBox(width: 16),
          Text('$_passengers та', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          _counterBtn(Icons.add, () => setState(() { if (_passengers < 4) _passengers++; }), IntercityColors.primaryBlue, Colors.white),
        ]),
      ]),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap, Color bg, Color iconColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: iconColor)),
    );
  }

  Widget _searchButton() {
    return Container(
      width: double.infinity, height: 56,
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [IntercityColors.primaryBlue, IntercityColors.darkBlue]), borderRadius: BorderRadius.circular(18)),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _searchRides,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)) : const Text('РЕЙСЛАРНИ ҚИДИРИШ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}

// ========== ПУЛСАЦИЯ ВИДЖЕТЛАРИ ==========
class _SeatPulseFast extends StatefulWidget {
  final int seats;
  const _SeatPulseFast({required this.seats});
  @override
  State<_SeatPulseFast> createState() => _SeatPulseFastState();
}

class _SeatPulseFastState extends State<_SeatPulseFast> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.4 + (_ctrl.value * 0.6),
        child: Text('💺Бўш ўрин:${widget.seats}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.red)),
      ),
    );
  }
}

class _SeatPulseSlow extends StatefulWidget {
  final int seats;
  const _SeatPulseSlow({required this.seats});
  @override
  State<_SeatPulseSlow> createState() => _SeatPulseSlowState();
}

class _SeatPulseSlowState extends State<_SeatPulseSlow> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    final duration = widget.seats == 2 ? 600 : 900;
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: duration))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.5 + (_ctrl.value * 0.5),
        child: Text('💺Бўш ўрин:${widget.seats}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
      ),
    );
  }
}