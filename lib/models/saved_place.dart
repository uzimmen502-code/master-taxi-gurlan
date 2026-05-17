/// Foydalanuvchi сақлаб қўйган манзил (уй, иш, дўкон...). Локал
/// `SharedPreferences`-да сақланади (`saved_places` калити).
class SavedPlace {
  const SavedPlace({required this.name, required this.address});

  final String name;
  final String address;

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        name: (json['name'] ?? '') as String,
        address: (json['address'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
      };
}
