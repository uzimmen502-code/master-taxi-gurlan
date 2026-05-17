/// Ҳайдовчининг локал сессияси — SharedPreferences'дан ўқилади.
///
/// Бу модел ҳайдовчи бош экранда сақланадиган маълумотларни ифодалайди.
/// Firestore document эмас — иммобилизация: builderи controller'да.
class DriverSession {
  const DriverSession({
    this.name = 'Ҳайдовчи',
    this.gender = 'male',
    this.phone = '',
    this.carModel = '',
    this.carPlate = '',
    this.taxiType = 'alone',
    this.driverId = '',
    this.todayTrips = 0,
    this.todayEarnings = 0,
    this.totalTrips = 0,
  });

  final String name;
  final String gender;
  final String phone;
  final String carModel;
  final String carPlate;

  /// `alone` | `marshrut` | `intercity` | `both`.
  final String taxiType;

  /// Phone'дан фақат рақамлар.
  final String driverId;

  final int todayTrips;
  final int todayEarnings;
  final int totalTrips;

  String get honorificName =>
      gender == 'female' ? '$name хоним' : 'жаноб $name';

  /// "Хайрли тонг" / "Хайрли кун" / "Хайрли оқшом" / "Яхши кеч".
  String get greeting {
    final h = DateTime.now().hour;
    if (h < 6) return 'Яхши тун';
    if (h < 12) return 'Хайрли тонг';
    if (h < 17) return 'Хайрли кун';
    if (h < 21) return 'Хайрли оқшом';
    return 'Яхши кеч';
  }

  DriverSession copyWith({
    String? name,
    String? gender,
    String? phone,
    String? carModel,
    String? carPlate,
    String? taxiType,
    String? driverId,
    int? todayTrips,
    int? todayEarnings,
    int? totalTrips,
  }) {
    return DriverSession(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      phone: phone ?? this.phone,
      carModel: carModel ?? this.carModel,
      carPlate: carPlate ?? this.carPlate,
      taxiType: taxiType ?? this.taxiType,
      driverId: driverId ?? this.driverId,
      todayTrips: todayTrips ?? this.todayTrips,
      todayEarnings: todayEarnings ?? this.todayEarnings,
      totalTrips: totalTrips ?? this.totalTrips,
    );
  }
}
