import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/formatters.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../repositories/user_repository.dart';

/// Avtomobil ma'lumotlari to'liq emas bo'lsa profilga yo'naltiradi.
/// Saqlansa `true`. Bekor qilinsa bosh sahifaga qaytadi va `false`.
Future<bool> ensureCarInfoViaProfile(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('user_phone') ?? '';
  final uid = canonicalPhoneId(phoneDigits(phone));
  if (uid.length < 9) return false;

  final car = await UserRepository().getCarInfo(uid);
  if (_isComplete(car)) return true;

  if (!context.mounted) return false;
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => const ProfileScreen(
        autoOpenCarEdit: true,
        returnAfterSave: true,
      ),
    ),
  );

  if (saved == true) return true;

  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
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
