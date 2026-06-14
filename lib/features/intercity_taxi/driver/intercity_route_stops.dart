/// `intercity_drivers` ҳужжатидан тўлиқ маршрут нуқталарини олиш.
List<String> intercityRouteStopsFromTrip(Map<String, dynamic>? trip) {
  if (trip == null) return const [];
  final raw = trip['stops'];
  if (raw is List && raw.isNotEmpty) {
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  final from = (trip['from'] as String? ?? '').trim();
  final to = (trip['to'] as String? ?? '').trim();
  if (from.isNotEmpty && to.isNotEmpty) return [from, to];
  return const [];
}
