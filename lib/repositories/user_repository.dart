import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../models/identity_change_request.dart';
import '../models/risk_event.dart';
import '../models/user_address.dart';
import '../models/user_model.dart';
import '../models/wallet_ledger_entry.dart';
import 'news_repository.dart';

/// `users` collection bilan ishlash.
///
/// Hech qachon UI'ga bog'liq bo'lmaydi — faqat ma'lumot olib keladi/yozadi.
class UserRepository {
  UserRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _birthDateRequests =>
      _db.collection('birthdate_change_requests');
  CollectionReference<Map<String, dynamic>> get _riskEvents =>
      _db.collection('risk_events');
  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  /// Real-time foydalanuvchi hujjati.
  Stream<UserModel> watch(String uid) =>
      _col.doc(uid).snapshots().map(UserModel.fromDoc);

  /// Bir martalik o'qish.
  Future<UserModel?> getById(String uid) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return UserModel.fromDoc(snap);
  }

  /// **Legacy:** `users/{uid}.blockedUntil` (eski local taxi 3 bekor → 30 daq).
  ///
  /// Yangi local taxi blok: [LocalTaxiBlockRepository] → `local_taxi_block/state`.
  /// Marshrut: [MarshrutBlockRepository] → `marshrut_block/state`.
  ///
  /// Hech qachon throw qilmaydi — read xatoligi `null` bo'lib qaytadi.
  @Deprecated('LocalTaxiBlockRepository yoki MarshrutBlockRepository ishlating')
  Future<DateTime?> getBlockedUntil(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _col.doc(uid).get();
      final ts = snap.data()?['blockedUntil'] as Timestamp?;
      if (ts == null) return null;
      final until = ts.toDate();
      if (!until.isAfter(DateTime.now())) return null;
      return until;
    } catch (_) {
      return null;
    }
  }

  /// Bonus balans (Kosholyok) — tezkor stream.
  Stream<int> watchBonusBalance(String uid) => _col
      .doc(uid)
      .snapshots()
      .map((s) => (s.data()?['bonusBalance'] as num?)?.toInt() ?? 0);

  /// Wallet ledger — oxirgi operatsiyalar.
  Stream<List<WalletLedgerEntry>> watchWalletLedger(
    String uid, {
    int limit = 8,
  }) =>
      _col
          .doc(uid)
          .collection('wallet_ledger')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(WalletLedgerEntry.fromDoc).toList());

  /// Berilgan sanadan boshlab ledger (real-time).
  Stream<List<WalletLedgerEntry>> watchWalletLedgerSince(
    String uid, {
    required DateTime since,
    int limit = 200,
  }) {
    if (uid.isEmpty) {
      return Stream.value(const []);
    }
    return _col
        .doc(uid)
        .collection('wallet_ledger')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((q) => q.docs.map(WalletLedgerEntry.fromDoc).toList());
  }

  Stream<int> watchBirthdayBonusAmount() {
    return _appSettings.snapshots().map((snap) {
      return (snap.data()?['birthdayBonusAmount'] as num?)?.toInt() ?? 10000;
    });
  }

  Future<void> setBirthdayBonusAmount(int amount) async {
    await _appSettings.set({
      'birthdayBonusAmount': amount < 0 ? 0 : amount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<UserModel>> watchUsersWithBirthDate({int limit = 500}) {
    return _col
        .where('birthDate', isGreaterThan: '')
        .limit(limit)
        .snapshots()
        .map((q) {
      final users = q.docs.map(UserModel.fromDoc).toList();
      users.sort((a, b) => a.name.compareTo(b.name));
      return users;
    });
  }

  Future<bool> hasBirthdayBonusClaim({
    required String uid,
    required int year,
  }) async {
    if (uid.isEmpty) return false;
    final snap = await _col
        .doc(uid)
        .collection('birthday_bonus_claims')
        .doc('$year')
        .get();
    return snap.exists;
  }

  Stream<List<RiskEvent>> watchOpenRiskEvents({int limit = 200}) {
    return _riskEvents
        .where('status', isEqualTo: 'open')
        .limit(limit)
        .snapshots()
        .map((q) {
      final items = q.docs.map(RiskEvent.fromDoc).toList();
      items.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return items;
    });
  }

  Future<void> resolveRiskEvent(String id, {String operatorPhone = ''}) async {
    if (id.isEmpty) return;
    await _riskEvents.doc(id).set({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': operatorPhone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _addRiskEvent({
    required String userId,
    required String type,
    required String message,
    String severity = 'medium',
    String deviceId = '',
    Map<String, dynamic> meta = const <String, dynamic>{},
  }) async {
    await _riskEvents.add({
      'userId': userId.trim(),
      'type': type,
      'severity': severity,
      'status': 'open',
      'deviceId': deviceId.trim(),
      'message': message.trim(),
      'meta': meta,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Onboarding tugaganda yangi foydalanuvchi hujjati yaratiladi.
  /// `uid` — telefon raqamининг faқat raqamlari.
  ///
  /// **Muhim:** `merge: true` ishlatamiz — agar hujjat allaqachon mavjud bo'lsa
  /// (FCMService token'ni avval yozgan, Cloud Function welcome-bonus qo'shgan,
  /// foydalanuvchi ilovani qayta o'rnatgan va h.k.), `bonusBalance`,
  /// `fcmToken`, legacy `blockedUntil` kabi maydonlar **saqlanib qoladi**. `merge`
  /// bo'lmaganda `set()` butun hujjatni almashtiradi va `walletFieldsUntouched()`
  /// firestore qoidasi `permission-denied` qaytaradi.
  Future<void> create({
    required String uid,
    required String phone,
    required String name,
    required String gender,
    required String address,
  }) async {
    await _col.doc(uid).set({
      'phone': phone.trim(),
      'name': name.trim(),
      'gender': gender,
      'address': address.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Onboarding tugashi: bitta yozuv — `create` + `saveAddress` birlashtirilgan.
  /// Ikki marta `update` qilmaslik (Firestore qoidalari bilan mosroq).
  Future<void> createOrMergeProfileWithAddress({
    required String uid,
    required String phone,
    required String name,
    required String gender,
    String birthDate = '',
    required String legacyAddressLine,
    required UserAddress address,
  }) async {
    if (uid.isEmpty) return;
    final validation = address.validationError;
    if (validation != null) {
      throw ArgumentError(validation);
    }
    final ref = _col.doc(uid);
    final snap = await ref.get();
    final data = <String, Object?>{
      'phone': phone.trim(),
      'name': name.trim(),
      'gender': gender,
      if (birthDate.trim().isNotEmpty) 'birthDate': birthDate.trim(),
      if (birthDate.trim().isNotEmpty)
        'birthDateSetAt': FieldValue.serverTimestamp(),
      'address': address.toMap(),
      'legacyAddress': legacyAddressLine.trim(),
      'addressUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(data, SetOptions(merge: true));
  }

  /// Birth date бир марта эркин сақланади. Кейинги ўзгартиришлар admin
  /// тасдиғи учун алоҳида request орқали юборилади.
  Future<void> setBirthDateIfEmpty({
    required String uid,
    required String birthDate,
  }) async {
    if (uid.isEmpty || birthDate.trim().isEmpty) return;
    final ref = _col.doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['birthDate'] ?? '') as String;
      if (current.trim().isNotEmpty && current.trim() != birthDate.trim()) {
        throw StateError('birth_date_locked');
      }
      tx.set(
        ref,
        {
          'birthDate': birthDate.trim(),
          if (current.trim().isEmpty)
            'birthDateSetAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Birth date ўзгартириш admin approval навбати.
  Future<void> requestBirthDateChange({
    required String uid,
    required String currentBirthDate,
    required String requestedBirthDate,
  }) async {
    if (uid.isEmpty || requestedBirthDate.trim().isEmpty) return;
    await _birthDateRequests.add({
      'userId': uid,
      'currentBirthDate': currentBirthDate.trim(),
      'requestedBirthDate': requestedBirthDate.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addRiskEvent(
      userId: uid,
      type: 'birthdate_change_request',
      severity: 'low',
      message: 'User birthDate ўзгартириш сўрови юборди',
      meta: {
        'currentBirthDate': currentBirthDate.trim(),
        'requestedBirthDate': requestedBirthDate.trim(),
      },
    );
  }

  Stream<List<BirthDateChangeRequest>> watchPendingBirthDateChangeRequests() {
    return _birthDateRequests
        .where('status', isEqualTo: 'pending')
        .limit(100)
        .snapshots()
        .map((q) {
      final items = q.docs.map(BirthDateChangeRequest.fromDoc).toList();
      items.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return items;
    });
  }

  Future<void> approveBirthDateChange(BirthDateChangeRequest request) async {
    final userRef = _col.doc(request.userId);
    final requestRef = _birthDateRequests.doc(request.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(requestRef);
      if ((snap.data()?['status'] ?? '') != 'pending') return;
      tx.set(
          userRef,
          {
            'birthDate': request.requestedBirthDate.trim(),
            'birthDateApprovedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      tx.update(requestRef, {
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectBirthDateChange(String requestId) async {
    await _birthDateRequests.doc(requestId).set({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Профил расми — Storage URL (Qarindoshlar «Мен» bilan sinxron).
  Future<void> updatePhoto({
    required String uid,
    required String photoUrl,
    String photoPath = '',
  }) async {
    if (uid.isEmpty) return;
    final id = canonicalPhoneId(uid);
    final patch = <String, Object?>{
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (photoPath.isNotEmpty) {
      patch['photoPath'] = photoPath;
    } else if (photoUrl.isEmpty) {
      patch['photoPath'] = FieldValue.delete();
    }
    await _col.doc(id).set(patch, SetOptions(merge: true));
  }

  /// Профил маълумотларини бирваракай янгилаш.
  Future<void> updateProfile({
    required String uid,
    String? name,
    String? phone,
    String? gender,
    String? role,
  }) async {
    if (uid.isEmpty) return;
    final patch = <String, Object?>{};
    if (name != null) patch['name'] = name.trim();
    if (phone != null) patch['phone'] = phone.trim();
    if (gender != null) patch['gender'] = gender;
    if (role != null) patch['role'] = role;
    if (patch.isEmpty) return;
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(uid).set(patch, SetOptions(merge: true));
  }

  /// Структуралaнган манзилни сақлаш.
  /// Эски `address` (String) — `legacyAddress` сифатида сақланади.
  Future<void> saveAddress({
    required String uid,
    required UserAddress address,
    String? legacyFromString,
  }) async {
    if (uid.isEmpty) return;
    final validation = address.validationError;
    if (validation != null) {
      throw ArgumentError(validation);
    }
    final patch = <String, Object?>{
      'address': address.toMap(),
      'addressUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (legacyFromString != null && legacyFromString.trim().isNotEmpty) {
      patch['legacyAddress'] = legacyFromString.trim();
    }
    await _col.doc(uid).set(patch, SetOptions(merge: true));
  }

  /// Configuration-driven platforma: foydalanuvchi geo zonasini saqlash.
  ///
  /// [serviceAreaId] — xizmat mavjudligini aniqlaydi; [regionId]/[districtId]
  /// hisobot uchun. Firestore rules: bu maydonlar himoyalanmagan → egasi yozadi.
  Future<void> saveServiceArea({
    required String uid,
    required String regionId,
    required String districtId,
    required String serviceAreaId,
  }) async {
    if (uid.isEmpty) return;
    await _col.doc(canonicalPhoneId(uid)).set({
      'regionId': regionId.trim(),
      'districtId': districtId.trim(),
      'serviceAreaId': serviceAreaId.trim(),
      'geoUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Умумий янгиликлар ўқилди.
  Future<void> markNewsRead(String uid) async {
    if (uid.isEmpty) return;
    await NewsRepository(db: _db).markGeneralRead(uid);
  }

  /// Буюртма хабарлари ўқилди.
  Future<void> markOrderNewsRead(String uid) async {
    if (uid.isEmpty) return;
    await NewsRepository(db: _db).markOrderNewsRead(uid);
  }

  /// «Хабарлар» таби (мурожаатлар) ўқилди.
  Future<void> markMessagesRead(String uid) async {
    if (uid.isEmpty) return;
    await NewsRepository(db: _db).markMessagesRead(uid);
  }

  Future<void> saveCarInfo({
    required String uid,
    required String carModel,
    required String carColor,
    required String carPlate,
    required int carSeats,
    String carBrand = '',
    int carYear = 0,
    String carEngine = '',
    String carFuelType = '',
    List<String> carUsageTags = const [],
  }) async {
    if (uid.isEmpty) return;
    final tags =
        carUsageTags.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await _col.doc(canonicalPhoneId(uid)).update({
      'carModel': carModel.trim(),
      'carColor': carColor.trim(),
      'carPlate': carPlate.trim().toUpperCase(),
      'carSeats': carSeats,
      'carBrand': carBrand.trim(),
      'carYear': carYear,
      'carEngine': carEngine.trim(),
      'carFuelType': carFuelType.trim(),
      'carUsageTags': tags,
      'carUpdatedAt': FieldValue.serverTimestamp(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('car_model', carModel.trim());
    await prefs.setString('car_color', carColor.trim());
    await prefs.setString('car_plate', carPlate.trim().toUpperCase());
    await prefs.setInt('car_seats', carSeats);
    await prefs.setString('car_brand', carBrand.trim());
    await prefs.setInt('car_year', carYear);
    await prefs.setString('car_engine', carEngine.trim());
    await prefs.setString('car_fuel_type', carFuelType.trim());
    await prefs.setStringList('car_usage_tags', tags);
  }

  /// `users/{uid}` ва SharedPreferences'dan avtomobil ma'lumotlarini tozalash.
  Future<void> clearCarInfo(String uid) async {
    if (uid.isEmpty) return;
    await _col.doc(canonicalPhoneId(uid)).update({
      'carModel': '',
      'carColor': '',
      'carPlate': '',
      'carSeats': 0,
      'carBrand': '',
      'carYear': 0,
      'carEngine': '',
      'carFuelType': '',
      'carUsageTags': <String>[],
      'carUpdatedAt': FieldValue.serverTimestamp(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('car_model');
    await prefs.remove('car_color');
    await prefs.remove('car_plate');
    await prefs.remove('car_seats');
    await prefs.remove('car_brand');
    await prefs.remove('car_year');
    await prefs.remove('car_engine');
    await prefs.remove('car_fuel_type');
    await prefs.remove('car_usage_tags');
  }

  Future<Map<String, String>?> getCarInfo(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _col.doc(canonicalPhoneId(uid)).get();
      if (!snap.exists) return null;
      final d = snap.data()!;
      final model = d['carModel'] as String? ?? '';
      final color = d['carColor'] as String? ?? '';
      final plate = d['carPlate'] as String? ?? '';
      final seats = (d['carSeats'] as num?)?.toInt() ?? 0;
      final brand = d['carBrand'] as String? ?? '';
      final year = (d['carYear'] as num?)?.toInt() ?? 0;
      final engine = d['carEngine'] as String? ?? '';
      final fuel = d['carFuelType'] as String? ?? '';
      final rawTags = d['carUsageTags'];
      final tags = rawTags is List
          ? rawTags.map((e) => '$e').where((e) => e.trim().isNotEmpty).join(',')
          : '';
      if (model.isEmpty && plate.isEmpty && seats == 0 && brand.isEmpty) {
        return null;
      }
      return {
        'carModel': model,
        'carColor': color,
        'carPlate': plate,
        'carSeats': seats > 0 ? '$seats' : '',
        'carBrand': brand,
        'carYear': year > 0 ? '$year' : '',
        'carEngine': engine,
        'carFuelType': fuel,
        'carUsageTags': tags,
      };
    } catch (_) {
      return null;
    }
  }
}
