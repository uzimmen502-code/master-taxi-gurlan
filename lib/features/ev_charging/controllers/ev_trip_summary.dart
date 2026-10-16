// ⚡ EV сафар — вақт ва зарядлаш маълумоти (режа хулосаси, тўхташ
// карточкалари). ТОЗА Dart: плагинсиз `flutter test`да текширилади.
//
// Принцип (эга қарори, 2026-10-16): ўйлаб топилган рақам йўқ.
//  * Йўл вақти — Google маршрутидан (`EvTripController.routeMinutes`).
//  * Тўхташда қўшиладиган энергия = (чиқиш% − келиш%) × фойдаланиладиган
//    батарея сиғими (`EvCarSpec.usableBatteryKwh`). Фоизлар режадан
//    (бутун сонга юмалоқланган) — аниқлик ~±1% сиғим.
//  * Зарядлаш вақти ФАҚАТ «камида»: энергия ÷ станция қуввати. Машинанинг
//    максимал DC қабул қилиш қуввати БАЗАДА ЙЎҚ (UNKNOWN) ва уни тахмин
//    қилмаймиз; ҳақиқий вақт одатда узунроқ (машина секинроқ қабул қилади,
//    80%дан кейин секинлашади). Қувват номаълум станцияда вақт кўрсатилмайди,
//    фақат энергия.

import '../../../models/ev_charging_station.dart';
import '../models/ev_trip_plan.dart';

/// Давомийликни «13 с 10 дақ» шаклида қайтаради. Бирликлар тилга қараб
/// ташқаридан берилади (`ev_trip_unit_h` / `ev_trip_unit_min`) — қаттиқ
/// «h/min» йўқ. 60 дақиқадан кам — фақат дақиқа; тўла соат — фақат соат.
/// `minutes <= 0` (номаълум) — бўш матн.
String evFormatDuration(
  int minutes, {
  required String hourUnit,
  required String minuteUnit,
}) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m $minuteUnit';
  if (m == 0) return '$h $hourUnit';
  return '$h $hourUnit $m $minuteUnit';
}

/// Станциянинг ишлатиладиган қуввати (kW): `powerKw ?? sitePowerKw` — тўхташ
/// карточкасидаги қатор билан БИР ХИЛ қоида ([evTripStationSpecLine]).
num? evStationPowerKw(EvChargingStation s) => s.powerKw ?? s.sitePowerKw;

/// Тўхташда батареяга қўшиладиган энергия (kWh):
/// `(departSoc − arriveSoc)% × usableBatteryKwh`. Манфий/нол фарқ ёки
/// яроқсиз сиғим — 0.
double evStopEnergyKwh(EvTripStop stop, EvCarSpec car) {
  final delta = stop.departSocPercent - stop.arriveSocPercent;
  if (delta <= 0 || !(car.usableBatteryKwh > 0)) return 0;
  return car.usableBatteryKwh * delta / 100;
}

/// «Камида» зарядлаш вақти (дақиқа, юқорига юмалоқланган, камида 1):
/// `energy ÷ power × 60`. Қувват номаълум ёки ≤ 0, энергия ≤ 0 — `null`.
/// Бу ҲАҚИҚИЙ вақтнинг қуйи чегараси: станция берадиган қувватдан тез
/// зарядлаш мумкин эмас.
int? evMinChargeMinutes({required double energyKwh, required num? powerKw}) {
  if (powerKw == null || powerKw <= 0 || !(energyKwh > 0)) return null;
  // Сузувчи нуқта хатоси «ва 1 дақиқа» қўшмаслиги учун кичик оғиш.
  final minutes = (energyKwh * 60 / powerKw - 1e-9).ceil();
  return minutes < 1 ? 1 : minutes;
}

/// Битта тўхташ учун зарядлаш маълумоти.
class EvStopCharge {
  const EvStopCharge({required this.energyKwh, required this.minMinutes});

  final double energyKwh;

  /// «Камида» вақт (дақиқа); станция қуввати номаълум бўлса `null`.
  final int? minMinutes;
}

/// Тўхташ маълумоти; автомобил йўқ/яроқсиз ёки энергия нол — `null`
/// (ҳеч нарса кўрсатилмайди).
EvStopCharge? evStopCharge(EvTripStop stop, EvCarSpec? car) {
  if (car == null) return null;
  final energy = evStopEnergyKwh(stop, car);
  if (!(energy > 0)) return null;
  return EvStopCharge(
    energyKwh: energy,
    minMinutes: evMinChargeMinutes(
        energyKwh: energy, powerKw: evStationPowerKw(stop.station)),
  );
}

/// Режа бўйича «камида» зарядлаш вақтлари йиғиндиси — фақат қуввати
/// маълум тўхташлар бўйича ([knownStops]); қолганлари 0 деб ҲИСОБЛАНМАЙДИ,
/// балки кирмайди, шунинг учун йиғинди ҳам қуйи чегара. Ҳеч бири маълум
/// эмас ([knownStops] == 0) — вақт кўрсатилмайди.
({int minutes, int knownStops, int totalStops}) evPlanMinChargeMinutes(
  EvTripPlan plan,
  EvCarSpec? car,
) {
  var minutes = 0;
  var known = 0;
  var total = 0;
  for (final s in plan.stops) {
    final c = evStopCharge(s, car);
    if (c == null) continue;
    total += 1;
    final m = c.minMinutes;
    if (m != null) {
      minutes += m;
      known += 1;
    }
  }
  return (minutes: minutes, knownStops: known, totalStops: total);
}

/// Энергияни қисқа кўринишда: 10 kWh дан катта — бутун; кичик — битта ўнлик
/// (`.0` ташланади). Бирлик ("kWh") чақирувчида.
String evFormatKwh(double kwh) {
  if (kwh >= 10) return '${kwh.round()}';
  final s = kwh.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
