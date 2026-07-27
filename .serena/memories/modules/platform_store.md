# Platform store (Платформа дўкони)

Catalog collection: `platform_products/{id}`.
Fields: name, description, price(int), imageUrl (cover), imageUrls (1–5), unit, minQty, step, totalStock(0=unlimited), soldToday, active, featuredOnHome, showInMarket, sortOrder, createdAt, updatedAt.
Rules: read true; write isAdmin. Index: active+sortOrder.

Code: `lib/models/platform_product.dart`, `lib/repositories/platform_products_repository.dart`, customer `features/platform_store/screens/platform_store_screen.dart`, admin `admin_web/screens/platform_products_admin_screen.dart` (shell: «Платформа дўкони»). Images: up to 5 (`imageUrls`, cover=`imageUrl`). Admin multi FilePicker / Ctrl+V → compress → Storage `platform_images/{id}_{i}_{ts}.ext`. Store card: PageView gallery.

Home «Тавсия этамиз»: bread + food + platform. Tap: bread/food modules, platform→PlatformStoreScreen. Витрина: `settings/app.platformFeaturedAuto` (default true=АВТО all active; false=ҚЎЛДА only featuredOnHome). Admin bar ҚЎЛДА/АВТО + CF `adminSetPlatformFeaturedAuto`.

Cart+checkout DONE: `PlatformStoreController` submit via `placeOrderPostPaid` type=`platform` (server reprice from `platform_products`, wallet±cashDue, inventory soldToday on same docs). Cart sheet: delivery|pickup, AddressGate, wallet banner. Orders list shows as OrderCard «Платформа дўкони». Market mix DONE: `CheapProductsScreen` filters Ҳаммаси|AVA|Хусусий; platform cards `PlatformMarketCard` (AVA badge) → PlatformStoreScreen; private ads unchanged.
