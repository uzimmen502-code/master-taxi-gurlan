/// Foydalanuvchi сақлаб қўйган манзил (уй, иш, дўкон...). Локал
/// `SharedPreferences`-да сақланади (`saved_places` калити).
class SavedPlace {
  const SavedPlace({
    required this.name,
    required this.address,
    this.lat,
    this.lng,
  });

  final String name;
  final String address;
  final double? lat;
  final double? lng;

  bool get hasCoordinates =>
      lat != null &&
      lng != null &&
      (lat!.abs() > 1e-6 || lng!.abs() > 1e-6);

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        name: (json['name'] ?? '') as String,
        address: (json['address'] ?? '') as String,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };
}
