import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/formatters.dart';
import '../features/demand_offer/data/demand_repository.dart'
    show kDemandCoreRegion;
import '../features/demand_offer/domain/canonical_id.dart' show canonicalUserId;
import '../models/driver_model.dart';
import '../models/driver_roles.dart';
import '../models/driver_stats.dart';
import 'user_repository.dart';

/// Haydovchi arizasi yuborish natijasi.
class DriverApplicationSubmitResult {
  const DriverApplicationSubmitResult({
    required this.autoApproved,
    required this.isFirstSubmission,
  });

  final bool autoApproved;
  final bool isFirstSubmission;
}

/// `drivers` collection.
class DriverRepository {
  DriverRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('drivers');
  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');
  CollectionReference<Map<String, dynamic>> get _driverRequests =>
      _db.collection('driver_requests');

  Future<DriverStats?> getStats(String uid) async {
    if (uid.isEmpty) return null;
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return DriverStats.fromDoc(snap);
  }

  /// Online va bo'sh haydovchilar (filtrlash uchun koordinatasi borlari).
  ///
  /// E'tibor: bu so'rov barcha online+bo'sh haydovchilarni qaytaradi.
  /// Yo'lovchi tarafida masofa bo'yicha filtrlanadi. Katta hududda
  /// kelajakda geohash-based query bilan optimallashtirilishi mumkin.
  Future<List<DriverModel>> getAvailable() async {
    // 'local' va 'alone' — mahalliy taksi uchun ikki xil nom (nomenklatura birlashtirilguncha).
    final snap = await _col
        .where('isOnline', isEqualTo: true)
        .where('isBusy', isEqualTo: false)
        .where('taxiType', whereIn: ['local', 'alone', 'both']).get();
    return snap.docs
        .map(DriverModel.fromDoc)
        .where((d) => d.hasCoordinates)
        .toList();
  }

  /// Ҳайдовчи профилини upsert қилиш (умумий kalit'лар).
  Future<void> upsertProfile({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
  }) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).set({
        'name': name,
        'phone': phone,
        'car': car,
        'plate': plate,
        'taxiType': taxiType,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// `auto` — haydovchi darhol faol. `manual` — admin tasdiqi.
  Stream<String> watchDriverApprovalMode() {
    return _appSettings.snapshots().map((snap) {
      final mode = snap.data()?['driverApprovalMode'] as String? ?? 'manual';
      return mode == 'auto' ? 'auto' : 'manual';
    });
  }

  Future<String> getDriverApprovalMode() async {
    try {
      final snap = await _appSettings.get();
      final mode = snap.data()?['driverApprovalMode'] as String? ?? 'manual';
      return mode == 'auto' ? 'auto' : 'manual';
    } catch (_) {
      return 'manual';
    }
  }

  Future<void> setDriverApprovalMode(String mode) async {
    final v = mode == 'auto' ? 'auto' : 'manual';
    await _appSettings.set({
      'driverApprovalMode': v,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _driverDocId(String uid) => canonicalPhoneId(uid);

  List<String> _driverDocIds(String uid) {
    final canon = canonicalPhoneId(uid);
    final raw = phoneDigits(uid);
    return {canon, raw, uid.trim()}
        .where((id) => phoneDigits(id).length >= 9)
        .toList(growable: false);
  }

  /// Taxi capability'ни сўраш (D-TAXI-1): сервер `starter` беради — админ
  /// тасдиғи КУТИЛМАЙДИ, келишув ҳам шарт эмас (D-TAXI-24.1). Starter
  /// тугаган бўлса ва келишув ҳали қабул қилинмаган бўлса сервер
  /// `agreementRequired: true` қайтаради — UI варақни тақдим қилади.
  ///
  /// `{accountId, status, agreementRequired, agreementVersion}`.
  Future<Map<String, dynamic>> requestTaxiCapability() async {
    final res = await FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
        .httpsCallable('requestCapability')
        .call<Object?>({'service': 'taxi'});
    final d = res.data is Map ? (res.data as Map) : const {};
    return {
      'accountId': (d['accountId'] ?? '').toString(),
      'status': (d['status'] ?? '').toString(),
      'agreementRequired': d['agreementRequired'] == true,
      'agreementVersion': (d['agreementVersion'] as num?)?.toInt(),
    };
  }

  /// D-CLEAN-1 / D-TAXI-1: ҳайдовчи ЎЗИ ёқади, дарҳол `starter`.
  ///
  /// Эски оқим (`driver_requests` → админ тасдиғи → `drivers.approved`)
  /// ИШЛАТИЛМАЙДИ. Ҳуқуқ — `provider_capabilities.status.taxi`,
  /// `drivers/{uid}` эса фақат ПРОФИЛ (исм, машина, рақам). Такси турлари
  /// ҳайдовчининг ўз декларатсияси: `provider_capabilities.taxi.taxiTypes`
  /// (қоида шу бўйича филтрлайди, ҳуқуқ эмас).
  Future<DriverApplicationSubmitResult> submitDriverApplication({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    // D-TAXI-24.1: келишув бу ерда ТАЛАБ ҚИЛИНМАЙДИ — starter дарҳол.
    final cap = await requestTaxiCapability();
    final accountId = (cap['accountId'] ?? '').toString();
    if (accountId.isEmpty) {
      throw StateError('accountId qaytmadi');
    }

    final docId = _driverDocId(uid);
    // Профил — тасдиқ майдонларисиз (қоида рад этади, керак ҳам эмас).
    await _col.doc(docId).set({
      'name': name,
      'phone': phone,
      'car': car,
      'plate': plate,
      'taxiType': taxiType,
      'taxiTypes': FieldValue.arrayUnion([taxiType]),
      if (routeFrom.isNotEmpty) 'routeFrom': routeFrom,
      if (routeTo.isNotEmpty) 'routeTo': routeTo,
      if (routeStops.isNotEmpty) 'routeStops': routeStops,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Такси тури декларатсияси — capability ичида (клиент майдони).
    await _db.collection('provider_capabilities').doc(accountId).set({
      'taxi': {
        'active': true,
        'taxiTypes': FieldValue.arrayUnion([taxiType]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // `starter` — реал ишлаш ҳуқуқи (D-TAXI-1), шунинг учун «тасдиқланди».
    return const DriverApplicationSubmitResult(
      autoApproved: true,
      isFirstSubmission: false,
    );
  }

  /// R-7: ҳуқуқ — `provider_capabilities.status.taxi` (capability), `drivers.approved`
  /// ЭМАС. Ишлайдиган ҳолатлар: `starter` `verification_required` `verified`
  /// (`functions_demand/core/capabilities.js` → `LIFECYCLES.taxi.working`
  /// билан бир хил). Тур — `taxi.taxiTypes` декларатсияси (`alone`↔`local`
  /// синоним).
  Future<bool> isApprovedForTaxi({
    required String uid,
    required String taxiType,
  }) async =>
      (await taxiAccess(uid: uid, taxiType: taxiType)).approved;

  /// `isApprovedForTaxi` + capability статуси — битта ўқиш билан
  /// (`verification_required` бўлса UI келишувни тақдим қилади, D-TAXI-24.1).
  Future<({bool approved, String status})> taxiAccess({
    required String uid,
    required String taxiType,
  }) async {
    if (uid.isEmpty) return (approved: false, status: '');
    final cap = await _taxiCapability(uid);
    if (cap == null) return (approved: false, status: '');
    final status = ((cap['status'] as Map?)?['taxi'] ?? '').toString();
    if (!const {'starter', 'verification_required', 'verified'}.contains(status)) {
      return (approved: false, status: status);
    }
    final types = ((cap['taxi'] as Map?)?['taxiTypes'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        const <String>{};
    final typeOk = types.contains(taxiType) ||
        (taxiType == 'alone' && types.contains('local')) ||
        (taxiType == 'local' && types.contains('alone'));
    return (approved: typeOk, status: status);
  }

  /// Ҳайдовчи/курьер индикатори: ишлайдиган ҳолатдаги такси турлари ва улардан
  /// ҳозир фаоллари, шунингдек курьер онлайнми. Хато бўлса индикатор жим
  /// йўқолади (`none`), экран йиқилмайди.
  Future<DriverRoles> driverRoles(String uid) async {
    final courierOnline = await _courierOnline(uid);
    try {
      final cap = await _taxiCapability(uid);
      if (cap == null) return DriverRoles(courierOnline: courierOnline);
      final courierStatus =
          ((cap['status'] as Map?)?['courier'] ?? '').toString();
      final status = ((cap['status'] as Map?)?['taxi'] ?? '').toString();
      if (!const {'starter', 'verification_required', 'verified'}
          .contains(status)) {
        return DriverRoles(
          courierOnline: courierOnline,
          courierStatus: courierStatus,
        );
      }
      final raw = ((cap['taxi'] as Map?)?['taxiTypes'] as List?)
              ?.map((e) => e.toString() == 'alone' ? 'local' : e.toString())
              .toSet() ??
          const <String>{};
      const order = ['intercity', 'local', 'marshrut'];
      final types = order.where(raw.contains).toList(growable: false);
      if (types.isEmpty) {
        return DriverRoles(
          courierOnline: courierOnline,
          courierStatus: courierStatus,
        );
      }

      final id = canonicalPhoneId(uid);
      final active = <String>{};
      if (types.contains('intercity')) {
        final ic = await _db.collection('intercity_drivers').doc(id).get();
        if (ic.data()?['isActive'] == true) active.add('intercity');
      }
      if (types.contains('local') || types.contains('marshrut')) {
        final d = await _db.collection('drivers').doc(id).get();
        final data = d.data() ?? const <String, dynamic>{};
        if (data['isOnline'] == true) {
          final t = (data['taxiType'] ?? '').toString();
          if (t == 'marshrut' && types.contains('marshrut')) {
            active.add('marshrut');
          } else if ((t == 'local' || t == 'alone') && types.contains('local')) {
            active.add('local');
          }
        }
      }
      return DriverRoles(
        types: types,
        active: active,
        courierOnline: courierOnline,
        courierStatus: courierStatus,
      );
    } catch (_) {
      return DriverRoles(courierOnline: courierOnline);
    }
  }

  /// Курьер онлайнми: `provider_presence/{канон 12 хонали}.isOnline` (уни
  /// фақат курьер юборади; эскирганини `presenceSweeper` offline қилади).
  Future<bool> _courierOnline(String uid) async {
    try {
      final id = canonicalUserId(uid);
      if (id.isEmpty) return false;
      final s = await _db.collection('provider_presence').doc(id).get();
      return s.data()?['isOnline'] == true;
    } catch (_) {
      return false;
    }
  }
  /// `users/{uid}.accountId` → `provider_capabilities/{accountId}` (9/12 хонали).
  Future<Map<String, dynamic>?> _taxiCapability(String uid) async {
    for (final id in _driverDocIds(uid)) {
      final u = await _db.collection('users').doc(id).get();
      final accountId = u.data()?['accountId']?.toString() ?? '';
      if (accountId.isEmpty) continue;
      final cap = await _db.collection('provider_capabilities').doc(accountId).get();
      return cap.data();
    }
    return null;
  }

  /// Фойдаланувчининг ҳайдовчи аризаси (doc id = телефон).
  Stream<Map<String, dynamic>?> watchMyDriverRequest(String uid) {
    final id = canonicalPhoneId(uid);
    if (id.length < 9) return Stream.value(null);
    return _driverRequests.doc(id).snapshots().map((s) {
      if (!s.exists) return null;
      return s.data();
    });
  }

  /// `true` — yangi hujjat yaratildi (birinchi ariza).
  Future<bool> submitDriverRequest({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    final docId = _driverDocId(uid);
    if (docId.length < 12) {
      throw Exception('invalid_phone_format');
    }

    final ref = _driverRequests.doc(docId);
    final snap = await ref.get();
    final route = _routeFields(routeFrom, routeTo, routeStops);

    var carValue = car.trim();
    var plateValue = plate.trim();
    if (carValue.isEmpty || plateValue.isEmpty) {
      final carInfo =
          await UserRepository().getCarInfo(canonicalPhoneId(uid));
      if (carInfo != null) {
        carValue = carInfo['carModel'] ?? carValue;
        plateValue = carInfo['carPlate'] ?? plateValue;
      }
    }

    final payload = <String, dynamic>{
      'uid': docId,
      'name': name.trim(),
      'phone': phone.trim(),
      'car': carValue,
      'plate': plateValue,
      'taxiType': taxiType,
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      ...route,
    };

    if (!snap.exists) {
      await ref.set({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    }

    final prevStatus = snap.data()?['status'] as String? ?? '';
    if (prevStatus == 'rejected') {
      payload['rejectedAt'] = FieldValue.delete();
      payload['rejectedReason'] = FieldValue.delete();
      payload['rejectedBy'] = FieldValue.delete();
    }

    await ref.set(payload, SetOptions(merge: true));
    return false;
  }

  Map<String, dynamic> _routeFields(
    String routeFrom,
    String routeTo,
    List<String> routeStops,
  ) {
    final from = routeFrom.trim();
    final to = routeTo.trim();
    final stops = routeStops.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (from.isEmpty && to.isEmpty) return {};
    final label = stops.isEmpty
        ? '$from → $to'
        : '$from → ${stops.join(' → ')} → $to';
    return {
      'routeFrom': from,
      'routeTo': to,
      if (stops.isNotEmpty) 'routeStops': stops,
      'routeLabel': label,
    };
  }

  /// Auto-rejimда CF орқали тасдиқ; aks holda faqat `drivers` profilini yangilaydi.
  Future<void> approveDriverAutomatically({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    // D-CLEAN-1: `driverApprovalMode` va `autoApproveDriverApplication` CF
    // ISHLATILMAYDI — bitta yo'l: capability (`submitDriverApplication`).
    await submitDriverApplication(
      uid: uid,
      name: name,
      phone: phone,
      car: car,
      plate: plate,
      taxiType: taxiType,
      routeFrom: routeFrom,
      routeTo: routeTo,
      routeStops: routeStops,
    );
  }

  /// Онлайн ҳолатга ўтиш (универсал — barcha taxi турлари учун).
  Future<void> goOnline({
    required String uid,
    required String name,
    required String phone,
    required String taxiType,
    double? lat,
    double? lng,
  }) async {
    if (uid.isEmpty) return;
    await _col.doc(uid).set({
      'name': name,
      'phone': phone,
      'isOnline': true,
      'taxiType': taxiType,
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> goOffline(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'isOnline': false,
        'lat': null,
        'lng': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> updateLocation({
    required String uid,
    required double lat,
    required double lng,
  }) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> decrementSeats(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'seatsLeft': FieldValue.increment(-1),
      });
    } catch (_) {}
  }

  Future<void> incrementSeats(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'seatsLeft': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  Future<void> markUnavailable(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'isAvailable': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
