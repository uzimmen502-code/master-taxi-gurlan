import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../repositories/user_repository.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_public_profiles_repository.dart';

/// Телефон, бўш, @nick ва UI fallback матнларини чиқариб ташлайди.
bool tvOwnerNameLooksFake(String raw) => tvOwnerDisplayName(raw).isEmpty;

/// Ролик устидаги исм: клипдаги жойлаштирувчи → оммавий профил →
/// фақат ўз роликингиз бўлса локал профил. «Фойдаланувчи» қайтарилмайди.
String tvPublisherOverlayName({
  required TvClip clip,
  required String viewerPhone,
  required String viewerDisplayName,
  Map<String, String> publicNames = const {},
}) {
  final stored = tvOwnerDisplayName(clip.ownerName);
  if (stored.isNotEmpty) return stored;
  final pub = publicNames[canonicalPhoneId(clip.ownerPhone)] ?? '';
  if (pub.isNotEmpty) return pub;
  if (phonesMatch(clip.ownerPhone, viewerPhone)) {
    return tvOwnerDisplayName(viewerDisplayName);
  }
  return '';
}

/// `ownerName` бўш/@nick/телефон бўлган клипларга оммавий исм қўяди.
Future<List<TvClip>> applyPublicPublisherNames(List<TvClip> clips) async {
  final hydrated = await hydrateTvPublisherNames(clips);
  return hydrated.clips;
}

class TvPublisherHydrate {
  const TvPublisherHydrate({
    required this.clips,
    required this.publicNames,
  });
  final List<TvClip> clips;
  final Map<String, String> publicNames;
}

/// Барча жойлаштирувчилар учун `tv_public_profiles` / дўкон номи.
Future<TvPublisherHydrate> hydrateTvPublisherNames(List<TvClip> clips) async {
  if (clips.isEmpty) {
    return const TvPublisherHydrate(clips: [], publicNames: {});
  }
  final names =
      await TvPublicProfilesRepository().fetchMany(clips.map((c) => c.ownerPhone));
  if (names.isEmpty) {
    return TvPublisherHydrate(clips: clips, publicNames: names);
  }
  return TvPublisherHydrate(
    publicNames: names,
    clips: [
      for (final c in clips)
        if (tvOwnerDisplayName(c.ownerName).isNotEmpty)
          c
        else
          c.copyWith(
            ownerName: names[canonicalPhoneId(c.ownerPhone)] ?? c.ownerName,
          ),
    ],
  );
}

/// Жойлаштирувчи исми: prefs → Firestore `users.name` → Auth.
/// Топилса prefs ва `tv_public_profiles` га ёзилади (бошқалар ҳам ўқийди).
Future<String> resolveLocalTvOwnerGivenName({String phone = ''}) async {
  final prefs = await SharedPreferences.getInstance();
  final fromPrefs = tvOwnerDisplayName(prefs.getString('user_name') ?? '');
  if (fromPrefs.isNotEmpty) {
    await syncTvPublisherPublicName(fromPrefs, phone: phone);
    return fromPrefs;
  }

  final uid = canonicalPhoneId(prefs.getString('user_phone') ?? phone);
  if (uid.isNotEmpty) {
    try {
      final profile = await UserRepository().getById(uid);
      final fromFs = tvOwnerDisplayName(profile?.name ?? '');
      if (fromFs.isNotEmpty) {
        await prefs.setString('user_name', fromFs);
        await syncTvPublisherPublicName(fromFs, phone: uid);
        return fromFs;
      }
    } catch (_) {}
  }

  final authName = FirebaseAuth.instance.currentUser?.displayName ?? '';
  final fromAuth = tvOwnerDisplayName(authName);
  if (fromAuth.isNotEmpty) {
    await prefs.setString('user_name', fromAuth);
    await syncTvPublisherPublicName(fromAuth, phone: phone);
  }
  return fromAuth;
}

Future<void> syncTvPublisherPublicName(String name, {String phone = ''}) async {
  final display = tvOwnerDisplayName(name);
  if (display.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final uid = canonicalPhoneId(prefs.getString('user_phone') ?? phone);
  if (uid.isEmpty) return;
  try {
    await TvPublicProfilesRepository().upsert(uid: uid, name: display);
  } catch (_) {}
}
