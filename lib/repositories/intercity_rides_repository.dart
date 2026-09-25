import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/merged_stream.dart';
import '../models/intercity_ride.dart';
import '../utils/intercity_route_match.dart';

/// `intercity_drivers` collection — шаҳарлараро такси haydovchilari.
class IntercityRidesRepository {
  IntercityRidesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('intercity_drivers');

  static String scheduleDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<IntercityRide> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required String fromCity,
    required String toCity,
    required String passengerFromRaw,
    required String passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) {
    final dateKey = scheduleDateKey(baseDate);
    final todayKey = scheduleDateKey(DateTime.now());

    final rides = snap.docs
        .where((d) {
          final sd = (d.data()['scheduleDate'] as String?)?.trim() ?? '';
          if (sd.isEmpty) return dateKey == todayKey;
          return sd == dateKey;
        })
        .map((d) => IntercityRide.fromDoc(
              d,
              fromCity: fromCity,
              toCity: toCity,
              district: district,
              baseDate: baseDate,
            ))
        .toList(growable: false);

    return rides
        .where((r) => IntercityRouteMatch.matchesSegment(
              driverStops: r.routeStops,
              passengerFrom: passengerFromRaw,
              passengerTo: passengerToRaw,
            ))
        .toList(growable: false);
  }

  /// Бир марта қидирув.
  Future<List<IntercityRide>> getActiveRides({
    required String fromCity,
    required String toCity,
    String? passengerFromRaw,
    String? passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) async {
    final pFrom = passengerFromRaw ?? fromCity;
    final pTo = passengerToRaw ?? toCity;

    try {
      final snap = await _col.where('isActive', isEqualTo: true).get();
      return _mapSnapshot(
        snap,
        fromCity: fromCity,
        toCity: toCity,
        passengerFromRaw: pFrom,
        passengerToRaw: pTo,
        district: district,
        baseDate: baseDate,
      );
    } on FirebaseException catch (e) {
      throw IntercityRidesLoadException(
        e.code == 'permission-denied'
            ? 'Қидирув рухсати йўқ'
            : 'Қидирувда хатолик: ${e.message ?? e.code}',
      );
    } catch (e) {
      throw IntercityRidesLoadException('Қидирувда хатолик: $e');
    }
  }

  /// Real-time — бўш ўринлар брондан кейин ҳам янгиланади.
  Stream<List<IntercityRide>> watchActiveRides({
    required String fromCity,
    required String toCity,
    String? passengerFromRaw,
    String? passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) {
    final pFrom = passengerFromRaw ?? fromCity;
    final pTo = passengerToRaw ?? toCity;

    return _col.where('isActive', isEqualTo: true).snapshots().map((snap) {
      return _mapSnapshot(
        snap,
        fromCity: fromCity,
        toCity: toCity,
        passengerFromRaw: pFrom,
        passengerToRaw: pTo,
        district: district,
        baseDate: baseDate,
      );
    });
  }

  /// Бош саҳифадаги 4-бўлим: шу тумандан чиқаётган яқин рейслар.
  ///
  /// Мавжуд [watchActiveRides] дан фарқи: у `from`+`to` жуфтлигини
  /// талаб қилади (йўловчи қидируви), бу эса ЙЎНАЛИШСИЗ — рейслар
  /// ҳайдовчининг ўз тумани бўйича олинади.
  ///
  /// Ўтиб кетган рейс чиқмайди: жўнаш вақти `scheduleDate` (кун) ва
  /// `hour` (соат) дан йиғилади ва ҳозирги вақт билан солиштирилади.
  ///
  /// Эски ёзувларда `districtId` йўқ — улар иккинчи оқимда келади
  /// (қаранг: `backfill_intercity_district.js`).
  Stream<List<IntercityRide>> watchNearbyForHome({
    required String districtId,
    int limit = 5,
  }) {
    List<IntercityRide> upcoming(QuerySnapshot<Map<String, dynamic>> snap) {
      final now = DateTime.now();
      final out = <IntercityRide>[];
      for (final doc in snap.docs) {
        final ride = _fromHomeDoc(doc);
        if (ride == null) continue;
        if (ride.departureTime.isBefore(now)) continue;
        out.add(ride);
      }
      out.sort((a, b) => a.departureTime.compareTo(b.departureTime));
      return out;
    }

    final id = districtId.trim();
    final base = _col.where('isActive', isEqualTo: true);

    if (id.isEmpty) {
      return base.snapshots().map((s) => upcoming(s).take(limit).toList());
    }

    final scoped = base
        .where('districtId', isEqualTo: id)
        .snapshots()
        .map(upcoming);

    // `_fromHomeDoc` ҳужжатнинг `districtId` ини `district` майдонига
    // солади, шунинг учун ҳудудсиз эски ёзувлар шу бўйича ажратилади.
    final legacy = base.snapshots().map(
          (s) => upcoming(s).where((r) => r.district.trim().isEmpty).toList(),
        );

    return mergeListStreams(scoped, legacy, idOf: (r) => r.id).map((list) {
      final sorted = list.toList()
        ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
      return sorted.take(limit).toList();
    });
  }

  /// Ҳужжатнинг ЎЗИДАН рейс қуради (йўловчи танлаган йўналишдан эмас).
  /// `scheduleDate` бўш ёки нотўғри бўлса — рейс кўрсатилмайди.
  IntercityRide? _fromHomeDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final dateRaw = (d['scheduleDate'] as String?)?.trim() ?? '';
    final date = DateTime.tryParse(dateRaw);
    if (date == null) return null;
    final from = (d['from'] as String?)?.trim() ?? '';
    final to = (d['to'] as String?)?.trim() ?? '';
    return IntercityRide.fromDoc(
      doc,
      fromCity: from,
      toCity: to,
      district: (d['districtId'] as String?)?.trim() ?? '',
      baseDate: date,
    );
  }

  Future<void> startTrip(String driverId) async {
    await _col.doc(driverId).update({
      'tripStatus': 'in_progress',
      'tripStartedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class IntercityRidesLoadException implements Exception {
  IntercityRidesLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}
