import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/yuk_listing.dart';
import 'repositories/yuk_listings_repository.dart';
import 'yuk_listing_notifier.dart';
import 'yuk_vehicle_types.dart';

/// Юк биржаси — Firestore умумий рўйхат.
class YukBirjaStore extends ChangeNotifier {
  YukBirjaStore({YukListingsRepository? repository})
      : _repo = repository ?? YukListingsRepository();

  final YukListingsRepository _repo;
  final List<YukListing> _listings = [];
  StreamSubscription<List<YukListing>>? _sub;
  bool _ready = false;
  String? _error;

  bool get ready => _ready;
  String? get error => _error;
  List<YukListing> get listings => List.unmodifiable(_listings);

  Future<void> load() async {
    await _sub?.cancel();
    _error = null;
    _sub = _repo.watchActive().listen(
      (items) {
        _listings
          ..clear()
          ..addAll(items);
        _ready = true;
        _error = null;
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('YukBirjaStore.watch: $e\n$st');
        _error = e.toString();
        _ready = true;
        notifyListeners();
      },
    );
  }

  /// Ўз эълонларидан муддати ўтганларни ёпиш (CF ҳам ёпади).
  Future<List<YukListing>> closeExpired({
    String? ownerId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final me = (ownerId ?? '').trim();
    if (me.isEmpty) return const [];
    final mineClosed = <YukListing>[];
    for (final item in List<YukListing>.from(_listings)) {
      if (!item.isActive || !item.isExpired(at)) continue;
      if (item.ownerId != me) continue;
      try {
        await _repo.close(item.id);
        mineClosed.add(item.copyWith(status: YukListingStatus.closed));
      } catch (e) {
        debugPrint('YukBirjaStore.closeExpired ${item.id}: $e');
      }
    }
    if (mineClosed.isNotEmpty) {
      await YukListingNotifier.notifyJustClosed(mineClosed);
    }
    return mineClosed;
  }

  Future<void> addListing(YukListing item) async {
    final id = await _repo.create(item);
    final withId = YukListing(
      id: id,
      type: item.type,
      from: item.from,
      to: item.to,
      stops: item.stops,
      vehicleType: item.vehicleType,
      ownerId: item.ownerId,
      ownerName: item.ownerName,
      phone: item.phone,
      status: YukListingStatus.active,
      cargo: item.cargo,
      weight: item.weight,
      capacity: item.capacity,
      freeSpace: item.freeSpace,
      price: item.price,
      comment: item.comment,
      stars: item.stars,
      createdAt: item.createdAt,
      expiresAt: item.expiresAt,
    );
    _listings.removeWhere((e) => e.id == id);
    _listings.insert(0, withId);
    notifyListeners();
    await YukListingNotifier.scheduleFor(withId);
  }

  Future<bool> updateListing({
    required YukListing updated,
    required String currentOwnerId,
  }) async {
    if (updated.ownerId != currentOwnerId) return false;
    if (!updated.isActive) return false;
    try {
      await _repo.update(updated);
      final i = _listings.indexWhere((e) => e.id == updated.id);
      if (i >= 0) {
        _listings[i] = updated;
        notifyListeners();
      }
      await YukListingNotifier.scheduleFor(updated);
      return true;
    } catch (e) {
      debugPrint('YukBirjaStore.updateListing: $e');
      return false;
    }
  }

  Future<bool> closeListing({
    required String id,
    required String currentOwnerId,
  }) async {
    final i = _listings.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    final item = _listings[i];
    if (item.ownerId != currentOwnerId) return false;
    try {
      await _repo.close(id);
      _listings.removeAt(i);
      notifyListeners();
      await YukListingNotifier.cancelFor(id);
      return true;
    } catch (e) {
      debugPrint('YukBirjaStore.closeListing: $e');
      return false;
    }
  }

  List<YukListing> filtered({
    required String tab,
    String from = '',
    String to = '',
    double? maxWeightTons,
    String vehicleType = '',
    Set<String> matchedIds = const {},
  }) {
    final now = DateTime.now();
    final f = from.trim().toLowerCase();
    final t = to.trim().toLowerCase();
    final vt = vehicleType.trim().toLowerCase();

    var list = _listings.where((item) {
      if (!item.isActive || item.isExpired(now)) return false;
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

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
