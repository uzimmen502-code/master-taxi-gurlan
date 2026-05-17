import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/queue_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../driver/screens/driver_panel_marshrut_screen.dart';
import '../../driver/screens/driver_register_marshrut_screen.dart';
import '../../../../services/location_service.dart';
import '../../../../utils/app_theme.dart';
import '../controllers/marshrut_search_controller.dart';
import '../widgets/mfy_dropdown.dart';
import '../widgets/schedule_card.dart';
import 'marshrut_waiting_screen.dart';

/// Yo'lovchi marshrut taksi qidirayotgan ekran.
///
/// Ko'rsatadi: GPS banner, MFY tanlash dropdown'lari, qidiruv tugmasi,
/// natijalar ro'yxati va "ЧАҚИРИШ" tugmasi marshrut waiting flow'iga ulaydi.
class MarshrutTaxiScreen extends StatelessWidget {
  const MarshrutTaxiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MarshrutSearchController>(
      create: (ctx) => MarshrutSearchController(
        schedulesRepo: ctx.read<SchedulesRepository>(),
        queueRepo: ctx.read<QueueRepository>(),
        locationService: ctx.read<LocationService>(),
      )..init(),
      child: const _MarshrutTaxiView(),
    );
  }
}

class _MarshrutTaxiView extends StatefulWidget {
  const _MarshrutTaxiView();

  @override
  State<_MarshrutTaxiView> createState() => _MarshrutTaxiViewState();
}

class _MarshrutTaxiViewState extends State<_MarshrutTaxiView> {
  static const Color _blue = Color(0xFF0288D1);

  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  bool _showFromDropdown = false;
  bool _showToDropdown = false;
  Timer? _debounce;
  String? _lastErrorShown;
  bool _directionChanged = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _onFromQueryChanged(String q) {
    setState(() => _showFromDropdown = q.length >= 2);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _showFromDropdown = q.length >= 2);
    });
  }

  void _onToQueryChanged(String q) {
    setState(() => _showToDropdown = q.length >= 2);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _showToDropdown = q.length >= 2);
    });
  }

  Future<void> _openDriverPanel() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = phoneDigits(prefs.getString('user_phone') ?? '');
    if (!mounted) return;

    if (userId.isEmpty) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DriverRegisterMarshrutScreen()));
      return;
    }

    final profile =
        await context.read<MarshrutDriverRepository>().getProfile(userId);
    if (!mounted) return;

    if (profile != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DriverPanelMarshrutScreen(
          carModel: profile.carModel,
          plate: profile.plate,
          seats: profile.seats,
          stops: profile.stops,
          driverName: profile.driverName,
          driverPhone: profile.driverPhone,
          driverId: profile.uid,
        ),
      ));
    } else {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DriverRegisterMarshrutScreen()));
    }
  }

  Future<void> _onCall(int idx) async {
    final c = context.read<MarshrutSearchController>();
    final prep = await c.prepareCall(idx);
    if (!mounted) return;
    if (!prep.isReady) {
      _snack(prep.error!);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarshrutWaitingScreen(
          pickupMfy: c.fromMfy,
          pickupAddr: '',
          dropoffMfy: c.toMfy,
          drivers: prep.drivers,
          userLat: c.userLat,
          userLng: c.userLng,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _directionChanged = true);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF0277BD),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MarshrutSearchController>();

    if (c.errorMessage != null && c.errorMessage != _lastErrorShown) {
      _lastErrorShown = c.errorMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(c.errorMessage!);
        c.clearTransient();
        _lastErrorShown = null;
      });
    }

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
              onTap: _openDriverPanel,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          setState(() {
            _showFromDropdown = false;
            _showToDropdown = false;
          });
        },
        child: Column(children: [
          if (c.gpsUnavailable) const _GpsBanner(),
          _SearchPanel(
            fromCtrl: _fromCtrl,
            toCtrl: _toCtrl,
            fromMfy: c.fromMfy,
            toMfy: c.toMfy,
            showFromDropdown: _showFromDropdown,
            showToDropdown: _showToDropdown,
            isSearching: c.isSearching,
            onFromQueryChanged: _onFromQueryChanged,
            onToQueryChanged: _onToQueryChanged,
            onFromSelected: (v) {
              c.setFromMfy(v);
              _fromCtrl.text = v;
              setState(() => _showFromDropdown = false);
            },
            onToSelected: (v) {
              c.setToMfy(v);
              _toCtrl.text = v;
              setState(() => _showToDropdown = false);
            },
            onSearch: c.isSearching
                ? null
                : () {
                    setState(() => _directionChanged = false);
                    c.search();
                  },
          ),
          Expanded(child: _buildResults(c)),
        ]),
      ),
    );
  }

  Widget _buildResults(MarshrutSearchController c) {
    if (!c.searched) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🚐', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        Text('Манзил киритиб қидиринг',
            style: TextStyle(
                fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
      ]));
    }
    if (c.results.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('😔', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Ҳайдовчи топилмади',
            style: TextStyle(
                fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
        const SizedBox(height: 6),
        Text('Яқин атрофда мавжуд ҳайдовчи йўқ',
            style: TextStyle(
                fontSize: AppText.bodySmall, color: Colors.grey.shade400)),
      ]));
    }
    return Column(children: [
      if (c.searched && c.results.isNotEmpty && _directionChanged)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.refresh, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Ҳайдовчи йўналишни ўзгартирган бўлиши мумкин. Қайта қидиринг.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          ]),
        ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Text('🚐 ${c.results.length} та машина топилди',
              style: const TextStyle(
                  fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
        ]),
      ),
      Expanded(
          child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: c.results.length,
        itemBuilder: (_, i) => ScheduleCard(
          result: c.results[i],
          onCall: () => _onCall(i),
        ),
      )),
    ]);
  }
}

class _GpsBanner extends StatelessWidget {
  const _GpsBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Text(
        '📍 GPS аниқланмади — ҳамма ҳайдовчилар кўрсатилмоқда',
        style: TextStyle(color: Colors.white, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.fromCtrl,
    required this.toCtrl,
    required this.fromMfy,
    required this.toMfy,
    required this.showFromDropdown,
    required this.showToDropdown,
    required this.isSearching,
    required this.onFromQueryChanged,
    required this.onToQueryChanged,
    required this.onFromSelected,
    required this.onToSelected,
    required this.onSearch,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final String fromMfy;
  final String toMfy;
  final bool showFromDropdown;
  final bool showToDropdown;
  final bool isSearching;
  final ValueChanged<String> onFromQueryChanged;
  final ValueChanged<String> onToQueryChanged;
  final ValueChanged<String> onFromSelected;
  final ValueChanged<String> onToSelected;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _MarshrutTaxiViewState._blue,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(children: [
        const Text('Қаердан',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70)),
        const SizedBox(height: 4),
        MfyDropdown(
          ctrl: fromCtrl,
          hint: 'МФЙ танланг...',
          value: fromMfy,
          show: showFromDropdown,
          icon: Icons.circle_outlined,
          iconColor: Colors.greenAccent,
          onQueryChanged: onFromQueryChanged,
          onSelected: onFromSelected,
        ),
        const SizedBox(height: 20),
        const Text('Қаерга',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70)),
        const SizedBox(height: 4),
        MfyDropdown(
          ctrl: toCtrl,
          hint: 'МФЙ танланг...',
          value: toMfy,
          show: showToDropdown,
          icon: Icons.location_on,
          iconColor: Colors.redAccent,
          onQueryChanged: onToQueryChanged,
          onSelected: onToSelected,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: onSearch,
            icon: isSearching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, size: 20),
            label: Text(isSearching ? 'Қидирилмоқда...' : 'ҲАЙДОВЧИ ҚИДИРИШ',
                style: const TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _MarshrutTaxiViewState._blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}
