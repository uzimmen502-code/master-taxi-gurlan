/// Вақт қаторидаги битта нуқта — кун/соат + қиймат + ёрлиқ.
class TimeSeriesPoint {
  const TimeSeriesPoint({
    required this.timestamp,
    required this.value,
    this.label,
  });

  final DateTime timestamp;
  final num value;
  final String? label;

  /// `HH:00` — соатлик қаторлар учун.
  String get hourLabel =>
      '${timestamp.hour.toString().padLeft(2, '0')}:00';

  /// `DD.MM` — кунлик қаторлар учун.
  String get dayLabel =>
      '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')}';

  /// `Душ`, `Сеш`... — ҳафталик кўриниш учун.
  String get weekdayLabel {
    const names = ['Душ', 'Сеш', 'Чор', 'Пай', 'Жум', 'Шан', 'Якш'];
    return names[(timestamp.weekday - 1) % 7];
  }
}

/// Бутун қатор — мисол: охирги 24 соатдаги буюртмалар, охирги 30 кунлик тушум.
class TimeSeries {
  const TimeSeries({
    required this.label,
    required this.points,
    this.unit = '',
  });

  final String label;
  final List<TimeSeriesPoint> points;
  final String unit;

  num get total => points.fold<num>(0, (a, p) => a + p.value);
  num get max => points.isEmpty
      ? 0
      : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
  num get min => points.isEmpty
      ? 0
      : points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
  double get average => points.isEmpty ? 0 : total.toDouble() / points.length;
}
