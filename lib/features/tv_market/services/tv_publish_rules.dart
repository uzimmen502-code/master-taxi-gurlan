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
}
