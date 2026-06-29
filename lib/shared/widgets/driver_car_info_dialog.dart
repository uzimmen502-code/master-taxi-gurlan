import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/formatters.dart';
import '../../features/driver_schedule/screens/driver_schedule_screen.dart';
import '../../repositories/user_repository.dart';
import '../navigation/ensure_car_info_via_profile.dart';
import 'intercity_quick_start_sheet.dart';

/// Haydovchi sifatida ishga chiqish: avval profil avtomobili, keyin jadval.
Future<bool> showDriverCarInfoDialog({
  required BuildContext context,
  required String taxiType,
  required Color primaryColor,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('user_phone') ?? '';
  final name = prefs.getString('user_name') ?? '';
  final uid = canonicalPhoneId(phone.replaceAll(RegExp(r'[^\d]'), ''));
  if (!context.mounted) return false;
  if (uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Аввал профилдан телефон рақамини киритинг')));
    return false;
  }

  if (!await ensureCarInfoViaProfile(context)) return false;
  if (!context.mounted) return false;

  final car = await UserRepository().getCarInfo(uid);
  if (car == null) return false;
  final carModel = car['carModel'] ?? '';
  final carPlate = car['carPlate'] ?? '';

  if (taxiType == 'intercity') {
    final carSeats = int.tryParse(car['carSeats'] ?? '') ?? 0;
    if (!context.mounted) return false;
    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IntercityQuickStartSheet(
        driverName: name,
        driverPhone: phone,
        driverCar: carModel,
        driverPlate: carPlate,
        seats: carSeats > 0 ? carSeats : 4,
        primaryColor: primaryColor,
      ),
    );
    return started == true;
  }

  if (!context.mounted) return false;
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => DriverScheduleScreen(
        taxiType: taxiType,
        driverName: name,
        driverPhone: phone,
        driverCar: carModel,
        driverPlate: carPlate,
      ),
    ),
  );
  return ok == true;
}
