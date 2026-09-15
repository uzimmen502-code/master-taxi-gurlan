import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import 'models/yuk_listing.dart';
import 'repositories/yuk_listings_repository.dart';
import 'yuk_listing_filter.dart';

/// Юк биржаси — Firestore умумий рўйхат.
///
/// Муддат тугаши (48 с) ва унга боғлиқ хабарлар — фақат CF (expirePendingTrips`n/// → yuk_intercity.js): клиент ёпмайди ва локал эслатма қўймайди. UI'да
/// муддати ўтган эълон ilterYukListings орқали яширилади.
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
    String vehicleType = '',
  }) =>
      filterYukListings(
        _listings,
        tab: tab,
        from: from,
        to: to,
        vehicleType: vehicleType,
      );

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
