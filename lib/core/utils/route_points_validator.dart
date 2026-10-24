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
  /// Qaytadigan qiymat — l10n KALITI (`rpv_*`); ekranda `context.trMsg(key)`.
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
        return 'rpv_dup_as_last';
      }
      for (final mid in midStops) {
        if (samePoint(v, mid)) {
          return 'rpv_dup_as_mid';
        }
      }
      return null;
    }

    if (role == 'to') {
      if (samePoint(v, from)) {
        return 'rpv_dup_as_first';
      }
      for (final mid in midStops) {
        if (samePoint(v, mid)) {
          return 'rpv_dup_as_mid';
        }
      }
      return null;
    }

    if (samePoint(v, from)) {
      return 'rpv_dup_as_first';
    }
    if (samePoint(v, to)) {
      return 'rpv_dup_as_last';
    }
    for (final mid in midStops) {
      if (samePoint(v, mid)) {
        return 'rpv_point_already_added';
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
    if (from.trim().isEmpty) return 'rpv_pick_first';
    if (to.trim().isEmpty) return 'rpv_pick_last';

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
        return 'rpv_points_must_differ';
      }
      seen.add(key);
    }
    return null;
  }
}
