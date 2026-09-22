import 'package:cloud_firestore/cloud_firestore.dart';

/// ⚡ Электромобил зарядлаш нуқтаси — жамоа (foydalanuvchilar) tomonidan
/// to'ldiriladigan `ev_charging_stations` hujjati.
///
/// `name`, `workingHours`, `photo` — MVP modelga qo'shilmaydi (texnik
/// topshiriq 10-band). Koordinata majburiy, qolgan hamma maydon ixtiyoriy.
///
/// 2026-09-22: очиқ манба (OSM/TOK BOR/Yashil Energiya/Open Charge Map)
/// импорти учун `source*`/`review*`/`name`/`website`/... майдонлари
/// қўшилди (`functions/tools/import_ev_open_data.js`). Булар фақат
/// импортер/admin томонидан ёзилади — `firestore.rules`'даги
/// `evStationCommunityPatch()` whitelist'ига кирмайди, шунинг учун
/// жамоа таҳрири уларни ўзгартира олмайди.
class EvChargingStation {
  const EvChargingStation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.chargingTypes,
    required this.connectors,
    required this.status,
    required this.verificationStatus,
    required this.confirmationCount,
    required this.reportCount,
    required this.createdBy,
    required this.isActive,
    this.powerKw,
    this.price,
    this.operatorName,
    this.note,
    this.createdAt,
    this.updatedAt,
    this.lastConfirmedAt,
    this.name,
    this.region,
    this.operatorRef,
    this.accessType,
    this.website,
    this.phone,
    this.address,
    this.workingHours,
    this.sitePowerKw,
    this.powerRatingsKw = const [],
    this.sourceReportedStatus,
    this.sourceType,
    this.sourceProvider,
    this.sourceUrls = const [],
    this.reviewRequired = false,
    this.reviewFlags = const [],
    this.possibleDuplicateIds = const [],
  });

  final String id;
  final double latitude;
  final double longitude;
  final String geohash;

  /// `AC` / `DC` / `AC+DC` — bo'sh bo'lishi mumkin.
  final List<String> chargingTypes;

  /// `CCS2`, `Type 2`, `GB/T`, `CHAdeMO`, boshqa — bir nechta tanlash mumkin.
  final List<String> connectors;

  final num? powerKw;
  final num? price;
  final String? operatorName;
  final String? note;

  /// `working` | `partially_working` | `not_working` | `unknown`.
  final String status;

  /// `community` | `imported` | `verified` | `operator_verified`.
  final String verificationStatus;

  final int confirmationCount;
  final int reportCount;

  /// `users/{phoneDigits}` hujjat ID'i — Firebase UID emas (24-bandga qarang).
  /// Импорт ёзувларида `import:opendata` sentinel.
  final String createdBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastConfirmedAt;

  final bool isActive;

  // ---- Очиқ манба импорти (ихтиёрий, community-created nuqtalarda bo'sh) ----

  final String? name;
  final String? region;
  final String? operatorRef;

  /// Манбадаги хом қиймат: `yes`/`permissive`/`permit`/`private`/`unknown`.
  final String? accessType;
  final String? website;
  final String? phone;
  final String? address;
  final String? workingHours;

  /// Станция/майдоннинг УМУМИЙ қуввати — БИР разъём қуввати эмас
  /// (`powerKw`дан алоҳида, аралаштирилмайди).
  final num? sitePowerKw;

  /// Манбада бир нечта қиймат кўрсатилган бўлса (масалан "40+80 kW") —
  /// қайси разъёмга тегишли аниқ эмас, шунинг учун `powerKw`га эмас, шу
  /// рўйхатга тушади.
  final List<num> powerRatingsKw;

  /// Манбадаги ҳолат хабари (масалан "running") — РЕАЛ ВАҚТ ҳолати ЭМАС,
  /// фақат манба нима деганини кўрсатади (UI'да огоҳлантириш билан).
  final String? sourceReportedStatus;

  /// `import` — очиқ манбадан импорт қилинган; `null`/бошқа — жамоа (илова
  /// ичида) қўшган нуқта.
  final String? sourceType;
  final String? sourceProvider;
  final List<String> sourceUrls;

  /// Жойида ҳали текширилмаган ва хусусий/ишга тушмаган/тест режимидаги
  /// белги бор ёзувлар — булар `isActive=false` билан импорт қилинади
  /// (оддий очиқ станция сифатида кўрсатилмайди), admin қўлда текшириб
  /// "Xaritaga qaytarish" қилгандан кейин фаоллашади.
  final bool reviewRequired;
  final List<String> reviewFlags;

  /// Бошқа станцияларнинг (шу коллекциядаги) ID'лари — яқин атрофда
  /// такрор бўлиши мумкин, автоматик бирлаштирилмаган.
  final List<String> possibleDuplicateIds;

  bool get hasChargingType => chargingTypes.isNotEmpty;
  bool get hasConnectors => connectors.isNotEmpty;
  bool get hasPowerKw => powerKw != null;
  bool get hasPrice => price != null;
  bool get hasOperatorName => (operatorName ?? '').trim().isNotEmpty;
  bool get hasNote => (note ?? '').trim().isNotEmpty;

  bool get isImported => sourceType == 'import';
  bool get hasName => (name ?? '').trim().isNotEmpty;
  bool get hasWebsite => (website ?? '').trim().isNotEmpty;
  bool get hasPhone => (phone ?? '').trim().isNotEmpty;
  bool get hasAddress => (address ?? '').trim().isNotEmpty;
  bool get hasWorkingHours => (workingHours ?? '').trim().isNotEmpty;
  bool get hasSitePowerKw => sitePowerKw != null;
  bool get hasPowerRatingsKw => powerRatingsKw.isNotEmpty;
  bool get hasSourceReportedStatus => (sourceReportedStatus ?? '').trim().isNotEmpty;

  factory EvChargingStation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final location = (d['location'] as Map?) ?? const {};
    return EvChargingStation(
      id: doc.id,
      latitude: (location['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (location['longitude'] as num?)?.toDouble() ?? 0,
      geohash: (d['geohash'] ?? '') as String,
      chargingTypes: List<String>.from(d['chargingTypes'] as List? ?? const []),
      connectors: List<String>.from(d['connectors'] as List? ?? const []),
      powerKw: d['powerKw'] as num?,
      price: d['price'] as num?,
      operatorName: d['operatorName'] as String?,
      note: d['note'] as String?,
      status: (d['status'] ?? 'unknown') as String,
      verificationStatus: (d['verificationStatus'] ?? 'community') as String,
      confirmationCount: (d['confirmationCount'] as num?)?.toInt() ?? 0,
      reportCount: (d['reportCount'] as num?)?.toInt() ?? 0,
      createdBy: (d['createdBy'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      lastConfirmedAt: (d['lastConfirmedAt'] as Timestamp?)?.toDate(),
      isActive: d['isActive'] != false,
      name: d['name'] as String?,
      region: d['region'] as String?,
      operatorRef: d['operatorRef'] as String?,
      accessType: d['accessType'] as String?,
      website: d['website'] as String?,
      phone: d['phone'] as String?,
      address: d['address'] as String?,
      workingHours: d['workingHours'] as String?,
      sitePowerKw: d['sitePowerKw'] as num?,
      powerRatingsKw: List<num>.from(d['powerRatingsKw'] as List? ?? const []),
      sourceReportedStatus: d['sourceReportedStatus'] as String?,
      sourceType: d['sourceType'] as String?,
      sourceProvider: d['sourceProvider'] as String?,
      sourceUrls: List<String>.from(d['sourceUrls'] as List? ?? const []),
      reviewRequired: d['reviewRequired'] == true,
      reviewFlags: List<String>.from(d['reviewFlags'] as List? ?? const []),
      possibleDuplicateIds:
          List<String>.from(d['possibleDuplicateIds'] as List? ?? const []),
    );
  }
}
