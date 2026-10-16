import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../models/ev_charging_station.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../controllers/ev_trip_controller.dart';
import '../data/ev_trip_geo_catalog.dart';
import '../data/ev_trip_place_search.dart';
import '../widgets/ev_car_sheet.dart';
import '../models/ev_trip_plan.dart' show EvCarSpec;
import '../widgets/ev_trip_plan_view.dart';
import 'ev_trip_map_screen.dart';

/// ⚡ «Қаерга борамиз?» — EV сафар ёрдамчиси.
///
/// Экран атайин битта саволдан бошланади. Автомобил маълумоти гаражда
/// бир марта сақланади, шунинг учун бу ерда фақат МАНЗИЛ ва ҲОЗИРГИ
/// ЗАРЯД сўралади.
class EvTripScreen extends StatefulWidget {
  const EvTripScreen({
    super.key,
    required this.uid,
    required this.originLat,
    required this.originLng,
    required this.stations,
  });

  final String uid;
  final double originLat;
  final double originLng;

  /// Барча актив станциялар (`watchAllActive`) — экран ўз обунасини
  /// яратмайди, харита экрани аллақачон тинглаб турган рўйхат узатилади.
  final List<EvChargingStation> stations;

  @override
  State<EvTripScreen> createState() => _EvTripScreenState();
}

class _EvTripScreenState extends State<EvTripScreen> {
  final _repo = OilChangeRepository();
  final _controller = EvTripController();
  final _searchCtrl = TextEditingController();

  OilVehicle? _car;

  /// Режа ҲИСОБЛАНГАН пайтдаги автомобил: кейин ҳайдовчи машинани таҳрирласа
  /// ҳам, кўрсатилган энергия/вақт шу режага тегишли бўлиб қолади.
  EvCarSpec? _planCar;
  bool _carLoading = true;
  EvTripPlace? _destination;
  double _soc = 80;

  /// Qo'lda yozilgan 22 shahar darhol; tizimdagi barcha viloyat/tumanlar
  /// yuklangach (seans davomida bir marta) qo'shiladi.
  EvTripPlaceIndex _places = EvTripPlaceIndex.build();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _loadCar();
    _loadPlaces();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCar() async {
    final list = await _repo.watchVehicles(widget.uid).first;
    if (!mounted) return;
    // Гаражда бир нечта машина бўлиши мумкин — EV маълумоти тўлиқ
    // бўлгани устун (`watchVehicles` асосийни биринчи қайтаради).
    OilVehicle? withSpec;
    OilVehicle? electric;
    for (final v in list) {
      withSpec ??= v.hasEvSpec ? v : null;
      electric ??= v.isElectric ? v : null;
    }
    setState(() {
      _car = withSpec ?? electric;
      _carLoading = false;
    });
  }

  Future<void> _loadPlaces() async {
    final index = await EvTripGeoCatalog.load();
    if (!mounted) return;
    setState(() => _places = index);
  }

  Future<void> _editCar() async {
    final saved = await EvCarSheet.show(
      context,
      uid: widget.uid,
      vehicle: _car,
    );
    if (saved != null && mounted) setState(() => _car = saved);
  }

  String _langCode() {
    final locale = Localizations.localeOf(context);
    return switch (locale.languageCode) {
      'ru' => 'ru',
      'uz' => locale.scriptCode == 'Latn' ? 'uz_Latn' : 'uz_Cyrl',
      _ => 'uz_Cyrl',
    };
  }

  Future<void> _calculate() async {
    final car = _car?.evSpec;
    final dest = _destination;
    if (car == null || dest == null) return;
    _planCar = car;

    await _controller.planTrip(
      originLat: widget.originLat,
      originLng: widget.originLng,
      // Tayyor koordinata bor bo'lsa shu; tuman/viloyatda koordinata yo'q -
      // matnli manzil Google Directions'ga beriladi.
      destinationLat: dest.lat,
      destinationLng: dest.lng,
      destinationText: dest.hasCoords ? null : dest.routeText,
      car: car,
      socPercent: _soc.round(),
      stations: widget.stations,
    );

    // Reja tayyor - to'liq ekranli jonli xarita. Holat (kontroller) shu
    // ekranda qoladi: orqaga qaytilganda reja yo'qolmaydi.
    if (mounted && _controller.plan != null) _openMap();
  }

  /// To'liq ekranli xarita (reja + jonli mashina). Tugash nuqtasi:
  /// tayyor koordinata yoki Google topgan end_location.
  Future<void> _openMap() async {
    final plan = _controller.plan;
    final destLat = _controller.destinationLat;
    final destLng = _controller.destinationLng;
    if (plan == null || destLat == null || destLng == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EvTripMapScreen(
        plan: plan,
        route: _controller.routePoints,
        corridorStations: _controller.corridorStations,
        originLat: widget.originLat,
        originLng: widget.originLng,
        destinationLat: destLat,
        destinationLng: destLng,
        onOpenNavigator: _openNavigator,
        routeMinutes: _controller.routeMinutes,
        car: _planCar,
      ),
    ));
  }

  void _openNavigator() {
    // Haqiqiy koordinata: tayyor yoki Google topgan tugash nuqtasi.
    final destLat = _controller.destinationLat;
    final destLng = _controller.destinationLng;
    if (destLat == null || destLng == null) return;
    openMapsEvTripRoute(
      originLat: widget.originLat,
      originLng: widget.originLng,
      destinationLat: destLat,
      destinationLng: destLng,
      stops: _controller.navigationStops,
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _controller.plan;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: Text(context.tr('ev_trip_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carBlock(),
          const SizedBox(height: 16),
          _destinationBlock(),
          if (_destination != null) ...[
            const SizedBox(height: 16),
            _socBlock(),
            const SizedBox(height: 16),
            _calculateButton(),
          ],
          if (_controller.error != null) ...[
            const SizedBox(height: 16),
            _errorBox(_controller.error!),
          ],
          if (plan != null) ...[
            const SizedBox(height: 20),
            _showMapButton(),
            const SizedBox(height: 16),
            EvTripPlanView(
              plan: plan,
              onOpenNavigator: _openNavigator,
              routeMinutes: _controller.routeMinutes,
              car: _planCar,
            ),
          ],
        ],
      ),
    );
  }

  // ---- Автомобил ----

  Widget _carBlock() {
    if (_carLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    final car = _car;
    final ready = car?.hasEvSpec == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ready ? Colors.white : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ready ? const Color(0xFFE3E7EE) : const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          Icon(Icons.electric_car_rounded,
              color: ready ? AppColors.primaryText : const Color(0xFFE65100)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready
                      ? (car!.model.trim().isNotEmpty
                          ? car.model.trim()
                          : context.tr('ev_trip_car_title'))
                      : context.tr('ev_trip_car_missing'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (ready)
                  Text(
                    '${_fmt(car!.evBatteryKwh)} kWh · '
                    '${_fmt(car.evConsumptionKwhPer100Km)} kWh/100${context.tr('ev_trip_km')}'
                    '${car.evConnectors.isEmpty ? '' : ' · ${car.evConnectors.join(' · ')}'}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54),
                  )
                else
                  Text(
                    context.tr('ev_trip_car_missing_body'),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _editCar,
            child: Text(ready
                ? context.tr('edit')
                : context.tr('ev_trip_car_fill')),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  // ---- Манзил ----

  Widget _destinationBlock() {
    final lang = _langCode();
    final dest = _destination;

    if (dest != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E7EE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.place_rounded, color: AppColors.primaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dest.displayFor(lang),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _destination = null;
                _searchCtrl.clear();
                _controller.clear();
              }),
              child: Text(context.tr('ev_trip_change')),
            ),
          ],
        ),
      );
    }

    // Xotirada qidiruv: tarmoq so'rovi yo'q. Bo'sh maydon - mashhur shaharlar;
    // yozilganda - eng mos 8 ta (uch tildagi nom bo'yicha).
    final matches = _places.search(_searchCtrl.text, lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('ev_trip_where'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: context.tr('ev_trip_search_hint'),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3E7EE)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3E7EE)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(context.tr('ev_trip_not_found'),
                style: const TextStyle(color: Colors.black54)),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E7EE)),
            ),
            child: Column(
              children: [
                for (final d in matches)
                  ListTile(
                    dense: true,
                    title: Text(d.displayFor(lang)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => setState(() {
                      _destination = d;
                      _controller.clear();
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- Заряд ----

  Widget _socBlock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.battery_charging_full_rounded,
                  color: AppColors.primaryText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('ev_trip_charge_now'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Text('${_soc.round()}%',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          Slider(
            value: _soc,
            min: 5,
            max: 100,
            divisions: 19,
            label: '${_soc.round()}%',
            onChanged: (v) => setState(() => _soc = v),
          ),
        ],
      ),
    );
  }

  Widget _calculateButton() {
    final ready = _car?.hasEvSpec == true && _destination != null;
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: ready && !_controller.loading ? _calculate : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: AppColors.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _controller.loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.onPrimary),
              )
            : Text(
                context.tr('ev_trip_calculate'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  // ---- Харита ----

  /// Hisoblangan reja uchun to'liq ekranli xaritani qayta ochish.
  Widget _showMapButton() {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _openMap,
        icon: const Icon(Icons.map_rounded, size: 20),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryText,
          side: const BorderSide(color: AppColors.primaryText, width: 1.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        label: Text(context.tr('ev_trip_show_map')),
      ),
    );
  }

  Widget _errorBox(String code) {
    final text = switch (code) {
      'route_geometry_missing' => context.tr('ev_trip_error_geometry'),
      _ => context.tr('ev_trip_error_route'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFFC62828)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
