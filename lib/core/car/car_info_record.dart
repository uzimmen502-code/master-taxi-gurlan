import '../../repositories/user_repository.dart';

/// Foydalanuvchi asosiy profilidagi avtomobil ma'lumotlari.
class CarInfoRecord {
  const CarInfoRecord({
    required this.model,
    required this.color,
    required this.plate,
    required this.seats,
  });

  final String model;
  final String color;
  final String plate;
  final int seats;

  bool get isComplete =>
      model.trim().isNotEmpty &&
      color.trim().isNotEmpty &&
      plate.trim().isNotEmpty &&
      seats > 0;

  String get displayCar =>
      '$model${color.isEmpty ? '' : ' · $color'}';

  static CarInfoRecord? fromMap(Map<String, String>? map) {
    if (map == null) return null;
    final seatsRaw = map['carSeats'] ?? '';
    final seats = int.tryParse(seatsRaw) ?? 0;
    return CarInfoRecord(
      model: map['carModel'] ?? '',
      color: map['carColor'] ?? '',
      plate: map['carPlate'] ?? '',
      seats: seats,
    );
  }

  static Future<CarInfoRecord?> load(String uid) async {
    if (uid.isEmpty) return null;
    final map = await UserRepository().getCarInfo(uid);
    final record = fromMap(map);
    if (record == null || !record.isComplete) return null;
    return record;
  }
}
