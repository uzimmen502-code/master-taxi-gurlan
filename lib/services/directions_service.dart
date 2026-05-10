import 'package:dio/dio.dart';

class DirectionsService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';
  static const String _apiKey = 'AIzaSyDl6AwtVg1DNoev0zTNKBcaEYFfj93q_FE';

  final Dio _dio = Dio();

  Future<DirectionsResult?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'origin': '$originLat,$originLng',
          'destination': '$destLat,$destLng',
          'key': _apiKey,
          'mode': 'driving',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final leg = route['legs'][0];

          return DirectionsResult(
            distance: leg['distance']['value'] / 1000.0,
            duration: leg['duration']['value'] ~/ 60,
            distanceText: leg['distance']['text'],
            durationText: leg['duration']['text'],
            startAddress: leg['start_address'],
            endAddress: leg['end_address'],
            polyline: route['overview_polyline']['points'],
          );
        }
      }
      return null;
    } catch (e) {
      print('Directions API хатолик: $e');
      return null;
    }
  }
}

class DirectionsResult {
  final double distance;
  final int duration;
  final String distanceText;
  final String durationText;
  final String startAddress;
  final String endAddress;
  final String polyline;

  DirectionsResult({
    required this.distance,
    required this.duration,
    required this.distanceText,
    required this.durationText,
    required this.startAddress,
    required this.endAddress,
    required this.polyline,
  });
}