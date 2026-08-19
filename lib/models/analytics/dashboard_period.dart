/// Monitoring Center → Dashboard давр фильтри.
enum DashboardPeriod {
  today,
  days7,
  days15,
  days30,
  allTime,
}

extension DashboardPeriodX on DashboardPeriod {
  String get chipLabel {
    switch (this) {
      case DashboardPeriod.today:
        return 'Бугун';
      case DashboardPeriod.days7:
        return '7 кун';
      case DashboardPeriod.days15:
        return '15 кун';
      case DashboardPeriod.days30:
        return '30 кун';
      case DashboardPeriod.allTime:
        return 'Бугунгача';
    }
  }

  String get titleLabel {
    switch (this) {
      case DashboardPeriod.today:
        return 'Бугун';
      case DashboardPeriod.days7:
        return 'Охирги 7 кун';
      case DashboardPeriod.days15:
        return 'Охирги 15 кун';
      case DashboardPeriod.days30:
        return 'Охирги 30 кун';
      case DashboardPeriod.allTime:
        return 'Бугунгача';
    }
  }

  /// Инклюзив [from, to] — ҳар иккиси ҳам кун боши (local).
  (DateTime from, DateTime to) range(DateTime now) {
    final today0 = DateTime(now.year, now.month, now.day);
    switch (this) {
      case DashboardPeriod.today:
        return (today0, today0);
      case DashboardPeriod.days7:
        return (today0.subtract(const Duration(days: 6)), today0);
      case DashboardPeriod.days15:
        return (today0.subtract(const Duration(days: 14)), today0);
      case DashboardPeriod.days30:
        return (today0.subtract(const Duration(days: 29)), today0);
      case DashboardPeriod.allTime:
        return (DateTime(2024, 1, 1), today0);
    }
  }

  (DateTime from, DateTime to)? previousRange(DateTime now) {
    if (this == DashboardPeriod.allTime) return null;
    final (from, to) = range(now);
    final len = to.difference(from).inDays + 1;
    final prevTo = from.subtract(const Duration(days: 1));
    final prevFrom = prevTo.subtract(Duration(days: len - 1));
    return (prevFrom, prevTo);
  }

  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return DateTime(2024, 1, 1);
    return DateTime(
      int.tryParse(parts[0]) ?? 2024,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }
}
