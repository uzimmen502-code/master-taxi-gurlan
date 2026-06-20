/// Бош экрандаги битта модул карта тавсифи.
class HomeModule {
  const HomeModule({
    required this.id,
    required this.label,
    this.enabled = true,
  });

  /// Идентификатор — ҳаракат бошқарувида ишлатилади.
  final String id;

  /// `false` — вақтинча ёпилган; grid avtomatik qayta tuziladi.
  final bool enabled;
  final String label;
}
