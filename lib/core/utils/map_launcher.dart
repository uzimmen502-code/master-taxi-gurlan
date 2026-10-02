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

/// ⚡ EV сафар занжири — йўл бўйидаги зарядлаш тўхташлари билан битта
/// навигация чақируви.
///
/// Нега битта чақирув: Яндекс Навигаторда имзосиз ўтишлар бир қурилмада
/// 24 соатда 5 та билан чекланган (қаранг: `docs/vazifalar.md` В-12).
/// Бутун занжирни оралиқ нуқталар билан юбориш — 1 ўтиш, ҳар станцияга
/// алоҳида чақириш эса N ўтиш бўлар эди.
///
/// Тартиб [openMapsNavigation] билан бир хил: аввал Google (калит ҳам,
/// имзо ҳам талаб қилмайди), кейин Яндекс, охирида `geo:`.
Future<bool> openMapsEvTripRoute({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
  List<({double lat, double lng})> stops = const [],
}) async {
  // Google `api=1` схемаси кўпи билан 9 оралиқ нуқтани қабул қилади;
  // Яндексда чеклов ҳужжатда кўрсатилмаган, лекин бир хил рўйхат
  // юборилиши учун шу ерда қисқартирилади.
  const maxWaypoints = 9;
  final limited =
      stops.length > maxWaypoints ? stops.sublist(0, maxWaypoints) : stops;

  final googleParams = <String, String>{
    'api': '1',
    'origin': '$originLat,$originLng',
    'destination': '$destinationLat,$destinationLng',
    'travelmode': 'driving',
    if (limited.isNotEmpty)
      'waypoints': limited.map((s) => '${s.lat},${s.lng}').join('|'),
  };
  final google = Uri.https('www.google.com', '/maps/dir/', googleParams);
  if (await canLaunchUrl(google)) {
    return launchUrl(google, mode: LaunchMode.externalApplication);
  }

  final yandexParams = <String>[
    'lat_from=$originLat',
    'lon_from=$originLng',
    for (var i = 0; i < limited.length; i++)
      'lat_via_$i=${limited[i].lat}&lon_via_$i=${limited[i].lng}',
    'lat_to=$destinationLat',
    'lon_to=$destinationLng',
  ];
  final yandex =
      Uri.parse('yandexnavi://build_route_on_map?${yandexParams.join('&')}');
  if (await canLaunchUrl(yandex)) {
    return launchUrl(yandex, mode: LaunchMode.externalApplication);
  }

  // Охирги чора — фақат манзил (оралиқ нуқталарсиз).
  final geo = Uri.parse('geo:$destinationLat,$destinationLng');
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
