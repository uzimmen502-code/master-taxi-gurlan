# shared/widgets/

**Ko'p featureda ishlatiladigan** widget'lar.

## Qoidalar:
1. Faqat **business logic'siz** UI komponentlari (tugma, dialog, kartochka, empty state).
2. Repository yoki Service'ga bog'liq emas — kerakli ma'lumot `props` (constructor) orqali kiradi.
3. Bitta widget faqat bitta featureda ishlatilsa — uni `features/<feature_name>/widgets/` ichida saqlash kerak, bu yerga **emas**.

## Hozir planlangan widgetlar:
- `AppButton` — yagona stildagi tugma
- `AppDialog` / `ConfirmDialog`
- `EmptyState`
- `RatingStars`
- `LoadingOverlay`
- `PhoneField` — telefon kiritish uchun
