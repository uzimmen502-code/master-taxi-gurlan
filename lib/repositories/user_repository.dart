import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/identity_change_request.dart';
import '../models/risk_event.dart';
import '../models/user_address.dart';
import '../models/user_model.dart';
import '../models/wallet_ledger_entry.dart';

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
  CollectionReference<Map<String, dynamic>> get _deviceChangeRequests =>
      _db.collection('device_change_requests');
  CollectionReference<Map<String, dynamic>> get _deviceBindings =>
      _db.collection('device_bindings');
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

  /// Ghost protection — agar foydalanuvchi vaqtinchalik bloklangan bo'lsa
  /// `blockedUntil` qaytaradi (kelajakdagi vaqt), aks holda `null`.
  ///
  /// Hech qachon throw qilmaydi — read xatoligi `null` bo'lib qaytadi.
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
    final snap =
        await _col.doc(uid).collection('birthday_bonus_claims').doc('$year').get();
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

  /// Birthday bonus — бир user учун бир календар йилда фақат 1 марта.
  Future<void> grantBirthdayBonus({
    required String uid,
    required int year,
    required int amount,
    String operatorPhone = '',
  }) async {
    if (uid.isEmpty || amount <= 0) return;
    final userRef = _col.doc(uid);
    final claimRef =
        userRef.collection('birthday_bonus_claims').doc(year.toString());
    final ledgerRef = userRef.collection('wallet_ledger').doc('birthday_$year');
    await _db.runTransaction((tx) async {
      final claimSnap = await tx.get(claimRef);
      if (claimSnap.exists) {
        throw StateError('birthday_bonus_already_claimed');
      }
      final userSnap = await tx.get(userRef);
      final currentBalance =
          (userSnap.data()?['bonusBalance'] as num?)?.toInt() ?? 0;
      tx.set(claimRef, {
        'year': year,
        'amount': amount,
        'status': 'granted',
        'operatorPhone': operatorPhone.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(ledgerRef, {
        'type': 'birthday_bonus',
        'amount': amount,
        'module': 'loyalty',
        'refType': 'birthday_bonus',
        'refId': year.toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'meta': {
          'year': year,
          'operatorPhone': operatorPhone.trim(),
          'note': 'Birthday bonus',
        },
      });
      tx.set(userRef, {
        'bonusBalance': currentBalance + amount,
        'birthdayBonusLastYear': year,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Onboarding tugaganda yangi foydalanuvchi hujjati yaratiladi.
  /// `uid` — telefon raqamининг faқat raqamlari.
  ///
  /// **Muhim:** `merge: true` ishlatamiz — agar hujjat allaqachon mavjud bo'lsa
  /// (FCMService token'ni avval yozgan, Cloud Function welcome-bonus qo'shgan,
  /// foydalanuvchi ilovani qayta o'rnatgan va h.k.), `bonusBalance`,
  /// `fcmToken`, `blockedUntil` kabi maydonlar **saqlanib qoladi**. `merge`
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

  /// Device binding: биринчи киритилган телефон шу app install'га боғланади.
  ///
  /// Агар device бошқа рақамга боғланган бўлса, change request яратилади ва
  /// `StateError('device_bound_to_other_phone')` қайтарилади.
  Future<void> bindDeviceOrRequestChange({
    required String deviceId,
    required String uid,
    required String phone,
    String signalKey = '',
    Map<String, String> signals = const <String, String>{},
  }) async {
    if (deviceId.trim().isEmpty || uid.trim().isEmpty) return;
    final ref = _deviceBindings.doc(deviceId.trim());
    var similarBindingUserId = '';
    if (signalKey.trim().isNotEmpty) {
      final similar = await _deviceBindings
          .where('signalKey', isEqualTo: signalKey.trim())
          .limit(5)
          .get();
      for (final doc in similar.docs) {
        if (doc.id == deviceId.trim()) continue;
        final otherUid = (doc.data()['userId'] ?? '') as String;
        if (otherUid.isNotEmpty && otherUid != uid.trim()) {
          similarBindingUserId = otherUid;
          break;
        }
      }
    }
    final allowed = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final currentUid = (snap.data()?['userId'] ?? '') as String;
      if (snap.exists && currentUid.isNotEmpty && currentUid != uid.trim()) {
        final requestRef = _deviceChangeRequests.doc();
        tx.set(requestRef, {
          'deviceId': deviceId.trim(),
          'currentUserId': currentUid,
          'requestedUserId': uid.trim(),
          'requestedPhone': phone.trim(),
          'signalKey': signalKey.trim(),
          'signals': signals,
          'status': 'pending',
          'reason': 'same_device_new_phone',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return false;
      }

      tx.set(
        ref,
        {
          'deviceId': deviceId.trim(),
          'userId': uid.trim(),
          'phone': phone.trim(),
          'signalKey': signalKey.trim(),
          'signals': signals,
          'status': 'active',
          if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return true;
    });
    if (!allowed) {
      await _addRiskEvent(
        userId: uid,
        type: 'same_device_new_phone',
        severity: 'high',
        deviceId: deviceId,
        message: 'Бир қурилмадан бошқа телефон рақам билан кириш уриниши',
        meta: {
          'requestedPhone': phone.trim(),
          'signalKey': signalKey.trim(),
          'signals': signals,
        },
      );
      throw StateError('device_bound_to_other_phone');
    }
    if (similarBindingUserId.isNotEmpty) {
      await _addRiskEvent(
        userId: uid,
        type: 'similar_device_signal_new_install',
        severity: 'medium',
        deviceId: deviceId,
        message:
            'Янги install, лекин device signal аввал бошқа user билан ўхшаш',
        meta: {
          'similarUserId': similarBindingUserId,
          'requestedPhone': phone.trim(),
          'signalKey': signalKey.trim(),
          'signals': signals,
        },
      );
    }
  }

  /// Профилдан телефон рақамини алмаштириш тўғридан-тўғри эмас, admin approval.
  Future<void> requestPhoneChange({
    required String deviceId,
    required String currentUserId,
    required String currentPhone,
    required String requestedPhone,
    String signalKey = '',
    Map<String, String> signals = const <String, String>{},
  }) async {
    if (currentUserId.trim().isEmpty || requestedPhone.trim().isEmpty) return;
    await _deviceChangeRequests.add({
      'deviceId': deviceId.trim(),
      'currentUserId': currentUserId.trim(),
      'currentPhone': currentPhone.trim(),
      'requestedUserId': phoneDigits(requestedPhone),
      'requestedPhone': requestedPhone.trim(),
      'signalKey': signalKey.trim(),
      'signals': signals,
      'status': 'pending',
      'reason': 'profile_phone_change',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addRiskEvent(
      userId: currentUserId,
      type: 'profile_phone_change_request',
      severity: 'medium',
      deviceId: deviceId,
      message: 'User профилдан телефон рақамни алмаштириш сўрови юборди',
      meta: {
        'currentPhone': currentPhone.trim(),
        'requestedPhone': requestedPhone.trim(),
        'requestedUserId': phoneDigits(requestedPhone),
        'signalKey': signalKey.trim(),
        'signals': signals,
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

  Stream<List<DeviceChangeRequest>> watchPendingDeviceChangeRequests() {
    return _deviceChangeRequests
        .where('status', isEqualTo: 'pending')
        .limit(100)
        .snapshots()
        .map((q) {
      final items = q.docs.map(DeviceChangeRequest.fromDoc).toList();
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
      tx.set(userRef, {
        'birthDate': request.requestedBirthDate.trim(),
        'birthDateApprovedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

  Future<void> approveDeviceChange(DeviceChangeRequest request) async {
    final requestRef = _deviceChangeRequests.doc(request.id);
    final bindingRef = _deviceBindings.doc(request.deviceId);
    final requestedUserRef = _col.doc(request.requestedUserId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(requestRef);
      if ((snap.data()?['status'] ?? '') != 'pending') return;
      tx.set(bindingRef, {
        'deviceId': request.deviceId,
        'userId': request.requestedUserId,
        'phone': request.requestedPhone,
        'previousUserId': request.currentUserId,
        'signalKey': request.signalKey,
        'signals': request.signals,
        'status': 'active',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (request.requestedUserId.isNotEmpty) {
        tx.set(requestedUserRef, {
          'phone': request.requestedPhone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      tx.update(requestRef, {
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectDeviceChange(String requestId) async {
    await _deviceChangeRequests.doc(requestId).set({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final patch = <String, Object?>{
      'address': address.toMap(),
      'addressUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (legacyFromString != null && legacyFromString.trim().isNotEmpty) {
      patch['legacyAddress'] = legacyFromString.trim();
    }
    await _col.doc(uid).set(patch, SetOptions(merge: true));
  }

  /// `lastNewsReadAt`ни янгилаш — Унread badge'ни тозалаш.
  Future<void> markNewsRead(String uid) async {
    if (uid.isEmpty) return;
    await _col.doc(uid).set(
        {'lastNewsReadAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
  }
}
