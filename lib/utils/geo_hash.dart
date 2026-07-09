/// Oddiy geohash — Firestore mintaqaviy trip qidiruvi uchun (precision 4 ≈ 20 km).
abstract final class GeoHash {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// [precision] 1–12; mahalliy taksi uchun 4 tavsiya etiladi.
  static String encode(double lat, double lng, {int precision = 4}) {
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;
    final buf = StringBuffer();
    var bit = 0;
    var ch = 0;
    var even = true;

    while (buf.length < precision) {
      if (even) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) {
          ch |= 1 << (4 - bit);
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          ch |= 1 << (4 - bit);
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      even = !even;
      bit++;
      if (bit == 5) {
        buf.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return buf.toString();
  }

  /// Markaz hujayra + 8 qo'shni (jami 9) — radius ichidagi trip qidiruv.
  static List<String> neighborsForRadius(
    double lat,
    double lng, {
    int precision = 4,
  }) {
    final center = encode(lat, lng, precision: precision);
    final decoded = _decode(center);
    final latDelta = decoded.latErr * 2;
    final lngDelta = decoded.lngErr * 2;
    final seen = <String>{center};
    final out = <String>[center];

    void add(double la, double ln) {
      final h = encode(la, ln, precision: precision);
      if (seen.add(h)) out.add(h);
    }

    add(lat + latDelta, lng);
    add(lat - latDelta, lng);
    add(lat, lng + lngDelta);
    add(lat, lng - lngDelta);
    add(lat + latDelta, lng + lngDelta);
    add(lat + latDelta, lng - lngDelta);
    add(lat - latDelta, lng + lngDelta);
    add(lat - latDelta, lng - lngDelta);
    return out;
  }

  static ({double lat, double lng, double latErr, double lngErr}) _decode(
    String hash,
  ) {
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;
    var even = true;

    for (final c in hash.split('')) {
      final cd = _base32.indexOf(c);
      if (cd < 0) continue;
      for (var mask = 16; mask > 0; mask >>= 1) {
        if (even) {
          final mid = (minLng + maxLng) / 2;
          if ((cd & mask) != 0) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if ((cd & mask) != 0) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        even = !even;
      }
    }
    final lat = (minLat + maxLat) / 2;
    final lng = (minLng + maxLng) / 2;
    return (
      lat: lat,
      lng: lng,
      latErr: (maxLat - minLat) / 2,
      lngErr: (maxLng - minLng) / 2,
    );
  }
}
