import '../../business_map/domain/business.dart';
import '../../business_map/domain/business_category.dart';

/// «Ишлаб чиқарувчи завод/фабрикалар» (эга 2026-11-28): завод = `businesses/{id}` (category `manufacturing`).
///
/// Сервер майдонлари (`functions/factories.js`, client-write ЁПИҚ):
/// `factory {sellWholesale, showVideos, publishVacancies, avaSupplierReady}` — эганинг ЎЗ танлови;
/// `producerVerification.status` — `pending` | `approved` | `rejected` («Тасдиқланган ишлаб чиқарувчи»).
class FactoryOptions {
  const FactoryOptions({
    this.sellWholesale = false,
    this.showVideos = false,
    this.publishVacancies = false,
    this.avaSupplierReady = false,
  });

  static const none = FactoryOptions();

  final bool sellWholesale;
  final bool showVideos;
  final bool publishVacancies;

  /// «AVA'га таъминотчи бўлишга тайёрман» — фақат белги (админ кўради), буюртма мантиғи йўқ.
  final bool avaSupplierReady;

  /// Эски/бузуқ ҳужжат — ҳаммаси ўчиқ.
  factory FactoryOptions.fromMap(Object? raw) {
    if (raw is! Map) return none;
    return FactoryOptions(
      sellWholesale: raw['sellWholesale'] == true,
      showVideos: raw['showVideos'] == true,
      publishVacancies: raw['publishVacancies'] == true,
      avaSupplierReady: raw['avaSupplierReady'] == true,
    );
  }

  /// `setMyFactoryOptions` майдонлари (4 та bool — сервер шарт қилади).
  Map<String, bool> toCallable() => {
        'sellWholesale': sellWholesale,
        'showVideos': showVideos,
        'publishVacancies': publishVacancies,
        'avaSupplierReady': avaSupplierReady,
      };

  FactoryOptions copyWith({bool? sellWholesale, bool? showVideos, bool? publishVacancies, bool? avaSupplierReady}) =>
      FactoryOptions(
        sellWholesale: sellWholesale ?? this.sellWholesale,
        showVideos: showVideos ?? this.showVideos,
        publishVacancies: publishVacancies ?? this.publishVacancies,
        avaSupplierReady: avaSupplierReady ?? this.avaSupplierReady,
      );

  @override
  bool operator ==(Object other) =>
      other is FactoryOptions &&
      other.sellWholesale == sellWholesale &&
      other.showVideos == showVideos &&
      other.publishVacancies == publishVacancies &&
      other.avaSupplierReady == avaSupplierReady;

  @override
  int get hashCode => Object.hash(sellWholesale, showVideos, publishVacancies, avaSupplierReady);
}

/// Тасдиқ ҳолатлари (сервер `VERIFY_STATUSES`).
abstract final class ProducerStatus {
  static const none = '';
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';

  static String fromMap(Object? raw) {
    final s = raw is Map ? raw['status'] : null;
    return s == pending || s == approved || s == rejected ? s as String : none;
  }
}

/// Объект завод саналадими: `manufacturing` тури, блокланмаган.
bool isFactoryBusiness(Business b) => b.category == BusinessCategory.manufacturing && !b.isBlocked;

/// «Тасдиқланган ишлаб чиқарувчи» нишони кўринадими.
bool showsVerifiedProducerBadge(Business b) => isFactoryBusiness(b) && b.producerStatus == ProducerStatus.approved;
