import '../../../models/ev_charging_station.dart';

/// Bitta marker yoki bir nechta stansiyani birlashtiruvchi klaster
/// ("EvClusterCalculator.build" natijasi — 5-band).
class EvCluster {
  const EvCluster({
    required this.lat,
    required this.lng,
    required this.stations,
  });

  final double lat;
  final double lng;
  final List<EvChargingStation> stations;

  bool get isSingle => stations.length == 1;
  int get count => stations.length;

  String get id => stations.length == 1
      ? stations.first.id
      : 'cluster_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}_$count';
}
