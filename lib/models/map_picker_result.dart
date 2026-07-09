/// Xaritada tanlangan nuqta — matn + aniq koordinata.
class MapPickerResult {
  const MapPickerResult({
    required this.lat,
    required this.lng,
    required this.label,
  });

  final double lat;
  final double lng;
  final String label;
}
