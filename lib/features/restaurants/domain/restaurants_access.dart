// «Кафе-Ресторан» модулига кириш дарвозаси — БИТТА манба (бош экран
// бўлими ва курьер панели баннери шуни ишлатади, 7-қоида):
//   модул очиқ (`isOpenable`)            → ҳамма;
//   «Тез кунда»/«Ҳамкорлик» (`isVisible`) → фақат INTERNAL синовчи
//                                           (сервер `getRestaurantsAccess`);
//   яширин                                → йўқ.

import '../../../core/service_config_holder.dart';

const kRestaurantsModuleId = 'restaurants';

/// `accessCheck` — сервер синовчи текшируви ([RestaurantsRepository.hasAccess]);
/// фақат модул кўриниб, лекин очиқ бўлмаганда чақирилади.
Future<bool> resolveRestaurantsAccess({
  required Future<bool> Function() accessCheck,
}) async {
  if (ServiceConfigHolder.isOpenable(kRestaurantsModuleId)) return true;
  if (!ServiceConfigHolder.isVisible(kRestaurantsModuleId)) return false;
  return accessCheck();
}
