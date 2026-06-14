import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/saved_place.dart';
import '../../../../repositories/local_taxi_block_repository.dart';
import '../../../../services/location_service.dart';

/// Mahalliy taksi yo'lovchi entry-экранининг ҳолатини бошқаради:
///   - GPS орқали жорий манзилни аниқлаш
///   - SharedPreferences'da сақланган манзилларни (`SavedPlace`) бошқариш
///   - Qidiruv bekor blok (`local_taxi_block/state`, CF, 5/10/10)
///
/// `from`/`to` text fieldlarini ушбу controller кузатмайди — View ўз
/// `TextEditingController`лари бўйича иш олиб боради ва қидирув тугмаси
/// босилганда қийматларни бевосита `SearchingScreen`-га узатади.
class LocalTaxiController extends ChangeNotifier {
  LocalTaxiController({
    required LocationService locationService,
    LocalTaxiBlockRepository? blockRepo,
  })  : _locationService = locationService,
        _blockRepo = blockRepo ?? LocalTaxiBlockRepository();

  final LocationService _locationService;
  final LocalTaxiBlockRepository _blockRepo;

  static const _savedPlacesKey = 'saved_places';
  static const _maxSavedPlaces = 6;

  bool isGpsLoading = false;
  String? infoMessage;
  String? errorMessage;
  List<SavedPlace> savedPlaces = const [];

  Future<void> init() async {
    await loadSavedPlaces();
  }

  // ─── GPS ───────────────────────────────────────────────────────────

  /// Жорий GPS манзилни матн кўринишида қайтаради. Хатолик бўлса `null`,
  /// `errorMessage` сақланади.
  Future<String?> getCurrentAddress() async {
    isGpsLoading = true;
    notifyListeners();
    try {
      final addr = await _locationService.getCurrentAddress(
        gpsMediumTimeout: const Duration(seconds: 5),
        gpsHighTimeout: const Duration(seconds: 12),
        geocodeTimeout: const Duration(seconds: 5),
      );
      infoMessage = 'gps_detected';
      return addr;
    } on LocationException catch (e) {
      errorMessage = switch (e.kind) {
        LocationErrorKind.permissionDenied => 'gps_permission_denied_msg',
        LocationErrorKind.serviceDisabled => 'gps_service_disabled_msg',
        LocationErrorKind.timeout => 'gps_timeout_msg',
        LocationErrorKind.lookupFailed => 'gps_lookup_failed_msg',
      };
      return null;
    } catch (_) {
      errorMessage = 'gps_error';
      return null;
    } finally {
      isGpsLoading = false;
      notifyListeners();
    }
  }

  // ─── Saved places (SharedPreferences) ─────────────────────────────

  Future<void> loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPlacesKey);
    if (raw == null || raw.isEmpty) {
      savedPlaces = const [];
      notifyListeners();
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List;
      savedPlaces = decoded
          .map((e) => SavedPlace.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {
      savedPlaces = const [];
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _savedPlacesKey, jsonEncode(savedPlaces.map((p) => p.toJson()).toList()));
  }

  /// Янги манзил қўшиш. Лимит ошса `false` ва `errorMessage` сақланади.
  Future<bool> addSavedPlace(SavedPlace place) async {
    if (savedPlaces.length >= _maxSavedPlaces) {
      errorMessage = 'max_saved_places|$_maxSavedPlaces';
      notifyListeners();
      return false;
    }
    savedPlaces = [...savedPlaces, place];
    await _persist();
    infoMessage = 'place_saved|${place.name}';
    notifyListeners();
    return true;
  }

  Future<void> removeSavedPlaceByName(String name) async {
    final next = savedPlaces.where((p) => p.name != name).toList(growable: false);
    if (next.length == savedPlaces.length) return;
    savedPlaces = next;
    await _persist();
    infoMessage = 'place_deleted|$name';
    notifyListeners();
  }

  // ─── Local taxi qidiruv bloki ─────────────────────────────────────

  /// Агар фойдаланувчи hозирча бloкlangan bo'lsa, "qancha minutdan keyin"
  /// xabari qaytadi; aks holda `null`.
  Future<String?> checkGhostBlock() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = (prefs.getString('user_phone') ?? '')
        .replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) return null;
    final blockedUntil = await _blockRepo.getBlockedUntil(phone);
    if (blockedUntil == null) return null;
    final remaining = blockedUntil.difference(DateTime.now());
    return 'ghost_blocked|${remaining.inMinutes}';
  }

  void clearMessages() {
    if (infoMessage == null && errorMessage == null) return;
    infoMessage = null;
    errorMessage = null;
    notifyListeners();
  }
}
