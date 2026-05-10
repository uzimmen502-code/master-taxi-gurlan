import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../l10n/app_localizations.dart';
import 'local_taxi_screen.dart';
import 'marshrut_taxi_screen.dart';
import 'intercity_taxi_screen.dart';
import 'bread_screen.dart';
import 'job_screen.dart';
import 'profile_screen.dart';
import 'driver_register_marshrut_screen.dart';
import 'dart:math';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _name   = 'Фойдаланувчи';
  String _gender = 'male';
  bool _hasInternet = true;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  final List<Map<String, String>> _duas = [
    {'ar': 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',   'uz': 'Меҳрибон ва Раҳмли Аллоҳ номи билан'},
    {'ar': 'اللَّهُمَّ بَارِكْ لَنَا',                 'uz': 'Аллоҳим, бизга барака бер!'},
    {'ar': 'رَبِّ زِدْنِي عِلْمًا',                    'uz': 'Парвардигорим, илмимни зиёда қил!'},
    {'ar': 'اللَّهُمَّ يَسِّرْ وَلَا تُعَسِّرْ',       'uz': 'Аллоҳим, осон қил, қийинлаштирма!'},
    {'ar': 'حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ',    'uz': 'Аллоҳ бизга кифоя, У нақадар яхши вакил!'},
    {'ar': 'اللَّهُمَّ احْفَظْنَا',                    'uz': 'Аллоҳим, бизни ҳифз эт!'},
    {'ar': 'بِاللَّهِ التَّوْفِيقُ',                   'uz': 'Тавфиқ фақат Аллоҳдандир'},
    {'ar': 'اللَّهُمَّ اجْعَلْ يَوْمَنَا خَيْرًا',     'uz': 'Аллоҳим, кунимизни хайрли қил!'},
    {'ar': 'رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً',  'uz': 'Парвардигорим, дунёда яхшилик бер!'},
    {'ar': 'اللَّهُمَّ بَارِكْ فِي رِزْقِنَا',         'uz': 'Аллоҳим, ризқимизни баракали қил!'},
    {'ar': 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ',           'uz': 'Аллоҳ поктир, Унга ҳамд бўлсин'},
    {'ar': 'اللَّهُمَّ اغْفِرْ لَنَا',                 'uz': 'Аллоҳим, бизни мағфират қил!'},
    {'ar': 'تَوَكَّلْتُ عَلَى اللَّهِ',                'uz': 'Аллоҳга таваккал қилдим'},
    {'ar': 'اللَّهُمَّ اشْفِنَا',                      'uz': 'Аллоҳим, бизни шифо бер!'},
  ];

  Map<String, String> get _todayDua {
    final day = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return _duas[day % _duas.length];
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
    _initConnectivity();
    _maybeShowAgroPromo();
  }

  Future<void> _maybeShowAgroPromo() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final installMs = prefs.getInt('first_install_ms') ?? now.millisecondsSinceEpoch;
    await prefs.setInt('first_install_ms', installMs);
    final first = DateTime.fromMillisecondsSinceEpoch(installMs);
    final dayDiff = now.difference(DateTime(first.year, first.month, first.day)).inDays;
    if (dayDiff < 0 || dayDiff > 2) return;

    final key = '${now.year}-${now.month}-${now.day}';
    final sentKey = prefs.getString('promo_daily_key') ?? '';
    if (sentKey == key) return;
    await prefs.setString('promo_daily_key', key);
    if (!mounted) return;

    final random = Random();
    final extraSuggestion = random.nextDouble() < 0.55
        ? '\n\n🎯 Таклиф: гўшт ўрнига сут, гуруч, тухум ва бошқа қишлоқ хўжалик маҳсулотлари билан ҳисоб-китоб қилиш имкони бор.'
        : '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📢 Янгилик'),
        content: Text(
          'Бизда Сут, Қатиқ, Тухум, Гуруч ва бошқа маҳсулотлар билан ҳам ҳисоб-китоб қилиш мумкин.'
          '$extraSuggestion',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Тушунарли'),
          ),
        ],
      ),
    );
  }

  Future<void> _initConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectivity(result);
    _connectSub = Connectivity().onConnectivityChanged.listen(_updateConnectivity);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (mounted) setState(() => _hasInternet = connected);
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name   = prefs.getString('user_name')   ?? 'Фойдаланувчи';
      _gender = prefs.getString('user_gender') ?? 'male';
    });
  }

  String _greeting(AppLocalizations loc) {
    final h = DateTime.now().hour;
    if (h < 6)  return loc.translate('greeting_night');
    if (h < 12) return loc.translate('greeting_morning');
    if (h < 17) return loc.translate('greeting_day');
    if (h < 21) return loc.translate('greeting_evening');
    return loc.translate('greeting_night');
  }

  String _honorificName(AppLocalizations loc) {
    if (_gender == 'female') return 'Опажон $_name';
    return 'Биродарим $_name';
  }

  List<Map<String, dynamic>> _getModules(AppLocalizations loc) => [
    {'image': 'assets/images/bread.png',          'label': 'Нон буюртма',    'c1': const Color(0xFFE65100), 'c2': const Color(0xFFEF6C00)},
    {'image': 'assets/images/taxi_marshrut.png',  'label': 'Маршрут такси',  'c1': const Color(0xFF00695C), 'c2': const Color(0xFF00897B)},
    {'image': 'assets/images/taxi_local.png',     'label': 'Маҳаллий такси', 'c1': const Color(0xFF1565C0), 'c2': const Color(0xFF1E88E5)},
    {'image': 'assets/images/taxi_intercity.png', 'label': 'Шаҳарлараро',    'c1': const Color(0xFF6A1B9A), 'c2': const Color(0xFF8E24AA)},
    {'image': 'assets/images/ishtop.png',         'label': 'ИШ ТОП',         'c1': const Color(0xFF0277BD), 'c2': const Color(0xFF0288D1)},
  ];

  void _open(int i) {
    final screens = [
      const BreadScreen(),
      const MarshrutTaxiScreen(),
      const LocalTaxiScreen(),
      const IntercityTaxiScreen(),
      const JobScreen(),
    ];
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => screens[i],
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 280),
    ));
  }

  void _openMarshrutMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text('🚐 Маршрут такси',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // Такси чақириш
          _menuItem(
            icon: Icons.directions_bus,
            color: const Color(0xFF0277BD),
            title: 'Такси чақириш',
            sub: 'Яқин маршрут такси топинг',
            onTap: () {
              Navigator.pop(context);
              _open(1);
            },
          ),
          const SizedBox(height: 12),

          // Ҳайдовчи сифатида ишлаш
          _menuItem(
            icon: Icons.drive_eta,
            color: const Color(0xFF00695C),
            title: 'Ҳайдовчи сифатида ишлаш',
            sub: 'Рўйхатдан ўтинг ва йўловчи олинг',
            onTap: () async {
              Navigator.pop(context);
              final p = await SharedPreferences.getInstance();
              if (!mounted) return;
              final name  = p.getString('user_name')  ?? '';
              final phone = p.getString('user_phone') ?? '';
              final uid   = phone.replaceAll(RegExp(r'[^\d]'), '');
              if (uid.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Профилдан телефон рақамини киритинг'),
                      behavior: SnackBarBehavior.floating,
                    ));
                return;
              }
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const DriverRegisterMarshrutScreen(),
              ));
            },
          ),
        ]),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade500)),
            ],
          )),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF1B5E20),
              Color(0xFF2E7D32),
              Color(0xFF81C784),
              Color(0xFFE8F5E9),
              Color(0xFFF1F8F1),
            ],
            stops: [0.0, 0.12, 0.28, 0.45, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            if (!_hasInternet) _buildNoBanner(loc),
            Expanded(child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _buildHeader(loc)),
              SliverToBoxAdapter(child: _buildModules(loc)),
              SliverToBoxAdapter(child: _buildDua(loc)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildModules(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(children: List.generate(5, (i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildCardWide(i, loc),
      ))),
    );
  }

  Widget _buildCardWide(int i, AppLocalizations loc) {
    final m = _getModules(loc)[i];

    // Маршрут такси — индекс 1
    if (i == 1) {
      return _RaisedCard(
        onTap: () => _openMarshrutMenu(),
        color: m['c1'] as Color,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            m['image'] as String,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [m['c1'] as Color, m['c2'] as Color],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _RaisedCard(
      onTap: () => _open(i),
      color: m['c1'] as Color,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          m['image'] as String,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [m['c1'] as Color, m['c2'] as Color],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoBanner(AppLocalizations loc) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFB71C1C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.wifi_off, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(loc.translate('no_internet'),
            style: const TextStyle(
                color: Colors.white,
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildHeader(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${_greeting(loc)}, ${_honorificName(loc)}',
            style: const TextStyle(
                fontSize: AppText.titleMedium,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black26, blurRadius: 4)]),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            loc.translate('allah_protect'),
            style: TextStyle(
                fontSize: AppText.bodySmall,
                color: Colors.white.withOpacity(0.85),
                fontStyle: FontStyle.italic),
          ),
        ])),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()))
              .then((_) => _loadUser()),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(child: Text(
              _name.isNotEmpty ? _name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: AppText.titleSmall,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            )),
          ),
        ),
      ]),
    );
  }

  Widget _buildDua(AppLocalizations loc) {
    final dua = _todayDua;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(dua['ar']!,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1), height: 1.8),
        ),
        const SizedBox(height: 4),
        Text(dua['uz']!,
          textAlign: TextAlign.left,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: Color(0xFF1565C0), height: 1.4),
        ),
      ]),
    );
  }
}

// ── 3D карточка ──
class _RaisedCard extends StatefulWidget {
  final VoidCallback onTap;
  final Color color;
  final Widget child;

  const _RaisedCard({
    required this.onTap,
    required this.color,
    required this.child,
  });

  @override
  State<_RaisedCard> createState() => _RaisedCardState();
}

class _RaisedCardState extends State<_RaisedCard>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double>   _scaleAnim;
  late Animation<double>   _translateAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnim = Tween(begin: 1.0, end: 0.96).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _translateAnim = Tween(begin: -8.0, end: 2.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_)  => _ctrl.forward();
  void _onTapUp(_)    { _ctrl.reverse(); widget.onTap(); }
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   _onTapDown,
      onTapUp:     _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..translate(0.0, _translateAnim.value)
            ..scale(_scaleAnim.value),
          child: Material(
            elevation: 12 - _ctrl.value * 8,
            shadowColor: widget.color.withOpacity(0.5),
            borderRadius: BorderRadius.circular(18),
            color: Colors.transparent,
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(children: [
                  Positioned.fill(child: child!),
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: 1.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.white.withOpacity(
                              0.6 - _ctrl.value * 0.5),
                          Colors.white.withOpacity(0),
                        ]),
                      ),
                    ),
                  ),
                  if (_ctrl.value > 0)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black
                            .withOpacity(_ctrl.value * 0.08),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}