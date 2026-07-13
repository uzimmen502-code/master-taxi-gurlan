# Seller role / POS audit (2026-07-13)

Overall **~5.5/10**. Entry: profile «Sotuv paneli» (`seller|admin|superadmin`). UI: Tezkor + Buyurtmalar.

## P0 (DONE 2026-07-13)
1. `sellerPlaceSale` — `resolveSellerCatalogLine` (food_catalog / bread_products tayyor only).
2. `placeOrderPostPaid` writes `inventoryDecrements`; midnight reset re-applies unpaid reservations.
3. `setUserRoleByAdmin` resolves `canonicalUid` then legacy 9-digit doc.
4. `sellerSubmitPickupPayment` requires `fulfillmentStatus===ready`.
UI: Tezkor wide≥720 split + adaptive grid (phone/tablet/monoblock).

## P1 (DONE 2026-07-13)
1. Badge = waiting+ready (`queueBadgeCount`); default filter waiting; unpaid pickup query + index `fulfillmentMode+paymentStatus+createdAt`.
2. `food_inventory` realtime + Tezkor sale refresh; order wait time; `ordersLoadError` / `walletLoadError` UI.
3. `onOrderCreate` pickup → FCM sellers (`type=seller_pickup`, `screen=seller_pos`); PushNavigation → `SellerPosScreen`.
POS scope = ready bread + food ONLY (no extras/yopish — by design).

## P2 (DONE 2026-07-13)
1. Tezkor idempotency — UUID per checkout attempt (cart o‘zgarsa yangilanadi; retry xavfsiz).
2. Mahsulot qidiruv + sotuv/olib-ketish chek dialog.
3. `sellerGetShiftSummary` (Tashkent kuni, `paidBySellerId`+`paidAt`) — AppBar «Bugun» sheet; sessionTotal sync.
4. Home pin `SellerPosHomePin` — role `seller|admin|superadmin`.
Index: `orders.paidBySellerId`+`paidAt`.

## 10/10 (optional later)
Print/share receipt; multi-seller store shift; offline queue.

Detail: canvas `seller-pos-audit`.
