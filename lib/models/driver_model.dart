class DriverModel {
  final String id;
  final String name;
  final String phone;
  final String carModel;
  final String carNumber;
  final double rating;
  final bool isAvailable;
  final double latitude;
  final double longitude;

  DriverModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.carModel,
    required this.carNumber,
    required this.rating,
    required this.isAvailable,
    required this.latitude,
    required this.longitude,
  });
}