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

  suspended,
}

/// «Текширув» карточкаси иш панелида кўринадими (умумий калит). Эга қарори
/// (2026-10-15): бепул давр узоқ бўлса — ЯШИРИН ([hubVerifKind] `none`);
/// кўринади: тугашига ≤ 3 кун қолганда, текширув талаб қилинганда ва
/// тўхтатилганда. Тасдиқланган ҳайдовчига ҳам кўрсатилмайди. Калитни `false`
/// қилиш карточкани бутунлай ўчиради (код сақланади).
const bool hubShowVerification = true;

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
      // Тасдиқланган — кўрсатиладиган нарса йўқ (эга: фақат 3 ҳолатда чиқсин).
      return HubVerifKind.none;
    case 'suspended':
      // `types` бу ҳолатда бўш (ишламайдиган статус) — `taxiStatus` ўзи етарли.
      return HubVerifKind.suspended;
    default:
      return HubVerifKind.none;
  }
}
