import '../../models/user_address.dart';
import '../demand_offer/domain/demand.dart';
import '../demand_offer/ui_adapters/demand_ui_adapter.dart';

/// Қидирувдаги intent карточкаси босилганда қаерга олиб бориш (аудит №4).
///
/// Соф функциялар — Firebase ва экранларсиз синаладиган қарор қисми.
enum IntentTarget {
  /// Ядрога уланган модул (ҳозир `service` — «Уста чақириш»): сўров формаси.
  composer,

  /// Ядрога уланмаган, лекин иловада ишлайдиган экран.
  courier,
  intercityTaxi,
  realty,
  market,
  freightLocal,

  /// Номаълум — ҳеч нарса очилмайди.
  none,
}

/// Intent → мақсад.
///
/// `existingScreen` калитлари `assets/data/intent_keywords.json` даги
/// `modules.*.existingScreen` билан бир хил.
IntentTarget intentTargetFor(IntentResult intent) {
  if (intent.opensCoreFlow) return IntentTarget.composer;
  switch (intent.existingScreen) {
    case 'courier':
      return IntentTarget.courier;
    case 'intercity_taxi':
      return IntentTarget.intercityTaxi;
    case 'realty':
      return IntentTarget.realty;
    case 'market':
      return IntentTarget.market;
    case 'yuk_local':
      return IntentTarget.freightLocal;
  }
  return IntentTarget.none;
}

/// Сўров формаси учун бошланғич жойлашув: фойдаланувчининг сақланган манзили.
///
/// Форма жойлашув танлагични ЎЗИ кўрсатмайди (`ServiceDemandForm`да йўқ),
/// шунинг учун координата чақирувчидан келиши шарт. Координата йўқ бўлса
/// (`null`) — форма юборилмас эди, шу сабабли чақирувчи аввал Кабинетда
/// манзил киритишни таклиф қилади.
///
/// `regionId`/`districtId`/`geohash`ни сервер ҳисоблайди — бу ерда
/// ЮБОРИЛМАЙДИ (қаранг: [DemandPoint]).
DemandPoint? demandPointFromAddress(UserAddress? a) {
  // `hasGps`: (0, 0) ва бўш қиймат «координата йўқ» деб ҳисобланади.
  if (a == null || !a.hasGps) return null;
  return DemandPoint(
    lat: a.lat,
    lng: a.lng,
    addressText: a.formatted,
  );
}
