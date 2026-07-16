# Moy almashtirish (`oil_change`)

## Maqsad
Foydalanuvchi mashinasidan moy muddatini kuzatadi, tarix yuritadi, punkt/narx ko‘radi. Mashina manbasi — **profil** (`users.car*`) + `users/{uid}/vehicles`.

## Kirish (YAGONA)
**Home grid** → `oil_change` (enabled) → **`OilChangeHomeScreen`**.
Boshqa parallel home entry yo‘q. HTML prototip (source of truth): `docs/oil_change_app.html`.

## Flutter ekranlar
- `OilChangeHomeScreen` — asosiy hub (avto + hajm, DOCTOR OIL, gallery, narx/sifat tavsiya, linklar)
- `OilCarSetupScreen` — 2-step sozlash
- `OilGalleryScreen`, `OilTypesScreen` — `oil_car_setup_screen.dart` ichida
- `OilRefScreen` — «Билиб қўйган яхши»: «Мой ҳақида» tab = SAE qo'llanma (akkordeon + qiyosiy jadval) + 3 katalog tab (full/semi/mineral)
- `OilVehicleEditScreen` — odometr/kuzatuv
- `OilHistoryScreen`, `OilServicesScreen`, `OilPricesScreen`
- `OilBookingScreen` — O'CHIRILDI (dead edi). Repo'da `createBooking`/`watchMyBookings` + `OilBooking` model latent qoldi (UI yo'q).

## Data fayllar (bitta manba — chalkashmaslik uchun)
- `data/oil_catalog.dart` — sotuv katalogi (`OilProduct`) + reco mantig'i + `OilTypeInfo`. Hub shuni ishlatadi.
- `data/oil_car_data.dart` — avto faktlari: `OilModelCapacity`+`modelCapacities`+`resolveCapacity`, `MileageReco`+`mileageRecos`. Hub shuni ishlatadi.
- `data/oil_ref_catalog.dart` — SAE ma'lumotnoma: `OilRefProduct` (90 mahsulot), `SaeGuideEntry`+`saeGuide`+`saeCompareRows`, `modelRecos`. Faqat `OilRefScreen` ishlatadi.
- `data/oil_type_article.dart` — «Мой турлари» detal maqolalari (mineral/semi/full), blok-asosli model (`OilArtBlock` + turlari) + `OilTypeArticleView` renderer. Manba: HTML `TYPE_DETAILS`. `showOilTypeDetail` (oil_hub_widgets) shuni ochadi (DraggableScrollableSheet).
- Muhim: hub endi `oil_ref_catalog.dart` ga bog'liq EMAS (hajm/mileage `oil_car_data.dart` da).
- `data/oil_l10n.dart` — 3 tilli kontent yordamchisi: `class L3(cyrl, latn, ru)` + `oilLangOf(context)` (`AppLocalizations.locale` → OilLang). Og'ir kontent (maqola/SAE/mileage/legenda) endi to'liq 3 tilli: `mileageRecos`, `SaeGuideEntry` maydonlari, `saeCompareRows`, `OilArtBlock` matnlari, `oil_hub_widgets` legendasi — hammasi `L3` va `.t(lang)` orqali renderlanadi (JSON kalit emas, co-located).
- Qisqa UI matnlar (SAE bo'lim sarlavha/label, km suffix, key-tip label, tier/km) esa l10n kalit orqali. Oil l10n kalitlarining SOURCE OF TRUTH: `tools/merge_oil_l10n.py` (KEYS dict → 3 JSON). JSON'ni qo'lda emas, shu skript orqali yangilang (`py tools\merge_oil_l10n.py`). Windows'da `python` Store-alias — `py` ishlating.
- Onboarding car step (`onboarding_screen.dart`, `_pageCar`/`_obCarStep1`/`_obCarStep2`) endi to'liq 3 tilli: `context.tr` orqali. `OilCarOptions.fuels/usages` endi `List<String>` (faqat kalit: petrol/cng/lpg, personal/taxi/corp/dust/long); label `oil_fuel_${key}`/`oil_usage_${key}`, boshqa label/hint/sarlavhalar `onb_car_*` kalitlar (SOURCE OF TRUTH: `merge_oil_l10n.py`). `oil_car_options.dart` da endi hardcoded uz_Cyrl label yo'q.

## Collections
- `users/{uid}/vehicles/{id}` (+ oil_history)
- `oil_change_catalog`, `oil_change_services`, `oil_change_bookings`
- `settings/oil_change`, `car_profile_bonus_claims` (CF)

## CF
- `claimCarProfileBonus`
