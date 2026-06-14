/// Marshrut MFY nuqtalari — dublikat tekshiruvi (boshlang'ich / o'rta / oxirgi).
class RoutePointsValidator {
  RoutePointsValidator._();

  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool samePoint(String a, String b) {
    if (a.trim().isEmpty || b.trim().isEmpty) return false;
    return normalize(a) == normalize(b);
  }

  /// `from` / `to` / `mid` — qaysi maydon uchun tekshirilayotgani.
  static String? duplicateMessage({
    required String candidate,
    required String from,
    required String to,
    required List<String> midStops,
    required String role,
  }) {
    final v = candidate.trim();
    if (v.isEmpty) return null;

    if (role == 'from') {
      if (samePoint(v, to)) {
        return 'Bu MFY allaqachon oxirgi nuqta sifatida tanlangan';
      }
      for (final mid in midStops) {
        if (samePoint(v, mid)) {
          return 'Bu MFY allaqachon o‘rta nuqta sifatida tanlangan';
        }
      }
      return null;
    }

    if (role == 'to') {
      if (samePoint(v, from)) {
        return 'Bu MFY allaqachon boshlang‘ich nuqta sifatida tanlangan';
      }
      for (final mid in midStops) {
        if (samePoint(v, mid)) {
          return 'Bu MFY allaqachon o‘rta nuqta sifatida tanlangan';
        }
      }
      return null;
    }

    if (samePoint(v, from)) {
      return 'Bu MFY allaqachon boshlang‘ich nuqta sifatida tanlangan';
    }
    if (samePoint(v, to)) {
      return 'Bu MFY allaqachon oxirgi nuqta sifatida tanlangan';
    }
    for (final mid in midStops) {
      if (samePoint(v, mid)) {
        return 'Bu nuqta allaqachon qo‘shilgan';
      }
    }
    return null;
  }

  /// Saqlashdan oldin — barcha nuqtalar noyobligi.
  static String? validateRoute({
    required String from,
    required String to,
    required List<String> midStops,
  }) {
    if (from.trim().isEmpty) return 'Boshlang‘ich nuqtani tanlang';
    if (to.trim().isEmpty) return 'Oxirgi nuqtani tanlang';

    final errFrom = duplicateMessage(
      candidate: from,
      from: '',
      to: to,
      midStops: midStops,
      role: 'from',
    );
    if (errFrom != null) return errFrom;

    final errTo = duplicateMessage(
      candidate: to,
      from: from,
      to: '',
      midStops: midStops,
      role: 'to',
    );
    if (errTo != null) return errTo;

    final seen = <String>{};
    for (final stop in [from, ...midStops, to]) {
      final key = normalize(stop);
      if (key.isEmpty) continue;
      if (seen.contains(key)) {
        return 'Marshrut nuqtalari takrorlanmasin';
      }
      seen.add(key);
    }
    return null;
  }
}
