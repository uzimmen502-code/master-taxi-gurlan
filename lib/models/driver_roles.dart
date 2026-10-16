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
    this.taxiStatus = '',
    this.starterEndsAt,
    this.agreementAccepted = false,
    this.known = false,
  });

  /// Ҳуқуқ ҳолати ҲАҚИҚАТАН ўқилдими. Ўқишда хато бўлса `false` — бундай
  /// натижадан «ҳайдовчи эмас» деб хулоса чиқарилмайди (аудитория белгиси
  /// тасодифий узилишда йўқолиб қолмасин).
  final bool known;

  /// Такси келишуви қабул қилинганми (`service_agreements/{accountId}.taxi`).
  /// Фақат кўрсатиш учун ишора: «текширувга юбориш»да ҳал қилувчи — сервер
  /// (`requestCapability.agreementRequired`), версияни ҳам у айтади.
  final bool agreementAccepted;

  static const none = DriverRoles();

  /// `provider_capabilities.status.taxi` (`starter`, `verification_required`,
  /// `verified`, `suspended`…); бўш — ўқилмаган ёки ҳайдовчи эмас.
  final String taxiStatus;

  /// `window.taxi.verificationDueAt` — 4 ойлик starter тугайдиган сана
  /// (сервер ёзган; фақат `starter` ҳолатида маъноли).
  final DateTime? starterEndsAt;

  /// Starter тугашига қолган тўлиқ кунлар (`now` дан), мусбат бўлса.
  int? starterDaysLeft(DateTime now) {
    final end = starterEndsAt;
    if (taxiStatus != 'starter' || end == null) return null;
    final left = end.difference(now);
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil();
  }

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
