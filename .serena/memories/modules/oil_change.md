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
- Hub UX (proto B): `OilChangeHomeScreen` — AVA promise → car setup → oil types (animated bars) → gallery → ranked 1/2/3 (+ filter bundle) → book/history
- Bars ticker: **parallel** 20s cycle (all start together); km label 0→5k/7k/10k synced with flag fill; no «ихчам · босиб» hint.
- Catalog: static `data/oil_catalog.dart` + Firestore `oil_change_catalog` via `OilCatalogRepository` (app gallery fallback to static)
- Admin: `OilCatalogAdminScreen` — seed, CRUD, image → Storage `oil_images/` (sotuv katalogi only; rasm optional; «Yangi moy/filtr»)
- Reference guide: static `data/oil_ref_catalog.dart` (90 products + SAE/model capacity)
- **Unified HTML (Flutter-synced):** `docs/oil_change_app.html` — hub + full OilRef (90 products, Tavsiya first, SAE, detail). Old paths redirect: `oil_ref_catalog.html`, `docs/oil_change_b_prototype.html`, `docs/oil_change_latest.html`.
- `OilRefScreen(uid, initialVehicleId?)`: tabs **Tavsiya | Sintetik | Yarim | Mineral**; open gate → `OilCarSetupScreen` if 0 cars or selected `!isRecommendationReady`; 2+ cars → chip picker on Tavsiya; home navigates with uid+vehicleId
- widgets: `oil_hub_widgets.dart`; setup: `OilCarSetupScreen`
- Home grid: oil_change after bread (page1); carpet_wash after car_wash (page2). `oil_change` must be `enabled` in `config/module_defaults` when enforce=true (else «Tez orada»).
- Onboarding: 7-sahifa ixtiyoriy mashina + 5 000 so‘m bonus; finish → saveCarInfo + claimCarProfileBonus

## CF
- `claimCarProfileBonus` — auth; car complete; idempotent v1; ledger bonus

## Later
Onlayn navbat, QR chek, analitika.
