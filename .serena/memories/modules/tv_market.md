# TV Market (video commerce)

Home attraction + full-screen vertical feed + seller mini-shop / AVA vitrine. Module id `tv_market` in `kKnownModuleIds`. Storage: `tv_clips/{ownerPhone}/{file}`, shop photos `tv_shop/{ownerPhone}/{file}`. Settings: `settings/app.tvAutoApprove` (true → create `active`, false → `pending`).

## Domain (do not rebuild collections)
Five layers, flat Firestore + IDs — not nested subcollections (feed needs top-level `tv_clips`):
- `users/{uid}` 🔒 private account (wallet, address, role)
- `tv_public_profiles/{uid}` 👤 public face (name; photo later). App-wide display, not `users` reads
- `tv_shops/{uid}` 🏪 one shop per user
- `tv_shop_items/{id}` 🛍️ Offer (commerce source of truth: title/optional price/`photoUrl`+`photoUrls` 1–5/kind). Domain name Offer; keep collection id
- `tv_clips/{id}` 🎥 video; `shopItemId` optional (clip-only posts allowed). Feed denorms title/price/ownerName/district
Do not rename to generic `shops`/`offers`/`clips` (collides with platform_store / ads). Owner edit/delete on overlay, home card, own clip grid; edit syncs offer if `shopItemId` set; delete unlinks `clipIds`.

## Files
- `lib/features/tv_market/models/tv_shop.dart` — offer `photoUrls` 1–5, `photoUrl` cover; price 0 = optional/hidden (vitrine does not require price)
- `lib/features/tv_market/models/tv_clip.dart` — status `pending|active|blocked`; price 0 = optional/hidden; `shopItemId`, `socialConsent`, `socialPostedAt`, `searchTokens`; `tvOwnerDisplayName` (full profile name; @nick/phone/«Фойдаланувчи» → empty); `tvOwnerGivenName` = first word for search tokens only
- `lib/features/tv_market/utils/tv_clip_search.dart` — CatalogSearch wrapper: title/desc/district/owner/category 3-lang (uz_Cyrl/uz_Latn/ru) + score; `buildTokens` (both scripts, category, district, title prefixes)
- `lib/features/tv_market/repositories/tv_public_profiles_repository.dart` — `tv_public_profiles/{phone}` + shop-name hydrate
- `lib/features/tv_market/repositories/tv_clips_repository.dart` — Home pagination; likes `tv_clips/{id}/likes/{uid}` ±1 `likeCount`; saves `users/{uid}/saved_tv_clips/{clipId}`; search = recent pool (400, 45s cache) + `searchTokens` array-contains (latin/cyrillic probe) then CatalogSearch AND+rank
- `lib/features/tv_market/screens/tv_clip_search_screen.dart` — 3-script hint; district scope + «search all districts»; result count; title highlight; tap opens clip in feed
- `lib/features/tv_market/screens/tv_publish_screen.dart` — create + `editClip` save (tokens, optional new video, sync offer if shopItemId); new offer 1–5 photos
- `lib/features/tv_market/screens/tv_shop_item_photos_screen.dart` — owner adds/removes offer photos (max 5)
- `lib/features/tv_market/widgets/tv_owner_action_bar.dart` — owner Edit + Delete
- `lib/features/tv_market/widgets/tv_clip_overlay.dart` — publisher display name (hide if unknown), title, description, price, district; owner Edit/Delete else Contact; «Дўконга» if shopItemId
- `lib/features/tv_market/screens/tv_market_feed_screen.dart` — district chip (no TV MARKET title); search icon left of camera; videocam + 20% smaller arrow; like/share/save/profile; «Дўконга» if shopItemId
- Admin: `tv_clips_moderation_screen.dart` — activate/block/delete + «Соцсетда чоп» + «Реклама 7 кун» (`boostUntil`)

## Search (3 language rule)
- Engine: `CatalogSearch` + `AdSearchText.foldMarks` (‘ ’ ʻ ʼ → `'` so o‘/o'/oʻ ↔ ў)
- Match fields: title, description, district, mfy, price, given name, category aliases (mahsulot/маҳсулот/товар, xizmat/хизмат/услуга), searchTokens
- Do not put TV clips into Home `search_index` (CF-write-only)

## Rules / indexes
- `tv_clips` read all; create auth; update admin/owner **or** likeCount ±1; likes subcol create/delete own uid
- `tv_public_profiles` read all; write owner phone match
- Indexes: status+createdAt, status+districtId+createdAt, status+districtId+viewCount, ownerPhone+createdAt, **status + searchTokens CONTAINS**
- Storage tv_shop: authed write ≤8MB

## Gotchas
- `users` is not publicly readable. Publisher name lives on `tv_clips.ownerName` and public `tv_public_profiles/{phone}` (synced on publish, profile save, onboarding, TV open). Overlay: clip name → public profile / `tv_shops.name` → only if viewer is publisher, local profile. Never show viewer name on someone else's clip; never phone / `Фойдаланувчи`. Hide name line if still unknown. Feed/home hydrate all clip phones from `tv_public_profiles`. Owner play patches `tv_clips.ownerName`. Old empty/phone `ownerName` backfill: `functions/tools/backfill_tv_publisher_names.js --apply` (Admin SDK → `users.name`).
- Clip-only publish (shop declined) has no product photo and no `shopItemId`.
- Meta auto-post is **not** implemented; consent + admin manual flag only.
- Home bottom «Магазиним» tab only if `tv_shops/{phone}` exists.
- No dedicated CF; client writes + admin flags.
- Old clips may lack `searchTokens`; title/description still match in the recent-400 pool. Token query helps newer/prefixed titles beyond that pool.
