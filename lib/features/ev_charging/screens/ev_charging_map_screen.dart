import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../../core/ev_charging_rules_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../../../services/location_service.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../controllers/ev_charging_map_controller.dart';
import '../controllers/ev_navigation_session_controller.dart';
import '../widgets/ev_arrival_flow.dart';
import '../widgets/ev_map_view.dart';
import '../widgets/ev_station_card.dart';
import '../widgets/ev_station_tariff_sheet.dart';
import 'add_ev_station_screen.dart';

/// ⚡ Электромобил зарядлаш нуқталари — асосий xarita ekrani (11-band).
/// Faqat ro'yxatdan o'tgan (registratsiyadan o'tgan) foydalanuvchilar uchun —
/// anonim (guest) bo'lsa ro'yxatdan o'tishga yo'naltiriladi (2-band, mavjud
/// `profile_screen.dart` gate idiomiga mos).
class EvChargingMapScreen extends StatelessWidget {
  const EvChargingMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
      return const _EvChargingAnonymousGate();
    }
    return ChangeNotifierProvider<EvChargingMapController>(
      create: (ctx) => EvChargingMapController(
        repository: ctx.read<EvStationRepository>(),
        locationService: ctx.read<LocationService>(),
      )..init(),
      child: const _EvChargingMapView(),
    );
  }
}

class _EvChargingAnonymousGate extends StatelessWidget {
  const _EvChargingAnonymousGate();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: const Text('⚡ Зарядлаш нуқталари')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.ev_station_rounded, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'Бу бўлим фақат рўйхатдан ўтган фойдаланувчилар учун очиқ.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                      (_) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Рўйхатдан ўтиш'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvChargingMapView extends StatefulWidget {
  const _EvChargingMapView();

  @override
  State<_EvChargingMapView> createState() => _EvChargingMapViewState();
}

class _EvChargingMapViewState extends State<_EvChargingMapView> {
  late final EvNavigationSessionController _nav;

  @override
  void initState() {
    super.initState();
    EvChargingRulesHolder.load();
    _nav = EvNavigationSessionController()
      ..onArrived = (station) {
        EvArrivalFlow.show(
          context,
          station: station,
          repository: context.read<EvStationRepository>(),
        );
      };
  }

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  void _onStationTap(EvChargingStation station) {
    final controller = context.read<EvChargingMapController>();
    final distanceKm = controller.hasLocation
        ? Geolocator.distanceBetween(
              controller.lat!,
              controller.lng!,
              station.latitude,
              station.longitude,
            ) /
            1000
        : null;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EvStationCard(
        station: station,
        distanceKm: distanceKm,
        // «Бўш / Банд» — жамоа хабари; 30 дақиқа амал қилади.
        onSetOccupancy: ({required bool busy}) =>
            context.read<EvStationRepository>().setOccupancy(
                  station.id,
                  busy: busy,
                ),
        onNavigate: () {
          Navigator.pop(context);
          openMapsNavigation(lat: station.latitude, lng: station.longitude);
          _nav.startNavigationTo(station);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EvChargingMapController>();
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('⚡ Зарядлаш нуқталари'),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.error != null
              ? Center(child: Text(controller.error!))
              : Column(
                  children: [
                    _buildAddStationAndFilters(controller),
                    Expanded(
                      child: EvMapView(
                        centerLat: controller.lat!,
                        centerLng: controller.lng!,
                        stations: controller.stations,
                        onStationTap: _onStationTap,
                      ),
                    ),
                  ],
                ),
    );
  }

  /// ⚡ Станция қўшиш — ПУЛЛИК (эга қарори, 2026-09-22): аввал тариф+қадамлар
  /// варақаси, тариф танлангандан кейин форма экранига ўтилади.
  Future<void> _openPaidAddFlow(
    BuildContext context,
    EvChargingMapController controller,
  ) async {
    final phone = canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    if (phone.length < 9) return; // Гейт allaqachon юқорида — назарий ҳимоя.

    final tariff = await showModalBottomSheet<EvStationTariff>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EvStationTariffSheet(uid: phone),
    );
    if (tariff == null || !context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEvStationScreen(
          initialLat: controller.lat,
          initialLng: controller.lng,
          tariff: tariff,
          phone: phone,
        ),
      ),
    );
  }

  Widget _buildAddStationAndFilters(EvChargingMapController controller) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _PaidAddStationBar(
            onTap: () => _openPaidAddFlow(context, controller),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('Ҳаммаси', null, controller),
                _filterChip('AC', 'AC', controller),
                _filterChip('DC', 'DC', controller),
                _filterChip('AC+DC', 'AC+DC', controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value, EvChargingMapController controller) {
    final isSelected = controller.chargingTypeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => controller.setChargingTypeFilter(value),
      ),
    );
  }
}

/// «Станция қўшиш (пуллик)» — қидирув майдони ўрнига жойлашган тўлиқ энли
/// панель (2026-09-22, дизайн тузатиш #2: қидирув майдони олиб ташланди,
/// тугма унинг ўрнига кўчирилди ва ранги харита панели/AppBar рангига
/// (яшил, [AppColors.primaryDark]) уйғунлаштирилди — энди алоҳида сузиб
/// юрган элемент эмас, юқори панелнинг табиий давоми). "Пуллик" сигнали
/// йўқолиб кетмаслиги учун кичик олтин белги сақлаб қолинди.
class _PaidAddStationBar extends StatelessWidget {
  const _PaidAddStationBar({required this.onTap});

  final VoidCallback onTap;

  static const _badgeGold = Color(0xFFF9A825);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryDark,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              const Text(
                'Станция қўшиш',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _badgeGold,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'пуллик',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
