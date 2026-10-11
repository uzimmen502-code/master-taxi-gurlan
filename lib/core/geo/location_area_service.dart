import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/geo_area.dart';
import '../../repositories/service_config_repository.dart';
import '../../utils/geo_hash.dart';
import '../brand_labels.dart';
import 'district_matcher.dart';
import 'geo_context.dart';

/// Локация таклифи (D-GEO-12): «Сиз ҳозир Чилонзордасиз…» — тасдиқсиз
/// ўтмайди, «Йўқ» шу туманга 24 соат сўралмайди.
const kGeoSuggestQuiet = Duration(hours: 24);

/// Таклиф кўрсатиладими (тоза функция — тест учун).
bool shouldSuggestLocation({
  required GeoArea? detected,
  required GeoArea active,
  required DateTime? dismissedAt,
  required DateTime now,
}) {
  if (detected == null || detected.isEmpty) return false;
  if (detected.sameAs(active)) return false;
  if (dismissedAt != null && now.difference(dismissedAt) < kGeoSuggestQuiet) return false;
  return true;
}

String _dismissKey(String districtId) => 'geo_suggest_dismiss_$districtId';

Future<DateTime?> suggestionDismissedAt(String districtId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_dismissKey(districtId));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  } catch (_) {
    return null;
  }
}

Future<void> dismissSuggestion(String districtId, DateTime now) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissKey(districtId), now.millisecondsSinceEpoch);
  } catch (_) {}
}

/// Жорий жойлашувдан туманни аниқлайди (D-GEO-13, А вариант — телефон
/// geocoder'и + номни мослаш).
///
/// - GPS рухсати ОЛДИН берилган бўлса ишлайди; рухсат СЎРАМАЙДИ (GPS
///   фақат керак пайтда сўралади — таклиф шартлари).
/// - Вебда ишламайди (geocoder йўқ).
/// - Натижа geohash-5 (~5 км) катак бўйича 7 кун кешланади — ҳар очилишда
///   Firestore ўқиш ва geocoder чақирувидан сақлайди (37-банд).
class LocationAreaService {
  LocationAreaService({ServiceConfigRepository? repo}) : _repo = repo ?? ServiceConfigRepository();

  final ServiceConfigRepository _repo;
  static const _cacheTtl = Duration(days: 7);
  static List<GeoRegion>? _regions;
  static final Map<String, List<GeoDistrict>> _districts = {};

  Future<GeoArea?> detect() async {
    if (kIsWeb) return null;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
      return await _areaFor(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('LocationAreaService.detect: $e');
      return null;
    }
  }

  /// Исталган нуқтанинг тумани (масалан кўчмас мулк пини, D-GEO-11).
  /// Жойлашув рухсати керак эмас — фақат geocoder. Вебда — `null`.
  Future<GeoArea?> areaAt(double lat, double lng) async {
    if (kIsWeb) return null;
    try {
      return await _areaFor(lat, lng);
    } catch (e) {
      debugPrint('LocationAreaService.areaAt: $e');
      return null;
    }
  }

  Future<GeoArea?> _areaFor(double lat, double lng) async {
    final cell = GeoHash.encode(lat, lng, precision: 5);
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'geo_loc_v1_$cell';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      final j = jsonDecode(cached) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt());
      if (DateTime.now().difference(at) < _cacheTtl) {
        final a = j['area'];
        return a is Map ? GeoArea.fromJson(Map<String, dynamic>.from(a)) : null;
      }
    }

    final marks = await placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 6));
    GeoArea? area;
    if (marks.isNotEmpty) {
      final p = marks.first;
      final regions = _regions ??= await _repo.fetchRegions();
      final regionIds = matchRegions(
        p.administrativeArea,
        regions.map((r) => RegionCandidate(id: r.id, names: [r.name, r.nameUz])).toList(),
      );
      // Вилоят аниқланмаса — 200+ туманни ўқимаймиз, таклиф йўқ.
      if (regionIds.isNotEmpty) {
        final all = <GeoDistrict>[];
        for (final id in regionIds) {
          all.addAll(_districts[id] ??= await _repo.fetchDistricts(id));
        }
        final m = matchDistrict(
          [p.subAdministrativeArea, p.locality, p.subLocality],
          all.map((d) => DistrictCandidate(id: d.id, regionId: d.regionId, names: [d.name, d.nameUz])).toList(),
          regionIds: regionIds,
        );
        if (m != null) {
          final d = all.firstWhere((x) => x.id == m.id);
          final r = regions.where((x) => x.id == d.regionId).firstOrNull;
          area = GeoArea(
            regionId: d.regionId,
            districtId: d.id,
            // Яшаш жойи ёрлиғи каби (`ServiceConfigHolder._resolveRegionLabel`).
            regionLabel: r?.displayName.trim() ?? '',
            districtLabel: BrandLabels.shortDistrictName(d.displayName),
          );
        }
      }
      debugPrint(jsonEncode({
        'action': 'geoLocationMatch',
        'result': area == null ? 'no_match' : 'matched',
        'subAdmin': p.subAdministrativeArea,
        'locality': p.locality,
        'admin': p.administrativeArea,
      }));
    }
    await prefs.setString(
      cacheKey,
      jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'area': area?.toJson()}),
    );
    return area;
  }
}
