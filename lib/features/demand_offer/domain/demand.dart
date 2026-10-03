// ТАЛАБ → ТАКЛИФ ядроси — `demands` ҳужжатининг иловадаги модели.
//
// ТАШҚИ боғламлар йўқ: `Map<String, dynamic>`дан ўқийди, Firestore
// типларини БИЛМАЙДИ. Шунинг учун `flutter test`да плагинсиз ишлайди ва
// сервер фикстуралари билан паритет тести ёзилади (Т-16 — codegen
// ўрнига).
//
// Вақт майдонлари: Firestore `Timestamp` объекти келади, лекин бу модел
// уни `DateTime`га айлантириш учун `toDate()` методини динамик чақиради
// (`_parseDate`). Шунда модел `cloud_firestore`га боғланмайди.

import 'demand_enums.dart';

/// Нуқта — манзил, ҳудуд ва geohash билан.
///
/// ДИҚҚАТ: `regionId`/`districtId`/`geohash` СЕРВЕРДА ҳисобланади.
/// Илова уларни ЮБОРМАЙДИ (схема рад этади), фақат ўқийди.
class DemandPoint {
  const DemandPoint({
    this.lat,
    this.lng,
    this.geohash = '',
    this.regionId = '',
    this.districtId = '',
    this.addressText = '',
  });

  final double? lat;
  final double? lng;
  final String geohash;
  final String regionId;
  final String districtId;
  final String addressText;

  bool get hasCoords => lat != null && lng != null;

  static DemandPoint? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return DemandPoint(
      lat: _toDouble(m['lat']),
      lng: _toDouble(m['lng']),
      geohash: (m['geohash'] ?? '').toString(),
      regionId: (m['regionId'] ?? '').toString(),
      districtId: (m['districtId'] ?? '').toString(),
      addressText: (m['addressText'] ?? '').toString(),
    );
  }

  /// `createDemand` юкламаси учун — ФАҚАТ координата ва манзил матни.
  ///
  /// `geohash`, `regionId`, `districtId` АТАЙЛАБ юборилмайди: сервер
  /// уларни фойдаланувчи профилидан ва координатадан ўзи қўяди. Акс
  /// ҳолда фойдаланувчи ўз талабини истаган ҳудудга «жойлаштириб»
  /// қўя оларди.
  Map<String, dynamic> toInput() => <String, dynamic>{
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (addressText.isNotEmpty) 'addressText': addressText,
      };
}

/// Вақт ойнаси.
class DemandTimeWindow {
  const DemandTimeWindow({this.neededBy, this.expiresAt});

  final DateTime? neededBy;
  final DateTime? expiresAt;

  /// Муддати ўтганми.
  ///
  /// Илова рўйхатларда сервер sweeper'ига қўшимча равишда ШУ
  /// текширувни ҳам ишлатади (Т-5): sweeper кечикса ҳам эскирган талаб
  /// кўринмайди.
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && expiresAt!.isBefore(now);

  static DemandTimeWindow fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DemandTimeWindow();
    return DemandTimeWindow(
      neededBy: _parseDate(m['neededBy']),
      expiresAt: _parseDate(m['expiresAt']),
    );
  }
}

/// Бюджет. Концепцияда `null` эди, тузатишдан кейин тузилма.
class DemandBudget {
  const DemandBudget({
    this.min,
    this.max,
    this.currency = 'UZS',
    this.priceType,
  });

  final num? min;
  final num? max;
  final String currency;
  final String? priceType;

  bool get isEmpty => min == null && max == null;

  static DemandBudget? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return DemandBudget(
      min: m['min'] as num?,
      max: m['max'] as num?,
      currency: (m['currency'] ?? 'UZS').toString(),
      priceType: m['priceType']?.toString(),
    );
  }

  Map<String, dynamic> toInput() => <String, dynamic>{
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        'currency': currency,
        if (priceType != null) 'priceType': priceType,
      };
}

/// Тайинланган ижрочи.
class DemandAssignment {
  const DemandAssignment({this.providerId, this.offerId, this.acceptedAt});

  final String? providerId;
  final String? offerId;
  final DateTime? acceptedAt;

  bool get isAssigned => providerId != null && providerId!.isNotEmpty;

  static DemandAssignment fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DemandAssignment();
    return DemandAssignment(
      providerId: _emptyToNull(m['providerId']),
      offerId: _emptyToNull(m['offerId']),
      acceptedAt: _parseDate(m['acceptedAt']),
    );
  }
}

/// Matching ҳолати — статусдан алоҳида.
class DemandMatchingInfo {
  const DemandMatchingInfo({
    this.state = DemandMatchingState.pending,
    this.matchedBucket = MatchedBucket.none,
    this.wave = 0,
  });

  final DemandMatchingState state;

  /// Т-8: аниқ рақам эмас, панжара.
  final MatchedBucket matchedBucket;

  final int wave;

  static DemandMatchingInfo fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DemandMatchingInfo();
    return DemandMatchingInfo(
      state: DemandMatchingState.tryParse(m['state']?.toString())
          ?? DemandMatchingState.pending,
      matchedBucket: MatchedBucket.parse(m['matchedBucket']?.toString()),
      wave: _toInt(m['wave']) ?? 0,
    );
  }
}

/// Талаб — ХАРИДОР кўрадиган тўлиқ нусха.
///
/// Таклифчи буни ҲЕЧ ҚАЧОН ўқимайди (Firestore қоидаси рад этади) —
/// у `demand_matches` проекциясини ўқийди ([DemandMatch]).
class Demand {
  const Demand({
    required this.id,
    required this.ownerId,
    required this.module,
    required this.mode,
    required this.status,
    this.schemaVersion = 1,
    this.categoryId,
    this.categoryGroup,
    this.matching = const DemandMatchingInfo(),
    this.source = 'module',
    this.title = '',
    this.description = '',
    this.location,
    this.destination,
    this.timeWindow = const DemandTimeWindow(),
    this.budget,
    this.quantity,
    this.wholesale = false,
    this.images = const [],
    this.recipientName = '',
    this.recipientPhone,
    this.attributes = const {},
    this.assignment = const DemandAssignment(),
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerId;
  final DemandModule module;
  final DemandMode mode;
  final DemandStatus status;
  final int schemaVersion;
  final String? categoryId;
  final String? categoryGroup;
  final DemandMatchingInfo matching;
  final String source;
  final String title;
  final String description;
  final DemandPoint? location;
  final DemandPoint? destination;
  final DemandTimeWindow timeWindow;
  final DemandBudget? budget;
  final int? quantity;
  final bool wholesale;
  final List<String> images;
  final String recipientName;
  final String? recipientPhone;

  /// Модулга хос майдонлар. Сервердаги JSON Schema билан текширилган.
  final Map<String, dynamic> attributes;

  final DemandAssignment assignment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Рўйхатда кўрсатиладими.
  ///
  /// Сервер статусига ИШОНМАЙМИЗ холос: муддат ҳам текширилади (Т-5).
  bool isVisibleAt(DateTime now) {
    if (status == DemandStatus.draft) return false;
    if (status == DemandStatus.active && timeWindow.isExpiredAt(now)) {
      return false;
    }
    return true;
  }

  factory Demand.fromMap(String id, Map<String, dynamic> m) {
    return Demand(
      id: id,
      ownerId: (m['ownerId'] ?? '').toString(),
      module: DemandModule.tryParse(m['module']?.toString())
          ?? DemandModule.service,
      mode: DemandMode.tryParse(m['mode']?.toString()) ?? DemandMode.quote,
      status: DemandStatus.tryParse(m['status']?.toString())
          ?? DemandStatus.draft,
      schemaVersion: _toInt(m['schemaVersion']) ?? 1,
      categoryId: _emptyToNull(m['categoryId']),
      categoryGroup: _emptyToNull(m['categoryGroup']),
      matching: DemandMatchingInfo.fromMap(_asMap(m['matching'])),
      source: (m['source'] ?? 'module').toString(),
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      location: DemandPoint.fromMap(_asMap(m['location'])),
      destination: DemandPoint.fromMap(_asMap(m['destination'])),
      timeWindow: DemandTimeWindow.fromMap(_asMap(m['timeWindow'])),
      budget: DemandBudget.fromMap(_asMap(m['budget'])),
      quantity: _toInt(m['quantity']),
      wholesale: m['wholesale'] == true,
      images: _stringList(_asMap(m['media'])?['images']),
      recipientName: (_asMap(m['contact'])?['recipientName'] ?? '').toString(),
      recipientPhone: _emptyToNull(_asMap(m['contact'])?['recipientPhone']),
      attributes: _asMap(m['attributes']) ?? const {},
      assignment: DemandAssignment.fromMap(_asMap(m['assignment'])),
      createdAt: _parseDate(m['createdAt']),
      updatedAt: _parseDate(m['updatedAt']),
    );
  }
}

// ── Ёрдамчилар ────────────────────────────────────────────────────────

Map<String, dynamic>? _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, value) => MapEntry(k.toString(), value));
  return null;
}

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _emptyToNull(Object? v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? null : s;
}

List<String> _stringList(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

/// Firestore `Timestamp`, ISO сатр ёки миллисекунддан `DateTime`.
///
/// `cloud_firestore`га боғланмаслик учун `toDate()` динамик чақирилади:
/// шунда модел тестда плагинсиз ишлайди.
DateTime? _parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  try {
    final d = (v as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {
    // Timestamp эмас — эътиборсиз қолдирилади.
  }
  return null;
}

/// Моделлардан ташқарида ҳам керак (`offer.dart`, `demand_match.dart`).
DateTime? parseDemandDate(Object? v) => _parseDate(v);
Map<String, dynamic>? asDemandMap(Object? v) => _asMap(v);
int? toDemandInt(Object? v) => _toInt(v);
double? toDemandDouble(Object? v) => _toDouble(v);
List<String> demandStringList(Object? v) => _stringList(v);
String? demandEmptyToNull(Object? v) => _emptyToNull(v);
