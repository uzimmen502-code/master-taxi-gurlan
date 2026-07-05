/// Marshrut yo'nalishi: MFY dan → MFY ga.
class MarshrutRoutePair {
  const MarshrutRoutePair({required this.from, required this.to});

  final String from;
  final String to;

  String get key => '$from|$to';

  @override
  bool operator ==(Object other) =>
      other is MarshrutRoutePair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
