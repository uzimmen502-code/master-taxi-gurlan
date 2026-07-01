# Agro pickup (sut qabul)

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions` (Agro pickup section).

## Collection
- `agro_pickup_orders/{id}` — CF-only writes. `productType`: `milk` (future: qatiq, guruch).
- Fields: customerId, customerPhone, customerName, productType, pickupAddress, pickupLat/Lng, literCount, note, priceMode(admin), finalPrice, status, createdAt, updatedAt.

## Status flow (milk MVP)
`new` → `accepted` → `pickup_in_delivery` (courier claim) → `arrivedAt` + ring → `picked_up` → `completed` (or `cancelled`). Admin can still override status via adminSetAgroPickupStatus.

## CFs (onCall)
- placeAgroPickupOrder — customer creates order (`productType`, `literCount` 1..500).
- adminSetAgroPickupStatus — admin sets status + optional finalPrice.
- courierClaimAgroPickup / courierMarkAgroPickupArrived / courierMarkAgroPickedUp — courier pickup flow + ring on arrived.

## Flutter
- Model: `lib/models/agro_pickup_order.dart`
- Repo: `lib/repositories/agro_pickup_orders_repository.dart`
- Service: `lib/services/agro_pickup_service.dart`
- Customer: `features/agro_pickup/screens/milk_pickup_screen.dart`, `milk_pickup_orders_screen.dart`
- Courier: `features/agro_pickup/screens/agro_pickup_courier_screen.dart` — banner on courier panel.
- Admin web: `agro_pickup_admin_screen.dart` — section `Sut qabul` in admin_shell.
- Home grid: `service_milk.png` «Сут қабул» (page 1); Moy almashtirish on page 2.
- PromoCarousel: `banner_milk.jpg` after Gilam.

## Pricing MVP
Admin sets `finalPrice` on accept (optional total for order).
