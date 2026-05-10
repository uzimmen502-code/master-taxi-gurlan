class SavedPlace {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String icon;
  final bool isDefault; // Уй ёки Иш - ўчириб бўлмайди

  SavedPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.icon,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'icon': icon,
      'isDefault': isDefault,
    };
  }

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      lat: json['lat'] ?? 0.0,
      lng: json['lng'] ?? 0.0,
      icon: json['icon'] ?? '📍',
      isDefault: json['isDefault'] ?? false,
    );
  }
}