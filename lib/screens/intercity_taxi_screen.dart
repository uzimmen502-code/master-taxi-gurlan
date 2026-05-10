import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'driver_schedule_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ========== РАНГЛАР ==========
class IntercityColors {
  static const Color primary    = Color(0xFF7B1FA2);
  static const Color dark       = Color(0xFF9C27B0);
  static const Color light      = Color(0xFFF3E5F5);
  static const Color accent     = Color(0xFF9C27B0);
  static const Color bg         = Color(0xFFF3E5F5);
  static const Color card       = Color(0xFFFFFFFF);
  static const Color green      = Color(0xFF43A047);
  static const Color red        = Color(0xFFE53935);
  static const Color gold       = Color(0xFFFFB300);
  static const Color text       = Color(0xFF1A1A2E);
  static const Color textLight  = Color(0xFF7986CB);
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
  final TextEditingController _toController   = TextEditingController();
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode   = FocusNode();

  String? _selectedFromLocation;
  String? _selectedToLocation;
  String? _selectedDistrict;
  bool _isToday    = true;
  int  _passengers = 1;

  List<IntercityRideModel> _rides = [];
  bool _isLoading   = false;
  bool _hasSearched = false;

  List<String> _fromSuggestions = [];
  List<String> _toSuggestions   = [];
  bool _showFromSuggestions = false;
  bool _showToSuggestions   = false;

  final List<String> _tashkentDistricts = [
    'Чилонзор','Юнусобод','Миробод','Шайхонтоҳур','Олмазор',
    'Сергели','Учтепа','Яшнобод','Бектемир','Яккасарой',
  ];

  final List<String> _allLocations = [
    // Вилоят марказлари
    'Тошкент', 'Самарқанд', 'Бухоро', 'Наманган', 'Андижон',
    'Фарғона', 'Қарши', 'Термиз', 'Жиззах', 'Гулистон',
    'Навоий', 'Урганч', 'Нукус',
    // Тошкент вилояти
    'Тошкент • Олмалиқ', 'Тошкент • Ангрен', 'Тошкент • Чирчиқ',
    'Тошкент • Бекобод', 'Тошкент • Янгийўл', 'Тошкент • Келес',
    'Тошкент • Зангиота', 'Тошкент • Бўстонлиқ', 'Тошкент • Паркент',
    'Тошкент • Қибрай', 'Тошкент • Оҳангарон', 'Тошкент • Пскент',
    'Тошкент • Тўйтепа',
    // Тошкент шаҳри туманлари
    'Тошкент ш. • Чилонзор', 'Тошкент ш. • Юнусобод', 'Тошкент ш. • Миробод',
    'Тошкент ш. • Шайхонтоҳур', 'Тошкент ш. • Олмазор', 'Тошкент ш. • Сергели',
    'Тошкент ш. • Учтепа', 'Тошкент ш. • Яшнобод', 'Тошкент ш. • Бектемир',
    'Тошкент ш. • Яккасарой',
    // Самарқанд вилояти
    'Самарқанд • Каттақўрғон', 'Самарқанд • Иштихон', 'Самарқанд • Жомбой',
    'Самарқанд • Нарпай', 'Самарқанд • Пастдарғом', 'Самарқанд • Пайариқ',
    'Самарқанд • Қўшработ', 'Самарқанд • Тайлоқ', 'Самарқанд • Булунғур',
    'Самарқанд • Ургут', 'Самарқанд • Оқдарё',
    // Бухоро вилояти
    'Бухоро • Когон', 'Бухоро • Қоракўл', 'Бухоро • Ғиждувон',
    'Бухоро • Шофиркон', 'Бухоро • Вобкент', 'Бухоро • Ромитан',
    'Бухоро • Жондор', 'Бухоро • Олот', 'Бухоро • Пешку',
    // Наманган вилояти
    'Наманган • Чуст', 'Наманган • Поп', 'Наманган • Тўрақўрғон',
    'Наманган • Уйчи', 'Наманган • Косонсой', 'Наманган • Мингбулоқ',
    'Наманган • Учқўрғон', 'Наманган • Янгиқўрғон', 'Наманган • Норин',
    // Андижон вилояти
    'Андижон • Асака', 'Андижон • Хонобод', 'Андижон • Пахтаобод',
    'Андижон • Балиқчи', 'Андижон • Бўз', 'Андижон • Жалолқудуқ',
    'Андижон • Избосқан', 'Андижон • Мархамат', 'Андижон • Шахрихон',
    'Андижон • Улуғнор', 'Андижон • Қўрғонтепа',
    // Фарғона вилояти
    'Фарғона • Марғилон', 'Фарғона • Қўқон', 'Фарғона • Қувасой',
    'Фарғона • Риштон', 'Фарғона • Қува', 'Фарғона • Боғдод',
    'Фарғона • Данғара', 'Фарғона • Олтиариқ', 'Фарғона • Тошлоқ',
    'Фарғона • Учқўприк', 'Фарғона • Яйпан',
    // Қашқадарё вилояти
    'Қашқадарё • Шаҳрисабз', 'Қашқадарё • Китоб', 'Қашқадарё • Муборак',
    'Қашқадарё • Чироқчи', 'Қашқадарё • Яккабоғ', 'Қашқадарё • Косон',
    'Қашқадарё • Камаши', 'Қашқадарё • Деҳқонобод', 'Қашқадарё • Нишон',
    // Сурхондарё вилояти
    'Сурхондарё • Денов', 'Сурхондарё • Шўрчи', 'Сурхондарё • Бойсун',
    'Сурхондарё • Жарқўрғон', 'Сурхондарё • Сариосиё', 'Сурхондарё • Қумқўрғон',
    'Сурхондарё • Олтинсой', 'Сурхондарё • Музработ',
    // Жиззах вилояти
    'Жиззах • Зафаробод', 'Жиззах • Зомин', 'Жиззах • Ғаллаорол',
    'Жиззах • Дўстлик', 'Жиззах • Мирзачўл', 'Жиззах • Пахтакор',
    'Жиззах • Янгиобод', 'Жиззах • Арнасой', 'Жиззах • Бахмал',
    // Сирдарё вилояти
    'Сирдарё • Янгийер', 'Сирдарё • Боёвут', 'Сирдарё • Сардоба',
    'Сирдарё • Хавос', 'Сирдарё • Мирзаобод', 'Сирдарё • Сайхунобод',
    // Навоий вилояти
    'Навоий • Зарафшон', 'Навоий • Учқудуқ', 'Навоий • Нурота',
    'Навоий • Қизилтепа', 'Навоий • Хатирчи', 'Навоий • Томди',
    'Навоий • Конимех', 'Навоий • Навбаҳор',
    // Хоразм вилояти
    'Хоразм • Гурлан', 'Хоразм • Хива', 'Хоразм • Қўшкўпир',
    'Хоразм • Шовот', 'Хоразм • Янгиариқ', 'Хоразм • Янгибозор',
    'Хоразм • Боғот', 'Хоразм • Ҳазорасп', 'Хоразм • Хонқа',
    'Хоразм • Тупроққалъа', 'Хоразм • Питнак',
    // Қорақалпоғистон
    'Қорақалпоғистон • Мўйноқ', 'Қорақалпоғистон • Чимбой',
    'Қорақалпоғистон • Хўжайли', 'Қорақалпоғистон • Қўнғирот',
    'Қорақалпоғистон • Тахтакўпир', 'Қорақалпоғистон • Беруний',
    'Қорақалпоғистон • Кегейли', 'Қорақалпоғистон • Қораўзак',
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
  }

  void _onToFocusChanged() {
    if (!_toFocusNode.hasFocus) setState(() => _showToSuggestions = false);
  }

  void _selectFromLocation(String loc) {
    _fromController.text = loc;
    _selectedFromLocation = loc;
    setState(() => _showFromSuggestions = false);
    _fromFocusNode.unfocus();
  }

  void _selectToLocation(String loc) {
    _toController.text = loc;
    _selectedToLocation = loc;
    _selectedDistrict = loc.contains('•') ? loc.split('•')[1].trim() : null;
    setState(() => _showToSuggestions = false);
    _toFocusNode.unfocus();
    if (loc == 'Тошкент ш.') _showDistrictPicker();
  }

  void _showDistrictPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Тошкент туманини танланг', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tashkentDistricts.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.location_city, color: IntercityColors.primary, size: 20),
                  title: Text(_tashkentDistricts[i]),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: IntercityColors.primary),
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

  // ========== FIREBASE ==========
  Future<List<IntercityRideModel>> _fetchRidesFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('intercity_drivers')
          .where('isActive', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) return [];
      final now   = DateTime.now();
      final today = _isToday ? now : now.add(const Duration(days: 1));
      return snapshot.docs.map((doc) {
        final d = doc.data();
        return IntercityRideModel(
          id: doc.id,
          driverName: d['name'] ?? '',
          rating: (d['rating'] ?? 4.0).toDouble(),
          carNumber: d['plate'] ?? '',
          phoneNumber: d['phone'] ?? '',
          acceptsParcel: d['parcel'] ?? false,
          price: d['price'] ?? 0,
          availableSeats: d['seats'] ?? 4,
          fromCity: _extractCity(_selectedFromLocation ?? ''),
          toCity: _extractCity(_selectedToLocation ?? ''),
          district: _selectedDistrict ?? '',
          departureTime: DateTime(today.year, today.month, today.day, d['hour'] ?? 8, 0),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  List<IntercityRideModel> _generateDemoRides() {
    final now = DateTime.now();
    final d = _isToday ? now : now.add(const Duration(days: 1));
    final from = _extractCity(_selectedFromLocation ?? '');
    final to   = _extractCity(_selectedToLocation ?? '');
    return [
      IntercityRideModel(id:'1', driverName:'Сардор', rating:4.8, carNumber:'01A123AA', phoneNumber:'+998901234567', acceptsParcel:true,  price:150000, availableSeats:1, fromCity:from, toCity:to, district:'Чилонзор', departureTime:DateTime(d.year,d.month,d.day,8,0)),
      IntercityRideModel(id:'2', driverName:'Баҳодир', rating:4.9, carNumber:'01B456BB', phoneNumber:'+998934567890', acceptsParcel:false, price:180000, availableSeats:2, fromCity:from, toCity:to, district:'Чилонзор', departureTime:DateTime(d.year,d.month,d.day,14,0)),
      IntercityRideModel(id:'3', driverName:'Акмал',  rating:4.7, carNumber:'01C789CC', phoneNumber:'+998977889900', acceptsParcel:true,  price:120000, availableSeats:3, fromCity:from, toCity:to, district:'Сергели',  departureTime:DateTime(d.year,d.month,d.day,10,30)),
      IntercityRideModel(id:'4', driverName:'Дилшод', rating:4.6, carNumber:'01D456DD', phoneNumber:'+998945612378', acceptsParcel:true,  price:130000, availableSeats:4, fromCity:from, toCity:to, district:'Юнусобод', departureTime:DateTime(d.year,d.month,d.day,16,0)),
      IntercityRideModel(id:'5', driverName:'Элёр',  rating:4.9, carNumber:'01E789EE', phoneNumber:'+998945612379', acceptsParcel:false, price:140000, availableSeats:2, fromCity:from, toCity:to, district:'Миробод',  departureTime:DateTime(d.year,d.month,d.day,12,0)),
    ];
  }

  void _searchRides() {
    if (_selectedFromLocation == null || _selectedToLocation == null) {
      _showError('Илтимос, йўналишни танланг');
      return;
    }
    setState(() { _isLoading = true; _hasSearched = true; });
    _fetchRidesFromFirestore().then((rides) {
      if (!mounted) return;
      setState(() {
        _rides = rides.isEmpty ? _generateDemoRides() : rides;
        _rides.sort((a, b) => a.availableSeats.compareTo(b.availableSeats));
        _isLoading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _rides = _generateDemoRides()
          ..sort((a, b) => a.availableSeats.compareTo(b.availableSeats));
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.warning_amber, color: Colors.white), const SizedBox(width: 8), Text(msg)]),
        backgroundColor: IntercityColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    final url = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _bookRide(IntercityRideModel ride) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: IntercityColors.green, size: 40),
            ),
            const SizedBox(height: 12),
            const Text('Брон қабул қилинди!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _bookingRow(Icons.person, 'Ҳайдовчи', ride.driverName),
            const Divider(height: 20),
            _bookingRow(Icons.directions_car, 'Машина', ride.carNumber),
            const Divider(height: 20),
            _bookingRow(Icons.access_time, 'Жўнаш', '${ride.departureTime.hour.toString().padLeft(2,"0")}:${ride.departureTime.minute.toString().padLeft(2,"0")}'),
            const Divider(height: 20),
            _bookingRow(Icons.payments, 'Йўлкира', '${_formatPrice(ride.price)} сўм'),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _callDriver(ride.phoneNumber); },
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Қўнғироқ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: IntercityColors.primary,
                    side: const BorderSide(color: IntercityColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); setState(() { _hasSearched = false; _rides = []; }); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: IntercityColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _bookingRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 20, color: IntercityColors.primary),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ]);
  }

  String _formatPrice(int p) {
    final s = p.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ========== BUILD ==========
  @override
  Widget build(BuildContext context) {
    final today    = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    return Scaffold(
      backgroundColor: IntercityColors.bg,
      appBar: _hasSearched ? null : AppBar(
        backgroundColor: IntercityColors.dark,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Шаҳарлараро такси',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          _driverButton(context, 'intercity'),
        ],
      ),

      body: _hasSearched ? _buildResultsView() : _buildSearchForm(today, tomorrow),
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
                  color: IntercityColors.primary)),
        ),
      ),
    );
  }

  void _showCarInfoDialog(BuildContext context, String userId,
      String phone, String name, String taxiType) async {
    final prefs    = await SharedPreferences.getInstance();
    final carModel = prefs.getString('car_model') ?? '';
    final carPlate = prefs.getString('car_plate') ?? '';

    // Агар маълумотлар сақланган — диалогсиз ўтиш
    if (carModel.isNotEmpty && carPlate.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DriverScheduleScreen(
          taxiType:    taxiType,
          driverName:  name,
          driverPhone: phone,
          driverCar:   carModel,
          driverPlate: carPlate,
        ),
      ));
      return;
    }

    // Маълумотлар йўқ — диалог
    final carCtrl   = TextEditingController();
    final plateCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🚗 Машина маълумотлари'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: carCtrl,
              decoration: const InputDecoration(
                  hintText: 'Машина маркаси',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: plateCtrl,
              decoration: const InputDecoration(
                  hintText: 'Давлат рақами',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Бекор')),
          ElevatedButton(
            onPressed: () async {
              if (carCtrl.text.isEmpty || plateCtrl.text.isEmpty) return;
              await prefs.setString('car_model', carCtrl.text.trim());
              await prefs.setString('car_plate', plateCtrl.text.trim());
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
            style: ElevatedButton.styleFrom(
                backgroundColor: IntercityColors.primary),
            child: const Text('ДАВОМ ЭТИШ',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ========== ҚИДИРИШ ФОРМАСИ ==========
  Widget _buildSearchForm(DateTime today, DateTime tomorrow) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // ===== ЮҚОРИ БАННЕР =====
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [IntercityColors.dark, IntercityColors.primary, IntercityColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.route, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('Шаҳарлараро такси', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                ]),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== ЙЎНАЛИШ КАРТОЧКАСИ =====
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: IntercityColors.primary.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Қаердан
                      Row(children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: IntercityColors.green, shape: BoxShape.circle)),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(
                          controller: _fromController,
                          focusNode: _fromFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Қаердан?',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                            border: InputBorder.none,
                            isDense: true,
                            suffixIcon: _fromController.text.isNotEmpty
                                ? IconButton(
                                icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade400),
                                onPressed: () { _fromController.clear(); setState(() { _selectedFromLocation = null; _fromSuggestions = []; _showFromSuggestions = false; }); })
                                : null,
                          ),
                        )),
                      ]),

                      // Ажратгич
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          const SizedBox(width: 4),
                          Container(width: 2, height: 24, color: Colors.grey.shade200),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              final tmp = _fromController.text;
                              _fromController.text = _toController.text;
                              _toController.text = tmp;
                              final tmpLoc = _selectedFromLocation;
                              _selectedFromLocation = _selectedToLocation;
                              _selectedToLocation = tmpLoc;
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: IntercityColors.light,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.swap_vert, color: IntercityColors.primary, size: 20),
                            ),
                          ),
                        ]),
                      ),

                      // Қаерга
                      Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: IntercityColors.red, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(
                          controller: _toController,
                          focusNode: _toFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Қаерга?',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                            border: InputBorder.none,
                            isDense: true,
                            suffixIcon: _toController.text.isNotEmpty
                                ? IconButton(
                                icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade400),
                                onPressed: () { _toController.clear(); setState(() { _selectedToLocation = null; _selectedDistrict = null; _toSuggestions = []; _showToSuggestions = false; }); })
                                : null,
                          ),
                        )),
                      ]),
                    ],
                  ),
                ),

                // Таклифлар
                if (_showFromSuggestions && _fromSuggestions.isNotEmpty) _suggestionsList(_fromSuggestions, _selectFromLocation),
                if (_showToSuggestions && _toSuggestions.isNotEmpty) _suggestionsList(_toSuggestions, _selectToLocation),

                const SizedBox(height: 16),

                // ===== САНА =====
                Row(children: [
                  Expanded(child: _dateCard('БУГУН', '${today.day}.${today.month.toString().padLeft(2,"0")}', _isToday, () => setState(() => _isToday = true))),
                  const SizedBox(width: 12),
                  Expanded(child: _dateCard('ЭРТАГА', '${tomorrow.day}.${tomorrow.month.toString().padLeft(2,"0")}', !_isToday, () => setState(() => _isToday = false))),
                ]),

                const SizedBox(height: 16),

                // ===== ЙЎЛОВЧИЛАР =====
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: IntercityColors.light, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.people, color: IntercityColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text('Йўловчилар', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      _counterBtn(Icons.remove, () => setState(() { if (_passengers > 1) _passengers--; }), Colors.grey.shade100, Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Text('$_passengers', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: IntercityColors.primary)),
                      const SizedBox(width: 12),
                      _counterBtn(Icons.add, () => setState(() { if (_passengers < 4) _passengers++; }), IntercityColors.primary, Colors.white),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ===== ҚИДИРИШ ТУГМАСИ =====
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [IntercityColors.dark, IntercityColors.accent], begin: Alignment.centerLeft, end: Alignment.centerRight),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: IntercityColors.primary.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _searchRides,
                      icon: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.search, size: 22),
                      label: const Text('РЕЙСЛАРНИ ҚИДИРИШ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== НАТИЖАЛАР ==========
  Widget _buildResultsView() {
    return Column(
      children: [
        // Сарлавҳа
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [IntercityColors.dark, IntercityColors.primary]),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() { _hasSearched = false; _rides = []; }),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                    const SizedBox(width: 6),
                    Text(_extractCity(_selectedFromLocation ?? ''), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, color: Colors.white70, size: 14)),
                    const Icon(Icons.location_on, color: Colors.redAccent, size: 10),
                    const SizedBox(width: 4),
                    Text(_extractCity(_selectedToLocation ?? ''), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 2),
                  Text('${_rides.length} та рейс топилди', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                ]),
              ),
              _driverButton(context, 'intercity'),
            ],
          ),
        ),

        // Рейслар
        Expanded(
          child: _rides.isEmpty
              ? Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.search_off, size: 72, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text('Рейслар топилмади', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() { _hasSearched = false; _rides = []; }),
                icon: const Icon(Icons.refresh),
                label: const Text('Қайта қидириш'),
              ),
            ]),
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
            itemCount: _rides.length,
            itemBuilder: (_, i) => _rideCard(_rides[i], i + 1),
          ),
        ),
      ],
    );
  }

  // ========== РЕЙС КАРТОЧКАСИ ==========
  Widget _rideCard(IntercityRideModel ride, int number) {
    final seatsColor = ride.availableSeats == 1
        ? IntercityColors.red
        : ride.availableSeats <= 3
        ? Colors.orange
        : IntercityColors.green;

    const mandarin = Color(0xFFE65100);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Stack(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: IntercityColors.light,
                child: Text(ride.driverName.substring(0, 1),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: IntercityColors.primary)),
              ),
              Positioned(bottom: 0, right: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(color: IntercityColors.primary, shape: BoxShape.circle),
                    child: Center(child: Text('$number',
                        style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold))),
                  )),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ride.driverName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: IntercityColors.text)),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.star, color: IntercityColors.gold, size: 13),
                const SizedBox(width: 2),
                Text('${ride.rating}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: IntercityColors.gold)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(5)),
                  child: Text(ride.carNumber,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ),
              ]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_formatPrice(ride.price),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: mandarin)),
              const Text('сўм', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 8),
          Row(children: [
            Flexible(
              child: Text(ride.carNumber.isNotEmpty ? ride.carNumber.split(' ').first : '',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Text('·', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _callDriver(ride.phoneNumber),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: IntercityColors.light,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.call, size: 15, color: IntercityColors.primary),
              ),
            ),
            const Spacer(),
            _SeatPulse(seats: ride.availableSeats, color: seatsColor),
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: ElevatedButton(
                onPressed: () => _bookRide(ride),
                style: ElevatedButton.styleFrom(
                  backgroundColor: IntercityColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                child: const Text('БРОН'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  // ========== ВИДЖЕТЛАР ==========
  Widget _suggestionsList(List<String> list, Function(String) onTap) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12)],
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: list.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (_, i) => ListTile(
          leading: Icon(Icons.location_on, color: IntercityColors.primary, size: 18),
          title: Text(list[i], style: const TextStyle(fontSize: 14)),
          dense: true,
          onTap: () => onTap(list[i]),
        ),
      ),
    );
  }

  Widget _dateCard(String title, String date, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          gradient: sel ? const LinearGradient(colors: [IntercityColors.dark, IntercityColors.primary]) : null,
          color: sel ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: sel
              ? [BoxShadow(color: IntercityColors.primary.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))]
              : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sel ? Icons.calendar_today : Icons.calendar_today_outlined,
              size: 14,
              color: sel ? Colors.white : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: sel ? Colors.white : IntercityColors.text)),
              Text(date, style: TextStyle(fontSize: 11, color: sel ? Colors.white70 : Colors.grey.shade500)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap, Color bg, Color iconColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

// ========== МЕРЦАЙДИГАН ЎРИНЛАР ==========
class _SeatPulse extends StatefulWidget {
  final int seats;
  final Color color;
  const _SeatPulse({required this.seats, required this.color});
  @override
  State<_SeatPulse> createState() => _SeatPulseState();
}

class _SeatPulseState extends State<_SeatPulse> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    final ms = widget.seats == 1 ? 400 : widget.seats <= 3 ? 700 : 1200;
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: ms))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: widget.color.withOpacity(0.4), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.airline_seat_recline_normal, size: 15, color: widget.color),
            const SizedBox(width: 4),
            Text(
              '${widget.seats} бўш ўрин',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: widget.color,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}