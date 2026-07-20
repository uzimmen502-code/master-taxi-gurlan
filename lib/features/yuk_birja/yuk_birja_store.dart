import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/yuk_listing.dart';
import 'yuk_listing_notifier.dart';
import 'yuk_vehicle_types.dart';

/// Юк биржаси — маҳаллий MVP store (кейин Firestore).
class YukBirjaStore extends ChangeNotifier {
  YukBirjaStore();

  static const _prefsKey = 'yuk_birja_listings_v1';
  static const _seededKey = 'yuk_birja_seeded_v1';

  final List<YukListing> _listings = [];
  bool _ready = false;

  bool get ready => _ready;
  List<YukListing> get listings => List.unmodifiable(_listings);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _listings.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            _listings.add(YukListing.fromJson(e));
          } else if (e is Map) {
            _listings.add(YukListing.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {
        _listings.clear();
      }
    }
    if (_listings.isEmpty && !(prefs.getBool(_seededKey) ?? false)) {
      _listings.addAll(_demoSeed());
      await prefs.setBool(_seededKey, true);
    }
    await closeExpired();
    _ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_listings.map((e) => e.toJson()).toList()),
    );
  }

  /// Муддати ўтган актив эълонларни автоёпиш.
  /// Қайтиш: эндигина ёпилган эълонлар (хабар учун).
  Future<List<YukListing>> closeExpired({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final closed = <YukListing>[];
    for (var i = 0; i < _listings.length; i++) {
      final item = _listings[i];
      if (item.isActive && item.isExpired(at)) {
        final next = item.copyWith(status: YukListingStatus.closed);
        _listings[i] = next;
        closed.add(next);
      }
    }
    if (closed.isNotEmpty) {
      await _persist();
      notifyListeners();
      await YukListingNotifier.notifyJustClosed(closed);
    }
    return closed;
  }

  Future<void> addListing(YukListing item) async {
    await closeExpired();
    _listings.insert(0, item);
    await _persist();
    notifyListeners();
    await YukListingNotifier.scheduleFor(item);
  }

  /// Фақат эълон эгаси таҳрирлай олади.
  Future<bool> updateListing({
    required YukListing updated,
    required String currentOwnerId,
  }) async {
    final i = _listings.indexWhere((e) => e.id == updated.id);
    if (i < 0) return false;
    final prev = _listings[i];
    if (prev.ownerId != currentOwnerId) return false;
    if (!prev.isActive) return false;
    final next = updated.copyWith(
      ownerId: prev.ownerId,
      ownerName: prev.ownerName,
      phone: prev.phone,
      createdAt: prev.createdAt,
      expiresAt: prev.expiresAt,
      status: YukListingStatus.active,
      stars: prev.stars,
    );
    _listings[i] = next;
    await _persist();
    notifyListeners();
    await YukListingNotifier.scheduleFor(next);
    return true;
  }

  /// Фақат эълон эгаси ёпа олади.
  Future<bool> closeListing({
    required String id,
    required String currentOwnerId,
  }) async {
    final i = _listings.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    final item = _listings[i];
    if (item.ownerId != currentOwnerId) return false;
    if (!item.isActive) return false;
    _listings[i] = item.copyWith(status: YukListingStatus.closed);
    await _persist();
    notifyListeners();
    await YukListingNotifier.cancelFor(id);
    return true;
  }

  List<YukListing> filtered({
    required String tab, // all | cargo | truck | matched
    String from = '',
    String to = '',
    double? maxWeightTons,
    String vehicleType = '',
    Set<String> matchedIds = const {},
  }) {
    // Sync expire — хабар async (filtered sync қолсин).
    final now = DateTime.now();
    final justClosed = <YukListing>[];
    for (var i = 0; i < _listings.length; i++) {
      final item = _listings[i];
      if (item.isActive && item.isExpired(now)) {
        final next = item.copyWith(status: YukListingStatus.closed);
        _listings[i] = next;
        justClosed.add(next);
      }
    }
    if (justClosed.isNotEmpty) {
      _persist();
      // ignore: unawaited_futures
      YukListingNotifier.notifyJustClosed(justClosed);
    }

    final f = from.trim().toLowerCase();
    final t = to.trim().toLowerCase();
    final vt = vehicleType.trim().toLowerCase();

    var list = _listings.where((item) {
      if (!item.isActive) return false;
      final cities = item.routeCities.map((c) => c.toLowerCase()).toList();
      if (f.isNotEmpty && !cities.any((c) => c.contains(f))) return false;
      if (t.isNotEmpty && !cities.any((c) => c.contains(t))) return false;
      if (vt.isNotEmpty &&
          normalizeYukVehicleType(item.vehicleType) !=
              normalizeYukVehicleType(vt)) {
        return false;
      }
      if (maxWeightTons != null && maxWeightTons > 0) {
        if (item.isCargo && (item.weight ?? 0) > maxWeightTons) return false;
        if (!item.isCargo && (item.freeSpace ?? 0) < maxWeightTons) {
          return false;
        }
      }
      return true;
    }).toList();

    if (tab == 'cargo') {
      list = list.where((e) => e.isCargo).toList();
    } else if (tab == 'truck') {
      list = list.where((e) => !e.isCargo).toList();
    } else if (tab == 'matched') {
      list = list.where((e) => matchedIds.contains(e.id)).toList();
    }

    list.sort((a, b) {
      if (tab == 'matched' || matchedIds.isNotEmpty) {
        final am = matchedIds.contains(a.id) ? 0 : 1;
        final bm = matchedIds.contains(b.id) ? 0 : 1;
        if (am != bm) return am - bm;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<YukMatchPair> smartMatch({int minScore = 45, int limit = 16}) {
    final cargos = _listings.where((e) => e.isActive && e.isCargo).toList();
    final trucks = _listings.where((e) => e.isActive && !e.isCargo).toList();
    final pairs = <YukMatchPair>[];
    for (final c in cargos) {
      for (final t in trucks) {
        final score = _scorePair(c, t);
        if (score >= minScore) {
          pairs.add(YukMatchPair(cargo: c, truck: t, score: score));
        }
      }
    }
    pairs.sort((a, b) => b.score.compareTo(a.score));
    if (pairs.length > limit) return pairs.sublist(0, limit);
    return pairs;
  }

  int _scorePair(YukListing cargo, YukListing truck) {
    var score = 0;
    final cFrom = cargo.from.toLowerCase();
    final cTo = cargo.to.toLowerCase();
    final tCities = truck.routeCities.map((c) => c.toLowerCase()).toSet();
    final cCities = cargo.routeCities.map((c) => c.toLowerCase()).toSet();

    if (truck.from.toLowerCase() == cFrom) score += 30;
    if (truck.to.toLowerCase() == cTo) score += 30;
    if (tCities.contains(cFrom)) score += 15;
    if (tCities.contains(cTo)) score += 15;

    var overlap = 0;
    for (final c in cCities) {
      if (tCities.contains(c)) overlap++;
    }
    score += (overlap * 5).clamp(0, 20);

    if (normalizeYukVehicleType(cargo.vehicleType) ==
        normalizeYukVehicleType(truck.vehicleType)) {
      score += 15;
    }
    final w = cargo.weight ?? 0;
    if ((truck.freeSpace ?? 0) >= w) {
      score += 20;
    } else if ((truck.capacity ?? 0) >= w) {
      score += 8;
    }
    return score.clamp(0, 100);
  }

  List<YukListing> _demoSeed() {
    var n = 0;
    String id() => 'demo_${DateTime.now().microsecondsSinceEpoch}_${n++}';
    final now = DateTime.now();
    return [
      YukListing(
        id: id(),
        type: YukListingType.cargo,
        from: 'Гурлан',
        to: 'Самарқанд',
        stops: const ['Хива', 'Бухоро'],
        vehicleType: 'fura',
        ownerId: 'u_aziz',
        ownerName: 'Азиз',
        phone: '+998901234567',
        status: YukListingStatus.active,
        cargo: 'Ун',
        weight: 18,
        price: 4500000,
        stars: 4.9,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.cargo,
        from: 'Урганч',
        to: 'Тошкент',
        stops: const ['Навоий'],
        vehicleType: 'fura',
        ownerId: 'u_bekzod',
        ownerName: 'Бекзод',
        phone: '+998937778899',
        status: YukListingStatus.active,
        cargo: 'Пахта',
        weight: 15,
        price: 5200000,
        stars: 4.6,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.cargo,
        from: 'Бухоро',
        to: 'Навоий',
        stops: const [],
        vehicleType: 'fura',
        ownerId: 'u_madina',
        ownerName: 'Мадина',
        phone: '+998911112233',
        status: YukListingStatus.active,
        cargo: 'Қуруқ мева',
        weight: 12,
        price: 2200000,
        stars: 4.7,
        createdAt: now.subtract(const Duration(hours: 20)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.cargo,
        from: 'Хива',
        to: 'Бухоро',
        stops: const [],
        vehicleType: 'furgon',
        ownerId: 'u_nigora',
        ownerName: 'Нигора',
        phone: '+998933334455',
        status: YukListingStatus.active,
        cargo: 'Ҳунармандчилик',
        weight: 3,
        price: 800000,
        stars: 4.5,
        createdAt: now.subtract(const Duration(hours: 30)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.truck,
        from: 'Урганч',
        to: 'Тошкент',
        stops: const ['Навоий', 'Жиззах'],
        vehicleType: 'fura',
        ownerId: 'u_sardor',
        ownerName: 'Сардор',
        phone: '+998945551122',
        status: YukListingStatus.active,
        capacity: 22,
        freeSpace: 18,
        stars: 4.9,
        createdAt: now.subtract(const Duration(hours: 4)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.truck,
        from: 'Гурлан',
        to: 'Самарқанд',
        stops: const ['Хива', 'Бухоро'],
        vehicleType: 'bort',
        ownerId: 'u_olim',
        ownerName: 'Олим',
        phone: '+998972211334',
        status: YukListingStatus.active,
        capacity: 20,
        freeSpace: 20,
        stars: 5.0,
        createdAt: now.subtract(const Duration(hours: 12)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.truck,
        from: 'Навоий',
        to: 'Нукус',
        stops: const ['Бухоро'],
        vehicleType: 'ref',
        ownerId: 'u_jamshid',
        ownerName: 'Жамшид',
        phone: '+998959900112',
        status: YukListingStatus.active,
        capacity: 20,
        freeSpace: 12,
        stars: 4.8,
        createdAt: now.subtract(const Duration(hours: 36)),
      ),
      YukListing(
        id: id(),
        type: YukListingType.truck,
        from: 'Хива',
        to: 'Бухоро',
        stops: const [],
        vehicleType: 'manipulator',
        ownerId: 'u_kamol',
        ownerName: 'Камол',
        phone: '+998933445566',
        status: YukListingStatus.active,
        capacity: 5,
        freeSpace: 5,
        stars: 4.5,
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
    ];
  }
}
