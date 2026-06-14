import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import 'screens/intercity_driver_panel_screen.dart';

/// Актив шаҳарлараро рейс (`intercity_drivers.isActive`) бўлса панельга қайтариш.
class IntercityDriverResume {
  IntercityDriverResume._();

  static bool _launchCheckDone = false;
  static String? _launchCheckUid;

  /// Профилдан чиқиш — кейинги фойдаланувчи учун қайта текшириш.
  static void resetSession() {
    _launchCheckDone = false;
    _launchCheckUid = null;
  }

  static Future<bool> hasActiveListing(String driverId) async {
    if (driverId.length < 9) return false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('intercity_drivers')
          .doc(driverId)
          .get();
      if (!snap.exists) return false;
      return snap.data()?['isActive'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<({
    String driverId,
    String driverName,
    String driverPhone,
    String driverCar,
    String driverPlate,
  })?> loadPanelArgs(String driverId) async {
    if (driverId.length < 9) return null;

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    var name = prefs.getString('user_name') ?? '';
    var car = prefs.getString('car_model') ?? '';
    var plate = prefs.getString('car_plate') ?? '';

    if (car.isEmpty || plate.isEmpty || name.isEmpty) {
      try {
        final d = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driverId)
            .get();
        final data = d.data();
        if (data != null) {
          if (name.isEmpty) name = (data['name'] ?? data['driverName'] ?? '') as String;
          if (car.isEmpty) car = (data['car'] ?? '') as String;
          if (plate.isEmpty) plate = (data['plate'] ?? '') as String;
        }
      } catch (_) {}
    }

    final intercitySnap = await FirebaseFirestore.instance
        .collection('intercity_drivers')
        .doc(driverId)
        .get();
    final ic = intercitySnap.data();
    if (ic != null) {
      if (name.isEmpty) name = (ic['name'] ?? '') as String;
      if (car.isEmpty) car = (ic['car'] ?? '') as String;
      if (plate.isEmpty) plate = (ic['plate'] ?? '') as String;
    }

    return (
      driverId: driverId,
      driverName: name.isEmpty ? 'default_driver_name' : name,
      driverPhone: phone,
      driverCar: car,
      driverPlate: plate,
    );
  }

  /// Актив рейс бўлса панельни очади.
  static Future<bool> openPanelIfActive(
    BuildContext context, {
    required String driverId,
  }) async {
    if (!await hasActiveListing(driverId)) return false;
    final args = await loadPanelArgs(driverId);
    if (args == null || !context.mounted) return false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IntercityDriverPanelScreen(
          driverId: args.driverId,
          driverName: args.driverName == 'default_driver_name'
              ? context.tr('default_driver_name')
              : args.driverName,
          driverPhone: args.driverPhone,
          driverCar: args.driverCar,
          driverPlate: args.driverPlate,
        ),
      ),
    );
    return true;
  }

  /// Илова қайта очилганда бир марта (HomeScreen).
  static Future<void> tryResumeOnAppLaunch(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);
    if (uid.length < 9) return;
    if (_launchCheckDone && _launchCheckUid == uid) return;
    _launchCheckDone = true;
    _launchCheckUid = uid;
    if (!context.mounted) return;
    await openPanelIfActive(context, driverId: uid);
  }
}
