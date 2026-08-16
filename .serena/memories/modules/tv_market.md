# TV Market (video commerce)

Home attraction + full-screen vertical feed + seller mini-shop / AVA vitrine. Module id `tv_market` in `kKnownModuleIds`. Storage: `tv_clips/{ownerPhone}/{file}`, shop photos `tv_shop/{ownerPhone}/{file}`. Firestore: `tv_clips`, `tv_shops/{ownerPhone}`, `tv_shop_items`. Settings: `settings/app.tvAutoApprove` (true → create `active`, false → `pending`).

## Files
- `lib/features/tv_market/models/tv_clip.dart` — status `pending|active|blocked`; price 0 = optional/hidden; `shopItemId`, `socialConsent`, `socialPostedAt`, `searchTokens`; `displayOwnerName` (given name, never phone)
- `lib/features/tv_market/utils/tv_clip_search.dart` — CatalogSearch wrapper: title/desc/district/owner/category 3-lang (uz_Cyrl/uz_Latn/ru) + score; `buildTokens` (both scripts, category, district, title prefixes)
- `lib/features/tv_market/repositories/tv_clips_repository.dart` — Home pagination; likes `tv_clips/{id}/likes/{uid}` ±1 `likeCount`; saves `users/{uid}/saved_tv_clips/{clipId}`; search = recent pool (400, 45s cache) + `searchTokens` array-contains (latin/cyrillic probe) then CatalogSearch AND+rank
- `lib/features/tv_market/screens/tv_clip_search_screen.dart` — 3-script hint; district scope + «search all districts»; result count; title highlight; tap opens clip in feed
- `lib/features/tv_market/screens/tv_publish_screen.dart` — tokens via `TvClipSearch.buildTokens` (not raw AdSearchText)
- `lib/features/tv_market/widgets/tv_clip_overlay.dart` — given name, title, description (white, transparent bg, max 4 lines), price, district; Contact/Delete; «Дўконга» if shopItemId
- `lib/features/tv_market/screens/tv_market_feed_screen.dart` — district chip (no TV MARKET title); search icon left of camera; videocam + 20% smaller arrow; like/share/save/profile; «Дўконга» if shopItemId
- Admin: `tv_clips_moderation_screen.dart` — activate/block/delete + «Соцсетда чоп» + «Реклама 7 кун» (`boostUntil`)

## Search (3 language rule)
- Engine: `CatalogSearch` + `AdSearchText.foldMarks` (‘ ’ ʻ ʼ → `'` so o‘/o'/oʻ ↔ ў)
- Match fields: title, description, district, mfy, price, given name, category aliases (mahsulot/маҳсулот/товар, xizmat/хизмат/услуга), searchTokens
- Do not put TV clips into Home `search_index` (CF-write-only)

## Rules / indexes
- `tv_clips` read all; create auth; update admin/owner **or** likeCount ±1; likes subcol create/delete own uid
- Indexes: status+createdAt, status+districtId+createdAt, status+districtId+viewCount, ownerPhone+createdAt, **status + searchTokens CONTAINS**
- Storage tv_shop: authed write ≤8MB

## Gotchas
- `users` is not publicly readable — persist given name on clip at publish (`resolveLocalTvOwnerGivenName`: prefs → Firestore `users.name` → Auth; writes back to prefs). Overlay: own clips always show profile given name (`@nick` / `Фойдаланувчи` ignored). Own clip `ownerName` patched on play if it differs.
- Clip-only publish (shop declined) has no product photo and no `shopItemId`.
- Meta auto-post is **not** implemented; consent + admin manual flag only.
- Home bottom «Магазиним» tab only if `tv_shops/{phone}` exists.
- No dedicated CF; client writes + admin flags.
- Old clips may lack `searchTokens`; title/description still match in the recent-400 pool. Token query helps newer/prefixed titles beyond that pool.
