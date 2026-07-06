/// Yo'lovchi marshrut qidiruvi / qayta dispatch konteksti.
class MarshrutPassengerRouteContext {
  const MarshrutPassengerRouteContext({
    required this.pickupMfy,
    required this.pickupAddr,
    required this.dropoffMfy,
    this.userLat,
    this.userLng,
  });

  final String pickupMfy;
  final String pickupAddr;
  final String dropoffMfy;
  final double? userLat;
  final double? userLng;
}
