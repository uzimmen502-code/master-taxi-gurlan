/// Haydovchi mashina ma'lumotlari — ariza / drivers / prefs prefill.
class DriverCarPrefill {
  const DriverCarPrefill({
    required this.carModel,
    required this.plate,
    required this.seats,
  });

  final String carModel;
  final String plate;
  final int seats;

  bool get isComplete =>
      carModel.trim().isNotEmpty &&
      plate.trim().isNotEmpty &&
      seats > 0;

  /// `"Nexia · Oq"` → `"Nexia"`.
  static String parseModelFromDisplay(String car) {
    final s = car.trim();
    if (s.isEmpty) return '';
    const separators = [' · ', ' ·', '· ', '·'];
    for (final sep in separators) {
      final idx = s.indexOf(sep);
      if (idx > 0) return s.substring(0, idx).trim();
    }
    return s;
  }

  static int maxSeatsForModel(String model) {
    final m = model.toLowerCase();
    if (m.contains('damas') || m.contains('дамас')) return 6;
    return 4;
  }

  factory DriverCarPrefill.fromParts({
    required String carModel,
    required String plate,
    int? seats,
  }) {
    final model = carModel.trim();
    return DriverCarPrefill(
      carModel: model,
      plate: plate.trim().toUpperCase(),
      seats: seats ?? maxSeatsForModel(model),
    );
  }
}
