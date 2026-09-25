import '../../core/theme/ava_tokens.dart';

/// AVA дўкони палитраси — [AvaColors] токенларининг шу модулдаги номлари.
///
/// Илгари бу ерда неон-бирюза (#00FFFF) алоҳида бренд ранги эди; янги
/// дизайн тизимида битта бренд ранги бўлгани учун у олиб ташланди.
abstract final class AvaStoreColors {
  /// Бренд.
  static const brand = AvaLight.brand;

  /// Бренд фони устидаги матн.
  static const onBrand = AvaLight.brandInk;

  /// Юмшоқ фон / карточка.
  static const soft = AvaLight.brandSoft;

  /// Бир оз тўйинган fill.
  static const softFill = AvaLight.brandSoft;

  /// Акцент / нарх / иконка.
  static const deep = AvaLight.brand;

  /// Экран фони.
  static const scaffold = AvaLight.bg;

  /// Асосий матн.
  static const ink = AvaLight.ink;

  /// Иккинчи даража матн.
  static const muted = AvaLight.ink2;

  /// Карточка юзаси.
  static const surface = AvaLight.surface;

  /// Чизиқ / чегара.
  static const border = AvaLight.line;
}
