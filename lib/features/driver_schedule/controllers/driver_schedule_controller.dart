import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/car/car_info_record.dart';
import '../../../core/utils/driver_car_prefill.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/route_points_validator.dart';
import '../../../models/marshrut_driver_profile.dart';
import '../../../repositories/marshrut_driver_repository.dart';
import '../../../repositories/schedules_repository.dart';

/// Haydovchining bugungi reys (schedule)'ни рўйxатдан ўтказадиган universal
/// controller — `marshrut`, `alone`, `intercity` учун ишлайди.
///
/// `taxiType` бўйича turli UI хатти-ҳаракат:
///   - `marshrut`: МФЙ pickerlar (from/mid/to), профилdan stops yuklash
///   - `alone`: erkin адрес текст fields + ишлаш вақти (start/end)
///   - `intercity`: erkin адрес текст fields + йўлкира нархи
///
/// Saqlash атомар: [SchedulesRepository.registerDriverSchedule] чақирилади
/// (eski схемалар деактивацияси + янги schedule + queue + drivers update).
class DriverScheduleController extends ChangeNotifier {
  DriverScheduleController({
    required this.taxiType,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
    required SchedulesRepository schedulesRepo,
    required MarshrutDriverRepository marshrutDriverRepo,
    List<String>? initialRouteStops,
    this.initialRouteReversed = false,
    int? initialSeats,
  })  : _schedulesRepo = schedulesRepo,
        _marshrutDriverRepo = marshrutDriverRepo,
        initialRouteStops = initialRouteStops == null
            ? null
            : List<String>.unmodifiable(initialRouteStops) {
    if (initialSeats != null && initialSeats > 0) {
      _userMaxSeats = initialSeats;
      seats = initialSeats;
    } else {
      seats = maxSeats;
    }
    if (this.initialRouteStops != null && this.initialRouteStops!.length >= 2) {
      applyRouteStops(this.initialRouteStops!, reversed: initialRouteReversed);
    }
  }

  /// Панельдан «қайтиш рейси» — маршрут олдиндан тўлдирилади.
  final List<String>? initialRouteStops;
  final bool initialRouteReversed;

  final String taxiType;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  final SchedulesRepository _schedulesRepo;
  final MarshrutDriverRepository _marshrutDriverRepo;

  bool get isMarshrut => taxiType == 'marshrut';
  bool get isAlone => taxiType == 'alone';
  bool get isIntercity => taxiType == 'intercity';

  int _userMaxSeats = 0;

  int get maxSeats {
    if (_userMaxSeats > 0) return _userMaxSeats;
    return DriverCarPrefill.maxSeatsForModel(driverCar);
  }

  // ─── Marshrut state ────────────────────────────────────────────────
  String fromMfy = '';
  String toMfy = '';
  List<String> midStops = const [];
  String direction = 'forward';

  // ─── Alone / intercity state ───────────────────────────────────────
  String fromAddr = '';
  String toAddr = '';

  // ─── Alone-only ────────────────────────────────────────────────────
  TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);

  // ─── Intercity-only ────────────────────────────────────────────────
  String priceText = '';
  TimeOfDay departureTime = const TimeOfDay(hour: 8, minute: 0);
  /// `false` — бүгун, `true` — эртага (йўловчи «Эртага» қидируви билан mos).
  bool departureIsTomorrow = false;

  // ─── Common state ─────────────────────────────────────────────────
  int seats = 4;
  bool isSaving = false;
  String? errorMessage;

  String get dateStr {
    final d = scheduleDay;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Intercity: бүгун ёки эртага; бошқа турлар — ҳамеша бүгун.
  DateTime get scheduleDay {
    final now = DateTime.now();
    if (isIntercity && departureIsTomorrow) {
      return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    }
    return DateTime(now.year, now.month, now.day);
  }

  /// Marshrut уchun профилdan stops, alone/intercity uchun SharedPreferences'dan
  /// сақланган манзилlar.
  Future<void> init() async {
    if (initialRouteStops != null && initialRouteStops!.length >= 2) {
      if (isIntercity) await _loadIntercityPrefs();
      notifyListeners();
      return;
    }

    if (isMarshrut) {
      final uid = await _loadUid();
      if (uid.isEmpty) return;
      final car = await CarInfoRecord.load(canonicalPhoneId(uid));
      if (car != null && car.seats > 0) {
        _userMaxSeats = car.seats;
        seats = car.seats;
      }
      final profile = await _marshrutDriverRepo.getProfile(uid);
      final stops = profile?.stops ?? const <String>[];
      if (_userMaxSeats == 0 && profile != null && profile.seats > 0) {
        _userMaxSeats = profile.seats;
        seats = profile.seats;
      }
      if (stops.length >= 2) {
        fromMfy = stops.first;
        toMfy = stops.last;
        midStops = stops.length > 2
            ? List<String>.from(stops.sublist(1, stops.length - 1))
            : const <String>[];
        notifyListeners();
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    fromAddr = prefs.getString('route_from_$taxiType') ?? '';
    toAddr = prefs.getString('route_to_$taxiType') ?? '';
    final midRaw = prefs.getString('route_mid_$taxiType') ?? '';
    if (midRaw.isNotEmpty) {
      midStops = midRaw.split('|').where((s) => s.trim().isNotEmpty).toList();
    }
    if (isIntercity) await _loadIntercityPrefs();
    if (fromAddr.isNotEmpty || toAddr.isNotEmpty || midStops.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<void> _loadIntercityPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final dep = prefs.getString('intercity_departure_hour');
    if (dep != null && dep.contains(':')) {
      final p = dep.split(':');
      departureTime = TimeOfDay(
        hour: int.tryParse(p[0]) ?? 8,
        minute: int.tryParse(p[1]) ?? 0,
      );
    }
    departureIsTomorrow = prefs.getBool('intercity_departure_tomorrow') ?? false;
    final savedPrice = prefs.getString('intercity_price_$taxiType');
    if (savedPrice != null && savedPrice.trim().isNotEmpty) {
      priceText = savedPrice;
    }
  }

  Future<String> _loadUid() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  // ─── Marshrut setters ──────────────────────────────────────────────
  String? trySetFromMfy(String v) {
    if (v.trim().isEmpty) {
      fromMfy = '';
      notifyListeners();
      return null;
    }
    final err = RoutePointsValidator.duplicateMessage(
      candidate: v,
      from: '',
      to: toMfy,
      midStops: midStops,
      role: 'from',
    );
    if (err != null) {
      errorMessage = err;
      notifyListeners();
      return err;
    }
    fromMfy = v.trim();
    midStops = midStops
        .where((m) => !RoutePointsValidator.samePoint(m, fromMfy))
        .toList();
    notifyListeners();
    return null;
  }

  String? trySetToMfy(String v) {
    if (v.trim().isEmpty) {
      toMfy = '';
      notifyListeners();
      return null;
    }
    final err = RoutePointsValidator.duplicateMessage(
      candidate: v,
      from: fromMfy,
      to: '',
      midStops: midStops,
      role: 'to',
    );
    if (err != null) {
      errorMessage = err;
      notifyListeners();
      return err;
    }
    toMfy = v.trim();
    midStops = midStops
        .where((m) => !RoutePointsValidator.samePoint(m, toMfy))
        .toList();
    notifyListeners();
    return null;
  }

  void setFromMfy(String v) => trySetFromMfy(v);

  void setToMfy(String v) => trySetToMfy(v);

  /// Qo'shildi yoki dublikat (false).
  bool addMidStop(String v) {
    if (v.trim().isEmpty) return false;
    final err = RoutePointsValidator.duplicateMessage(
      candidate: v,
      from: isMarshrut ? fromMfy : fromAddr.trim(),
      to: isMarshrut ? toMfy : toAddr.trim(),
      midStops: midStops,
      role: 'mid',
    );
    if (err != null) {
      errorMessage = err;
      notifyListeners();
      return false;
    }
    midStops = [...midStops, v.trim()];
    notifyListeners();
    return true;
  }

  void removeMidStop(int index) {
    if (index < 0 || index >= midStops.length) return;
    final next = [...midStops]..removeAt(index);
    midStops = next;
    notifyListeners();
  }

  // ─── Alone/intercity setters ───────────────────────────────────────
  void setFromAddr(String v) {
    fromAddr = v;
    notifyListeners();
  }

  void setToAddr(String v) {
    toAddr = v;
    notifyListeners();
  }

  void swapAddrs() {
    final tmp = fromAddr;
    fromAddr = toAddr;
    toAddr = tmp;
    notifyListeners();
  }

  /// Тўлиқ маршрутни тескари қилиш (from ↔ to, оралиқлар ҳам reversed).
  void applyRouteStops(List<String> stops, {bool reversed = false}) {
    var list = stops.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (list.length < 2) return;
    if (reversed) list = list.reversed.toList();

    if (isMarshrut) {
      fromMfy = list.first;
      toMfy = list.last;
      midStops = list.length > 2
          ? List<String>.from(list.sublist(1, list.length - 1))
          : const [];
    } else {
      fromAddr = list.first;
      toAddr = list.last;
      midStops = list.length > 2
          ? List<String>.from(list.sublist(1, list.length - 1))
          : const [];
    }
  }

  /// Йўналишни орқага қайтариш (intercity/marshrut — барча нуқталар).
  void reverseRoute() {
    final stops = allStops;
    if (stops.length >= 2) {
      applyRouteStops(stops, reversed: true);
    } else if (isMarshrut) {
      final tmp = fromMfy;
      fromMfy = toMfy;
      toMfy = tmp;
    } else {
      swapAddrs();
    }
    notifyListeners();
  }

  bool get canReverseRoute => allStops.length >= 2;

  // ─── Alone-only ────────────────────────────────────────────────────
  void setStartTime(TimeOfDay t) {
    startTime = t;
    notifyListeners();
  }

  void setEndTime(TimeOfDay t) {
    endTime = t;
    notifyListeners();
  }

  // ─── Intercity-only ────────────────────────────────────────────────
  void setPriceText(String v) {
    priceText = v;
  }

  void setDepartureTime(TimeOfDay t) {
    departureTime = t;
    notifyListeners();
  }

  void setDepartureIsTomorrow(bool v) {
    if (departureIsTomorrow == v) return;
    departureIsTomorrow = v;
    notifyListeners();
  }

  // ─── Common setters ────────────────────────────────────────────────
  void setSeats(int n) {
    if (n < 1 || n > maxSeats) return;
    seats = n;
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  // ─── Validation + save ─────────────────────────────────────────────

  String? _validate() {
    if (isMarshrut) {
      return RoutePointsValidator.validateRoute(
        from: fromMfy,
        to: toMfy,
        midStops: midStops,
      );
    } else if (!isAlone) {
      // Маҳаллий такси (alone) йўналиш белгиламайди — манзил талаб қилинмайди.
      if (fromAddr.trim().isEmpty) return 'Қаердан манзилини киритинг';
      if (toAddr.trim().isEmpty) return 'Қаерга манзилини киритинг';
    }
    if (isIntercity && priceText.trim().isEmpty) {
      return 'Нархни киритинг';
    }
    if (isAlone) {
      final startMin = startTime.hour * 60 + startTime.minute;
      final endMin = endTime.hour * 60 + endTime.minute;
      if (endMin <= startMin) {
        return 'Тугаш вақти бошланишдан кейин бўлиши керак';
      }
    }
    return null;
  }

  List<String> get allStops {
    if (isMarshrut) {
      return [
        if (fromMfy.isNotEmpty) fromMfy,
        ...midStops,
        if (toMfy.isNotEmpty) toMfy,
      ];
    }
    if (isIntercity) {
      return [
        if (fromAddr.trim().isNotEmpty) fromAddr.trim(),
        ...midStops,
        if (toAddr.trim().isNotEmpty) toAddr.trim(),
      ];
    }
    return const [];
  }

  /// Saqlash flow. Муваффақиятли бўлса `true` — экранни pop қилиш мумкин.
  Future<bool> confirm() async {
    final err = _validate();
    if (err != null) {
      errorMessage = err;
      notifyListeners();
      return false;
    }

    final uid = await _loadUid();
    if (uid.isEmpty) {
      errorMessage = 'Телефон рақами топилмади';
      notifyListeners();
      return false;
    }

    isSaving = true;
    notifyListeners();
    try {
      final day = scheduleDay;
      final midnight = DateTime(day.year, day.month, day.day, 23, 59, 59);

      final fromText = isMarshrut ? fromMfy : fromAddr.trim();
      final toText = isMarshrut ? toMfy : toAddr.trim();
      final stops = (isMarshrut || isIntercity) ? allStops : const <String>[];
      final dir = isMarshrut ? direction : '';

      if (!isMarshrut) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('route_from_$taxiType', fromText);
        await prefs.setString('route_to_$taxiType', toText);
        if (isIntercity) {
          await prefs.setString('route_mid_$taxiType', midStops.join('|'));
          await prefs.setString(
              'intercity_departure_hour', _fmt(departureTime));
          await prefs.setBool(
              'intercity_departure_tomorrow', departureIsTomorrow);
          await prefs.setString('intercity_price_$taxiType', priceText.trim());
        }
      }

      if (isMarshrut) {
        final profile = await _marshrutDriverRepo.getProfile(uid);
        final startLabel = profile?.startTime ?? '07:00';
        final startParts = startLabel.split(':');
        final startHour = int.tryParse(startParts.first) ?? 7;
        final startMinute =
            startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
        final plannedStartAt = DateTime(
          day.year,
          day.month,
          day.day,
          startHour,
          startMinute,
        );
        await _marshrutDriverRepo.register(
          profile: MarshrutDriverProfile(
            uid: uid,
            driverName: driverName,
            driverPhone: driverPhone,
            carModel: driverCar,
            plate: driverPlate,
            seats: seats,
            stops: stops,
            startTime: startLabel,
          ),
          date: dateStr,
          expiresAt: midnight,
          plannedStartAt: plannedStartAt,
        );
      } else {
        await _schedulesRepo.registerDriverSchedule(
          driverId: uid,
          taxiType: taxiType,
          driverName: driverName,
          driverPhone: driverPhone,
          driverCar: driverCar,
          driverPlate: driverPlate,
          date: dateStr,
          expiresAt: midnight,
          seats: seats,
          fromText: fromText,
          toText: toText,
          stops: stops,
          direction: dir,
          startTime: isAlone
              ? _fmt(startTime)
              : (isIntercity ? _fmt(departureTime) : null),
          endTime: isAlone ? _fmt(endTime) : null,
          price: isIntercity
              ? int.tryParse(priceText.trim().replaceAll(' ', '')) ?? 0
              : null,
        );
      }
      isSaving = false;
      notifyListeners();
      return true;
    } on DriverScheduleApprovalException catch (e) {
      isSaving = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      isSaving = false;
      final msg = e.toString();
      if (msg.contains('permission-denied')) {
        errorMessage =
            'Firestore рухсати йўқ. Admin тасдиғини ва интернетни текширинг.';
      } else if (msg.contains('failed-precondition')) {
        errorMessage =
            'Индекс кутилмоқда. Бир неча дақиқа сабр қилинг ёки админга мурожаат қилинг.';
      } else {
        errorMessage = 'Хатолик: $e';
      }
      notifyListeners();
      return false;
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
