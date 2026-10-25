/// AVA расмий Instagram / Facebook / YouTube / Telegram —
/// фойдаланувчи чипи = қайси саҳифа.
///
/// TikTok олиб ташланди (эга қарори, 2026-09-24). Эски клипларда
/// `socialNetworks: ['tiktok']` учраши мумкин — [parse] уни энди
/// эътиборга олмайди, шунчаки ташлаб кетади.
class TvSocial {
  TvSocial._();

  static const instagram = 'instagram';
  static const facebook = 'facebook';
  static const youtube = 'youtube';
  static const telegram = 'telegram';
  static const ordered = [instagram, facebook, youtube, telegram];

  /// Пуллик реклама (`category == 'ad'`) учун МАЖБУРИЙ тармоқлар — эга
  /// чекбокс танламайди, тўлов қилинган заҳоти шуларга чиқади. YouTube
  /// ад ичига кирмайди (алгоритм спам сифатида белгилаши хавфи).
  static const adForced = [instagram, facebook, telegram];

  /// «Рухсат бераман» матни версияси (7-босқич, 2026-10-25) — клипга `socialConsentVersion`
  /// бўлиб ёзилади; матн маъноси ўзгарса оширилади. Сервер биринчи жойлашда уни
  /// `socialPost.consent`га ўзгармас қилиб кўчиради.
  static const consentVersion = 1;

  /// Пуллик реклама: тўловдан олдин кўрсатилган «реклама AVA тармоқларига ҳам чиқади»
  /// огоҳлантириши версияси (`publishTvAd` → `socialNoticeVersion`).
  static const adNoticeVersion = 1;

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
