import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/ev_charging_rules_holder.dart';
import '../../../models/ev_charging_station.dart';

/// Faqat "🧭 Йўл кўрсатиш" босилганда активланадиган navigatsiya sessiyasi
/// (14–16-band): background geofencing YO'Q — faqat foreground'da GPS
/// tinglanadi, ilova background'ga o'tsa yoki foydalanuvchi bekor qilsa
/// target tozalanadi. Shu sababli oddiy o'tib ketishda hech qanday xabar
/// chiqmaydi — faqat aktiv sessiya davomida.
class EvNavigationSessionController extends ChangeNotifier
    with WidgetsBindingObserver {
  EvChargingStation? _target;
  bool _arrived = false;
  StreamSubscription<Position>? _positionSub;
  void Function(EvChargingStation station)? onArrived;

  EvChargingStation? get target => _target;
  bool get isActive => _target != null;
  bool get arrived => _arrived;

  /// "🧭 Йўл кўрсатиш" bosilganda chaqiriladi (15-band).
  void startNavigationTo(EvChargingStation station) {
    _target = station;
    _arrived = false;
    WidgetsBinding.instance.addObserver(this);
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onPosition);
    notifyListeners();
  }

  /// Foydalanuvchi navigatsiyani bekor qilganda yoki flow tugaganda.
  void cancelNavigation() {
    _clearSession();
    notifyListeners();
  }

  void _onPosition(Position pos) {
    final target = _target;
    if (target == null || _arrived) return;
    final radiusMeters = EvChargingRulesHolder.current.arrivalRadiusMeters;
    if (hasArrived(
      currentLat: pos.latitude,
      currentLng: pos.longitude,
      targetLat: target.latitude,
      targetLng: target.longitude,
      radiusMeters: radiusMeters,
    )) {
      _arrived = true;
      onArrived?.call(target);
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Oddiy o'tib ketishda xabar chiqmasin — background'da session yo'q (16-band).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _clearSession();
      notifyListeners();
    }
  }

  void _clearSession() {
    _target = null;
    _arrived = false;
    _positionSub?.cancel();
    _positionSub = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    _clearSession();
    super.dispose();
  }

  /// Sof mantiq — Geolocator streamsiz test qilinadi.
  static bool hasArrived({
    required double currentLat,
    required double currentLng,
    required double targetLat,
    required double targetLng,
    required int radiusMeters,
  }) {
    return Geolocator.distanceBetween(
          currentLat,
          currentLng,
          targetLat,
          targetLng,
        ) <=
        radiusMeters;
  }
}
