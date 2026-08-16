# TV Market (video commerce)

Home attraction + full-screen vertical feed + seller mini-shop / AVA vitrine. Module id `tv_market` in `kKnownModuleIds`. Storage: `tv_clips/{ownerPhone}/{file}`, shop photos `tv_shop/{ownerPhone}/{file}`. Firestore: `tv_clips`, `tv_shops/{ownerPhone}`, `tv_shop_items`. Settings: `settings/app.tvAutoApprove` (true → create `active`, false → `pending`).

## Files
- `lib/features/tv_market/models/tv_clip.dart` — status `pending|active|blocked`; price 0 = optional/hidden; `shopItemId`, `socialConsent`, `socialPostedAt`, `searchTokens`; `displayOwnerName` (given name, never phone)
- `lib/features/tv_market/models/tv_shop.dart` — `TvShop` + `TvShopItem` (photo+price+clipIds required for vitrine; `boostUntil` paid pin; `socialPostedAt`)
- `lib/features/tv_market/repositories/tv_clips_repository.dart` — Home pagination; likes `tv_clips/{id}/likes/{uid}` ±1 `likeCount`; saves `users/{uid}/saved_tv_clips/{clipId}`
- `lib/features/tv_market/repositories/tv_shop_repository.dart` — ensureShop, items, vitrine rank (boosted → video → views → new)
- `lib/features/tv_market/screens/tv_market_feed_screen.dart` — district chip (no TV MARKET title); search icon left of camera; videocam + 20% smaller arrow; like/share/save/profile; «Дўконга» if shopItemId
- `lib/features/tv_market/screens/tv_clip_search_screen.dart` — title search (CatalogSearch + searchTokens); respects district filter; tap opens that clip in the feed
- `lib/features/tv_market/screens/tv_publish_screen.dart` — shop offer on publish; photo+price required if shop; attach extra clip to existing item; social consent checkbox
- `lib/features/tv_market/screens/tv_my_shop_screen.dart` / `tv_shop_public_screen.dart` / `tv_owner_clips_screen.dart`
- `lib/features/tv_market/widgets/tv_vitrine_section.dart` — seller cards inside AVA store (Contact only; official AVA SKUs stay on `platform_products` with cart)
- Admin: `tv_clips_moderation_screen.dart` — activate/block/delete + «Соцсетда чоп» + «Реклама 7 кун» (`boostUntil`)

## Rules / indexes
- `tv_clips` read all; create auth; update admin/owner **or** likeCount ±1; likes subcol create/delete own uid
- `tv_shops` / `tv_shop_items` read all; write owner (item update cannot change boostUntil/socialPostedAt/viewCount/ownerPhone)
- `users/{uid}/saved_tv_clips` owner only
- Indexes: existing tv_clips + tv_shop_items status+createdAt, status+districtId+createdAt, ownerPhone+createdAt
- Storage tv_shop: authed write ≤8MB

## Gotchas
- `users` is not publicly readable — persist given name on clip/item at publish.
- Clip-only publish (shop declined) has no product photo and no `shopItemId`.
- Meta auto-post is **not** implemented; consent + admin manual flag only.
- Home bottom «Магазиним» tab only if `tv_shops/{phone}` exists.
- No dedicated CF; client writes + admin flags.
