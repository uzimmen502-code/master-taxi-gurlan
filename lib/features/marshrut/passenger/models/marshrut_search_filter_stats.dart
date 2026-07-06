/// Marshrut qidiruv filtrlash statistikasi — kam natija sabablari.
class MarshrutSearchFilterStats {
  const MarshrutSearchFilterStats({
    this.totalActive = 0,
    this.shown = 0,
    this.offline = 0,
    this.full = 0,
    this.routeMismatch = 0,
    this.expired = 0,
    this.tooFar = 0,
  });

  final int totalActive;
  final int shown;
  final int offline;
  final int full;
  final int routeMismatch;
  final int expired;
  final int tooFar;

  int get hidden => offline + full + routeMismatch + expired + tooFar;

  bool get hasHiddenReasons => hidden > 0;
}
