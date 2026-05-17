import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../models/marshrut_driver_profile.dart';
import '../../../../repositories/marshrut_driver_repository.dart';

/// Marshrut haydovchi ro'yxatdan o'tish/yangilash formasi state mashinasi.
///
/// Mas'uliyat:
/// - profil va profil tarixini yuklash (`SharedPreferences` + Firestore)
/// - mashina maydonlari, ўрин сони (Damas → 6, аks 4), маршрут нуқталари
/// - валидация ва батч-yozish (`MarshrutDriverRepository.register()`)
class MarshrutRegisterController extends ChangeNotifier {
  MarshrutRegisterController({required MarshrutDriverRepository repo})
      : _repo = repo;

  final MarshrutDriverRepository _repo;

  // ─── State ──────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRegistered = false;
  bool _missingPhone = false;

  String _userId = '';
  String _userName = '';
  String _userPhone = '';

  String _carModel = '';
  String _plate = '';
  int _seats = 4;

  String _fromMfy = '';
  List<String> _midStops = [];
  String _toMfy = '';

  MarshrutDriverProfile? _savedProfile;
  String? _errorMessage;

  // ─── Getters ────────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isRegistered => _isRegistered;
  bool get missingPhone => _missingPhone;
  String get userId => _userId;
  String get userName => _userName;
  String get userPhone => _userPhone;
  String get carModel => _carModel;
  String get plate => _plate;
  int get seats => _seats;
  String get fromMfy => _fromMfy;
  List<String> get midStops => List.unmodifiable(_midStops);
  String get toMfy => _toMfy;
  MarshrutDriverProfile? get savedProfile => _savedProfile;
  String? get errorMessage => _errorMessage;

  int get maxSeats {
    final m = _carModel.toLowerCase();
    return m.contains('damas') || m.contains('дамас') ? 6 : 4;
  }

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

  // ─── Lifecycle ──────────────────────────────────────────────────────

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
      if (existing != null) {
        _isRegistered = true;
        _carModel = existing.carModel;
        _plate = existing.plate;
        _seats = existing.seats;
        if (existing.stops.isNotEmpty) {
          _fromMfy = existing.stops.first;
          if (existing.stops.length > 1) {
            _toMfy = existing.stops.last;
            if (existing.stops.length > 2) {
              _midStops = existing.stops.sublist(1, existing.stops.length - 1);
            }
          }
        }
      }
    } catch (_) {
      // Tarix yuklashda xato — bo'sh forma ko'rsatamiz
    }
    _isLoading = false;
    notifyListeners();
  }

  // ─── Form setters ───────────────────────────────────────────────────

  void setCarModel(String v) {
    _carModel = v;
    if (_seats > maxSeats) _seats = maxSeats;
    notifyListeners();
  }

  void setPlate(String v) {
    _plate = v;
    notifyListeners();
  }

  void setSeats(int n) {
    if (n < 1 || n > maxSeats) return;
    _seats = n;
    notifyListeners();
  }

  void setFromMfy(String v) {
    _fromMfy = v;
    notifyListeners();
  }

  void setToMfy(String v) {
    _toMfy = v;
    notifyListeners();
  }

  /// Oraliq nuqta qo'shish. Allaqachon bor bo'lsa yoki from/to bilan bir xil
  /// bo'lsa — `false` qaytaradi (screen snack ko'rsatadi).
  bool addMidStop(String v) {
    if (v.isEmpty) return false;
    if (_midStops.contains(v) || v == _fromMfy || v == _toMfy) {
      return false;
    }
    _midStops = [..._midStops, v];
    notifyListeners();
    return true;
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

  // ─── Save ───────────────────────────────────────────────────────────

  /// Validatsiya + atomic batch yozish. Muvaffaqiyatli bo'lsa
  /// [savedProfile] ga tayinlanadi va `true` qaytaradi.
  Future<bool> save() async {
    final err = _validate();
    if (err != null) {
      _errorMessage = err;
      notifyListeners();
      return false;
    }

    _isSaving = true;
    notifyListeners();

    final profile = MarshrutDriverProfile(
      uid: _userId,
      driverName: _userName,
      driverPhone: _userPhone,
      carModel: _carModel.trim(),
      plate: _plate.trim().toUpperCase(),
      seats: _seats,
      stops: allStops,
    );

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
      await _repo.register(
        profile: profile,
        date: _todayDateStr,
        expiresAt: midnight,
      );
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
    if (_carModel.trim().isEmpty) return 'Машина маркасини киритинг';
    if (_plate.trim().isEmpty) return 'Давлат рақамини киритинг';
    if (_fromMfy.isEmpty) return 'Бошлангич нуқтани танланг';
    if (_toMfy.isEmpty) return 'Охирги нуқтани танланг';
    if (_fromMfy == _toMfy) {
      return 'Бошлангич ва охирги нуқта бир хил бўлмасин';
    }
    return null;
  }
}
