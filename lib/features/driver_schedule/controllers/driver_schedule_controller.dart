import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  })  : _schedulesRepo = schedulesRepo,
        _marshrutDriverRepo = marshrutDriverRepo {
    seats = maxSeats;
  }

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

  int get maxSeats {
    final c = driverCar.toLowerCase();
    return (c.contains('damas') || c.contains('дамас')) ? 6 : 4;
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

  // ─── Common state ─────────────────────────────────────────────────
  int seats = 4;
  bool isSaving = false;
  String? errorMessage;

  String get dateStr {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Marshrut уchun профилdan stops, alone/intercity uchun SharedPreferences'dan
  /// сақланган манзилlar.
  Future<void> init() async {
    if (isMarshrut) {
      final uid = await _loadUid();
      if (uid.isEmpty) return;
      final profile = await _marshrutDriverRepo.getProfile(uid);
      final stops = profile?.stops ?? const <String>[];
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
    if (fromAddr.isNotEmpty || toAddr.isNotEmpty) notifyListeners();
  }

  Future<String> _loadUid() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  // ─── Marshrut setters ──────────────────────────────────────────────
  void setFromMfy(String v) {
    fromMfy = v;
    notifyListeners();
  }

  void setToMfy(String v) {
    toMfy = v;
    notifyListeners();
  }

  /// Қайтариш қиймати — қўшилди ёки йўq (дубликат бўлса false).
  bool addMidStop(String v) {
    if (v.isEmpty) return false;
    if (midStops.contains(v) || v == fromMfy || v == toMfy) {
      errorMessage = 'Бу нуқта аллақачон қўшилган';
      notifyListeners();
      return false;
    }
    midStops = [...midStops, v];
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
    // Текстfield ўз ҳолатини бошқаради — фойдаланувчи фақат submit'да валидация
    // кўрсин, ҳар инпут учун `notifyListeners()` чақирмаймиз.
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
      if (fromMfy.isEmpty) return 'Бошлангич нуқтани танланг';
      if (toMfy.isEmpty) return 'Охирги нуқтани танланг';
      if (fromMfy == toMfy) return 'Бошлангич ва охирги нуқта бир хил бўлмасин';
    } else {
      if (fromAddr.trim().isEmpty) return 'Қаердан манзилини киритинг';
      if (!isAlone && toAddr.trim().isEmpty) return 'Қаерга манзилини киритинг';
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

  List<String> get allStops => [
        if (fromMfy.isNotEmpty) fromMfy,
        ...midStops,
        if (toMfy.isNotEmpty) toMfy,
      ];

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
      final today = DateTime.now();
      final midnight = DateTime(today.year, today.month, today.day, 23, 59, 59);

      final fromText = isMarshrut ? fromMfy : fromAddr.trim();
      final toText = isMarshrut ? toMfy : toAddr.trim();
      final stops = isMarshrut ? allStops : const <String>[];
      final dir = isMarshrut ? direction : '';

      if (!isMarshrut) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('route_from_$taxiType', fromText);
        await prefs.setString('route_to_$taxiType', toText);
      }

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
        startTime: isAlone ? _fmt(startTime) : null,
        endTime: isAlone ? _fmt(endTime) : null,
        price: isIntercity
            ? int.tryParse(priceText.trim().replaceAll(' ', '')) ?? 0
            : null,
      );
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      isSaving = false;
      errorMessage = 'Хатолик: $e';
      notifyListeners();
      return false;
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
