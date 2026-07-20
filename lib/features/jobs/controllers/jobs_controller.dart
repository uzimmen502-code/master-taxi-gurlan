import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../services/user_role_sync.dart';

/// ИШ ТОП экранининг controller'и.
class JobsController extends ChangeNotifier {
  JobsController({required JobsRepository repo}) : _repo = repo {
    _init();
  }

  static const int dailyAdLimit = 10;

  final JobsRepository _repo;

  String userName = '';
  String userPhone = '';
  String userAddress = '';
  bool isAdmin = false;
  String searchQuery = '';

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userName = prefs.getString('user_name') ?? '';
    userPhone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    userAddress = prefs.getString('user_address') ?? '';
    final role = await UserRoleSync().syncToPreferences();
    isAdmin = UserRoleSync.isPrivileged(role);
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
      userPhone.isNotEmpty && phonesMatch(ad.authorPhone, userPhone);

  List<JobAd> _filterExpiredAndSearch(List<JobAd> source) {
    var list = source.where((a) => !a.isExpired).toList();
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

  /// Шошилинч алоҳида бўлим; қолганлар вақт бўйича.
  ({List<JobAd> urgent, List<JobAd> regular}) partitionFeed(List<JobAd> source) {
    final list = _filterExpiredAndSearch(source);
    final urgent = <JobAd>[];
    final regular = <JobAd>[];
    for (final a in list) {
      if (a.supportsUrgent && a.isUrgent) {
        urgent.add(a);
      } else {
        regular.add(a);
      }
    }
    return (urgent: urgent, regular: regular);
  }

  /// Эски API — фақат бир рўйхат (керак бўлса).
  List<JobAd> filterAndSort(List<JobAd> source) {
    final p = partitionFeed(source);
    return [...p.urgent, ...p.regular];
  }

  /// Таб бўйича рўйхат: шошилинч алоҳида таб; «Иш» таби йўқ.
  List<JobAd> feedForTab(
    List<JobAd> source, {
    AdKind? kind,
    bool urgentOnly = false,
  }) {
    Iterable<JobAd> list = source;
    if (urgentOnly) {
      list = list.where((a) => a.supportsUrgent && a.isUrgent);
    } else if (kind != null) {
      list = list.where(
        (a) => a.kind == kind && !(a.supportsUrgent && a.isUrgent),
      );
    }
    return _filterExpiredAndSearch(list.toList(growable: false));
  }

  String _cfError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'unauthenticated':
          return 'Аввал тизимга киринг';
        case 'resource-exhausted':
          return e.message?.contains('complaint') == true
              ? '⚠️ Кунига шикоят лимити тугади'
              : '⚠️ Кунига максимум $dailyAdLimit та эълон!';
        case 'invalid-argument':
          return e.message ?? 'Маълумотлар нотўғри';
        case 'failed-precondition':
          return e.message ?? 'Амал бажарилмади';
        case 'permission-denied':
          return 'Рухсат йўқ — профилда телефонни текширинг';
        default:
          return e.message ?? 'Хатолик: ${e.code}';
      }
    }
    return 'Хатолик: $e';
  }

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
    if (phoneDigits(userPhone).length < 9) {
      return (success: false, error: 'Профилда телефон рақамини киритинг');
    }
    try {
      // UI hint; сервер `submitJobAd` ҳам текширади.
      final dailyCount = await _repo.dailyCountByAuthor(userPhone);
      if (dailyCount >= dailyAdLimit) {
        return (
          success: false,
          error: '⚠️ Кунига максимум $dailyAdLimit та эълон!'
        );
      }
      final days = isUrgent
          ? AdKindX.urgentExpiryDays
          : AdKindX.parse(type).expiresInDays;
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
      return (success: false, error: _cfError(e));
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
      if (isAdmin) {
        await _repo.updateAd(
          adId: adId,
          text: text.trim(),
          isUrgent: isUrgent,
          type: type,
          status: status,
          title: title,
          priceText: priceText,
        );
      } else {
        await _repo.updateAdByOwner(
          adId: adId,
          callerPhone: userPhone,
          text: text.trim(),
          isUrgent: isUrgent,
          type: type,
          title: title,
          priceText: priceText,
        );
      }
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Хатолик: $e');
    }
  }

  Future<({bool success, String? error})> deleteAd(String adId) async {
    try {
      if (isAdmin) {
        await _repo.deleteAdAdmin(adId);
      } else {
        await _repo.deleteAdByOwner(adId: adId, callerPhone: userPhone);
      }
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Хатолик: $e');
    }
  }

  Future<({bool success, String? error})> submitComplaint({
    required String adId,
    required String reason,
  }) async {
    if (phoneDigits(userPhone).length < 9) {
      return (success: false, error: 'Профилда телефон рақамини киритинг');
    }
    try {
      await _repo.addComplaint(adId: adId, reason: reason);
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: _cfError(e));
    }
  }

  Stream<List<JobAd>> watch(String type) => _repo.watchActiveByType(type);

  Stream<List<JobAd>> watchAll() => _repo.watchAllActive();

  Stream<List<JobAd>> watchMyAds() => _repo.watchAdsByAuthor(userPhone);
}
