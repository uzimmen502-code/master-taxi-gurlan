# Moy almashtirish (`oil_change`)

## Maqsad
Foydalanuvchi mashinasidan moy muddatini kuzatadi, tarix yuritadi, punkt/narx ko‘radi, bron qiladi. Mashina manbasi — **profil** (`users.car*`) + `users/{uid}/vehicles`.

## MVP qamrov (Must + Should + #14)
- Mashina (profil sync), odometr, moy turi, oxirgi sana, keyingi muddat (+5000 km yoki +6 oy)
- Asosiy holat kartasi (yashil/sariq/qizil + matn), tarix, lokal push eslatma
- Narx paketlari (`settings/oil_change.packages` yoki default), servis punktlari, bron
- Ko‘p mashina (oddiy), profil avto bonus (`claimCarProfileBonus`, default 5000)

## Collections
- `users/{uid}/vehicles/{id}` — model,color,plate,brand,year,engine,fuelType,usageTags[],seats,oilType,lastChangedAt,last/currentOdometerKm,intervalKm/Months,isPrimary
- `users/{uid}/vehicles/{id}/oil_history/{id}`
- `users/{uid}/car_profile_bonus_claims/v1` — CF-only
- `oil_change_services/{id}` — admin write
- `oil_change_bookings/{id}`
- `oil_change_catalog/{id}` — admin catalog (kind oil|filter, name, meta, price, reason, imageUrl, specs, sortOrder, active, must/dust/gas); Storage `oil_images/`
- `settings/oil_change` — packages[], carProfileBonusAmount

## Flutter
- `lib/models/oil_vehicle.dart` (+ brand, engine, fuelType, usageTags), repo, service
- Hub UX (proto B): `OilChangeHomeScreen` — car status cell → «DOCTOR OIL» bars → gallery preview → ranked 1/2/3 (+ filter bundle) → book/history
- Bars ticker: **parallel** 20s cycle; range bars (mineral/semi/full) with safe flag+car
- **OilGalleryScreen**: TabBar **Мойлар | Фильтрлар**, each tab vertical GridView (2 cols)
- Catalog: static `data/oil_catalog.dart` + Firestore `oil_change_catalog` via `OilCatalogRepository`
- Admin: `OilCatalogAdminScreen` — seed, CRUD, image → Storage `oil_images/`
- Reference: static `data/oil_ref_catalog.dart` + `OilRefScreen` (Tavsiya first + gate)
- **Unified HTML:** `docs/oil_change_app.html`
- Home grid: oil_change after bread; module must be `enabled` in `config/module_defaults` when enforce=true
- Onboarding: optional car + claimCarProfileBonus

## CF
- `claimCarProfileBonus` — auth; car complete; idempotent v1; ledger bonus

## Later
Onlayn navbat, QR chek, analitika.
