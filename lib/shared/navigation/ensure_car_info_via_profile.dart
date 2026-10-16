import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/formatters.dart';
import '../../repositories/user_repository.dart';
import '../car/car_edit_dialog.dart';
import 'app_home_route.dart';

/// Avtomobil ma'lumotlari to'liq emas bo'lsa kiritish oynasini ochadi
/// (Kabinet/profil ekrani orqali EMAS — oyna `shared/car` da).
/// Saqlansa `true`. Bekor qilinsa bosh sahifaga qaytadi va `false`.
Future<bool> ensureCarInfoViaProfile(
  BuildContext context, {
  bool goHomeOnCancel = true,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('user_phone') ?? '';
  final uid = canonicalPhoneId(phoneDigits(phone));
  if (uid.length < 9) return false;

  final car = await UserRepository().getCarInfo(uid);
  if (_isComplete(car)) return true;

  if (!context.mounted) return false;
  final saved = await showCarEditDialog(
    context,
    uid: phoneDigits(phone),
    driverFlow: true,
  );

  if (saved == true) return true;

  if (goHomeOnCancel && context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(appHomeRoute(), (_) => false);
  }
  return false;
}

bool _isComplete(Map<String, String>? car) {
  if (car == null) return false;
  final model = car['carModel'] ?? '';
  final color = car['carColor'] ?? '';
  final plate = car['carPlate'] ?? '';
  final seats = int.tryParse(car['carSeats'] ?? '') ?? 0;
  return model.trim().isNotEmpty &&
      color.trim().isNotEmpty &&
      plate.trim().isNotEmpty &&
      seats > 0;
}
