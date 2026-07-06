import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/marshrut_driver_option.dart';
import '../../../../models/queue_entry.dart';
import '../../../../models/schedule.dart';
import '../../../../models/schedule_search_result.dart';
import '../../../../repositories/marshrut_block_repository.dart';
import '../../../../repositories/queue_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../services/location_service.dart';
import '../../../../utils/gurlan_places.dart';
import '../models/marshrut_search_filter_stats.dart';

/// Marshrut yo'lovchi qidiruv ekrani state mashinasi.
///
/// Mas'uliyatlari:
/// - GPS faqat qidiruvda (ixtiyoriy masofa filtri; ekran ochilganda banner yo'q)
/// - Bugungi aktiv `schedules` ni olish va yo'nalish/masofa/ETA bo'yicha filtrlash
/// - Blok holati: Firestore `.snapshots()` + one-shot expiry timer (poll yo'q)
/// - "ЧАҚИРИШ" — keshlangan blok holatini tekshirish va navbatga qo'yish
class MarshrutSearchController extends ChangeNotifier {
  MarshrutSearchController({
    required SchedulesRepository schedulesRepo,
    required QueueRepository queueRepo,
    required LocationService locationService,
    MarshrutBlockRepository? blockRepo,
  })  : _schedules = schedulesRepo,
        _queue = queueRepo,
        _location = locationService,
        _blockRepo = blockRepo ?? MarshrutBlockRepository();

  static const double _maxRadiusKm = 5;
  static const double _kmPerMinute = 0.4; // ~24 km/h taxi tezligi

  final SchedulesRepository _schedules;
  final QueueRepository _queue;
  final LocationService _location;
  final MarshrutBlockRepository _blockRepo;

  StreamSubscription<MarshrutBlockState>? _blockSub;
  Timer? _blockExpiryTimer;
  MarshrutBlockState _blockState = const MarshrutBlockState();
  bool _blockJustCleared = false;

  // ─── State ──────────────────────────────────────────────────────────
  double? _userLat;
  double? _userLng;
  String _fromMfy = '';
  String _toMfy = '';
  bool _isSearching = false;
  bool _searched = false;
  List<ScheduleSearchResult> _results = const [];
  String? _errorMessage;
  MarshrutSearchFilterStats _filterStats = const MarshrutSearchFilterStats();

  MarshrutBlockState get blockState => _blockState;
  bool get isBlockActive => _blockState.isBlocked;
  int? get blockMinutesRemaining => _blockState.blockMinutesRemaining;

  /// Blokdan oldin qolgan bekorlar (accepted safardan keyin bekor qoidasi).
  int? get cancelsUntilBlock => null;

  int get effectiveCancelCount => _blockState.cancelCount;

  double? get userLat => _userLat;
  double? get userLng => _userLng;
  String get fromMfy => _fromMfy;
  String get toMfy => _toMfy;
  bool get isSearching => _isSearching;
  bool get searched => _searched;
  List<ScheduleSearchResult> get results => _results;
  String? get errorMessage => _errorMessage;
  MarshrutSearchFilterStats get filterStats => _filterStats;

  // ─── Blok (Firestore stream, poll yo'q) ─────────────────────────────

  Future<bool> isBlocked(String userPhone) async {
    try {
      final phone = RidesRepository.normalizeMarshrutPhone(userPhone);
      if (phone.isEmpty) return false;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .collection('marshrut_block')
          .doc('state')
          .get();
      if (!doc.exists) return false;
      final blockedUntil =
          (doc.data()?['blockedUntil'] as Timestamp?)?.toDate();
      if (blockedUntil == null) return false;
      return DateTime.now().isBefore(blockedUntil);
    } catch (_) {
      return false;
    }
  }

  Future<DateTime?> getBlockedUntil(String userPhone) async {
    try {
      final phone = RidesRepository.normalizeMarshrutPhone(userPhone);
      if (phone.isEmpty) return null;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .collection('marshrut_block')
          .doc('state')
          .get();
      if (!doc.exists) return null;
      final blockedUntil =
          (doc.data()?['blockedUntil'] as Timestamp?)?.toDate();
      if (blockedUntil == null) return null;
      return DateTime.now().isBefore(blockedUntil) ? blockedUntil : null;
    } catch (_) {
      return null;
    }
  }

  /// Ekran ochilganda chaqiring — `users/{phone}/marshrut_block/state` stream.
  Future<void> initBlockWatch() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = RidesRepository.normalizeMarshrutPhone(
      prefs.getString('user_phone') ?? '',
    );
    await _blockSub?.cancel();
    _blockExpiryTimer?.cancel();
    if (phone.isEmpty) {
      _onBlockStateChanged(const MarshrutBlockState());
      return;
    }
    _blockSub = _blockRepo.watchState(phone).listen(
      _onBlockStateChanged,
      onError: (_) {},
    );
  }

  /// Blok tugaganda snack ko'rsatish uchun bir martalik flag.
  bool consumeBlockClearedSnack() {
    if (!_blockJustCleared) return false;
    _blockJustCleared = false;
    return true;
  }

  void _onBlockStateChanged(MarshrutBlockState incoming) {
    _blockExpiryTimer?.cancel();

    final wasActive = _blockState.isBlocked;
    final effective = _effectiveState(incoming);

    if (effective.isBlocked && effective.blockedUntil != null) {
      final remaining = effective.blockedUntil!.difference(DateTime.now());
      if (!remaining.isNegative) {
        _blockExpiryTimer = Timer(remaining, _onLocalBlockExpiry);
      }
    }

    if (wasActive && !effective.isBlocked) {
      _blockJustCleared = true;
    }
    _blockState = effective;
    notifyListeners();
  }

  /// Eski/stale hujjat yoki vaqt o'tgan — faqat UI (Firestore ga yozilmaydi).
  MarshrutBlockState _effectiveState(MarshrutBlockState incoming) {
    final until = incoming.blockedUntil;
    if (until == null) return incoming;
    if (DateTime.now().isBefore(until)) return incoming;
    return MarshrutBlockState(cancelCount: incoming.cancelCount);
  }

  void _onLocalBlockExpiry() {
    if (!_blockState.isBlocked) return;
    _blockState = MarshrutBlockState(cancelCount: _blockState.cancelCount);
    _blockJustCleared = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _blockSub?.cancel();
    _blockExpiryTimer?.cancel();
    super.dispose();
  }

  // ─── Form ───────────────────────────────────────────────────────────

  void setFromMfy(String v) {
    _fromMfy = GurlanPlaces.normalizeMfyName(v);
    notifyListeners();
  }

  void setToMfy(String v) {
    _toMfy = GurlanPlaces.normalizeMfyName(v);
    notifyListeners();
  }

  void clearTransient() {
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Search ─────────────────────────────────────────────────────────

  Future<void> search() async {
    if (_fromMfy.isEmpty) {
      _errorMessage = 'select_from_mfy';
      notifyListeners();
      return;
    }
    if (_toMfy.isEmpty) {
      _errorMessage = 'select_to_mfy';
      notifyListeners();
      return;
    }

    _isSearching = true;
    _results = const [];
    notifyListeners();

    await _loadGpsForSearch();

    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final schedules = await _schedules.searchActiveToday(date: dateStr);
      _results = await _filterAndSort(schedules);
    } catch (e) {
      _errorMessage = 'error_generic|$e';
    }

    _isSearching = false;
    _searched = true;
    notifyListeners();
  }

  /// Marshrut qidiruvida GPS ixtiyoriy — MFY bo‘yicha asosiy filtr.
  Future<void> _loadGpsForSearch() async {
    try {
      final c = await _location.getCurrentCoords(
        mediumTimeout: const Duration(seconds: 4),
        highTimeout: const Duration(seconds: 6),
      );
      _userLat = c.lat;
      _userLng = c.lng;
    } catch (_) {
      _userLat = null;
      _userLng = null;
    }
  }

  Future<List<ScheduleSearchResult>> _filterAndSort(
      List<Schedule> schedules) async {
    final list = <ScheduleSearchResult>[];
    final hasGps = _userLat != null && _userLng != null;
    var stats = const MarshrutSearchFilterStats();

    for (final s in schedules) {
      stats = MarshrutSearchFilterStats(
        totalActive: stats.totalActive + 1,
        shown: stats.shown,
        offline: stats.offline,
        full: stats.full,
        routeMismatch: stats.routeMismatch,
        expired: stats.expired,
        tooFar: stats.tooFar,
      );

      if (s.hasExpired) {
        stats = _copyStats(stats, expired: stats.expired + 1);
        continue;
      }
      if (s.seatsLeft <= 0) {
        stats = _copyStats(stats, full: stats.full + 1);
        continue;
      }
      if (s.actualOnlineAt == null) {
        stats = _copyStats(stats, offline: stats.offline + 1);
        continue;
      }
      if (!s.routeAllows(_fromMfy, _toMfy)) {
        stats = _copyStats(stats, routeMismatch: stats.routeMismatch + 1);
        continue;
      }
      // Narx belgilanmagan reys ko'rsatilmaydi (dispatch'ga ham chiqmaydi).
      if (s.price <= 0) {
        continue;
      }

      double? distance;
      int? eta;
      if (hasGps && s.lat != null && s.lng != null) {
        distance =
            LocationService.distanceKm(_userLat!, _userLng!, s.lat!, s.lng!);
        if (distance > _maxRadiusKm) {
          stats = _copyStats(stats, tooFar: stats.tooFar + 1);
          continue;
        }
        eta = (distance / _kmPerMinute).round().clamp(1, 60);
      }

      list.add(
          ScheduleSearchResult(schedule: s, distanceKm: distance, etaMin: eta));
      stats = _copyStats(stats, shown: stats.shown + 1);
    }

    _filterStats = stats;

    list.sort((a, b) {
      final byEligible =
          _compareTs(a.schedule.queueEligibleAt, b.schedule.queueEligibleAt);
      if (byEligible != 0) return byEligible;

      final byTrips = a.schedule.todayTrips.compareTo(b.schedule.todayTrips);
      if (byTrips != 0) return byTrips;

      final aMisses = a.schedule.todayRejects + a.schedule.todayTimeouts;
      final bMisses = b.schedule.todayRejects + b.schedule.todayTimeouts;
      final byMisses = aMisses.compareTo(bMisses);
      if (byMisses != 0) return byMisses;

      final byOnline =
          _compareTs(a.schedule.actualOnlineAt, b.schedule.actualOnlineAt);
      if (byOnline != 0) return byOnline;

      return _compareTs(a.schedule.onlineAt, b.schedule.onlineAt);
    });

    final activeDriverIds = await _getActiveQueueDriverIds();
    final synced = activeDriverIds == null
        ? list
        : list
            .where((r) => activeDriverIds.contains(r.schedule.driverId))
            .toList();
    _filterStats = _copyStats(_filterStats, shown: synced.length);
    return synced;
  }

  /// [QueueRepository.findNextEligibleMarshrutDrivers] bilan bir xil filtrlash.
  Future<Set<String>?> _getActiveQueueDriverIds() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('queue')
          .where('taxiType', isEqualTo: 'marshrut')
          .where('isActive', isEqualTo: true)
          .get();

      final candidates = snap.docs.map(QueueEntry.fromDoc).where((q) {
        if (q.hasExpired) return false;
        if (!q.isTimeEligible) return false;
        if (q.scheduleId.isEmpty) return false;
        if (q.price <= 0) return false;
        if (!q.routeAllows(_fromMfy, _toMfy)) return false;
        return true;
      }).toList();

      if (candidates.isEmpty) return {};

      final schedules = await Future.wait(
        candidates.map((q) => _schedules.getById(q.scheduleId)),
      );

      final ids = <String>{};
      for (var i = 0; i < candidates.length; i++) {
        final seats = schedules[i]?.seatsLeft ?? 0;
        if (seats <= 0) continue;
        ids.add(candidates[i].driverId);
      }
      return ids;
    } catch (e) {
      debugPrint('_getActiveQueueDriverIds error: $e');
      return null;
    }
  }

  MarshrutSearchFilterStats _copyStats(
    MarshrutSearchFilterStats s, {
    int? totalActive,
    int? shown,
    int? offline,
    int? full,
    int? routeMismatch,
    int? expired,
    int? tooFar,
  }) {
    return MarshrutSearchFilterStats(
      totalActive: totalActive ?? s.totalActive,
      shown: shown ?? s.shown,
      offline: offline ?? s.offline,
      full: full ?? s.full,
      routeMismatch: routeMismatch ?? s.routeMismatch,
      expired: expired ?? s.expired,
      tooFar: tooFar ?? s.tooFar,
    );
  }

  int _compareTs(Timestamp? a, Timestamp? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  // ─── Call (keshlangan blok + navbat) ────────────────────────────────

  /// "ЧАҚИРИШ" — система навбати (1→…→7); рўйхатдаги танлов навбатга таъсир қилмайди.
  Future<MarshrutCallPrep> prepareSystemQueueCall({
    Set<String> excludeDriverIds = const {},
    bool skipResultsGuard = false,
  }) async {
    if (_fromMfy.isEmpty) {
      return const MarshrutCallPrep.error('select_from_mfy');
    }
    if (_toMfy.isEmpty) {
      return const MarshrutCallPrep.error('select_to_mfy');
    }
    if (!skipResultsGuard && _results.isEmpty) {
      return const MarshrutCallPrep.error('search_first');
    }

    if (_blockState.isBlocked) {
      final remaining = _blockState.blockMinutesRemaining ?? 1;
      return MarshrutCallPrep.error('retry_after_minutes|$remaining');
    }

    final ordered = await _queue.findNextEligibleMarshrutDrivers(
      pickupMfy: _fromMfy,
      dropoffMfy: _toMfy,
      limit: 7,
      excludeDriverIds: excludeDriverIds,
    );
    if (ordered.isEmpty) {
      return const MarshrutCallPrep.error('no_queue_driver');
    }
    return MarshrutCallPrep.ready(ordered);
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
