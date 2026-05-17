import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';

/// ИШ ТОП экранининг controller'и — фойдаланувчи маълумотлари,
/// админ текшируви, қидирув матни, эълонларни фильтрлаш/сортлаш.
class JobsController extends ChangeNotifier {
  JobsController({required JobsRepository repo}) : _repo = repo {
    _init();
  }

  final JobsRepository _repo;

  String userName = '';
  String userPhone = '';
  String userAddress = '';
  bool isAdmin = false;
  String searchQuery = '';

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userName = prefs.getString('user_name') ?? '';
    userPhone = prefs.getString('user_phone') ?? '';
    userAddress = prefs.getString('user_address') ?? '';
    // Admin tekshiruvi — `user_role == 'admin'` ёрдамида.
    // (Esкi `admin_phone` мехaнизми hech qаerда set qилинмасди — alindirib
    // tashladik). Server-side ҳаqиqий тaсдиq `AdminService` orqali.
    final role = prefs.getString('user_role') ?? 'user';
    isAdmin = role == 'admin';
    notifyListeners();
  }

  void setSearch(String v) {
    searchQuery = v.toLowerCase();
    notifyListeners();
  }

  void clearSearch() {
    searchQuery = '';
    notifyListeners();
  }

  bool isOwner(JobAd ad) =>
      userPhone.isNotEmpty && ad.authorPhone == userPhone;

  /// Муддати ўтганларни чиқариш, **янги тепада** (latest first),
  /// `searchQuery` бўйича фильтр. Urgent — алоҳида чизиқ-белги, лекин
  /// энди мажбурий тепага суриб юбормайди — UX содда: вақт асосий.
  List<JobAd> filterAndSort(List<JobAd> source) {
    final list = source.where((a) => !a.isExpired).toList();
    list.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    if (searchQuery.isEmpty) return list;
    return list
        .where((a) =>
            a.text.toLowerCase().contains(searchQuery) ||
            a.title.toLowerCase().contains(searchQuery))
        .toList(growable: false);
  }

  /// Янги эълон қўшиш: кунлик лимит текширилади.
  /// Қайтариш: `(success, error)`.
  Future<({bool success, String? error})> submitAd({
    required String type,
    required String text,
    required bool isUrgent,
    String title = '',
    String priceText = '',
  }) async {
    if (text.trim().isEmpty) {
      return (success: false, error: 'Матнни киритинг');
    }
    final dailyCount = await _repo.dailyCountByAuthor(userPhone);
    if (dailyCount >= 5) {
      return (success: false, error: '⚠️ Кунига максимум 5 та эълон!');
    }
    try {
      final days = AdKindX.parse(type).expiresInDays;
      final expiresAt = DateTime.now().add(Duration(days: days));
      await _repo.addAd(
        type: type,
        text: text.trim(),
        title: title.trim(),
        priceText: priceText.trim(),
        authorName: userName,
        authorPhone: userPhone,
        address: userAddress,
        isUrgent: isUrgent,
        expiresAt: expiresAt,
      );
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Хатолик: $e');
    }
  }

  Future<({bool success, String? error})> updateAd({
    required String adId,
    required String text,
    required bool isUrgent,
    required String type,
    String? status,
    String? title,
    String? priceText,
  }) async {
    if (text.trim().isEmpty) {
      return (success: false, error: 'Матнни киритинг');
    }
    try {
      await _repo.updateAd(
        adId: adId,
        text: text.trim(),
        isUrgent: isUrgent,
        type: type,
        status: isAdmin ? status : null,
        title: title,
        priceText: priceText,
      );
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Хатолик: $e');
    }
  }

  Future<void> submitComplaint({
    required String adId,
    required String reason,
  }) async {
    await _repo.addComplaint(adId: adId, reason: reason);
  }

  /// Eski API'га mos.
  Stream<List<JobAd>> watch(String type) => _repo.watchActiveByType(type);

  /// Барча 3 тур бирваракай (mini-OLX feed).
  Stream<List<JobAd>> watchAll() => _repo.watchAllActive();
}
