// ⚡ EV сафар — «Йўл режими» (эга қарори, 2026-10-16: Режа → Алтернативалар →
// Навигация → Йўл режими).
//
// ТОЗА Dart (ёлғиз геолокатор масофа функцияси): `flutter test`да
// сохта вақт ва сохта GPS билан текширилади.
//
// Йўл режими — машина ҳақиқатан ҳаракатда бўлганда ихчам «Кейинги зарядлаш»
// карточкаси. Ҳайдовчи йўлда оғир режа варағи билан ишламайди.

import '../models/ev_trip_plan.dart';
import 'ev_navigation_session_controller.dart';
import 'ev_trip_planner.dart';

/// Машина ҳаракатда экани ҳақидаги қарор (GPS тезлигидан).
///
/// Титраб кетмаслиги учун гистерезис:
///  * ҳаракат бошланди — тезлик [enterKmh] дан ЮҚОРИ [enterFixes] та
///    КЕТМА-КЕТ нуқтада;
///  * тўхтади — тезлик [exitKmh] дан ПАСТ [exitFixes] та кетма-кет нуқтада
///    ЁКИ [staleAfter] давомида янги нуқта келмаса (GPS 10 м филтр билан
///    ишлайди — тўхтаган машинада нуқта умуман келмайди);
///  * [exitKmh]..[enterKmh] оралиғида ҳеч нарса ўзгармайди.
///
/// Тезлик номаълум (`null`/манфий) нуқта ҳисобланмайди. Қўлда ёқиш/ўчириш
/// ([toggleManual]) кейинги автоматик ўзгаришгача амал қилади.
class EvDriveModeMachine {
  EvDriveModeMachine({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Шундан тез — «ҳаракатда».
  static const double enterKmh = 8;

  /// Шундан секин — «тўхтаяпти» (гистерезис: [enterKmh]дан паст).
  static const double exitKmh = 4;

  static const int enterFixes = 3;
  static const int exitFixes = 3;

  /// Янги нуқта келмаса, шунча вақтдан кейин «тўхтади».
  static const Duration staleAfter = Duration(seconds: 20);

  final DateTime Function() _clock;

  bool _auto = false;
  bool? _manual;
  int _fast = 0;
  int _slow = 0;
  DateTime? _lastFixAt;

  /// Автоматик қарор (тезликдан).
  bool get autoDriving => _auto;

  /// Қўлда танланган ҳолат (`null` — автоматик).
  bool? get manual => _manual;

  /// Йўл режими ёқиқми.
  bool get driving => _manual ?? _auto;

  /// Янги GPS нуқтаси ([speedMps] — м/с). Ҳолат ўзгарса `true`.
  bool onFix(double? speedMps) {
    _lastFixAt = _clock();
    final v = speedMps;
    if (v == null || v.isNaN || v < 0) return false;
    final kmh = v * 3.6;
    final before = driving;

    if (!_auto) {
      _fast = kmh >= enterKmh ? _fast + 1 : 0;
      if (_fast >= enterFixes) {
        _auto = true;
        _fast = 0;
        _slow = 0;
        _manual = null;
      }
    } else {
      _slow = kmh < exitKmh ? _slow + 1 : 0;
      if (_slow >= exitFixes) {
        _auto = false;
        _fast = 0;
        _slow = 0;
        _manual = null;
      }
    }
    return driving != before;
  }

  /// Вақт ўтиши билан текшириш (даврий таймер чақиради): нуқта
  /// [staleAfter] келмаса — тўхтади. Ҳолат ўзгарса `true`.
  bool tick() {
    final last = _lastFixAt;
    if (!_auto || last == null) return false;
    if (_clock().difference(last) <= staleAfter) return false;
    final before = driving;
    _auto = false;
    _fast = 0;
    _slow = 0;
    _manual = null;
    return driving != before;
  }

  /// «Йўл режими» чипи: ҳозирги ҳолатнинг тескариси.
  void toggleManual() {
    _manual = !driving;
  }

  /// GPS йўқолди ёки сафар тугади.
  void reset() {
    _auto = false;
    _manual = null;
    _fast = 0;
    _slow = 0;
    _lastFixAt = null;
  }
}

/// Режадаги навбатдаги зарядлаш тўхташи (йўл режими карточкаси учун).
class EvDriveTarget {
  const EvDriveTarget({
    required this.stopIndex,
    required this.stop,
    required this.distanceKm,
    required this.arrived,
  });

  /// Режадаги индекс (`plan.stops[stopIndex]`).
  final int stopIndex;
  final EvTripStop stop;

  /// Йўл бўйлаб машинадан тўхташгача (км, режа масштабида, ≥ 0).
  final double distanceKm;

  /// Машина тўхташга [EvDriveNext.arrivalRadiusM] ичида.
  final bool arrived;

  /// «Келишда ~Y%» — режадаги (қайта ҳисобланган) қиймат.
  int get arriveSocPercent => stop.arriveSocPercent;
}

class EvDriveNext {
  const EvDriveNext._();

  /// «Етиб келдингиз» радиуси (м). Мавжуд навигация сессияси радиуси (50 м,
  /// `EvChargingRulesConfig`) ўта кичик — трасса бўйича юраётган машина учун
  /// карточка ўз вақтида чиқиши учун кенгроқ.
  static const int arrivalRadiusM = 150;

  /// Машина ортида қолган тўхташни яна шунча км гача «навбатдаги» деб
  /// ҳисоблаймиз (GPS шовқини); ундан кейин — ўтиб кетган, яширилади.
  static const double passedMarginKm = 0.5;

  /// Навбатдаги тўхташ: ўтиб кетганлари ва ҳайдовчи «Зарядлаш бошланди»
  /// деб тасдиқлаганлари ([acknowledgedIds]) ҳисобга олинмайди. Етиб
  /// келиш масофаси мавжуд [EvNavigationSessionController.hasArrived]
  /// орқали (такрорланмайди). Тўхташ қолмаса — `null`.
  static EvDriveTarget? next({
    required EvTripPlan plan,
    required double carAlongKm,
    required double carLat,
    required double carLng,
    Set<String> acknowledgedIds = const {},
  }) {
    for (var i = 0; i < plan.stops.length; i++) {
      final stop = plan.stops[i];
      if (acknowledgedIds.contains(stop.station.id)) continue;
      final arrived = EvNavigationSessionController.hasArrived(
        currentLat: carLat,
        currentLng: carLng,
        targetLat: stop.station.latitude,
        targetLng: stop.station.longitude,
        radiusMeters: arrivalRadiusM,
      );
      final ahead = stop.alongKm >= carAlongKm - passedMarginKm;
      if (!arrived && !ahead) continue; // аллақачон ўтиб кетилган
      final d = stop.alongKm - carAlongKm;
      return EvDriveTarget(
        stopIndex: i,
        stop: stop,
        distanceKm: d < 0 ? 0 : d,
        arrived: arrived,
      );
    }
    return null;
  }
}

/// Режа бўйича йўлнинг [alongKm] жойида кутилган заряд (%) — «Зарядни
/// янгилаш» варағининг бошланғич қиймати. Режа бошланғич шартлари номаълум
/// бўлса `null`. Қиймат 5..100 га қисқартирилади.
int? evPredictedSocAt(EvTripPlan plan, EvCarSpec car, double alongKm) {
  final start = plan.startSocPercent;
  if (start == null) return null;
  var position = plan.fromAlongKm;
  var soc = start.toDouble();
  for (final s in plan.stops) {
    if (s.alongKm > alongKm) break;
    position = s.alongKm;
    soc = s.departSocPercent.toDouble();
  }
  final km = alongKm - position;
  final result = soc - (km > 0 ? EvTripPlanner.socForKm(km, car) : 0);
  return result.round().clamp(5, 100);
}
