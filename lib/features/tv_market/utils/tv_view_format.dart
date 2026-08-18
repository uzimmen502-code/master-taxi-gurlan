/// Ko‘rish sonini qisqa format (3240 → 3.2K).
String tvFormatViewCount(int n) {
  if (n <= 0) return '0';
  if (n >= 1000000) {
    final v = n / 1000000;
    return v >= 10 ? '${v.round()}M' : '${v.toStringAsFixed(1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return v >= 10 ? '${v.round()}K' : '${v.toStringAsFixed(1)}K';
  }
  return '$n';
}
