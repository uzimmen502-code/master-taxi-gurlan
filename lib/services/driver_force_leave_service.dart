import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../repositories/driver_repository.dart';
import '../repositories/marshrut_driver_repository.dart';
import '../repositories/rides_repository.dart';
import 'driver_role_service.dart';
import 'fcm_service.dart';

/// Marshrut haydovchi rejimidan to'liq chiqish — panel va profil bir xil pipeline.
class DriverForceLeaveService {
  DriverForceLeaveService({
    MarshrutDriverRepository? marshrutDriverRepo,
    DriverRepository? driverRepo,
    RidesRepository? ridesRepo,
    FirebaseFirestore? db,
  })  : _marshrutDriverRepo = marshrutDriverRepo ?? MarshrutDriverRepository(),
        _driverRepo = driverRepo ?? DriverRepository(),
        _ridesRepo = ridesRepo ?? RidesRepository(),
        _db = db ?? FirebaseFirestore.instance;

  final MarshrutDriverRepository _marshrutDriverRepo;
  final DriverRepository _driverRepo;
  final RidesRepository _ridesRepo;
  final FirebaseFirestore _db;

  /// Safarlarni transaksiya bilan bekor → reys yopish → offline → CF (faqat rol/queue).
  Future<void> forceLeaveMarshrutDriver({required String userPhone}) async {
    final uid = phoneDigits(userPhone);
    if (uid.length < 9) {
      throw ArgumentError('Invalid userPhone');
    }

    await _cancelActiveMarshrutTrips(uid);
    await _deactivateActiveMarshrutSchedules(uid);

    await _marshrutDriverRepo.goOffline(uid);
    await _driverRepo.goOffline(uid);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', 'user');
    await prefs.remove('car_model');
    await prefs.remove('car_color');
    await prefs.remove('car_plate');
    await _markApprovalNotificationsSent(prefs);

    // Delete marshrut driver profile from Firestore
    try {
      final canonUid = canonicalPhoneId(
          prefs.getString('user_phone') ?? '');
      if (canonUid.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(canonUid)
            .collection('driverProfiles')
            .doc('marshrut')
            .delete();
      }
    } catch (e) {
      debugPrint('clearMarshrutProfile error: $e');
    }

    await DriverRoleService.leaveDriverMode(
      userPhone: userPhone,
      clientHandledCleanup: true,
    );
    await FCMService().refreshToken();
    FCMService().stopListeners();
    await FCMService().startListeners();
  }

  Future<void> _markApprovalNotificationsSent(
      SharedPreferences prefs) async {
    try {
      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) return;
      final alias = phone.replaceAll(RegExp(r'\D'), '');
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('targetPhone', isEqualTo: alias)
          .where('sent', isEqualTo: false)
          .where('type', isEqualTo: 'driver_request_approved')
          .get();
      for (final doc in snap.docs) {
        await doc.reference.update({'sent': true});
      }
    } catch (e) {
      debugPrint('markApprovalNotificationsSent: $e');
    }
  }

  Future<void> _cancelActiveMarshrutTrips(String uid) async {
    final trips = await _db
        .collection('trips')
        .where('acceptedDriverId', isEqualTo: uid)
        .where('taxiType', isEqualTo: 'marshrut')
        .where('status', isEqualTo: 'accepted')
        .get();

    for (final doc in trips.docs) {
      await _ridesRepo.cancelMarshrutByDriver(
        tripId: doc.id,
        reason: 'driver_left_mode',
      );
    }
  }

  Future<void> _deactivateActiveMarshrutSchedules(String uid) async {
    final schedules = await _db
        .collection('schedules')
        .where('driverId', isEqualTo: uid)
        .where('taxiType', isEqualTo: 'marshrut')
        .where('isActive', isEqualTo: true)
        .get();

    for (final doc in schedules.docs) {
      await doc.reference.update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
