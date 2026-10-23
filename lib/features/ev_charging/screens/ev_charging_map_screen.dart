import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/ev_map_top_overlay.dart';
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
    // Харита статус бар ва пастки соҳа остигача (эга қарори, 2026-10-16).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    // Бошқа экранлар учун одатдаги тизим панелларига қайтарилади.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _nav.dispose();
    super.dispose();
  }

  /// Харита экрани тўлиқ экранли (edge-to-edge); устига очиладиган оддий
  /// экранлар (сафар ёрдамчиси, станция қўшиш) одатдаги тизим панели билан
  /// чизилади, қайтганда харита режими тикланади.
  Future<void> _withNormalChrome(Future<Object?> Function() push) async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    try {
      await push();
    } finally {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
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
    final hasError = controller.error != null;
    // Хаританинг ўз тугмалари сузиб юрувчи панел тагидан чиқсин.
    final topInset = MediaQuery.paddingOf(context).top +
        EvChargingMapLayout.overlayHeight(hasError: hasError);
    // Харита бутун экранда: AppBar ва AC/DC филтр чиплари йўқ (эга қарори,
    // 2026-10-16). Филтр мантиқи контроллерда қолган, лекин UI йўқ —
    // харита доим барча станцияларни кўрсатади.
    return EvChargingMapLayout(
      loading: controller.loading,
      errorText: controller.error,
      onAddStation: () => _openPaidAddFlow(context, controller),
      onTripPlanner: () => _openTripPlanner(controller),
      map: EvMapView(
        centerLat: controller.centerLat,
        centerLng: controller.centerLng,
        initialZoom: controller.hasLocation
            ? 14
            : EvChargingMapController.fallbackZoom,
        stations: controller.stations,
        onStationTap: _onStationTap,
        // Пастда: тизим навигация тугмалари устида Google логотипи қолмасин.
        padding: EdgeInsets.only(
          top: topInset,
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
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

    await _withNormalChrome(() => Navigator.push(
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
    ));
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

    await _withNormalChrome(() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEvStationScreen(
          initialLat: controller.lat,
          initialLng: controller.lng,
          tariff: tariff,
          phone: phone,
        ),
      ),
    ));
  }
}
