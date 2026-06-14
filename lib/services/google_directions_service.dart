import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/directions_result.dart';
import '../models/route_candidate.dart';

class GoogleDirectionsService {
  GoogleDirectionsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Тармоқ чақируви учун чегара — спиннер абадий қотиб қолмаслиги учун.
  static const Duration _httpTimeout = Duration(seconds: 20);

  Future<RouteCandidate> enrichCandidate(RouteCandidate candidate) async {
    if (candidate.stops.isEmpty) return candidate;

    final result = await fetchDirections(candidate);
    return candidate.copyWith(
      distanceKm: result.distanceKm,
      durationMin: result.durationMin,
      polyline: result.polyline,
      hasGoogleDirections: true,
    );
  }

  Future<DirectionsResult> fetchDirections(RouteCandidate candidate) async {
    final stops = candidate.stops;
    final origin = '${candidate.startLat},${candidate.startLng}';
    final destination = '${stops.last.lat},${stops.last.lng}';
    final waypointStops =
        stops.length > 1 ? stops.sublist(0, stops.length - 1) : const [];
    final waypoints = waypointStops.isNotEmpty
        ? waypointStops.map((s) => '${s.lat},${s.lng}').join('|')
        : '';

    final Map<String, dynamic> json;

    if (kIsWeb) {
      // Web: CORS tufayli to'g'ri chaqirib bo'lmaydi — Cloud Function proxy
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getDirections',
        options: HttpsCallableOptions(timeout: _httpTimeout),
      );
      final result = await callable.call(<String, dynamic>{
        'origin': origin,
        'destination': destination,
        'waypoints': waypoints,
        'mode': 'driving',
        'language': 'uz',
      });
      json = Map<String, dynamic>.from(result.data as Map);
    } else {
      // Mobile: to'g'ridan HTTP chaqiruv
      final params = <String, String>{
        'origin': origin,
        'destination': destination,
        'mode': 'driving',
        'language': 'uz',
        'key': AppConfig.mapsApiKey,
        if (waypoints.isNotEmpty) 'waypoints': waypoints,
      };
      final uri = Uri.https(
          'maps.googleapis.com', '/maps/api/directions/json', params);
      final response = await _client.get(uri).timeout(
            _httpTimeout,
            onTimeout: () => throw Exception(
              'Маршрут серверига уланиб бўлмади — интернетни текширинг',
            ),
          );
      if (response.statusCode != 200) {
        throw Exception('Directions API HTTP ${response.statusCode}');
      }
      json = jsonDecode(response.body) as Map<String, dynamic>;
    }

    final status = json['status'] as String? ?? 'UNKNOWN';
    if (status != 'OK') {
      final message = json['error_message'] as String? ?? status;
      throw Exception('Directions API: $message');
    }

    final routes = json['routes'] as List? ?? const [];
    if (routes.isEmpty) throw Exception('Directions API: route topilmadi');

    final route = Map<String, dynamic>.from(routes.first as Map);
    final legs = route['legs'] as List? ?? const [];
    var distanceMeters = 0;
    var durationSeconds = 0;
    for (final rawLeg in legs) {
      final leg = Map<String, dynamic>.from(rawLeg as Map);
      final distance =
          Map<String, dynamic>.from((leg['distance'] as Map?) ?? const {});
      final duration =
          Map<String, dynamic>.from((leg['duration'] as Map?) ?? const {});
      distanceMeters += (distance['value'] as num?)?.toInt() ?? 0;
      durationSeconds += (duration['value'] as num?)?.toInt() ?? 0;
    }

    final overview = Map<String, dynamic>.from(
        (route['overview_polyline'] as Map?) ?? const {});
    final polyline = overview['points'] as String? ?? '';

    return DirectionsResult(
      distanceKm: distanceMeters / 1000,
      durationMin: (durationSeconds / 60).ceil(),
      polyline: polyline,
    );
  }

  /// Origin → (optimallashtirilgan waypoints) → destination.
  ///
  /// Google Directions `optimize:true` — eng qisqa vaqt tartibi.
  Future<DirectionsResult> fetchOptimizedRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required List<({double lat, double lng})> waypoints,
  }) async {
    if (waypoints.isEmpty) {
      return fetchSimpleRoute(
        originLat: originLat,
        originLng: originLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
      );
    }

    final origin = '$originLat,$originLng';
    final destination = '$destinationLat,$destinationLng';
    final wpBody = waypoints.map((w) => '${w.lat},${w.lng}').join('|');
    final waypointsParam = 'optimize:true|$wpBody';

    final json = await _requestDirectionsJson(
      origin: origin,
      destination: destination,
      waypoints: waypointsParam,
    );

    return _parseDirectionsJson(json, expectWaypointOrder: true);
  }

  Future<DirectionsResult> fetchSimpleRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final json = await _requestDirectionsJson(
      origin: '$originLat,$originLng',
      destination: '$destinationLat,$destinationLng',
      waypoints: '',
    );
    return _parseDirectionsJson(json);
  }

  Future<Map<String, dynamic>> _requestDirectionsJson({
    required String origin,
    required String destination,
    required String waypoints,
  }) async {
    final Map<String, dynamic> json;

    if (kIsWeb) {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getDirections',
        options: HttpsCallableOptions(timeout: _httpTimeout),
      );
      final result = await callable.call(<String, dynamic>{
        'origin': origin,
        'destination': destination,
        'waypoints': waypoints,
        'mode': 'driving',
        'language': 'uz',
      });
      json = Map<String, dynamic>.from(result.data as Map);
    } else {
      final params = <String, String>{
        'origin': origin,
        'destination': destination,
        'mode': 'driving',
        'language': 'uz',
        'key': AppConfig.mapsApiKey,
        if (waypoints.isNotEmpty) 'waypoints': waypoints,
      };
      final uri = Uri.https(
          'maps.googleapis.com', '/maps/api/directions/json', params);
      final response = await _client.get(uri).timeout(
            _httpTimeout,
            onTimeout: () => throw Exception(
              'Маршрут серверига уланиб бўлмади — интернетни текширинг',
            ),
          );
      if (response.statusCode != 200) {
        throw Exception('Directions API HTTP ${response.statusCode}');
      }
      json = jsonDecode(response.body) as Map<String, dynamic>;
    }

    final status = json['status'] as String? ?? 'UNKNOWN';
    if (status != 'OK') {
      final message = json['error_message'] as String? ?? status;
      throw Exception('Directions API: $message');
    }
    return json;
  }

  DirectionsResult _parseDirectionsJson(
    Map<String, dynamic> json, {
    bool expectWaypointOrder = false,
  }) {
    final routes = json['routes'] as List? ?? const [];
    if (routes.isEmpty) throw Exception('Directions API: route topilmadi');

    final route = Map<String, dynamic>.from(routes.first as Map);
    final legs = route['legs'] as List? ?? const [];
    var distanceMeters = 0;
    var durationSeconds = 0;
    for (final rawLeg in legs) {
      final leg = Map<String, dynamic>.from(rawLeg as Map);
      final distance =
          Map<String, dynamic>.from((leg['distance'] as Map?) ?? const {});
      final duration =
          Map<String, dynamic>.from((leg['duration'] as Map?) ?? const {});
      distanceMeters += (distance['value'] as num?)?.toInt() ?? 0;
      durationSeconds += (duration['value'] as num?)?.toInt() ?? 0;
    }

    final overview = Map<String, dynamic>.from(
        (route['overview_polyline'] as Map?) ?? const {});
    final polyline = overview['points'] as String? ?? '';

    List<int> waypointOrder = const [];
    if (expectWaypointOrder) {
      final raw = route['waypoint_order'] as List? ?? const [];
      waypointOrder = raw.map((e) => (e as num).toInt()).toList();
    }

    return DirectionsResult(
      distanceKm: distanceMeters / 1000,
      durationMin: (durationSeconds / 60).ceil(),
      polyline: polyline,
      waypointOrder: waypointOrder,
    );
  }
}
