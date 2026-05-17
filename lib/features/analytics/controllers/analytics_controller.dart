import 'package:flutter/foundation.dart';

import '../../../models/analytics/daily_report.dart';
import '../../../models/analytics/driver_analytics.dart';
import '../../../models/analytics/finance_analytics.dart';
import '../../../models/analytics/kpi_summary.dart';
import '../../../models/analytics/operations_analytics.dart';
import '../../../models/analytics/user_analytics.dart';
import '../../../repositories/analytics_repository.dart';
import '../../../services/daily_report_service.dart';

/// Аналитика марказининг асосий controller'и — барча табларнинг маълумоти.
///
/// Lazy yuklash: ҳар таб биринчи марта очилганда тегишли `fetch...` чақирилади.
class AnalyticsController extends ChangeNotifier {
  AnalyticsController({
    required AnalyticsRepository repo,
    required DailyReportService reportService,
  })  : _repo = repo,
        _reportService = reportService;

  final AnalyticsRepository _repo;
  final DailyReportService _reportService;

  KpiSummary? kpiSummary;
  UserAnalytics? userAnalytics;
  DriverAnalytics? driverAnalytics;
  OperationsAnalytics? operationsAnalytics;
  FinanceAnalytics? financeAnalytics;
  DailyReport? todayReport;
  List<DailyReport> historicalReports = const [];

  bool kpiLoading = false;
  bool usersLoading = false;
  bool driversLoading = false;
  bool operationsLoading = false;
  bool financeLoading = false;
  bool reportsLoading = false;

  /// **Per-tab errors** — ҳар бир таб ўз хатоси билан ишлайди, бошқа табларга
  /// xato yuqтиrmayди. Эски умумий `error` майдони барча табларга бир хил
  /// xato ko'rsатaр edi (масалaн, `loadReports` xato bo'lsa, dashboard ҳам
  /// "Reports: ..." кўрсaтар edi).
  String? kpiError;
  String? usersError;
  String? driversError;
  String? operationsError;
  String? financeError;
  String? reportsError;

  /// Кенг сафари — барча тiplerga xato bo'lsa, ozгина чекилган xato qaытariш.
  /// UI uchun кам qulay, lekin backward-compatibility.
  String? get error =>
      kpiError ??
      usersError ??
      driversError ??
      operationsError ??
      financeError ??
      reportsError;

  // ─── KPI dashboard ──────────────────────────────────────────────────
  Future<void> loadKpis({bool force = false}) async {
    if (kpiLoading) return;
    if (kpiSummary != null && !force) return;
    kpiLoading = true;
    kpiError = null;
    notifyListeners();
    try {
      kpiSummary = await _repo.fetchKpiSummary();
    } catch (e) {
      kpiError = 'KPI: $e';
    } finally {
      kpiLoading = false;
      notifyListeners();
    }
  }

  // ─── Users ─────────────────────────────────────────────────────────
  Future<void> loadUsers({bool force = false}) async {
    if (usersLoading) return;
    if (userAnalytics != null && !force) return;
    usersLoading = true;
    usersError = null;
    notifyListeners();
    try {
      userAnalytics = await _repo.fetchUserAnalytics();
    } catch (e) {
      usersError = 'Users: $e';
    } finally {
      usersLoading = false;
      notifyListeners();
    }
  }

  // ─── Drivers ───────────────────────────────────────────────────────
  Future<void> loadDrivers({bool force = false}) async {
    if (driversLoading) return;
    if (driverAnalytics != null && !force) return;
    driversLoading = true;
    driversError = null;
    notifyListeners();
    try {
      driverAnalytics = await _repo.fetchDriverAnalytics();
    } catch (e) {
      driversError = 'Drivers: $e';
    } finally {
      driversLoading = false;
      notifyListeners();
    }
  }

  // ─── Operations ────────────────────────────────────────────────────
  Future<void> loadOperations({bool force = false}) async {
    if (operationsLoading) return;
    if (operationsAnalytics != null && !force) return;
    operationsLoading = true;
    operationsError = null;
    notifyListeners();
    try {
      operationsAnalytics = await _repo.fetchOperationsAnalytics();
    } catch (e) {
      operationsError = 'Ops: $e';
    } finally {
      operationsLoading = false;
      notifyListeners();
    }
  }

  // ─── Finance ──────────────────────────────────────────────────────
  Future<void> loadFinance({bool force = false}) async {
    if (financeLoading) return;
    if (financeAnalytics != null && !force) return;
    financeLoading = true;
    financeError = null;
    notifyListeners();
    try {
      financeAnalytics = await _repo.fetchFinanceAnalytics();
    } catch (e) {
      financeError = 'Finance: $e';
    } finally {
      financeLoading = false;
      notifyListeners();
    }
  }

  // ─── Daily reports ─────────────────────────────────────────────────
  Future<void> loadReports({bool force = false}) async {
    if (reportsLoading) return;
    if (historicalReports.isNotEmpty && !force) return;
    reportsLoading = true;
    reportsError = null;
    notifyListeners();
    try {
      final today = DateTime.now();
      final key = DailyReportService.dateKeyFor(today);
      todayReport = await _repo.getDailyReport(key);
      historicalReports = await _repo.recentDailyReports(limit: 30);
    } catch (e) {
      reportsError = 'Reports: $e';
    } finally {
      reportsLoading = false;
      notifyListeners();
    }
  }

  Future<void> regenerateTodayReport() async {
    reportsLoading = true;
    reportsError = null;
    notifyListeners();
    try {
      todayReport = await _reportService.forceRegenerate();
      historicalReports = await _repo.recentDailyReports(limit: 30);
    } catch (e) {
      reportsError = 'Regenerate: $e';
    } finally {
      reportsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      loadKpis(force: true),
      loadUsers(force: true),
      loadDrivers(force: true),
      loadOperations(force: true),
      loadFinance(force: true),
      loadReports(force: true),
    ]);
  }
}
