import 'dart:math';

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

/// Хатони фойдаланувчига кўрсатиладиган МАТН КАЛИТИГА айлантиради
/// (`context.trMsg` форматида: `калит` ёки `калит|қиймат`).
///
/// Аудит A3 (2026-10-18). Symptom: экранда сервернинг инглизча матни
/// («Phone mismatch», «title 3..120»), `Хатолик: $e` ва `Хатолик: ${e.code}`
/// кўринарди. Root cause: `e.message`/`$e` тўғридан-тўғри фойдаланувчига
/// узатиларди. Fix: ички код (`details.code`) → маҳаллий матн калити;
/// номаълум хато → умумий матн. Тест: `test/features/jobs/jobs_error_key_test.dart`.
String jobsErrorKey(
  Object error, {
  String fallback = 'jobs_err_post',
  int dailyLimit = JobsController.dailyAdLimit,
}) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final code = details is Map ? details['code']?.toString() : null;
    switch (code) {
      case 'JOB_AD_DAILY_LIMIT':
        return 'jobs_err_daily_limit|$dailyLimit';
      case 'JOB_AD_TITLE_LENGTH':
        return 'jobs_err_title_short';
      case 'JOB_AD_TEXT_LENGTH':
        return 'jobs_err_text_short';
      case 'JOB_AD_INVALID_TYPE':
        return 'jobs_err_unknown_type';
      case 'UNAUTHENTICATED':
        return 'jobs_err_login';
      case 'PHONE_MISMATCH':
        return 'jobs_err_permission';
    }
    switch (error.code) {
      case 'unauthenticated':
        return 'jobs_err_login';
      case 'permission-denied':
        return 'jobs_err_permission';
      case 'resource-exhausted':
        // Шикоят функцияси `details.code` бермайди — матн бўйича фарқлаймиз.
        return error.message?.toLowerCase().contains('complaint') == true
            ? 'ad_report_limit'
            : 'jobs_err_daily_limit|$dailyLimit';
      default:
        return fallback;
    }
  }
  return fallback;
}

/// «Эълонлар» / «Хизматлар» бўлимлари экранининг controller'и.
class JobsController extends ChangeNotifier {
  JobsController({required JobsRepository repo}) : _repo = repo {
    _ready = _init();
  }

  static const int dailyAdLimit = 10;

  /// Рўйхат саҳифаси ва юқори чегара (аудит B7: аввал ҳар очилишда 500 та
  /// ҳужжат real-time тингланарди).
  static const int pageSize = 50;
  static const int maxLimit = 500;

  final JobsRepository _repo;

  String userName = '';
  String userPhone = '';
  bool isAdmin = false;
  String searchQuery = '';

  Future<void>? _ready;

  Future<void> ensureReady() => _ready ??= _init();

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userName = prefs.getString('user_name') ?? '';
    userPhone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    try {
      final role = await UserRoleSync().syncToPreferences();
      isAdmin = UserRoleSync.isPrivileged(role);
    } catch (e) {
      // Роль синхронланмади (оффлайн): оддий фойдаланувчи сифатида давом
      // этамиз — аввал бу хато `ensureReady()` орқали эълон юборишни йиқитарди.
      // Ҳақиқий рухсатни сервер/rules текширади.
      debugPrint('[Jobs] role sync: $e');
      isAdmin = false;
    }
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

  /// Янги эълон варағи очилганда бир марта — қайта юборишни аниқлаш учун
  /// тасодифий уруғ. Тармоқ узилиб тугмани қайта босганда ЭЪЛОН ТАКРОРЛАНМАЙДИ.
  static String newRequestSeed() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// `requestId` = уруғ + мазмун хеши: ЎША мазмун қайта юборилса — бир хил id
  /// (сервер дубликатни қайтаради); матн таҳрирланса — янги id (таҳрир йўқолмайди).
  @visibleForTesting
  static String requestIdFor(
    String seed, {
    required String type,
    required String title,
    required String text,
    required String priceText,
    required bool isUrgent,
  }) {
    final h = Object.hash(type, title, text, priceText, isUrgent) & 0x7fffffff;
    return '$seed-${h.toRadixString(36)}';
  }

  Future<({bool success, String? error, String? status, String? adId})> submitAd({
    required String type,
    required String text,
    required bool isUrgent,
    String title = '',
    String priceText = '',
    String requestSeed = '',
  }) async {
    await ensureReady();
    final t = title.trim();
    final body = text.trim();
    ({bool success, String? error, String? status, String? adId}) fail(
            String key) =>
        (success: false, error: key, status: null, adId: null);
    if (t.length < 3) return fail('jobs_err_title_short');
    if (body.length < 3) return fail('jobs_err_text_short');
    if (!JobAd.isJobsBoardType(type)) return fail('jobs_err_unknown_type');
    if (phoneDigits(userPhone).length < 9) return fail('jobs_err_phone');
    try {
      // UI hint; сервер `submitJobAd` ҳам текширади.
      final dailyCount = await _repo.dailyCountByAuthor(userPhone);
      if (dailyCount >= dailyAdLimit) {
        return fail('jobs_err_daily_limit|$dailyAdLimit');
      }
      final price = priceText.trim();
      final created = await _repo.addAdWithId(
        type: type,
        text: body,
        title: t,
        priceText: price,
        isUrgent: isUrgent,
        requestId: requestSeed.isEmpty
            ? ''
            : requestIdFor(
                requestSeed,
                type: type,
                title: t,
                text: body,
                priceText: price,
                isUrgent: isUrgent,
              ),
      );
      return (
        success: true,
        error: null,
        status: created.status,
        adId: created.adId,
      );
    } catch (e) {
      debugPrint('[Jobs] submitAd: $e');
      return fail(jobsErrorKey(e));
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
      return (success: false, error: 'jobs_err_text_short');
    }
    final t = (title ?? '').trim();
    if (t.isNotEmpty && t.length < 3) {
      return (success: false, error: 'jobs_err_title_short');
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
          return (success: false, error: 'jobs_err_phone');
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
      debugPrint('[Jobs] updateAd: $e');
      return (success: false, error: 'jobs_err_generic');
    }
  }

  Future<({bool success, String? error})> deleteAd(String adId) async {
    await ensureReady();
    try {
      if (isAdmin) {
        await _repo.deleteAdAdmin(adId);
      } else {
        if (phoneDigits(userPhone).length < 9) {
          return (success: false, error: 'jobs_err_phone');
        }
        await _repo.deleteAdByOwner(adId: adId, callerPhone: userPhone);
      }
      return (success: true, error: null);
    } catch (e) {
      debugPrint('[Jobs] deleteAd: $e');
      return (success: false, error: 'jobs_err_generic');
    }
  }

  Future<({bool success, String? error})> submitComplaint({
    required String adId,
    required String reason,
  }) async {
    if (phoneDigits(userPhone).length < 9) {
      return (success: false, error: 'jobs_err_phone');
    }
    try {
      await _repo.addComplaint(adId: adId, reason: reason);
      return (success: true, error: null);
    } catch (e) {
      debugPrint('[Jobs] submitComplaint: $e');
      return (success: false, error: jobsErrorKey(e, fallback: 'jobs_err_generic'));
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

  /// Ҳозирги саҳифа чегараси (B7). [loadMore] уни [pageSize]га оширади.
  int _limit = pageSize;
  int _lastCount = 0;
  int _countAtLoadMore = -1;
  bool _exhausted = false;

  /// Яна эълон юклаш мумкинми: охирги олинган сон чегарага яқин, чегара
  /// [maxLimit]га етмаган ва охирги "яна юклаш" янги эълон келтирган.
  bool get canLoadMore =>
      !_exhausted && _limit < maxLimit && _lastCount >= _limit - 5;

  void _onFeedEvent(int count) {
    final wasExhausted = _exhausted;
    if (_countAtLoadMore >= 0 && count <= _countAtLoadMore) _exhausted = true;
    if (count != _lastCount || wasExhausted != _exhausted) {
      _lastCount = count;
      notifyListeners();
    }
  }

  @visibleForTesting
  int get debugLimit => _limit;

  /// Оқимдан "count та эълон келди" ҳодисасини тақлид қилади (саҳифалаш тести).
  @visibleForTesting
  void debugFeedEvent(int count) => _onFeedEvent(count);

  Stream<List<JobAd>> watchAll() {
    final key = '${_scope.key}|$_limit';
    if (_feed == null || _feedKey != key) {
      _feedKey = key;
      _feed = _repo
          .watchScoped(_scope, limit: _limit)
          .map((list) {
            _onFeedEvent(list.length);
            return list;
          })
          .asBroadcastStream();
    }
    return _feed!;
  }

  void _resetPaging() {
    _limit = pageSize;
    _lastCount = 0;
    _countAtLoadMore = -1;
    _exhausted = false;
  }

  void setScope(GeoScope s) {
    if (s == _scope) return;
    _scope = s;
    _resetPaging();
    notifyListeners();
  }

  /// Рўйхатнинг кейинги саҳифаси: чегара [pageSize]га ошади (янги оқим).
  void loadMore() {
    if (!canLoadMore) return;
    _countAtLoadMore = _lastCount;
    _limit = min(_limit + pageSize, maxLimit);
    notifyListeners();
  }

  /// Юклаш хатосидан кейин қайта уриниш.
  void reload() {
    _feed = null;
    _resetPaging();
    notifyListeners();
  }

  /// Глобал қидирувдан аниқ эълонга келинганда — у бошқа ҳудудда бўлиши
  /// мумкин; шунда шу сафарга Республика (сақланмайди).
  void showNationwideOnce() {
    _scope = _scope.copyWith(level: GeoLevel.nation);
    _resetPaging();
    notifyListeners();
  }

  /// Менинг эълонларим (A2): ҳар қандай статус — `pending`/`blocked` ҳам.
  /// Телефон [ensureReady]дан кейин маълум бўлади.
  Stream<List<JobAd>> watchMyAds() async* {
    await ensureReady();
    yield* _repo.watchAdsByAuthor(userPhone);
  }
}
