import 'package:cloud_firestore/cloud_firestore.dart';

/// Moy almashtirish holati (rang + matn bilan).
enum OilDueLevel { ok, soon, overdue }

class OilDueStatus {
  const OilDueStatus({
    required this.level,
    this.kmLeft,
    this.daysLeft,
    this.nextDate,
    this.nextOdometerKm,
  });

  final OilDueLevel level;
  final int? kmLeft;
  final int? daysLeft;
  final DateTime? nextDate;
  final int? nextOdometerKm;

  String get levelLabelUz => switch (level) {
        OilDueLevel.ok => 'Яхши',
        OilDueLevel.soon => 'Яқинлашди',
        OilDueLevel.overdue => 'Муддат ўтди',
      };
}

/// Foydalanuvchi mashinasi + moy kuzatuvi.
/// Manba: profil avtomobili yoki `users/{uid}/vehicles`.
class OilVehicle {
  const OilVehicle({
    required this.id,
    required this.model,
    required this.color,
    required this.plate,
    this.brand = '',
    this.year = 0,
    this.engine = '',
    this.fuelType = '',
    this.usageTags = const [],
    this.seats = 4,
    this.oilType = '',
    this.lastChangedAt,
    this.lastOdometerKm = 0,
    this.currentOdometerKm = 0,
    this.intervalKm = 5000,
    this.intervalMonths = 6,
    this.isPrimary = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String model;
  final String color;
  final String plate;
  /// Марка (Chevrolet, Kia, …) — confidence B.
  final String brand;
  final int year;
  /// Двигатель ҳажми (1.5, 1.2, …).
  final String engine;
  /// petrol | cng | lpg
  final String fuelType;
  /// personal | taxi | corp | dust | long
  final List<String> usageTags;
  final int seats;
  final String oilType;
  final DateTime? lastChangedAt;
  final int lastOdometerKm;
  final int currentOdometerKm;
  final int intervalKm;
  final int intervalMonths;
  final bool isPrimary;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasOilTracking =>
      oilType.trim().isNotEmpty &&
      lastChangedAt != null &&
      lastOdometerKm > 0;

  /// Тавсия учун созлаш тугаган (модел + ёқилғи).
  bool get isRecommendationReady =>
      model.trim().isNotEmpty && fuelType.trim().isNotEmpty;

  String get fuelLabelUz => switch (fuelType.trim().toLowerCase()) {
        'petrol' => 'Бензин',
        'cng' => 'Метан',
        'lpg' => 'Пропан',
        _ => fuelType.trim().isEmpty ? '' : fuelType.trim(),
      };

  static String usageLabelUz(String tag) => switch (tag) {
        'personal' => 'Шахсий',
        'taxi' => 'Такси',
        'corp' => 'Корпоратив',
        'dust' => 'Қишлоқ / чангли',
        'long' => 'Узоқ масофа',
        _ => tag,
      };

  String get usageSummaryUz =>
      usageTags.map(usageLabelUz).where((s) => s.isNotEmpty).join(' · ');

  /// HTML hub format: `Chevrolet Cobalt · 1.5 · 2021`
  String get setupTitle {
    final head = [
      if (brand.trim().isNotEmpty) brand.trim(),
      if (model.trim().isNotEmpty) model.trim(),
    ].join(' ');
    final parts = <String>[
      if (head.isNotEmpty) head,
      if (engine.trim().isNotEmpty) engine.trim(),
      if (year > 0) '$year',
    ];
    return parts.isEmpty ? displayTitle : parts.join(' · ');
  }

  String get displayTitle {
    final parts = <String>[
      if (brand.trim().isNotEmpty) brand.trim(),
      if (model.trim().isNotEmpty) model.trim(),
      if (color.trim().isNotEmpty) color.trim(),
    ];
    final head = parts.isEmpty ? 'Автомобил' : parts.join(' · ');
    if (plate.trim().isEmpty) return head;
    return '$head · ${plate.trim().toUpperCase()}';
  }

  int get effectiveOdometer {
    if (currentOdometerKm > 0) return currentOdometerKm;
    return lastOdometerKm;
  }

  OilDueStatus computeDueStatus({DateTime? now}) {
    final n = now ?? DateTime.now();
    if (!hasOilTracking) {
      return const OilDueStatus(level: OilDueLevel.soon);
    }

    final nextOdo = lastOdometerKm + intervalKm;
    final kmLeft = nextOdo - effectiveOdometer;

    DateTime? nextDate;
    int? daysLeft;
    if (lastChangedAt != null) {
      nextDate = DateTime(
        lastChangedAt!.year,
        lastChangedAt!.month + intervalMonths,
        lastChangedAt!.day,
      );
      daysLeft = nextDate.difference(n).inDays;
    }

    final overdue = kmLeft <= 0 || (daysLeft != null && daysLeft <= 0);
    final soon = !overdue &&
        (kmLeft <= 1000 || (daysLeft != null && daysLeft <= 30));

    final level = overdue
        ? OilDueLevel.overdue
        : soon
            ? OilDueLevel.soon
            : OilDueLevel.ok;

    return OilDueStatus(
      level: level,
      kmLeft: kmLeft,
      daysLeft: daysLeft,
      nextDate: nextDate,
      nextOdometerKm: nextOdo,
    );
  }

  Map<String, dynamic> toMap({bool forCreate = false}) {
    return {
      'model': model.trim(),
      'color': color.trim(),
      'plate': plate.trim().toUpperCase(),
      'brand': brand.trim(),
      'year': year,
      'engine': engine.trim(),
      'fuelType': fuelType.trim(),
      'usageTags': usageTags,
      'seats': seats,
      'oilType': oilType.trim(),
      'lastChangedAt': lastChangedAt == null
          ? null
          : Timestamp.fromDate(lastChangedAt!),
      'lastOdometerKm': lastOdometerKm,
      'currentOdometerKm': currentOdometerKm > 0
          ? currentOdometerKm
          : lastOdometerKm,
      'intervalKm': intervalKm,
      'intervalMonths': intervalMonths,
      'isPrimary': isPrimary,
      'updatedAt': FieldValue.serverTimestamp(),
      if (forCreate) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static OilVehicle fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final rawTags = d['usageTags'];
    final tags = rawTags is List
        ? rawTags.map((e) => '$e').where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return OilVehicle(
      id: doc.id,
      model: (d['model'] as String?) ?? '',
      color: (d['color'] as String?) ?? '',
      plate: (d['plate'] as String?) ?? '',
      brand: (d['brand'] as String?) ?? '',
      year: (d['year'] as num?)?.toInt() ?? 0,
      engine: (d['engine'] as String?) ?? '',
      fuelType: (d['fuelType'] as String?) ?? '',
      usageTags: tags,
      seats: (d['seats'] as num?)?.toInt() ?? 4,
      oilType: (d['oilType'] as String?) ?? '',
      lastChangedAt: (d['lastChangedAt'] as Timestamp?)?.toDate(),
      lastOdometerKm: (d['lastOdometerKm'] as num?)?.toInt() ?? 0,
      currentOdometerKm: (d['currentOdometerKm'] as num?)?.toInt() ?? 0,
      intervalKm: (d['intervalKm'] as num?)?.toInt() ?? 5000,
      intervalMonths: (d['intervalMonths'] as num?)?.toInt() ?? 6,
      isPrimary: d['isPrimary'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  OilVehicle copyWith({
    String? id,
    String? model,
    String? color,
    String? plate,
    String? brand,
    int? year,
    String? engine,
    String? fuelType,
    List<String>? usageTags,
    int? seats,
    String? oilType,
    DateTime? lastChangedAt,
    int? lastOdometerKm,
    int? currentOdometerKm,
    int? intervalKm,
    int? intervalMonths,
    bool? isPrimary,
  }) {
    return OilVehicle(
      id: id ?? this.id,
      model: model ?? this.model,
      color: color ?? this.color,
      plate: plate ?? this.plate,
      brand: brand ?? this.brand,
      year: year ?? this.year,
      engine: engine ?? this.engine,
      fuelType: fuelType ?? this.fuelType,
      usageTags: usageTags ?? this.usageTags,
      seats: seats ?? this.seats,
      oilType: oilType ?? this.oilType,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
      lastOdometerKm: lastOdometerKm ?? this.lastOdometerKm,
      currentOdometerKm: currentOdometerKm ?? this.currentOdometerKm,
      intervalKm: intervalKm ?? this.intervalKm,
      intervalMonths: intervalMonths ?? this.intervalMonths,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class OilHistoryEntry {
  const OilHistoryEntry({
    required this.id,
    required this.changedAt,
    required this.odometerKm,
    required this.oilType,
    this.serviceName = '',
    this.note = '',
    this.createdAt,
  });

  final String id;
  final DateTime changedAt;
  final int odometerKm;
  final String oilType;
  final String serviceName;
  final String note;
  final DateTime? createdAt;

  static OilHistoryEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return OilHistoryEntry(
      id: doc.id,
      changedAt: (d['changedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      odometerKm: (d['odometerKm'] as num?)?.toInt() ?? 0,
      oilType: (d['oilType'] as String?) ?? '',
      serviceName: (d['serviceName'] as String?) ?? '',
      note: (d['note'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class OilServicePoint {
  const OilServicePoint({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    this.lat,
    this.lng,
    this.active = true,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final double? lat;
  final double? lng;
  final bool active;

  static OilServicePoint fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return OilServicePoint(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      address: (d['address'] as String?) ?? '',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      active: d['active'] != false,
    );
  }
}

class OilPricePackage {
  const OilPricePackage({
    required this.id,
    required this.name,
    required this.description,
    required this.priceFrom,
  });

  final String id;
  final String name;
  final String description;
  final int priceFrom;

  static const defaults = <OilPricePackage>[
    OilPricePackage(
      id: 'standard',
      name: 'Стандарт',
      description: 'Мой + фильтр',
      priceFrom: 180000,
    ),
    OilPricePackage(
      id: 'full',
      name: 'Тўлиқ',
      description: 'Мой + фильтр + ҳаво фильтри',
      priceFrom: 250000,
    ),
    OilPricePackage(
      id: 'filter_only',
      name: 'Фақат фильтр',
      description: 'Мой фильтрини алмаштириш',
      priceFrom: 50000,
    ),
  ];
}

class OilBooking {
  const OilBooking({
    required this.id,
    required this.uid,
    required this.vehicleId,
    required this.packageId,
    required this.servicePointId,
    required this.slotAt,
    required this.status,
    this.vehicleLabel = '',
    this.packageName = '',
    this.serviceName = '',
    this.priceFrom = 0,
    this.phone = '',
    this.name = '',
    this.createdAt,
  });

  final String id;
  final String uid;
  final String vehicleId;
  final String packageId;
  final String servicePointId;
  final DateTime slotAt;
  final String status;
  final String vehicleLabel;
  final String packageName;
  final String serviceName;
  final int priceFrom;
  final String phone;
  final String name;
  final DateTime? createdAt;

  static OilBooking fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return OilBooking(
      id: doc.id,
      uid: (d['uid'] as String?) ?? '',
      vehicleId: (d['vehicleId'] as String?) ?? '',
      packageId: (d['packageId'] as String?) ?? '',
      servicePointId: (d['servicePointId'] as String?) ?? '',
      slotAt: (d['slotAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: (d['status'] as String?) ?? 'new',
      vehicleLabel: (d['vehicleLabel'] as String?) ?? '',
      packageName: (d['packageName'] as String?) ?? '',
      serviceName: (d['serviceName'] as String?) ?? '',
      priceFrom: (d['priceFrom'] as num?)?.toInt() ?? 0,
      phone: (d['phone'] as String?) ?? '',
      name: (d['name'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
