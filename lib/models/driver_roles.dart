/// Фойдаланувчининг ҳайдовчилик/курьерлик ҳолати — индикатор (профиль чипи,
/// «＋» меню, бош экран тасмаси) учун. Ҳуқуқ манбаи: `provider_capabilities`;
/// «фаол» — шу тур бўйича ҳозир иш бораётгани (шаҳарлараро: фаол рейс;
/// маҳаллий/маршрут: онлайн; курьер: `provider_presence.isOnline`).
class DriverRoles {
  const DriverRoles({
    this.types = const [],
    this.active = const {},
    this.courierOnline = false,
    this.courierStatus = '',
  });

  static const none = DriverRoles();

  /// Ишлайдиган ҳолатдаги (`starter`/`verification_required`/`verified`)
  /// тур декларациялари: `intercity`, `local`, `marshrut` — шу тартибда.
  final List<String> types;

  /// `types` ичидан ҳозир ФАОЛлари.
  final Set<String> active;

  /// Курьер ҳозир онлайн.
  final bool courierOnline;

  /// `provider_capabilities.status.courier` (`not_registered`, `applied`,
  /// `trial`…); бўш — ҳолат ўқилмаган.
  final String courierStatus;

  bool get isDriver => types.isNotEmpty;
  bool get hasActive => active.isNotEmpty;
  bool isActive(String type) => active.contains(type);

  /// Бош экран тасмаси учун: ҳайдовчилик ёки курьерлик фаол.
  bool get hasAnyActiveRole => hasActive || courierOnline;
}
