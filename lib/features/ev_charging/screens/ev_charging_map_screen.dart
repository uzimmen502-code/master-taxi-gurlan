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
  final _searchCtrl = TextEditingController();

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
    _searchCtrl.dispose();
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
                    _buildSearchAndFilters(controller),
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
      floatingActionButton: controller.hasLocation
          ? _PaidAddStationFab(
              onTap: () => _openPaidAddFlow(context, controller),
            )
          : null,
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

  Widget _buildSearchAndFilters(EvChargingMapController controller) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Манзил бўйича қидириш',
              filled: true,
              fillColor: Colors.white,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => controller.centerOnAddress(_searchCtrl.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: controller.centerOnAddress,
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

/// «Станция қўшиш (пуллик)» — ихчам pill-тугма (2026-09-22, дизайн
/// тузатиш: стандарт `FloatingActionButton.extended` узун матн билан
/// иккиланиб, экран энига чўзилиб кетган эди — контент ўлчамига мос
/// қўлда ясалган тугма ишлатилди). Яшил эмас — харита фонидаги яшил ва
/// оранж белгилардан ажралиб турадиган "пуллик/premium" ранги (олтин).
class _PaidAddStationFab extends StatelessWidget {
  const _PaidAddStationFab({required this.onTap});

  final VoidCallback onTap;

  static const _accent = Color(0xFFB8860B); // тўқ олтин — "пуллик" белгиси
  static const _accentDark = Color(0xFF8C6400);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _accent,
      elevation: 4,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _accentDark, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              const Text(
                'Станция қўшиш',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(46),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'пуллик',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
