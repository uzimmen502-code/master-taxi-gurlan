/// Bosh ekran modul sarlavhalari — uzun matnni 2 qatorga bo'lish.
class HomeModuleTitleLayout {
  HomeModuleTitleLayout._();

  /// Matn zonasi chap chegarasi (rasm | matn).
  static double textZoneLeftFraction(double cardWidth) {
    if (cardWidth < 340) return 0.25;
    if (cardWidth < 380) return 0.28;
    return 0.30;
  }

  /// Bo'shliqsiz uzun sarlavhani ikki qatorga (so'z bo'yicha, keyin belgi).
  static String splitTitleLines(String plain) {
    if (plain.contains('\n')) return plain;
    final trimmed = plain.trim();
    if (trimmed.isEmpty) return plain;

    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      final mid = (words.length / 2).ceil();
      return '${words.sublist(0, mid).join(' ')}\n${words.sublist(mid).join(' ')}';
    }

    if (trimmed.length <= 14) return plain;
    final mid = (trimmed.length / 2).ceil();
    return '${trimmed.substring(0, mid)}\n${trimmed.substring(mid)}';
  }
}
