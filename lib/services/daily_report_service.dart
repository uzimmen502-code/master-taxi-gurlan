import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/analytics/daily_report.dart';
import '../repositories/analytics_repository.dart';

/// Бугунги ҳисоботни **20:00 да** генерация қилувчи сервис.
///
/// Ишлаш стратегияси:
/// 1. Илова очилганда `ensureToday()` чақирилади.
/// 2. Агар бугун соат 20:00 ёки ундан кейин ва бугунги ҳисобот ҳали
///    сақланмаган бўлса — генерация қилинади.
/// 3. Тахминан соат 20:00 га яқинроқ давр кутaётган `Timer` ўрнатилади.
/// 4. Cloud Function (server-side, scheduled) асосий чегарадан кафолатловчи
///    дублирующий механизм бўлади.
class DailyReportService {
  DailyReportService(this._repo);

  final AnalyticsRepository _repo;

  static const _lastGeneratedKey = 'last_daily_report_key';
  static const reportHour = 20;

  Timer? _timer;
  bool _disposed = false;

  static String dateKeyFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Илова стартида чақирилади — соат 20:00 ўтган бўлса дарҳол генерация.
  Future<void> ensureToday() async {
    final now = DateTime.now();
    if (now.hour >= reportHour) {
      await _generateIfNeeded();
    }
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (_disposed) return;
    final now = DateTime.now();
    DateTime target =
        DateTime(now.year, now.month, now.day, reportHour, 0, 0);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    final delay = target.difference(now);
    _timer = Timer(delay, () async {
      await _generateIfNeeded();
      _scheduleNext();
    });
  }

  Future<DailyReport?> _generateIfNeeded() async {
    final today = DateTime.now();
    final key = dateKeyFor(today);
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastGeneratedKey);
    if (last == key) return null;
    try {
      final existing = await _repo.getDailyReport(key);
      if (existing != null) {
        // Cloud Function аллақачон ясаб қўйган
        await prefs.setString(_lastGeneratedKey, key);
        return existing;
      }
      final report = await _repo.generateAndSaveDailyReport(at: today);
      await prefs.setString(_lastGeneratedKey, key);
      return report;
    } catch (_) {
      return null;
    }
  }

  /// Қўлда мажбурий қайта-ясаш — масалан, "Янгилаш" тугмаси.
  Future<DailyReport> forceRegenerate() async {
    final report = await _repo.generateAndSaveDailyReport();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastGeneratedKey, dateKeyFor(DateTime.now()));
    return report;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
