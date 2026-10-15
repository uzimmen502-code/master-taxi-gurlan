import '../../models/driver_roles.dart';

/// «Текширув» карточкасининг ҳолати — фақат КЎРСАТИШ учун соф функция.
/// Ҳуқуқни ва ўтишларни сервер ҳал қилади (`capabilities_model.js`:
/// starter → verification_required — фақат тизим, → verified — фақат админ).
enum HubVerifKind {
  /// Ҳайдовчи эмас — карточка кўрсатилмайди.
  none,

  /// Бепул давр тугашига ≤ [hubVerifEndingDays] кун.
  ending,

  /// Давр тугади, келишув ҳали қабул қилинмаган — «Текширувга юбориш».
  requiredToSubmit,

  /// Келишув қабул қилинган, админ текшируви кутилмоқда.
  requiredPending,

  verified,
  suspended,
}

/// «Текширув» карточкаси иш панелида кўринадими. Эга қарори (2026-10-15):
/// матн ва майдонча кўздан ЯШИРИЛСИН — код сақланади (қайта ёқиш учун битта
/// ўзгартириш). Яширинганда ҳам сервер келишувни пуллик рейс олдидан ўзи
/// тақдим қилади (`ensureTaxiCapability`), шунинг учун йўл бекилмайди.
const bool hubShowVerification = false;

/// Огоҳлантириш чегараси. Сервердаги `STARTER_NOTICE_DAYS` (taxi_billing.js)
/// билан бир хил: бу ерда фақат рангни/матнни танлайди, ҳуқуқ бермайди.
const int hubVerifEndingDays = 3;

HubVerifKind hubVerifKind(DriverRoles r, DateTime now) {
  switch (r.taxiStatus) {
    case 'starter':
      final days = r.starterDaysLeft(now);
      // Бепул давр узоқ бўлса ҳеч нарса кўрсатилмайди — «N кун қолди» ҳайдовчини
      // қўрқитади (эга, 2026-10-15). Фақат охирги [hubVerifEndingDays] кунда.
      if (days == null) return HubVerifKind.none;
      return days <= hubVerifEndingDays ? HubVerifKind.ending : HubVerifKind.none;
    case 'verification_required':
      return r.agreementAccepted
          ? HubVerifKind.requiredPending
          : HubVerifKind.requiredToSubmit;
    case 'verified':
      return HubVerifKind.verified;
    case 'suspended':
      // `types` бу ҳолатда бўш (ишламайдиган статус) — `taxiStatus` ўзи етарли.
      return HubVerifKind.suspended;
    default:
      return HubVerifKind.none;
  }
}
