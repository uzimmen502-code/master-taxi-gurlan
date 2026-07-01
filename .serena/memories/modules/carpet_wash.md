# Carpet wash (gilam yuvish)

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions` (Carpet wash section).

## Collection
- `carpet_wash_orders/{id}` — separate from `orders`. CF-only writes.
- Fields: customerId, customerPhone, customerName, pickupAddress, pickupLat/Lng, carpetCount, note, priceMode(admin), finalPrice, status, pickupCourierId, returnCourierId, createdAt, updatedAt.

## Status flow
`new` → `accepted` → `pickup_ready` → `pickup_in_delivery` → `picked_up` → `washing` → `drying` → `ready` → `return_ready` → `return_in_delivery` → `completed` (also `cancelled`, intermediate `delivered` allowed in schema but courier CF sets `completed` directly).

## CFs (onCall)
- placeCarpetWashOrder — customer creates order (auth phone match).
- adminSetCarpetWashStatus — admin/dispatcher sets status + optional finalPrice.
- courierClaimCarpetPickup / courierMarkCarpetArrived (leg) / courierMarkCarpetPickedUp — pickup_ready → pickup_in_delivery → (arrived) → picked_up.
- courierClaimCarpetReturn / courierMarkCarpetArrived (return) / courierMarkCarpetDelivered — return_ready → return_in_delivery → (arrived) → completed.

## Flutter
- Model: `lib/models/carpet_wash_order.dart`
- Repo: `lib/repositories/carpet_wash_orders_repository.dart` (watchForCustomer, watchByStatus, watchAll)
- Service: `lib/services/carpet_wash_service.dart`
- Customer: `features/carpet_wash/screens/carpet_wash_screen.dart` (form + auto call dispatcher via `SettingsRepository.getDispatcherPhone()`), `carpet_wash_orders_screen.dart`
- Courier: `carpet_wash_courier_screen.dart` — 3 tabs: pickup ready, return ready, my active (self-claim like bread, NOT admin-assigned).
- Admin web: `admin_web/screens/carpet_wash_admin_screen.dart` — section label `Gilam yuvish` in admin_shell.
- Home grid: `service_carpet_wash.png` at old Avto yuvish slot; `service_car_wash.png` moved next to Mening yaqinlarim (Tez kunda). PromoCarousel banner `banner_carpet_wash.jpg` after Non.
- Courier panel banner → `CarpetWashCourierScreen`.

## Pricing MVP
Admin sets `finalPrice` on accept (optional). Auto m² pricing later.

## Dispatcher phone
`settings/app.dispatcherPhone`, fallback `998912778777` via `SettingsRepository.getDispatcherPhone()`.