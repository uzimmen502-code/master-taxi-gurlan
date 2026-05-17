import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/saved_place.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/location_service.dart';

/// Mahalliy taksi yo'lovchi entry-экранининг ҳолатини бошқаради:
///   - GPS орқали жорий манзилни аниқлаш
///   - SharedPreferences'da сақланган манзилларни (`SavedPlace`) бошқариш
///   - Ghost protection (`users.blockedUntil`) текшируви
///
/// `from`/`to` text fieldlarini ушбу controller кузатмайди — View ўз
/// `TextEditingController`лари бўйича иш олиб боради ва қидирув тугмаси
/// босилганда қийматларни бевосита `SearchingScreen`-га узатади.
class LocalTaxiController extends ChangeNotifier {
  LocalTaxiController({
    required LocationService locationService,
    required UserRepository userRepo,
  })  : _locationService = locationService,
        _userRepo = userRepo;

  final LocationService _locationService;
  final UserRepository _userRepo;

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
        timeout: const Duration(seconds: 15),
      );
      infoMessage = '📍 Жойлашув аниқланди';
      return addr;
    } on LocationException catch (e) {
      errorMessage = e.kind == LocationErrorKind.permissionDenied
          ? 'GPS рухсати берилмади'
          : 'GPS аниқланмади';
      return null;
    } catch (_) {
      errorMessage = 'GPS аниқланмади';
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
      errorMessage = 'Максимум $_maxSavedPlaces та манзил';
      notifyListeners();
      return false;
    }
    savedPlaces = [...savedPlaces, place];
    await _persist();
    infoMessage = '${place.name} сақланди';
    notifyListeners();
    return true;
  }

  Future<void> removeSavedPlaceByName(String name) async {
    final next = savedPlaces.where((p) => p.name != name).toList(growable: false);
    if (next.length == savedPlaces.length) return;
    savedPlaces = next;
    await _persist();
    infoMessage = '$name ўчирилди';
    notifyListeners();
  }

  // ─── Ghost protection ──────────────────────────────────────────────

  /// Агар фойдаланувчи hозирча бloкlangan bo'lsa, "qancha minutdan keyin"
  /// xabari qaytadi; aks holda `null`.
  Future<String?> checkGhostBlock() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = (prefs.getString('user_phone') ?? '')
        .replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) return null;
    final blockedUntil = await _userRepo.getBlockedUntil(phone);
    if (blockedUntil == null) return null;
    final remaining = blockedUntil.difference(DateTime.now());
    return '⛔ ${remaining.inMinutes} дақиқадан кейин қайта уриниб кўринг';
  }

  void clearMessages() {
    if (infoMessage == null && errorMessage == null) return;
    infoMessage = null;
    errorMessage = null;
    notifyListeners();
  }
}
