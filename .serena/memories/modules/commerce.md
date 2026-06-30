# Commerce / Delivery (food + bread + orders + courier)

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`. Order placement ALWAYS via CF `placeOrderPostPaid` through `OrderPaymentService.placeOrderPostPaid({userPhone,idempotencyKey,orderBase,decrements})`.

## Shared
- `OrderModel` (`models/order_model.dart`): type(bread|food),total,status(legacy),fulfillmentStatus,paymentStatus,fulfillmentMode,balanceApplied/cashDue/cashPaid,items,extras,saltYeastCost,cartHadYopishBread,mfy,lat/lng,courierId,routeId. Getters: effectiveFulfillment, effectivePayment, canCourierArrive(=='courier_picked'), canCourierPay(=='arrived').
- `InventoryRepository`: enum InventoryKind{bread,extra,food}; StockChange{kind,id,qty,label}; InsufficientStockException. getRemaining=totalStock-soldToday; totalStock<=0 ⇒ unlimited.
- GOTCHA: idempotencyKey = FNV-1a 64-bit hash of `phone|date|cartSignature` (prefix food_/bread_). Old base64 bug hashed only phone → same-day dup dropped.

## food (`features/food/`)
- `food_screen.dart`,`food_controller.dart`,`product_card.dart`,`food_cart_sheet.dart`. fallback `utils/food_catalog.dart`; model `models/food_product.dart` (inventoryId,minQty,step,unit).
- FoodController(ordersRepo,inventoryRepo). cart = Map<int,double> productId→qty (0.5 multiples).
- reads: streams `food_catalog` (orderBy id); remaining via `food_inventory/{inventoryId}`; `users/{uid}.bonusBalance`.
- orderBase: type:'food',items[{name,emoji,price,qty,unit,total,inventoryId}],total,balanceApplied:0,cashDue:total,status:'new',fulfillmentStatus:'pending',paymentStatus:'unpaid',fulfillmentMode:'delivery'.
- GOTCHA: offline → pref `food_pending_orders`, flushed on connectivity. stock clamp `_wouldExceedStock`.

## bread (`features/bread/`)
- `bread_screen.dart`,`bread_controller.dart`,widgets bread_product_card/bread_extra_product_card/bread_cart_sheet,`services/bread_image_storage.dart`. models bread_product.dart (BreadProduct type tayyor|yopish|toy; flourG/milkMl/milkRatio), bread_extra_product.dart (qtyStep,tieToYopishBread,bonusPercent,effectiveMaxQtyValue).
- BreadController(breadRepo,ordersRepo,inventoryRepo). BreadRepository: `bread_products`,`extra_products` (orderBy createdAt), `settings/prices`.
- carts: cart Map<int,int>, extraProductsCart Map<int,double>, flourMilkChoice Map<int,String>('ours'|'yours').
- GOTCHAS: flourMilk 'ours' adds flourMilkCost = flourG/1000*flour_price + milkMl/1000*milk_price (default milkMl=milkRatio*flourG, ratio 0.575; flour≈8000, milk≈7000). saltYeastCost = 50 × (yopish+toy count). grandTotal=breadTotal+extrasTotal+saltYeastCost. Inventory decrements ONLY isReady bread (with firestoreId) + extras; yopish/toy NOT inventoried. tieToYopishBread extras clamped via `_clampTiedExtras`. offline key `pending_orders` (NOT food's key).

## orders (`features/orders/`)
- `orders_screen.dart` only; uses OrdersRepository.watchByUser + `profile/widgets/order_card.dart`.
- `OrdersRepository` (collection `orders`, `settings/app` for flow): watchByUser(whereIn phone aliases), recentByPhone, watchRecentOrders(admin), watchReadyOrders(courier), markDelivered, setOrderStatus/Batch (chunk450). OrderFlowModes: orderAcceptMode/orderReadyMode (auto|manual).
- `_statusPatch` maps legacy→fulfillment: new→pending, accepted/ready→confirmed, in_delivery→courier_picked, delivered→completed+paid, rejected→cancelled.
- GOTCHA: orders_screen.dart has some mojibake (corrupted Cyrillic) strings.

## courier (`features/courier/`)
- screens courier_screen/courier_mfy_selection/courier_collection_tasks/courier_collection_detail; `courier_controller.dart`; widgets courier_order_tile/courier_payment_sheet/route_map_view. services courier_route_service/collection_service. repos couriers_repository/delivery_routes_repository/collection_tasks_repository.
- CourierController(routesRepo,ordersRepo,couriersRepo); static `active` (for payment sheet outside Provider). courierUid=phone digits.
- `delivery_routes`: status ready|active|completed,courierId,orderIds,currentIndex,orderedStops,polyline. startRoute atomic ready→active; advanceIndex; completeRoute; watchActiveForCourier.
- `couriers/{uid}`: upsertStatus(CourierStatus{isOnline,lat,lng,fcmToken}) GPS heartbeat.
- `collection_tasks` READ-ONLY (CF-created); `warehouse_stock` CF-only.
- Flow: toggleOnline → GPS stream (distanceFilter20) + upsert couriers; if ready route → startRoute claim → load orders by orderIds. Per order: markPicked→markArrived→submitPayment(lines)→confirmAndAdvance (last→completeRoute). CourierPaymentSheet modes cash/card/wallet/product; auto wallet top-up for deficit; never overpays wallet.
- CFs: courierCreateRoute, courierRecoverOrphanRoute, courierMarkPicked, courierMarkArrived, courierGetCustomerWalletBalance, courierSubmitPayment, courierSubmitCourierOrderPayment, adminCreateCollectionTask, courierFinalizeCollection, adminGetWarehouseStock.
- GOTCHAS: isOrderFinalized = paid OR completed OR delivered. `_syncStuckCurrentOrderIfNeeded`/`finalizeCurrentOrderIfPaid` auto-advance paid-but-not-moved orders. recoverOrphanRoute rebuilds from orphan in_delivery unpaid orders. `_advancingRoute` guard prevents double-advance.
