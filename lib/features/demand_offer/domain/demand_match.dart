// ТАЛАБ → ТАКЛИФ ядроси — `demand_matches` модели.
//
// БУ ТАКЛИФЧИ КЎРАДИГАН ЯГОНА МАНБА.
//
// Таклифчи `demands` ҳужжатини ҲЕЧ ҚАЧОН ўқимайди — Firestore қоидаси
// рад этади. У фақат шу проекцияни кўради: туман, ТАХМИНИЙ нуқта
// (300–600 м, Т-20), категория, қисқа изоҳ, муддат, расм.
//
// Аниқ манзил ва телефон ФАҚАТ қабул қилингандан кейин, босқичма-босқич
// очилади ([MatchContact], Т-9):
//   1-поғона (`accepted`)     — юборувчи телефони + ОЛИШ манзили
//   2-поғона (`in_progress`)  — қабул қилувчи телефони + ЕТКАЗИШ манзили
//
// Сабаб: концепцияда иккаласи бирга очиларди ва бу «манзил йиғиш»
// ҳужумига очиқ эди — курьер қабул қилади, маълумотни ўқийди, келмайди.

import 'demand.dart'
    show asDemandMap, demandEmptyToNull, demandStringList, parseDemandDate,
        toDemandDouble, toDemandInt, DemandBudget;
import 'demand_enums.dart';

/// Таклифчи учун match ҳолати.
enum MatchStatus {
  /// Янги — ҳали кўрилмаган.
  isNew,
  seen,
  skipped,
  offered,
  accepted,

  /// Бошқа ижрочига берилди.
  taken,
  expired,
  cancelled,
  cancelledByProvider,
  deadlineMissed,

  /// AVA Logistics: ижрочи посилкани ОЛДИ (`scanHandover`) — иш кетмоқда.
  inProgress,

  /// AVA Logistics: топширди/етказди — LEG ёпилди, ҳақ ҳисобланди.
  completed;

  String get wire {
    switch (this) {
      case MatchStatus.isNew:
        return 'new';
      case MatchStatus.cancelledByProvider:
        return 'cancelled_by_provider';
      case MatchStatus.deadlineMissed:
        return 'deadline_missed';
      case MatchStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }

  static MatchStatus? tryParse(String? v) {
    if (v == null) return null;
    for (final s in MatchStatus.values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  /// Таклифчи ҳали таклиф бера оладими.
  bool get canOffer =>
      this == MatchStatus.isNew
      || this == MatchStatus.seen
      || this == MatchStatus.offered;

  /// Рўйхатда «ёпилган» деб кўрсатиладими.
  bool get isClosed =>
      this == MatchStatus.taken
      || this == MatchStatus.expired
      || this == MatchStatus.cancelled
      || this == MatchStatus.completed;
}

/// Босқичма-босқич очилган контакт (Т-9).
class MatchContact {
  const MatchContact({
    required this.stage,
    this.ownerPhone,
    this.pickupAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.recipientPhone,
    this.recipientName = '',
    this.dropoffAddress = '',
    this.dropoffLat,
    this.dropoffLng,
    this.nextProviderPhone,
    this.deliveryCodeRequired = false,
  });

  /// 1 — юборувчи; 2 — қабул қилувчи ҳам.
  final int stage;

  final String? ownerPhone;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;

  /// ФАҚАТ 2-поғонада тўлади (посилка олингандан кейин).
  final String? recipientPhone;

  /// AVA Logistics, 2-поғона, фақат охирги LEG: қабул қилувчи исми.
  final String recipientName;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;

  /// AVA Logistics: кейинги ижрочи LEG'ни олганда — унинг телефони
  /// (топшириш нуқтасини келишиш учун). Сервер `acceptLeg`да ёзади.
  final String? nextProviderPhone;

  /// AVA Logistics: бу LEG охиргиси — етказиш 6 хонали код билан ёпилади.
  final bool deliveryCodeRequired;

  bool get hasRecipient => stage >= 2 && (recipientPhone?.isNotEmpty ?? false);

  static MatchContact? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return MatchContact(
      stage: toDemandInt(m['stage']) ?? 1,
      ownerPhone: demandEmptyToNull(m['ownerPhone']),
      pickupAddress: (m['pickupAddress'] ?? '').toString(),
      pickupLat: toDemandDouble(m['pickupLat']),
      pickupLng: toDemandDouble(m['pickupLng']),
      recipientPhone: demandEmptyToNull(m['recipientPhone']),
      recipientName: (m['recipientName'] ?? '').toString(),
      dropoffAddress: (m['dropoffAddress'] ?? '').toString(),
      dropoffLat: toDemandDouble(m['dropoffLat']),
      dropoffLng: toDemandDouble(m['dropoffLng']),
      nextProviderPhone: demandEmptyToNull(m['nextProviderPhone']),
      deliveryCodeRequired: m['deliveryCodeRequired'] == true,
    );
  }
}

/// Таклифчи кўрадиган қисқартирилган талаб.
class MatchProjection {
  const MatchProjection({
    this.title = '',
    this.description = '',
    this.categoryId,
    this.districtId,
    this.regionId,
    this.approxLat,
    this.approxLng,
    this.geohash = '',
    this.budget,
    this.quantity,
    this.images = const [],
    this.neededBy,
    this.attributes = const {},
  });

  final String title;
  final String description;
  final String? categoryId;
  final String? districtId;
  final String? regionId;

  /// ТАХМИНИЙ нуқта — аниқ манзил ЭМАС (Т-20).
  ///
  /// `demandId` hash'идан детерминистик оғиш: ҳар доим бир хил нуқта,
  /// 300–600 м радиусда, йўналиши олдиндан айтиб бўлмайдиган. Шунинг
  /// учун бир нечта талабдан аниқ жойни тиклаш мумкин эмас.
  final double? approxLat;
  final double? approxLng;

  /// 5 белги (≈4,9 км). Тўлиқ 7–8 белги БЕРИЛМАЙДИ.
  final String geohash;

  final DemandBudget? budget;
  final int? quantity;
  final List<String> images;
  final DateTime? neededBy;
  final Map<String, dynamic> attributes;

  bool get hasApproxPoint => approxLat != null && approxLng != null;

  static MatchProjection fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MatchProjection();
    return MatchProjection(
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      categoryId: demandEmptyToNull(m['categoryId']),
      districtId: demandEmptyToNull(m['districtId']),
      regionId: demandEmptyToNull(m['regionId']),
      approxLat: toDemandDouble(m['approxLat']),
      approxLng: toDemandDouble(m['approxLng']),
      geohash: (m['geohash'] ?? '').toString(),
      budget: DemandBudget.fromMap(asDemandMap(m['budget'])),
      quantity: toDemandInt(m['quantity']),
      images: demandStringList(m['images']),
      neededBy: parseDemandDate(m['neededBy']),
      attributes: asDemandMap(m['attributes']) ?? const {},
    );
  }
}

/// Масофа ва ETA — сервер ҳисоблаган.
class MatchMetrics {
  const MatchMetrics({this.distanceKm, this.etaMinutes, this.detourKm});

  final double? distanceKm;
  final int? etaMinutes;

  /// «Йўлингиз устида, +2,1 км» — шаҳарлараро учун.
  final double? detourKm;

  static MatchMetrics fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MatchMetrics();
    return MatchMetrics(
      distanceKm: toDemandDouble(m['distanceKm']),
      etaMinutes: toDemandInt(m['etaMinutes']),
      detourKm: toDemandDouble(m['detourKm']),
    );
  }
}

class DemandMatch {
  const DemandMatch({
    required this.key,
    required this.demandId,
    required this.providerId,
    required this.module,
    required this.mode,
    required this.status,
    this.score = 0,
    this.rank = 0,
    this.sources = const [],
    this.consentGiven = true,
    this.metrics = const MatchMetrics(),
    this.projection = const MatchProjection(),
    this.contact,
    this.expiresAt,
    this.createdAt,
    this.seenAt,
  });

  /// Ҳужжат калити: `{demandId}_{providerId}`.
  final String key;

  final String demandId;

  /// ДИҚҚАТ: калитдан эмас, МАЙДОНДАН ўқилади. Firestore қоидаси ҳам
  /// айни шу майдонни текширади (Т-2.1).
  final String providerId;

  final DemandModule module;
  final DemandMode mode;
  final MatchStatus status;
  final double score;
  final int rank;

  /// Қайси манбалардан топилган (`capabilities`, `active_listings`...).
  final List<String> sources;

  /// Таклифчи талаблар олишга рози бўлганми.
  ///
  /// `false` — у `ads` эълонидан топилган (cold start) ва PUSH ОЛМАГАН.
  /// Шунда илова «Шу йўналишда талаблар олишни хоҳлайсизми?» деган
  /// розилик таклифини кўрсатади.
  final bool consentGiven;

  final MatchMetrics metrics;
  final MatchProjection projection;

  /// Қабул қилингандан кейин тўлади (Т-9).
  final MatchContact? contact;

  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? seenAt;

  bool get isNew => status == MatchStatus.isNew;

  /// Рўйхатда кўрсатиладими.
  ///
  /// Сервер sweeper'и кечикса ҳам эскирган талаб кўринмайди (Т-5).
  bool isVisibleAt(DateTime now) {
    if (status.isClosed) return false;
    if (expiresAt != null && expiresAt!.isBefore(now)) return false;
    return true;
  }

  /// Розилик таклифи кўрсатилсинми.
  bool get needsConsentPrompt => !consentGiven && status.canOffer;

  factory DemandMatch.fromMap(String key, Map<String, dynamic> m) {
    return DemandMatch(
      key: key,
      demandId: (m['demandId'] ?? '').toString(),
      providerId: (m['providerId'] ?? '').toString(),
      module: DemandModule.tryParse(m['module']?.toString())
          ?? DemandModule.service,
      mode: DemandMode.tryParse(m['mode']?.toString()) ?? DemandMode.quote,
      status: MatchStatus.tryParse(m['status']?.toString())
          ?? MatchStatus.isNew,
      score: toDemandDouble(m['score']) ?? 0,
      rank: toDemandInt(m['rank']) ?? 0,
      sources: demandStringList(m['sources']),
      consentGiven: m['consentGiven'] != false,
      metrics: MatchMetrics.fromMap(asDemandMap(m['metrics'])),
      projection: MatchProjection.fromMap(asDemandMap(m['projection'])),
      contact: MatchContact.fromMap(asDemandMap(m['contactUnlocked'])),
      expiresAt: parseDemandDate(m['expiresAt']),
      createdAt: parseDemandDate(m['createdAt']),
      seenAt: parseDemandDate(m['seenAt']),
    );
  }
}
