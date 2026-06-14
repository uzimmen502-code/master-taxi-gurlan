import 'package:google_maps_flutter/google_maps_flutter.dart';

class PolylineDecoder {
  const PolylineDecoder();

  List<LatLng> decode(String encoded) {
    if (encoded.isEmpty) return const [];

    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      final latResult = _decodeValue(encoded, index);
      index = latResult.nextIndex;
      lat += latResult.value;

      final lngResult = _decodeValue(encoded, index);
      index = lngResult.nextIndex;
      lng += lngResult.value;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  _DecodedValue _decodeValue(String encoded, int startIndex) {
    var index = startIndex;
    var result = 0;
    var shift = 0;
    int byte;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);

    final value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    return _DecodedValue(value: value, nextIndex: index);
  }
}

class _DecodedValue {
  const _DecodedValue({
    required this.value,
    required this.nextIndex,
  });

  final int value;
  final int nextIndex;
}
