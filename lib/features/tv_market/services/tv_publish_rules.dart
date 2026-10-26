import 'tv_social.dart';

/// Видео жойлаш экрани ([TvPublishScreen]) қоидалари — СОФ мантиқ (тестланади).
/// Экран шу қоидаларни чақиради, ўзи такрор ёзмайди (7-қоида).
abstract final class TvPublishRules {
  /// «Дўкон» режими: товар расмлари + `tv_shop_items` ёзуви керак бўладими.
  ///
  /// [hideShopOption] (ресторан/эълон/Улгуржи видеоси) бўлса дўкон блоки
  /// кўринмайди — режим ҲАМ ўчиқ бўлиши шарт. Аввал бу ҳисобга олинмасди:
  /// аввал дўкон очган фойдаланувчида `_openShop` ўзи `true` бўлиб қолиб,
  /// «расм қўшинг» хатоси чиқарди, расм қўшиш жойи эса экранда йўқ эди —
  /// жойлаб бўлмасди.
  static bool shopMode({
    required bool isAd,
    required bool isNews,
    required bool openShop,
    required String attachItemId,
    required bool hideShopOption,
  }) =>
      !hideShopOption && !isAd && !isNews && (openShop || attachItemId.isNotEmpty);

  /// Тур сегменти («Товар/Хизмат/…») кўринадими.
  ///
  /// [organicOnly] (бошқа нарсага боғланган видео) да тур `linkKind`дан
  /// аниқ: ресторан/бозор → `product`, хизмат → `service`. Эгадан сўраш
  /// ортиқча ва хато бўлар эди (ресторан видеоси «Хизмат» бўлиб ёзиларди).
  static bool showCategorySelector({
    required bool categoryLocked,
    required bool organicOnly,
  }) =>
      !categoryLocked && !organicOnly;

  /// [organicOnly] режимида клип тури.
  static String organicCategory(String linkKind) =>
      linkKind == 'service' ? 'service' : 'product';

  /// AVA расмий тармоқларига жойлаш (7-босқич, 2026-10-25): тармоқ танланган, лекин
  /// «Рухсат бераман» белгиланмаган — жойлаш тўхтатилади. Пуллик рекламада чип йўқ
  /// (тармоқлар мажбурий, тўловдан олдин огоҳлантирилади) — текширилмайди.
  static bool socialConsentMissing({
    required String category,
    required Set<String> networks,
    required bool consentChecked,
  }) =>
      category != 'ad' && networks.isNotEmpty && !consentChecked;

  /// Клипга розилик билан бирга ёзиладиган майдонлар. Вақт — фақат сервер вақти
  /// (қоида `request.time` талаб қилади), шунинг учун [serverTime] ташқаридан берилади.
  static Map<String, Object> socialConsentFields({
    required Set<String> networks,
    required int version,
    required Object serverTime,
  }) =>
      networks.isEmpty
          ? const {}
          : {'socialConsentAt': serverTime, 'socialConsentVersion': version};

  /// «Менинг каналим» (сотувчининг ўз Telegram канали, 2026-10-25) таклиф қилинадими: канал уланган ва видео
  /// товар/хизмат (янгилик ва пуллик рекламада йўқ — сервер ҳам фақат шуларни жойлайди).
  static bool sellerChannelOffered({required String category, required bool channelConnected}) =>
      channelConnected && (category == 'product' || category == 'service');

  /// Клипга ёзиладиган тармоқлар: «Менинг каналим» таклиф қилинмаса (тур ўзгарди ёки канал узилган) — олиб ташланади.
  static Set<String> effectiveSocialNetworks(Set<String> picked, {required bool sellerChannelOffered}) =>
      sellerChannelOffered ? {...picked} : {for (final id in picked) if (id != TvSocial.sellerTelegram) id};

  /// Розилик матни версияси: «Менинг каналим» танланса матн канални айтади — 2, акс ҳолда 1.
  static int socialConsentVersion(Set<String> networks) => networks.contains(TvSocial.sellerTelegram)
      ? TvSocial.sellerChannelConsentVersion
      : TvSocial.consentVersion;
}
