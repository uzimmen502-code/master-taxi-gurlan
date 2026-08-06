# Platform store (AVA дўкони)

UI brand: neon turquoise `#00FFFF` (`AvaStoreColors`). Catalog: card with add/mini ± stepper, bottom checkout bar. Detail: contain gallery (no crop), ± + «Саватга ўтиш» CTA, vertical PageView reverse=pull-down next, similar strip. Cart sheet: thumbs + sticky total/checkout.

Catalog collection: `platform_products/{id}`.
Fields: name, description, price(int), imageUrl (cover), imageUrls (1–5), unit, minQty, step, totalStock(0=unlimited), soldToday, active, featuredOnHome, showInMarket, sortOrder, goodsKind(`food`|`non_food`|''), createdAt, updatedAt. Admin batch classify + edit SegmentedButton. Store chips Ҳаммаси|Озиқ|Но-озиқ. Checkout: if cart only one kind → cross-sell opposite (price proximity + featured).
Rules: read true; write isAdmin. Index: active+sortOrder.

Code: `lib/models/platform_product.dart`, `lib/repositories/platform_products_repository.dart`, customer `features/platform_store/screens/platform_store_screen.dart`, detail `platform_product_detail_screen.dart` (market-like gallery + full info), admin `admin_web/screens/platform_products_admin_screen.dart`. Images: up to 5 (`imageUrls`, cover=`imageUrl`). Admin multi FilePicker / Ctrl+V → compress → Storage `platform_images/{id}_{i}_{ts}.ext`.

Delivery fee: `settings/app.platformDeliveryFeePercent` (default 5). Fee = round(itemsTotal × %). Admin: PlatformProductsAdminScreen bar + CF `adminSetPlatformDeliveryFeePercent`. Cart shows products / delivery (+hint) / pay total. Order: `itemsTotal`,`deliveryFee`,`deliveryFeePercent`; CF reprice adds fee to `total`. Client wallet against `grandTotal`.

Customer UX: catalog search; card add/±; detail stack images + similar. Cart: lines + fee + checkout. Checkout wallet dialog; AddressGate; `fulfillmentMode: delivery`; `placeOrderPostPaid` type=`platform`. Wallet opt-in.

Home «Тавсия этамиз»: bread + food + platform. Tap: bread/food modules, platform→PlatformStoreScreen. Витрина: `settings/app.platformFeaturedAuto` (default true=АВТО all active; false=ҚЎЛДА only featuredOnHome). Admin bar ҚЎЛДА/АВТО + CF `adminSetPlatformFeaturedAuto`.

Orders list: OrderCard «AVA дўкони» (BrandLabels + suffix). Market mix: `CheapProductsScreen` filters Ҳаммаси|AVA|Хусусий; platform cards `PlatformMarketCard` → PlatformStoreScreen.