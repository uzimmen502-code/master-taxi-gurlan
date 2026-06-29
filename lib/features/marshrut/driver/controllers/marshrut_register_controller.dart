import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/car/car_info_record.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/route_points_validator.dart';
import '../../../../models/marshrut_driver_profile.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/marshrut_route_price_repository.dart';
import '../../../../services/marshrut_pricing_service.dart';
import '../../../../utils/gurlan_places.dart';

/// Marshrut haydovchi ro'yxatdan o'tish/yangilash formasi state mashinasi.
class MarshrutRegisterController extends ChangeNotifier {
  MarshrutRegisterController({
    required MarshrutDriverRepository repo,
    MarshrutRoutePriceRepository? priceRepo,
  })  : _repo = repo,
        _priceRepo = priceRepo ?? MarshrutRoutePriceRepository();

  final MarshrutDriverRepository _repo;
  final MarshrutRoutePriceRepository _priceRepo;

  /// Joriy yo'nalish (from|to) uchun belgilangan narx (boshqa haydovchi seed
  /// qilgan) — `null` bo'lsa hali narx yo'q (shu haydovchi birinchi).
  int? _existingRoutePrice;
  bool _priceLoading = false;
  int? _priceInput;

  int? get existingRoutePrice => _existingRoutePrice;
  bool get routePriceLocked => _existingRoutePrice != null;
  bool get priceLoading => _priceLoading;
  int? get priceInput => _priceInput;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRegistered = false;
  bool _missingPhone = false;

  String _userId = '';
  String _userName = '';
  String _userPhone = '';

  TimeOfDayValue _startTime = const TimeOfDayValue(hour: 7, minute: 0);

  String _fromMfy = '';
  List<String> _midStops = [];
  String _toMfy = '';

  MarshrutDriverProfile? _savedProfile;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isRegistered => _isRegistered;
  bool get missingPhone => _missingPhone;
  String get userId => _userId;
  String get userName => _userName;
  String get userPhone => _userPhone;
  TimeOfDayValue get startTime => _startTime;
  String get startTimeLabel => _startTime.label;
  String get fromMfy => _fromMfy;
  List<String> get midStops => List.unmodifiable(_midStops);
  String get toMfy => _toMfy;
  MarshrutDriverProfile? get savedProfile => _savedProfile;
  String? get errorMessage => _errorMessage;

  bool get canSaveRoute =>
      RoutePointsValidator.validateRoute(
        from: _fromMfy,
        to: _toMfy,
        midStops: _midStops,
      ) ==
      null;

  List<String> get allStops => [
        if (_fromMfy.isNotEmpty) _fromMfy,
        ..._midStops,
        if (_toMfy.isNotEmpty) _toMfy,
      ];

  String get _todayDateStr {
    final d = DateTime.now();
    return '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _userPhone = prefs.getString('user_phone') ?? '';
    if (_userId.isEmpty && _userPhone.isNotEmpty) {
      _userId = phoneDigits(_userPhone);
    }
    if (_userId.isEmpty) {
      _missingPhone = true;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final existing = await _repo.getProfile(_userId);
      if (existing != null && existing.stops.length >= 2) {
        _isRegistered = true;
        _applyProfile(existing);
      } else {
        await _applyRoutePrefill();
      }
    } catch (_) {
      await _applyRoutePrefill();
    }

    _isLoading = false;
    notifyListeners();
    await _refreshRoutePrice();
  }

  void _applyProfile(MarshrutDriverProfile profile) {
    _startTime = TimeOfDayValue.tryParse(profile.startTime) ??
        const TimeOfDayValue(hour: 7, minute: 0);
    if (profile.stops.isNotEmpty) {
      _fromMfy = profile.stops.first;
      if (profile.stops.length > 1) {
        _toMfy = profile.stops.last;
        if (profile.stops.length > 2) {
          _midStops = profile.stops.sublist(1, profile.stops.length - 1);
        }
      }
    }
  }

  Future<void> _applyRoutePrefill() async {
    final route = await _repo.resolveRoutePrefill(_userId);
    if (route.from.isNotEmpty) _fromMfy = route.from;
    if (route.to.isNotEmpty) _toMfy = route.to;
    if (route.mid.isNotEmpty) _midStops = List<String>.from(route.mid);
  }

  /// Joriy from|to uchun belgilangan yo'nalish narxini o'qiydi.
  /// Bor bo'lsa — read-only (qulflangan); yo'q bo'lsa — shu haydovchi belgilaydi.
  Future<void> _refreshRoutePrice() async {
    final from = GurlanPlaces.normalizeMfyName(_fromMfy);
    final to = GurlanPlaces.normalizeMfyName(_toMfy);
    if (from.isEmpty || to.isEmpty) {
      _existingRoutePrice = null;
      _priceLoading = false;
      notifyListeners();
      return;
    }
    _priceLoading = true;
    notifyListeners();
    try {
      _existingRoutePrice = await _priceRepo.getPrice(from, to);
    } catch (_) {
      _existingRoutePrice = null;
    }
    _priceLoading = false;
    notifyListeners();
  }

  void setPriceInput(int? value) {
    _priceInput = (value != null && value > 0) ? value : null;
    notifyListeners();
  }

  /// Narx tayyor: yo'nalish qulflangan (mavjud) yoki haydovchi musbat narx kiritgan.
  bool get hasValidPrice => routePriceLocked || (_priceInput ?? 0) > 0;

  /// Saqlash uchun yo'nalish + narx ikkalasi ham to'g'ri bo'lsin.
  bool get canSave => canSaveRoute && hasValidPrice;

  void setStartTime(int hour, int minute) {
    _startTime = TimeOfDayValue(hour: hour, minute: minute);
    notifyListeners();
  }

  String? trySetFromMfy(String v) {
    if (v.trim().isEmpty) {
      _fromMfy = '';
      notifyListeners();
      return null;
    }
    final err = RoutePointsValidator.duplicateMessage(
      candidate: v,
      from: '',
      to: _toMfy,
      midStops: _midStops,
      role: 'from',
    );
    if (err != null) return err;
    _fromMfy = v.trim();
    _midStops = _midStops
        .where((m) => !RoutePointsValidator.samePoint(m, _fromMfy))
        .toList();
    notifyListeners();
    _refreshRoutePrice();
    return null;
  }

  String? trySetToMfy(String v) {
    if (v.trim().isEmpty) {
      _toMfy = '';
      notifyListeners();
      return null;
    }
    final err = RoutePointsValidator.duplicateMessage(
      candidate: v,
      from: _fromMfy,
      to: '',
      midStops: _midStops,
      role: 'to',
    );
    if (err != null) return err;
    _toMfy = v.trim();
    _midStops = _midStops
        .where((m) => !RoutePointsValidator.samePoint(m, _toMfy))
        .toList();
    notifyListeners();
    _refreshRoutePrice();
    return null;
  }

  String? tryAddMidStop(String v) {
    if (v.trim().isEmpty) return null;
    final err = RoutePointsValidator.duplicateMessage(
      candidate: v,
      from: _fromMfy,
      to: _toMfy,
      midStops: _midStops,
      role: 'mid',
    );
    if (err != null) return err;
    _midStops = [..._midStops, v.trim()];
    notifyListeners();
    return null;
  }

  void removeMidStop(int i) {
    if (i < 0 || i >= _midStops.length) return;
    _midStops = [..._midStops]..removeAt(i);
    notifyListeners();
  }

  void clearTransient() {
    _errorMessage = null;
    _savedProfile = null;
    notifyListeners();
  }

  Future<bool> save() async {
    final err = _validate();
    if (err != null) {
      _errorMessage = err;
      notifyListeners();
      return false;
    }

    final car = await CarInfoRecord.load(canonicalPhoneId(_userId));
    if (car == null || !car.isComplete) {
      _errorMessage = 'car_info_required';
      notifyListeners();
      return false;
    }

    _isSaving = true;
    notifyListeners();

    final profile = MarshrutDriverProfile(
      uid: _userId,
      driverName: _userName,
      driverPhone: _userPhone,
      carModel: car.model,
      plate: car.plate.toUpperCase(),
      seats: car.seats,
      stops: allStops,
      startTime: _startTime.label,
    );

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final plannedStartAt = DateTime(
        now.year,
        now.month,
        now.day,
        _startTime.hour,
        _startTime.minute,
      );
      final scheduleId = await _repo.register(
        profile: profile,
        date: _todayDateStr,
        expiresAt: midnight,
        plannedStartAt: plannedStartAt,
      );
      // Yo'nalish narxini server avtoritetida belgilash/ko'zgu qilish.
      // Mavjud bo'lsa CF uni qaytaradi (proposed e'tiborga olinmaydi).
      final proposed = _existingRoutePrice ?? _priceInput ?? 0;
      try {
        final res = await MarshrutPricingService.seedRoutePrice(
          scheduleId: scheduleId,
          price: proposed,
        );
        _existingRoutePrice = (res['price'] as num?)?.toInt();
      } catch (e) {
        // Narx ko'zgusi muvaffaqiyatsiz — reys baribir yaratildi.
        // Haydovchi navbatga price>0 darvozasidan o'tmaguncha kirmaydi.
        debugPrint('seedRoutePrice: $e');
      }
      _savedProfile = profile;
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  String? _validate() {
    return RoutePointsValidator.validateRoute(
      from: _fromMfy,
      to: _toMfy,
      midStops: _midStops,
    );
  }
}

class TimeOfDayValue {
  const TimeOfDayValue({
    required this.hour,
    required this.minute,
  });

  final int hour;
  final int minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static TimeOfDayValue? tryParse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDayValue(hour: h, minute: m);
  }
}
