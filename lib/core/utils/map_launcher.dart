import 'package:url_launcher/url_launcher.dart';

import '../../models/intercity_pickup_route.dart';

/// Google Maps орқали манзилга йўл кўрсатish.
Future<bool> openMapsNavigation({
  required double lat,
  required double lng,
  String? label,
}) async {
  final q = label != null && label.isNotEmpty
      ? Uri.encodeComponent(label)
      : '$lat,$lng';
  final google = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
  final yandex = Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng');
  if (await canLaunchUrl(google)) {
    return launchUrl(google, mode: LaunchMode.externalApplication);
  }
  if (await canLaunchUrl(yandex)) {
    return launchUrl(yandex, mode: LaunchMode.externalApplication);
  }
  final geo = Uri.parse('geo:$lat,$lng?q=$q');
  if (await canLaunchUrl(geo)) {
    return launchUrl(geo, mode: LaunchMode.externalApplication);
  }
  return false;
}

/// Optimallashtirilgan olib ketish zanjirini Google Maps da ochish.
Future<bool> openMapsPickupRoute(IntercityPickupRoute route) async {
  final origin = '${route.originLat},${route.originLng}';
  final destination = '${route.destinationLat},${route.destinationLng}';
  final waypoints = route.stops.map((s) => '${s.lat},${s.lng}').join('|');

  final params = <String, String>{
    'api': '1',
    'origin': origin,
    'destination': destination,
    'travelmode': 'driving',
    if (waypoints.isNotEmpty) 'waypoints': waypoints,
  };

  final uri = Uri.https('www.google.com', '/maps/dir/', params);
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}
