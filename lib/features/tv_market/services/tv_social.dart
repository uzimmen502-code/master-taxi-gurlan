/// AVA расмий Instagram / Facebook / TikTok / YouTube / Telegram —
/// фойдаланувчи чипи = қайси саҳифа.
class TvSocial {
  TvSocial._();

  static const instagram = 'instagram';
  static const facebook = 'facebook';
  static const tiktok = 'tiktok';
  static const youtube = 'youtube';
  static const telegram = 'telegram';
  static const ordered = [instagram, facebook, tiktok, youtube, telegram];

  /// Пуллик реклама (`category == 'ad'`) учун МАЖБУРИЙ тармоқлар — эга
  /// чекбокс танламайди, тўлов қилинган заҳоти шуларга чиқади. TikTok/
  /// YouTube ад ичига кирмайди (алгоритм спам сифатида белгилаши хавфи).
  static const adForced = [instagram, facebook, telegram];

  static String labelKey(String id) => 'tv_social_$id';

  static List<String> parse(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final id = '$e'.trim().toLowerCase();
      if (ordered.contains(id) && !out.contains(id)) out.add(id);
    }
    return out;
  }
}
