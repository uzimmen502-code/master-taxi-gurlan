import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../repositories/user_repository.dart';
import '../models/tv_clip.dart';

const _fakeGivenNames = {
  'фойдаланувчи',
  'foydalanuvchi',
  'пользователь',
  'user',
};

/// Телефон, бўш ва UI fallback матнларини чиқариб ташлайди.
bool tvOwnerNameLooksFake(String raw) {
  final g = tvOwnerGivenName(raw);
  if (g.isEmpty) return true;
  return _fakeGivenNames.contains(g.toLowerCase());
}

/// Профилдаги исм: аввал телефон кэши (`user_name`), сўнг Firestore, сўнг Auth.
Future<String> resolveLocalTvOwnerGivenName({String phone = ''}) async {
  final prefs = await SharedPreferences.getInstance();
  final fromPrefs = tvOwnerGivenName(prefs.getString('user_name') ?? '');
  if (fromPrefs.isNotEmpty) return fromPrefs;

  final uid = canonicalPhoneId(prefs.getString('user_phone') ?? phone);
  if (uid.isNotEmpty) {
    try {
      final profile = await UserRepository().getById(uid);
      final fromFs = tvOwnerGivenName(profile?.name ?? '');
      if (fromFs.isNotEmpty) return fromFs;
    } catch (_) {}
  }

  final authName = FirebaseAuth.instance.currentUser?.displayName ?? '';
  return tvOwnerGivenName(authName);
}
