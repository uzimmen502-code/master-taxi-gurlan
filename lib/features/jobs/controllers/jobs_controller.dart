import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../services/user_role_sync.dart';

/// Бўлим рўйхати — [sorted] тартибини сақлаб, шу [kind] даги ҲАММА
/// эълон; шошилинчлари ТЕПАДА.
///
/// Bug fix (2026-10-06). Symptom: «Шошилинч» белгиси қўйилган эълон
/// модул экранида умуман кўринмасди. Root cause: таб филтри шошилинчларни
/// чиқариб ташларди, уларни кўрсатадиган «Шошилинч» таби эса йўқ эди
/// (белги изоҳи «алоҳида бўлимда кўринади» дерди). Fix: шошилинчлар ўз
/// бўлимининг тепасида. Тест: `test/features/jobs/jobs_section_feed_test.dart`.
List<JobAd> jobsSectionFeed(List<JobAd> sorted, AdKind kind) {
  bool urgent(JobAd a) => a.supportsUrgent && a.isUrgent;
  final ofKind = sorted.where((a) => a.kind == kind);
  return [...ofKind.where(urgent), ...ofKind.where((a) => !urgent(a))];
}

/// «Эълонлар» / «Хизматлар» бўлимлари экранининг controller'и.
class JobsController extends ChangeNotifier {
  JobsController({required JobsRepository repo}) : _repo = repo {
    _ready = _init();
  }

  static const int dailyAdLimit = 10;

  final JobsRepository _repo;

  String userName = '';
  String userPhone = '';
  String userAddress = '';
  bool isAdmin = false;
  String searchQuery = '';

  Future<void>? _ready;

  Future<void> ensureReady() => _ready ??= _init();

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
    final q = searchQuery;
    final filtered = list
        .where((a) => CatalogSearch.matches(q, [a.title, a.text]))
        .toList();
    if (CatalogSearch.normalize(q).isEmpty) return filtered;
    filtered.sort((a, b) {
      return CatalogSearch.compare(
        q,
        titleA: a.title,
        titleB: b.title,
        extraA: [a.text],
        extraB: [b.text],
      );
    });
    return filtered;
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

  /// Бўлим бўйича рўйхат (муддати ўтганлар ва қидирув филтрланган):
  /// шу турдаги ҲАММА эълон, шошилинчлари тепада.
  List<JobAd> feedForTab(
    List<JobAd> source, {
    AdKind? kind,
    bool urgentOnly = false,
  }) {
    final sorted = _filterExpiredAndSearch(source);
    if (urgentOnly) {
      return sorted.where((a) => a.supportsUrgent && a.isUrgent).toList();
    }
    if (kind == null) return sorted;
    return jobsSectionFeed(sorted, kind);
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

  Future<({bool success, String? error, String? status})> submitAd({
    required String type,
    required String text,
    required bool isUrgent,
    String title = '',
    String priceText = '',
  }) async {
    await ensureReady();
    final t = title.trim();
    final body = text.trim();
    if (t.length < 3) {
      return (
        success: false,
        error: 'Сарлавҳани киритинг (камида 3 белги)',
        status: null,
      );
    }
    if (body.length < 3) {
      return (
        success: false,
        error: 'Матнни киритинг (камида 3 белги)',
        status: null,
      );
    }
    if (!JobAd.isJobsBoardType(type)) {
      return (success: false, error: 'Номаълум эълон тури', status: null);
    }
    if (phoneDigits(userPhone).length < 9) {
      return (
        success: false,
        error: 'Профилда телефон рақамини киритинг',
        status: null,
      );
    }
    try {
      // UI hint; сервер `submitJobAd` ҳам текширади.
      final dailyCount = await _repo.dailyCountByAuthor(userPhone);
      if (dailyCount >= dailyAdLimit) {
        return (
          success: false,
          error: '⚠️ Кунига максимум $dailyAdLimit та эълон!',
          status: null,
        );
      }
      final days = isUrgent
          ? AdKindX.urgentExpiryDays
          : AdKindX.parse(type).expiresInDays;
      final expiresAt = DateTime.now().add(Duration(days: days));
      final status = await _repo.addAd(
        type: type,
        text: body,
        title: t,
        priceText: priceText.trim(),
        authorName: userName,
        authorPhone: userPhone,
        address: userAddress,
        isUrgent: isUrgent,
        expiresAt: expiresAt,
      );
      return (success: true, error: null, status: status);
    } catch (e) {
      return (success: false, error: _cfError(e), status: null);
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
    await ensureReady();
    final body = text.trim();
    if (body.length < 3) {
      return (success: false, error: 'Матнни киритинг (камида 3 белги)');
    }
    final t = (title ?? '').trim();
    if (t.isNotEmpty && t.length < 3) {
      return (
        success: false,
        error: 'Сарлавҳани киритинг (камида 3 белги)',
      );
    }
    try {
      if (isAdmin) {
        await _repo.updateAd(
          adId: adId,
          text: body,
          isUrgent: isUrgent,
          type: type,
          status: status,
          title: title,
          priceText: priceText,
        );
      } else {
        if (phoneDigits(userPhone).length < 9) {
          return (
            success: false,
            error: 'Профилда телефон рақамини киритинг',
          );
        }
        await _repo.updateAdByOwner(
          adId: adId,
          callerPhone: userPhone,
          text: body,
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
    await ensureReady();
    try {
      if (isAdmin) {
        await _repo.deleteAdAdmin(adId);
      } else {
        if (phoneDigits(userPhone).length < 9) {
          return (
            success: false,
            error: 'Профилда телефон рақамини киритинг',
          );
        }
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

  /// Ҳудуд даражаси (D-GEO-1): туман → вилоят → Республика, танлов
  /// сақланади. Аввал экран доим бутун Республикадан 500 тасини олар эди.
  GeoScope get scope => _scope;
  GeoScope _scope = GeoContext.scopeFor('jobs');

  /// Оқим кешланади — қидирув ёзилганда (notify) янги listener очилмасин.
  Stream<List<JobAd>>? _feed;
  String _feedKey = '';

  Stream<List<JobAd>> watchAll() {
    if (_feed == null || _feedKey != _scope.key) {
      _feedKey = _scope.key;
      _feed = _repo.watchScoped(_scope).asBroadcastStream();
    }
    return _feed!;
  }

  void setScope(GeoScope s) {
    if (s == _scope) return;
    _scope = s;
    notifyListeners();
  }

  /// Глобал қидирувдан аниқ эълонга келинганда — у бошқа ҳудудда бўлиши
  /// мумкин; шунда шу сафарга Республика (сақланмайди).
  void showNationwideOnce() {
    _scope = _scope.copyWith(level: GeoLevel.nation);
    notifyListeners();
  }

  Stream<List<JobAd>> watchMyAds() => _repo.watchAdsByAuthor(userPhone);
}
