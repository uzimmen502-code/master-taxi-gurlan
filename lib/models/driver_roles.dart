/// Фойдаланувчининг ҳайдовчилик ҳолати — индикатор (профиль чипи, «＋» меню)
/// учун. Ҳуқуқ манбаи: `provider_capabilities`; «фаол» — шу тур бўйича
/// ҳозир иш бораётгани (шаҳарлараро: фаол рейс; маҳаллий/маршрут: онлайн).
class DriverRoles {
  const DriverRoles({this.types = const [], this.active = const {}});

  static const none = DriverRoles();

  /// Ишлайдиган ҳолатдаги (`starter`/`verification_required`/`verified`)
  /// тур декларациялари: `intercity`, `local`, `marshrut` — шу тартибда.
  final List<String> types;

  /// `types` ичидан ҳозир ФАОЛлари.
  final Set<String> active;

  bool get isDriver => types.isNotEmpty;
  bool get hasActive => active.isNotEmpty;
  bool isActive(String type) => active.contains(type);
}
