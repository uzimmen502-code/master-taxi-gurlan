# Platform store (Платформа дўкони)

Catalog collection: `platform_products/{id}`.
Fields: name, description, price(int), imageUrl (cover), imageUrls (1–5), unit, minQty, step, totalStock(0=unlimited), soldToday, active, featuredOnHome, showInMarket, sortOrder, createdAt, updatedAt.
Rules: read true; write isAdmin. Index: active+sortOrder.

Code: `lib/models/platform_product.dart`, `lib/repositories/platform_products_repository.dart`, customer `features/platform_store/screens/platform_store_screen.dart`, detail `platform_product_detail_screen.dart` (market-like gallery + full info), admin `admin_web/screens/platform_products_admin_screen.dart`. Images: up to 5 (`imageUrls`, cover=`imageUrl`). Admin multi FilePicker / Ctrl+V → compress → Storage `platform_images/{id}_{i}_{ts}.ext`.

Customer UX: card tap → detail; compact `+` on image (no «Саватга» CTA). Cart sheet lean: lines + total + checkout only — no delivery/pickup chips, no name/phone/address fields, no wallet in sheet body. Checkout: pay-confirm dialog shows wallet banner + total; phone from prefs/profile; AddressGate if address incomplete; always `fulfillmentMode: delivery`; `submitOrder` via `placeOrderPostPaid` type=`platform`. Wallet **opt-in** (`useWallet` default false; CF requires `useWallet===true`).

Home «Тавсия этамиз»: bread + food + platform. Tap: bread/food modules, platform→PlatformStoreScreen. Витрина: `settings/app.platformFeaturedAuto` (default true=АВТО all active; false=ҚЎЛДА only featuredOnHome). Admin bar ҚЎЛДА/АВТО + CF `adminSetPlatformFeaturedAuto`.

Orders list: OrderCard «Платформа дўкони». Market mix: `CheapProductsScreen` filters Ҳаммаси|AVA|Хусусий; platform cards `PlatformMarketCard` → PlatformStoreScreen.