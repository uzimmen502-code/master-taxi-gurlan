# Global Search Index (P0+P1+P2)

Collection: `search_index/{id}` (`type_sourceId`). Fields: type, moduleId, sourceCollection, sourceId, title, subtitle, price?, imageUrl, iconKey, keywords[], searchTokens[], geo{from,to,districtId}?, priorityBoost, active, updatedAt.

Types: `service` | `platform_product` | `job` | `market_ad` | `intercity_route` | `bread_product` | `food_product` | `yuk_listing` | `local_place`.

Rules: read true; write false (CF Admin SDK only).

CF Gen2 (`europe-west1`): `onSearchIndexPlatformProductWrite`, `onSearchIndexAdWrite`, `onSearchIndexBreadProductWrite` (`bread_products`), `onSearchIndexFoodProductWrite` (`food_catalog`), `onSearchIndexYukListingWrite` (`yuk_listings`). Callable `adminSeedSearchIndex` (+ Gurlen MFY `local_place`). Ops: `node functions/tools/seed_search_index.js`.

Client: `SearchIndexRepository` cache active≤1500 + P2 hybrid `array-contains` first token (merge; fallback cache if index missing). Index: `active` + `searchTokens` CONTAINS. `GlobalSearch.rank` intents: taxi/job/bread/food/shop/yuk/local(mfy). UI: `HomeGlobalSearchBar` before FeaturedProducts.

Deep-link: platform/bread/food highlight; yuk_listing → YukBirjaScreen(intercity+from/to+highlight); local_place → local_taxi; intercity_route → IntercityTaxiScreen.

Skip: live `yuk_local_drivers` / trips / drivers (ephemeral).