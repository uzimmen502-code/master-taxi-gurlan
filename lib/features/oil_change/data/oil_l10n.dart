// Oil modul uchun 3 tilli (uz_Cyrl / uz_Latn / ru) kontent yordamchisi.
//
// Og'ir ma'lumot kontenti (maqolalar, SAE qo'llanma, kilometraj) l10n JSON
// kalitlariga sig'maydi — shuning uchun matn shu yerda `L3` ichida co-located
// saqlanadi va joriy locale bo'yicha tanlanadi.

import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';

enum OilLang { cyrl, latn, ru }

/// Joriy locale bo'yicha oil tilini aniqlaydi.
OilLang oilLangOf(BuildContext context) {
  final loc = AppLocalizations.of(context)?.locale;
  if (loc == null) return OilLang.cyrl;
  switch (loc.languageCode) {
    case 'ru':
      return OilLang.ru;
    case 'uz':
      return loc.scriptCode == 'Latn' ? OilLang.latn : OilLang.cyrl;
    default:
      return OilLang.cyrl;
  }
}

/// Uch tilli matn bo'lagi.
class L3 {
  const L3(this.cyrl, this.latn, this.ru);
  final String cyrl;
  final String latn;
  final String ru;

  String t(OilLang l) => switch (l) {
        OilLang.cyrl => cyrl,
        OilLang.latn => latn,
        OilLang.ru => ru,
      };
}
