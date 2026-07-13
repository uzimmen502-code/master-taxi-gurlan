import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/oil_vehicle.dart';
import '../repositories/user_repository.dart';

/// Moy almashtirish — mashina, tarix, punkt, bron.
class OilChangeRepository {
  OilChangeRepository({
    FirebaseFirestore? db,
    UserRepository? userRepo,
  })  : _db = db ?? FirebaseFirestore.instance,
        _userRepo = userRepo ?? UserRepository();

  final FirebaseFirestore _db;
  final UserRepository _userRepo;

  CollectionReference<Map<String, dynamic>> _vehicles(String uid) =>
      _db.collection('users').doc(canonicalPhoneId(uid)).collection('vehicles');

  CollectionReference<Map<String, dynamic>> _history(
    String uid,
    String vehicleId,
  ) =>
      _vehicles(uid).doc(vehicleId).collection('oil_history');

  Stream<List<OilVehicle>> watchVehicles(String uid) {
    final id = canonicalPhoneId(uid);
    if (id.length < 9) return Stream.value(const []);
    return _vehicles(id).snapshots().map((s) {
      final list = s.docs.map(OilVehicle.fromDoc).toList();
      list.sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return (a.createdAt ?? DateTime(2000))
            .compareTo(b.createdAt ?? DateTime(2000));
      });
      return list;
    });
  }

  Future<List<OilVehicle>> listVehicles(String uid) async {
    final id = canonicalPhoneId(uid);
    if (id.length < 9) return const [];
    final snap = await _vehicles(id).get();
    final list = snap.docs.map(OilVehicle.fromDoc).toList();
    list.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return (a.createdAt ?? DateTime(2000))
          .compareTo(b.createdAt ?? DateTime(2000));
    });
    return list;
  }

  /// Profil avtomobilidan birlamchi mashina yaratadi (yo‘q bo‘lsa).
  Future<OilVehicle?> ensureFromProfile(String uid) async {
    final id = canonicalPhoneId(uid);
    if (id.length < 9) return null;

    final existing = await listVehicles(id);
    if (existing.isNotEmpty) {
      return existing.firstWhere((v) => v.isPrimary, orElse: () => existing.first);
    }

    final car = await _userRepo.getCarInfo(id);
    if (car == null) return null;
    final model = (car['carModel'] ?? '').trim();
    final color = (car['carColor'] ?? '').trim();
    final plate = (car['carPlate'] ?? '').trim();
    final seats = int.tryParse(car['carSeats'] ?? '') ?? 0;
    if (model.isEmpty && plate.isEmpty) return null;

    final ref = _vehicles(id).doc();
    final vehicle = OilVehicle(
      id: ref.id,
      model: model,
      color: color,
      plate: plate,
      seats: seats > 0 ? seats : 4,
      isPrimary: true,
    );
    await ref.set(vehicle.toMap(forCreate: true));
    return vehicle.copyWith(id: ref.id);
  }

  Future<String> saveVehicle({
    required String uid,
    required OilVehicle vehicle,
    bool syncProfile = true,
  }) async {
    final id = canonicalPhoneId(uid);
    final col = _vehicles(id);
    final isNew = vehicle.id.isEmpty;
    final ref = isNew ? col.doc() : col.doc(vehicle.id);

    if (vehicle.isPrimary) {
      final all = await col.get();
      final batch = _db.batch();
      for (final d in all.docs) {
        if (d.id == ref.id) continue;
        if (d.data()['isPrimary'] == true) {
          batch.update(d.reference, {'isPrimary': false});
        }
      }
      batch.set(
        ref,
        vehicle.copyWith(id: ref.id, isPrimary: true).toMap(forCreate: isNew),
        SetOptions(merge: true),
      );
      await batch.commit();
    } else {
      await ref.set(
        vehicle.copyWith(id: ref.id).toMap(forCreate: isNew),
        SetOptions(merge: true),
      );
    }

    if (syncProfile && vehicle.isPrimary) {
      await _userRepo.saveCarInfo(
        uid: id,
        carModel: vehicle.model,
        carColor: vehicle.color,
        carPlate: vehicle.plate,
        carSeats: vehicle.seats > 0 ? vehicle.seats : 4,
      );
    }
    return ref.id;
  }

  Future<void> recordOilChange({
    required String uid,
    required String vehicleId,
    required DateTime changedAt,
    required int odometerKm,
    required String oilType,
    String serviceName = '',
    String note = '',
    int intervalKm = 5000,
    int intervalMonths = 6,
  }) async {
    final id = canonicalPhoneId(uid);
    final vRef = _vehicles(id).doc(vehicleId);
    final hRef = _history(id, vehicleId).doc();
    final batch = _db.batch();
    batch.set(hRef, {
      'changedAt': Timestamp.fromDate(changedAt),
      'odometerKm': odometerKm,
      'oilType': oilType.trim(),
      'serviceName': serviceName.trim(),
      'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      vRef,
      {
        'oilType': oilType.trim(),
        'lastChangedAt': Timestamp.fromDate(changedAt),
        'lastOdometerKm': odometerKm,
        'currentOdometerKm': odometerKm,
        'intervalKm': intervalKm,
        'intervalMonths': intervalMonths,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Stream<List<OilHistoryEntry>> watchHistory(String uid, String vehicleId) {
    final id = canonicalPhoneId(uid);
    return _history(id, vehicleId)
        .orderBy('changedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(OilHistoryEntry.fromDoc).toList());
  }

  Stream<List<OilServicePoint>> watchServicePoints() {
    return _db
        .collection('oil_change_services')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map(OilServicePoint.fromDoc).toList());
  }

  Future<List<OilPricePackage>> loadPricePackages() async {
    try {
      final snap =
          await _db.collection('settings').doc('oil_change').get();
      if (!snap.exists) return OilPricePackage.defaults;
      final raw = snap.data()?['packages'];
      if (raw is! List || raw.isEmpty) return OilPricePackage.defaults;
      final list = <OilPricePackage>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        list.add(OilPricePackage(
          id: (m['id'] as String?) ?? 'pkg_${list.length}',
          name: (m['name'] as String?) ?? '',
          description: (m['description'] as String?) ?? '',
          priceFrom: (m['priceFrom'] as num?)?.toInt() ?? 0,
        ));
      }
      return list.isEmpty ? OilPricePackage.defaults : list;
    } catch (_) {
      return OilPricePackage.defaults;
    }
  }

  Future<String> createBooking({
    required String uid,
    required OilVehicle vehicle,
    required OilPricePackage package,
    required OilServicePoint point,
    required DateTime slotAt,
    required String phone,
    required String name,
  }) async {
    final id = canonicalPhoneId(uid);
    final ref = _db.collection('oil_change_bookings').doc();
    await ref.set({
      'uid': id,
      'vehicleId': vehicle.id,
      'vehicleLabel': vehicle.displayTitle,
      'packageId': package.id,
      'packageName': package.name,
      'servicePointId': point.id,
      'serviceName': point.name,
      'slotAt': Timestamp.fromDate(slotAt),
      'status': 'new',
      'priceFrom': package.priceFrom,
      'phone': phoneDigits(phone),
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<List<OilBooking>> watchMyBookings(String uid) {
    final id = canonicalPhoneId(uid);
    return _db
        .collection('oil_change_bookings')
        .where('uid', isEqualTo: id)
        .limit(20)
        .snapshots()
        .map((s) {
      final list = s.docs.map(OilBooking.fromDoc).toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));
      return list;
    });
  }
}
