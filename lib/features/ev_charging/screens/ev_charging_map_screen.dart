import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../../core/ev_charging_rules_holder.dart';
import '../../../core/l10n/l10n_extension.dart';
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
import 'ev_trip_screen.dart';

/// ⚡ Электромобил зарядлаш нуқталари — асосий xarita ekrani (11-band).
/// Faqat ro'yxatdan o'tgan (registratsiyadan o'tgan) foydalanuvchilar uchun —
/// anonim (guest) bo'lsa ro'yxatdan o'tishga yo'naltiriladi (2-band, mavjud
/// `profile_screen.dart` gate idiomiga mos).
class EvChargingMapScreen extends StatelessWidget {
  const EvChargingMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
      return const EvChargingAnonymousGate();
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

/// Рўйхатдан ўтмаган (меҳмон) фойдаланувчига кўрсатиладиган экран. Матнлар — 3 тилда (`ev_guest_gate_*`);
/// эга матни 2026-10-23: «EV станциялари базасини кўриш учун рўйхатдан ўтинг».
class EvChargingAnonymousGate extends StatelessWidget {
  const EvChargingAnonymousGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: Text('⚡ ${context.tr('ev_guest_gate_title')}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.ev_station_rounded, size: 64, color: AppColors.primaryText),
              const SizedBox(height: 16),
              Text(
                context.tr('ev_guest_gate_message'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(context.tr('ev_guest_gate_register')),
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

class _EvChargingMapViewState extends State<_EvChargingMapView>
    with WidgetsBindingObserver {
  late final EvNavigationSessionController _nav;
  StreamSubscription<ServiceStatus>? _gpsStatusSub;

  /// «GPS ўчиқ» хабари кўрсатилган бўлса, жойлашувни қайта аниқлайди — GPS ёқилгандан кейин хабар кетади.
  void _retryLocationIfNeeded() {
    if (!mounted) return;
    final controller = context.read<EvChargingMapController>();
    if (controller.error != null) controller.refreshLocation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Созламалардан (GPS/рухсат) қайтганда.
    if (state == AppLifecycleState.resumed) _retryLocationIfNeeded();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Тезкор панелдан GPS ёқилса — илова ёпилмайди, шунинг учун хизмат ҳолатини ҳам тинглаймиз.
    if (!kIsWeb) {
      try {
        _gpsStatusSub = Geolocator.getServiceStatusStream().listen(
          (status) {
            if (status == ServiceStatus.enabled) _retryLocationIfNeeded();
          },
          onError: (Object _) {},
        );
      } catch (_) {
        // Платформада қўллаб-қувватланмаса — фақат lifecycle ишлайди.
      }
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _gpsStatusSub?.cancel();
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
        title: Text('⚡ ${context.tr('ev_map_title')}'),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
                  children: [
                    // GPS йўқ — станциялар барибир кўринади, огоҳлантириш
                    // юқорида (аввал фақат хато матни эди).
                    if (controller.error != null)
                      MaterialBanner(
                        content: Text(context.trMsg(controller.error!)),
                        leading: const Icon(Icons.location_off_outlined),
                        actions: const [SizedBox.shrink()],
                      ),
                    _buildAddStationAndFilters(controller),
                    Expanded(
                      child: EvMapView(
                        centerLat: controller.centerLat,
                        centerLng: controller.centerLng,
                        initialZoom: controller.hasLocation
                            ? 14
                            : EvChargingMapController.fallbackZoom,
                        stations: controller.stations,
                        onStationTap: _onStationTap,
                      ),
                    ),
                  ],
                ),
    );
  }

  /// ⚡ Сафар ёрдамчиси. GPS бўлмаса очилмайди — режа бошланғич нуқтасиз
  /// ҳисобланмайди, шунинг учун ўйлаб топилган координата ишлатилмайди.
  Future<void> _openTripPlanner(EvChargingMapController controller) async {
    if (!controller.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('ev_trip_location_missing'))),
      );
      return;
    }
    final phone =
        canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    if (phone.length < 9) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EvTripScreen(
          uid: phone,
          originLat: controller.lat!,
          originLng: controller.lng!,
          // Филтрланмаган рўйхат — режа машинанинг разъёмига қараб
          // ўзи танлайди, AC/DC филтри фақат харита учун.
          stations: controller.allStations,
        ),
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
          // ⚡ «Қаерга борамиз?» — EV модули оддий станциялар харитаси
          // бўлиб қолмаслиги учун сафар ёрдамчиси энг устда.
          _TripPlannerBar(onTap: () => _openTripPlanner(controller)),
          const SizedBox(height: 8),
          _PaidAddStationBar(
            onTap: () => _openPaidAddFlow(context, controller),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(context.tr('bizmap_all'), null, controller),
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

/// ⚡ «Қаерга борамиз?» — сафар ёрдамчисига кириш. `_PaidAddStationBar`
/// билан бир хил шаклда, лекин тўлдирилган эмас — иккита тўлиқ яшил
/// панель бир-бири билан рақобатлашиб кетмаслиги учун.
class _TripPlannerBar extends StatelessWidget {
  const _TripPlannerBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryText, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.route_rounded,
                  color: AppColors.primaryText, size: 20),
              const SizedBox(width: 8),
              Text(
                context.tr('ev_trip_entry'),
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
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
              const Icon(Icons.add_rounded, color: AppColors.onPrimary, size: 20),
              const SizedBox(width: 6),
              Text(
                context.tr('ev_add_station'),
                style: const TextStyle(
                  color: AppColors.onPrimary,
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
                child: Text(
                  context.tr('ev_paid_badge'),
                  style: const TextStyle(
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
