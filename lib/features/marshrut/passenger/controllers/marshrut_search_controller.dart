import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../models/marshrut_driver_option.dart';
import '../../../../models/schedule.dart';
import '../../../../models/schedule_search_result.dart';
import '../../../../repositories/queue_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../services/location_service.dart';

/// Marshrut yo'lovchi qidiruv ekrani state mashinasi.
///
/// Mas'uliyatlari:
/// - GPS olish (xato bo'lsa, bayroq qo'yib, qidiruvni davom ettirish)
/// - Bugungi aktiv `schedules` ni olish va yo'nalish/masofa/ETA bo'yicha filtrlash
/// - "ЧАҚИРИШ" tugmasi bosilganda blok holatini tekshirish va navbatga qo'yish
class MarshrutSearchController extends ChangeNotifier {
  MarshrutSearchController({
    required SchedulesRepository schedulesRepo,
    required QueueRepository queueRepo,
    required LocationService locationService,
  })  : _schedules = schedulesRepo,
        _queue = queueRepo,
        _location = locationService;

  static const double _maxRadiusKm = 5;
  static const double _kmPerMinute = 0.4; // ~24 km/h taxi tezligi

  final SchedulesRepository _schedules;
  final QueueRepository _queue;
  final LocationService _location;

  // ─── State ──────────────────────────────────────────────────────────
  double? _userLat;
  double? _userLng;
  bool _gpsUnavailable = false;
  String _fromMfy = '';
  String _toMfy = '';
  bool _isSearching = false;
  bool _searched = false;
  List<ScheduleSearchResult> _results = const [];
  String? _errorMessage;

  double? get userLat => _userLat;
  double? get userLng => _userLng;
  bool get gpsUnavailable => _gpsUnavailable;
  String get fromMfy => _fromMfy;
  String get toMfy => _toMfy;
  bool get isSearching => _isSearching;
  bool get searched => _searched;
  List<ScheduleSearchResult> get results => _results;
  String? get errorMessage => _errorMessage;

  // ─── Lifecycle ──────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadGps();
  }

  Future<void> _loadGps() async {
    try {
      final c = await _location.getCurrentCoords(
          timeout: const Duration(seconds: 8));
      _userLat = c.lat;
      _userLng = c.lng;
      _gpsUnavailable = false;
    } catch (_) {
      _gpsUnavailable = true;
    }
    notifyListeners();
  }

  // ─── Form ───────────────────────────────────────────────────────────

  void setFromMfy(String v) {
    _fromMfy = v;
    notifyListeners();
  }

  void setToMfy(String v) {
    _toMfy = v;
    notifyListeners();
  }

  void clearTransient() {
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Search ─────────────────────────────────────────────────────────

  Future<void> search() async {
    if (_fromMfy.isEmpty) {
      _errorMessage = 'Қаердан МФЙ ни танланг';
      notifyListeners();
      return;
    }

    _isSearching = true;
    _results = const [];
    notifyListeners();

    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final schedules = await _schedules.searchActiveToday(date: dateStr);
      _results = _filterAndSort(schedules);
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
    }

    _isSearching = false;
    _searched = true;
    notifyListeners();
  }

  List<ScheduleSearchResult> _filterAndSort(List<Schedule> schedules) {
    final list = <ScheduleSearchResult>[];
    final hasGps = _userLat != null && _userLng != null;

    for (final s in schedules) {
      if (s.hasExpired) continue;
      if (s.seatsLeft <= 0) continue;
      if (!s.routeAllows(_fromMfy, _toMfy)) continue;

      double? distance;
      int? eta;
      if (hasGps && s.lat != null && s.lng != null) {
        distance = LocationService.distanceKm(
            _userLat!, _userLng!, s.lat!, s.lng!);
        if (distance > _maxRadiusKm) continue;
        eta = (distance / _kmPerMinute).round().clamp(1, 60);
      } else if (!hasGps) {
        eta = 3;
      }

      list.add(ScheduleSearchResult(
          schedule: s, distanceKm: distance, etaMin: eta));
    }

    list.sort((a, b) {
      final aT = a.schedule.onlineAt;
      final bT = b.schedule.onlineAt;
      if (aT == null && bT == null) return 0;
      if (aT == null) return 1;
      if (bT == null) return -1;
      return aT.compareTo(bT);
    });

    return list;
  }

  // ─── Call (block check + reorder) ──────────────────────────────────

  /// "ЧАҚИРИШ" натижаси: блок бўлса — xато, акс ҳолда system queue бўйича
  /// 1-навбат → 2-навбат → 3-навбатдаги мос ҳайдовчилар рўйхати.
  Future<MarshrutCallPrep> prepareCall(int selectedIdx) async {
    if (_fromMfy.isEmpty) {
      return const MarshrutCallPrep.error('Қаердан МФЙ ни танланг');
    }
    if (selectedIdx < 0 || selectedIdx >= _results.length) {
      return const MarshrutCallPrep.error('Ҳайдовчи топилмади');
    }

    final blocked = await _checkBlocked();
    if (blocked != null) return MarshrutCallPrep.error(blocked);

    final ordered = await _queue.findNextEligibleMarshrutDrivers(
      pickupMfy: _fromMfy,
      dropoffMfy: _toMfy,
      limit: 3,
    );
    if (ordered.isEmpty) {
      return const MarshrutCallPrep.error('Ҳозир навбатда мос ҳайдовчи йўқ');
    }
    return MarshrutCallPrep.ready(ordered);
  }

  Future<String?> _checkBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      if (phone.isEmpty) return null;

      final blockRef = FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .collection('marshrut_block')
          .doc('state');

      final snap = await blockRef.get();
      if (snap.exists) {
        final blockedUntil = snap.data()?['blockedUntil'] as Timestamp?;
        if (blockedUntil != null) {
          final blockedMs = blockedUntil.millisecondsSinceEpoch;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (blockedMs > nowMs) {
            final remaining = (blockedMs - nowMs) ~/ 60000;
            return '⛔ ${remaining + 1} дақиқадан кейин қайта урининг';
          }
        }
      }
    } catch (_) {
      // Tekshiruvda xato — davom etamiz
    }
    return null;
  }
}

/// "ЧАҚИРИШ" tayyorlanishi natijasi.
class MarshrutCallPrep {
  const MarshrutCallPrep.ready(this.drivers) : error = null;
  const MarshrutCallPrep.error(this.error) : drivers = const [];

  final List<MarshrutDriverOption> drivers;
  final String? error;

  bool get isReady => error == null;
}
