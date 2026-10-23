import '../../../models/ev_charging_station.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../wholesale/models/wholesale_seller.dart';
import 'business.dart';
import 'business_category.dart';

/// Объект қайси манбадан келган (B-3: харита 4 манбанинг бирлашмаси; ҳар бири ўз коллекциясида қолади).
enum BusinessSource { business, restaurant, evStation, wholesaleSeller }

/// Харитадаги бирлашган нуқта. Манба моделидан ясалади; кўрсатиш учун керакли майдонлар шу ерда,
/// манбанинг ўз экранини очиш учун [origin] сақланади.
class BusinessPin {
  const BusinessPin({
    required this.source,
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.subtitle = '',
    this.description = '',
    this.phone = '',
    this.address = '',
    this.hours = '',
    this.website = '',
    this.origin,
  });

  final BusinessSource source;

  /// Манба ичидаги ID; харита ичида `key` — `source:id` (ID'лар манбалар орасида тўқнашиши мумкин).
  final String id;
  final String name;
  final BusinessCategory category;
  final double lat;
  final double lng;
  final String subtitle;
  final String description;
  final String phone;
  final String address;
  final String hours;
  final String website;

  /// Манба модели (`Business` / `Restaurant` / `EvChargingStation` / `WholesaleSeller`).
  final Object? origin;

  String get key => '${source.name}:$id';

  factory BusinessPin.fromBusiness(Business b) => BusinessPin(
        source: BusinessSource.business,
        id: b.id,
        name: b.name,
        category: b.category,
        lat: b.lat,
        lng: b.lng,
        subtitle: b.subtype,
        description: b.description,
        phone: b.phone,
        address: b.address,
        hours: b.openingHours,
        website: b.website,
        origin: b,
      );

  /// Кафе-ресторан: координатаси йўқ бўлса — `null` (харитага қўйиб бўлмайди).
  static BusinessPin? fromRestaurant(Restaurant r) {
    final lat = r.lat;
    final lng = r.lng;
    if (lat == null || lng == null || !r.isApproved) return null;
    return BusinessPin(
      source: BusinessSource.restaurant,
      id: r.id,
      name: r.name,
      category: BusinessCategory.food,
      lat: lat,
      lng: lng,
      subtitle: r.cuisineTags.join(', '),
      description: r.description,
      phone: r.contactPhone,
      address: r.address,
      hours: r.openingHours?.label ?? '',
      origin: r,
    );
  }

  /// Зарядка станцияси: `auto` гуруҳи (PROPOSED — INFERRED: автомобил хизмати). Номи бўлмаса — оператор номи.
  static BusinessPin? fromEvStation(EvChargingStation s) {
    if (!s.isActive || (s.latitude == 0 && s.longitude == 0)) return null;
    final name = s.hasName
        ? s.name!.trim()
        : (s.hasOperatorName ? s.operatorName!.trim() : '');
    return BusinessPin(
      source: BusinessSource.evStation,
      id: s.id,
      name: name,
      category: BusinessCategory.auto,
      lat: s.latitude,
      lng: s.longitude,
      subtitle: [
        if (s.hasOperatorName && s.hasName) s.operatorName!.trim(),
        if (s.hasPowerKw) '${s.powerKw} kW',
      ].join(' · '),
      phone: s.phone ?? '',
      address: s.address ?? '',
      hours: s.workingHours ?? '',
      website: s.website ?? '',
      origin: s,
    );
  }

  /// Улгуржи сотувчи: фақат тасдиқланган ва координатаси бор. (Кўпида `lat/lng` бўш — docs R-2.)
  static BusinessPin? fromWholesaleSeller(WholesaleSeller s) {
    final lat = s.lat;
    final lng = s.lng;
    if (lat == null || lng == null || !s.isApproved) return null;
    return BusinessPin(
      source: BusinessSource.wholesaleSeller,
      id: s.phone,
      name: s.companyName,
      category: BusinessCategory.wholesale,
      lat: lat,
      lng: lng,
      phone: s.phone,
      address: s.address,
      origin: s,
    );
  }
}
