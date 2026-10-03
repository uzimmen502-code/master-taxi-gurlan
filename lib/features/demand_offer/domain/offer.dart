// ТАЛАБ → ТАКЛИФ ядроси — `demands/{id}/offers/{providerId}` модели.
//
// МУҲИМ МАХФИЙЛИК ҚОИДАСИ: таклифчилар бир-бирининг нархини КЎРМАЙДИ
// (тасдиқланган қарор). Firestore қоидаси таклифни фақат унинг эгаси ва
// талаб эгасига беради. Шунинг учун бу моделда «бошқа таклифлар»
// тушунчаси умуман йўқ — харидор рўйхатини `OfferList` жамлайди.

import 'demand.dart' show parseDemandDate, demandStringList, toDemandInt;
import 'demand_enums.dart';

class Offer {
  const Offer({
    required this.providerId,
    required this.demandId,
    required this.status,
    this.ownerId = '',
    this.price,
    this.priceType = 'fixed',
    this.quantity,
    this.message = '',
    this.etaMinutes,
    this.delivery = false,
    this.media = const [],
    this.revision = 0,
    this.createdAt,
    this.updatedAt,
    this.providerName = '',
    this.providerRating,
    this.providerRatingCount = 0,
    this.distanceKm,
  });

  /// Таклиф ҳужжатининг ID'си = `providerId`. Битта таклифчи битта
  /// талабга фақат БИТТА таклиф беради.
  final String providerId;

  final String demandId;
  final OfferStatus status;

  /// Талаб эгаси — Т-2.2 бўйича денормаллаштирилган: Firestore қоидаси
  /// ота ҳужжатга `get()` қилмасдан текширади.
  final String ownerId;

  final num? price;
  final String priceType;
  final int? quantity;
  final String message;
  final int? etaMinutes;
  final bool delivery;
  final List<String> media;

  /// Нечта марта таҳрирланган. Чегара — 3 (Т-19.4).
  final int revision;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ── Қўшимча маълумот (харидор рўйхатида кўрсатиш учун) ──────────────
  // Булар таклиф ҳужжатида ЙЎҚ: илова `provider_stats`дан алоҳида
  // олади ва шу ерга бириктиради. Сабаб: рейтинг тез-тез ўзгаради,
  // уни ҳар таклифга нусхалаш эскирган маълумот беради.

  final String providerName;
  final double? providerRating;
  final int providerRatingCount;
  final double? distanceKm;

  bool get isActive => status == OfferStatus.active;

  /// Яна таҳрирлаш мумкинми.
  bool canReviseWithLimit(int maxRevisions) =>
      isActive && revision < maxRevisions;

  factory Offer.fromMap(String id, Map<String, dynamic> m) {
    return Offer(
      providerId: (m['providerId'] ?? id).toString(),
      demandId: (m['demandId'] ?? '').toString(),
      status: OfferStatus.tryParse(m['status']?.toString())
          ?? OfferStatus.active,
      ownerId: (m['ownerId'] ?? '').toString(),
      price: m['price'] as num?,
      priceType: (m['priceType'] ?? 'fixed').toString(),
      quantity: toDemandInt(m['quantity']),
      message: (m['message'] ?? '').toString(),
      etaMinutes: toDemandInt(m['etaMinutes']),
      delivery: m['delivery'] == true,
      media: demandStringList(m['media']),
      revision: toDemandInt(m['revision']) ?? 0,
      createdAt: parseDemandDate(m['createdAt']),
      updatedAt: parseDemandDate(m['updatedAt']),
    );
  }

  Offer withProviderInfo({
    String? name,
    double? rating,
    int? ratingCount,
    double? distanceKm,
  }) {
    return Offer(
      providerId: providerId,
      demandId: demandId,
      status: status,
      ownerId: ownerId,
      price: price,
      priceType: priceType,
      quantity: quantity,
      message: message,
      etaMinutes: etaMinutes,
      delivery: delivery,
      media: media,
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      providerName: name ?? providerName,
      providerRating: rating ?? providerRating,
      providerRatingCount: ratingCount ?? providerRatingCount,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}

/// Харидор кўрадиган таклифлар рўйхати ва тартиблаш.
///
/// Концепция: «Таклифлар рўйхатида тартиблаш: нарх, рейтинг, масофа ва
/// етказиб бериш бўйича.»
enum OfferSort {
  priceAsc,
  ratingDesc,
  distanceAsc,
  deliveryFirst,
  newestFirst;

  String get l10nKey => 'offer_sort_$name';
}

class OfferList {
  const OfferList(this.offers);

  final List<Offer> offers;

  int get activeCount => offers.where((o) => o.isActive).length;

  /// Фақат актив таклифлар, танланган тартибда.
  ///
  /// Тартиблаш БАРҚАРОР: тенг қийматларда `providerId` бўйича. Акс
  /// ҳолда рўйхат ҳар қайта чизилганда сакрайди ва фойдаланувчи
  /// «нима ўзгарди?» деб ўйлайди.
  List<Offer> sorted(OfferSort sort) {
    final list = offers.where((o) => o.isActive).toList();
    int tie(Offer a, Offer b) => a.providerId.compareTo(b.providerId);

    switch (sort) {
      case OfferSort.priceAsc:
        list.sort((a, b) {
          final ap = a.price;
          final bp = b.price;
          // Нархсиз таклиф («келишамиз») охирида.
          if (ap == null && bp == null) return tie(a, b);
          if (ap == null) return 1;
          if (bp == null) return -1;
          final c = ap.compareTo(bp);
          return c != 0 ? c : tie(a, b);
        });
        break;
      case OfferSort.ratingDesc:
        list.sort((a, b) {
          final ar = a.providerRating ?? -1;
          final br = b.providerRating ?? -1;
          final c = br.compareTo(ar);
          return c != 0 ? c : tie(a, b);
        });
        break;
      case OfferSort.distanceAsc:
        list.sort((a, b) {
          final ad = a.distanceKm ?? double.maxFinite;
          final bd = b.distanceKm ?? double.maxFinite;
          final c = ad.compareTo(bd);
          return c != 0 ? c : tie(a, b);
        });
        break;
      case OfferSort.deliveryFirst:
        list.sort((a, b) {
          if (a.delivery != b.delivery) return a.delivery ? -1 : 1;
          return tie(a, b);
        });
        break;
      case OfferSort.newestFirst:
        list.sort((a, b) {
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          final c = bt.compareTo(at);
          return c != 0 ? c : tie(a, b);
        });
        break;
    }
    return list;
  }
}
