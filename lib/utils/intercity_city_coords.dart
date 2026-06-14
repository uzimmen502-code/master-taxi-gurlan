/// Shahar nomidan taxminiy markaz koordinatalari (Directions origin/destination).
library;

import 'intercity_places.dart';

abstract final class IntercityCityCoords {
  static const defaultOriginLat = 41.8443;
  static const defaultOriginLng = 60.3919;

  static const _coords = <String, (double lat, double lng)>{
    'gurlan': (41.8443, 60.3919),
    'xorazm': (41.5500, 60.6333),
    'xiva': (41.3783, 60.3639),
    'urganch': (41.5500, 60.6333),
    'toshkent': (41.2995, 69.2401),
    'samarqand': (39.6542, 66.9597),
    'buxoro': (39.7747, 64.4286),
    'namangan': (40.9983, 71.6726),
    'andijon': (40.7821, 72.3442),
    'fargona': (40.3842, 71.7843),
    'nukus': (42.4531, 59.6103),
    'navoiy': (40.0844, 65.3792),
    'qarshi': (38.8600, 65.7983),
    'termiz': (37.2242, 67.2783),
    'jizzax': (40.1158, 67.8422),
  };

  static (double lat, double lng) resolve(String cityName) {
    final city = IntercityPlaces.extractCity(cityName);
    final key = _latinKey(city);
    if (key.isEmpty) return (defaultOriginLat, defaultOriginLng);
    for (final entry in _coords.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) {
        return entry.value;
      }
    }
    return (defaultOriginLat, defaultOriginLng);
  }

  static String _latinKey(String raw) {
    const map = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
      'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
      'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
      'ф': 'f', 'х': 'x', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': '',
      'ы': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
      'ҳ': 'h', 'қ': 'q', 'ғ': 'g', 'ў': 'o', 'ң': 'ng',
    };
    final buf = StringBuffer();
    for (final rune in raw.toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      buf.write(map[c] ?? c);
    }
    return buf
        .toString()
        .replaceAll(RegExp(r'[^a-z]'), '')
        .trim();
  }
}
