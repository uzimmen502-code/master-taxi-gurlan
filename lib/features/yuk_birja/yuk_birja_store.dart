import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
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

  /// Биринчи snapshot (ёки хато) келгунча кутади — bootstrap sync учун.
  Future<void> load() async {
    await _sub?.cancel();
    _error = null;
    _ready = false;
    notifyListeners();

    final first = Completer<void>();
    _sub = _repo.watchActive().listen(
      (items) {
        _listings
          ..clear()
          ..addAll(items);
        _ready = true;
        _error = null;
        notifyListeners();
        if (!first.isCompleted) first.complete();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('YukBirjaStore.watch: $e\n$st');
        _error = e.toString();
        _ready = true;
        notifyListeners();
        if (!first.isCompleted) first.complete();
      },
    );

    try {
      await first.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      _ready = true;
      _error ??= 'timeout';
      notifyListeners();
    }
  }

  Future<void> reload() => load();

  /// Ўз эълонларидан муддати ўтганларни ёпиш (CF ҳам ёпади).
  Future<List<YukListing>> closeExpired({
    String? ownerId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final me = canonicalPhoneId(ownerId ?? '');
    if (me.length < 9) return const [];
    final mineClosed = <YukListing>[];
    for (final item in List<YukListing>.from(_listings)) {
      if (!item.isActive || !item.isExpired(at)) continue;
      if (!phonesMatch(item.ownerId, me)) continue;
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
      ownerId: canonicalPhoneId(item.ownerId),
      ownerName: item.ownerName,
      phone: item.phone,
      status: YukListingStatus.active,
      cargo: item.cargo,
      weightKg: item.weightKg,
      capacityKg: item.capacityKg,
      freeSpaceKg: item.freeSpaceKg,
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
    if (!phonesMatch(updated.ownerId, currentOwnerId)) return false;
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
    if (!phonesMatch(item.ownerId, currentOwnerId)) return false;
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

  Future<bool> reportListing({
    required YukListing item,
    required String reason,
    required String reporterId,
  }) async {
    if (phonesMatch(item.ownerId, reporterId)) return false;
    try {
      await _repo.report(
        listingId: item.id,
        reason: reason,
        reporterId: reporterId,
        targetOwnerId: item.ownerId,
        route: '${item.from} → ${item.to}',
      );
      return true;
    } catch (e) {
      debugPrint('YukBirjaStore.reportListing: $e');
      return false;
    }
  }

  List<YukListing> filtered({
    required String tab,
    String from = '',
    String to = '',
    double? maxWeightKg,
    String vehicleType = '',
    Set<String> matchedIds = const {},
  }) {
    final now = DateTime.now();
    final f = from.trim().toLowerCase();
    final t = to.trim().toLowerCase();
    final vt = vehicleType.trim().toLowerCase();

    var list = _listings.where((item) {
      if (!item.isActive || item.isExpired(now)) return false;
      // moto/traktor — фақат туман ичи; шаҳарлараро рўйхатда кўринмайди.
      if (kYukLocalOnlyVehicleValues
          .contains(normalizeYukVehicleType(item.vehicleType))) {
        return false;
      }
      final cities = item.routeCities.map((c) => c.toLowerCase()).toList();
      if (f.isNotEmpty && !cities.any((c) => c.contains(f))) return false;
      if (t.isNotEmpty && !cities.any((c) => c.contains(t))) return false;
      if (vt.isNotEmpty &&
          normalizeYukVehicleType(item.vehicleType) !=
              normalizeYukVehicleType(vt)) {
        return false;
      }
      if (maxWeightKg != null && maxWeightKg > 0) {
        if (item.isCargo && (item.weightKg ?? 0) > maxWeightKg) return false;
        if (!item.isCargo && (item.freeSpaceKg ?? 0) < maxWeightKg) {
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
