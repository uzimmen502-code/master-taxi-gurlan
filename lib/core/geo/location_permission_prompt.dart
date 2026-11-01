import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n_extension.dart';

const _kAsked = 'geo_perm_asked_v1';

/// Жойлашув рухсатини БИР МАРТА, ихчам матн билан сўраш (эга, 2026-11-01: «ихчам матнлар билан
/// ортиқча сўзларсиз рухсат сўрасин»). GPS — тепадаги ҳудуднинг биринчи манбаи ([GeoContext.applyGps]).
///
/// - Вебда йўқ (geocoder ишламайди).
/// - Рухсат аллақачон бор / абадий рад этилган / олдин сўралган — ойна чиқмайди.
/// - «Кейин» — қайта сўралмайди (ҳудудни ойнадан танлаш мумкин).
///
/// Қайтаради: рухсат ҲОЗИР берилдими (берилса — GPS дарҳол текширилади).
Future<bool> askLocationPermissionOnce(
  BuildContext context, {
  Future<LocationPermission> Function()? check,
  Future<LocationPermission> Function()? request,
}) async {
  if (kIsWeb) return false;
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    return false;
  }
  if (prefs.getBool(_kAsked) == true) return false;
  final LocationPermission perm;
  try {
    perm = await (check ?? Geolocator.checkPermission)();
  } catch (_) {
    return false;
  }
  if (perm != LocationPermission.denied) {
    // Бор ёки абадий рад — сўраш маъносиз; кейин ҳам сўралмайди.
    await prefs.setBool(_kAsked, true);
    return false;
  }
  if (!context.mounted) return false;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('geo_perm_dialog'),
      icon: const Icon(Icons.my_location),
      title: Text(ctx.tr('geo_perm_title')),
      content: Text(ctx.tr('geo_perm_body'), textAlign: TextAlign.center),
      actions: [
        TextButton(
          key: const ValueKey('geo_perm_later'),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('geo_perm_later')),
        ),
        FilledButton(
          key: const ValueKey('geo_perm_allow'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('geo_perm_allow')),
        ),
      ],
    ),
  );
  await prefs.setBool(_kAsked, true);
  if (yes != true) return false;
  try {
    final r = await (request ?? Geolocator.requestPermission)();
    return r == LocationPermission.always || r == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}
