import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MfyService {
  static Map<String, Map<String, List<String>>>? _mfyData;

  // JSON ни юклаш
  static Future<void> loadMfyData() async {
    if (_mfyData != null) return;

    try {
      final String jsonString = await rootBundle.loadString('assets/data/mfy_list.json');
      final Map<String, dynamic> data = json.decode(jsonString);

      _mfyData = data.map((key, value) {
        return MapEntry(key, (value as Map<String, dynamic>).map((k, v) {
          return MapEntry(k, List<String>.from(v));
        }));
      });
      debugPrint('МФЙ маълумотлари юкланди. ${_mfyData!.values.first.values.first.length} та МФЙ бор');
    } catch (e) {
      debugPrint('МФЙ маълумотларини юклашда хатолик: $e');
    }
  }

  // Туман бўйича МФЙ ларни олиш (`gurlan` / `Gurlan` / `Гурлан`).
  static List<String> getMfyByDistrict(String district) {
    if (_mfyData == null) return [];
    final needle = district.trim().toLowerCase();
    if (needle.isEmpty) return [];

    for (var region in _mfyData!.values) {
      for (final entry in region.entries) {
        final key = entry.key.toLowerCase();
        if (key == needle ||
            key.replaceAll('ʻ', '').replaceAll("'", '') ==
                needle.replaceAll('_', '')) {
          return entry.value;
        }
      }
    }
    return [];
  }

  // Барча МФЙ ларни олиш (агар туман танланмаган бўлса)
  static List<String> getAllMfy() {
    if (_mfyData == null) return [];

    final List<String> allMfy = [];
    for (var region in _mfyData!.values) {
      for (var districtMfy in region.values) {
        allMfy.addAll(districtMfy);
      }
    }
    return allMfy;
  }

  // Қидириш (автокомплит учун)
  static List<String> searchMfy(String query, {String? district}) {
    if (query.isEmpty) return [];

    final List<String> source = district != null
        ? getMfyByDistrict(district)
        : getAllMfy();

    return source.where((mfy) {
      return mfy.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }

  // Туман номини текшириш (МФЙ борми?)
  static bool hasDistrict(String district) {
    if (_mfyData == null) return false;

    for (var region in _mfyData!.values) {
      for (var key in region.keys) {
        if (key.toLowerCase() == district.toLowerCase()) {
          return true;
        }
      }
    }
    return false;
  }
}