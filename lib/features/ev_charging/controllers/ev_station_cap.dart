import '../../../models/ev_charging_station.dart';

/// Харитада бир вақтда кўринадиган станциялар чегараси (эга, 2026-10-23: кластер ўрнига «≤400 нуқта,
/// марказга яқинлари» — бизнес харитаси билан бир хил қоида).
const int kEvMapMaxMarkers = 400;

/// [stations] дан камера маркази ([lat], [lng]) га энг яқин [cap] тасини қайтаради (камидан ошмаса — ўзгаришсиз).
/// Тартиб барқарор: масофа тенг бўлса — рўйхатдаги тартиб сақланади.
List<EvChargingStation> capNearestStations(
  List<EvChargingStation> stations,
  double lat,
  double lng, {
  int cap = kEvMapMaxMarkers,
}) {
  if (stations.length <= cap) return stations;
  double d2(EvChargingStation s) =>
      (s.latitude - lat) * (s.latitude - lat) + (s.longitude - lng) * (s.longitude - lng);
  final indexed = [for (var i = 0; i < stations.length; i++) (i, stations[i], d2(stations[i]))];
  indexed.sort((a, b) {
    final c = a.$3.compareTo(b.$3);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed.take(cap)) e.$2];
}
