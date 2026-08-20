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
- `lib/features/tv_market/widgets/tv_channel_header.dart` — public channel head (name, district, clip count)
- `lib/features/tv_market/widgets/tv_shop_item_card.dart` — vitrine product card: kind, description, highlight badge
- `lib/features/tv_market/widgets/tv_shop_photo_gallery.dart` — product carousel (swipe + thumbnail select + zoom hint) + fullscreen pinch/double-tap zoom, swipe, thumbnail pick; CachedNetworkImage
- `lib/features/tv_market/widgets/tv_channel_contact_bar.dart` — bottom call CTA
- `lib/features/tv_market/screens/tv_channel_screen.dart` — shop-less publisher channel (clips grid, highlight from reel, owner FAB publish)
- `lib/features/tv_market/screens/tv_shop_public_screen.dart` — channel header + vitrine; highlight item sorted first
- `lib/features/tv_market/widgets/tv_clip_overlay.dart` — right-rail like/share/lime «Дўкон»/save always for every clip; tap routes shop or channel
- `lib/features/tv_market/screens/tv_market_feed_screen.dart` — lime Дўкон → TvMyShopScreen / TvShopPublicScreen (has tv_shops) or TvChannelScreen (no shop); highlightItemId / highlightClipId passed
- `lib/features/tv_market/services/tv_clip_view_recorder.dart` — 3s/25% watch threshold; session dedup; 24h Firestore dedup via `views/{viewerId}`; skips owner self-view
- `lib/features/tv_market/utils/tv_view_format.dart` — K/M view display
- Lime CTA label: `tv_market_shop` if `tv_shops` else `tv_market_channel` (same open handler)
- Players: `TvPlayerPool` maxReady Home=1 / Feed=2; `releaseAll` on route leave/background (do not keep paused ExoPlayers). Play 1.0.24 vitals: OOM in ExoPlayer + Impeller AHBTextureSourceVK SIGSEGV. Android: EnableImpeller=false, largeHeap=true. Posters decode with cacheWidth.
- Upload: `TvClipCompress` → 720p/24fps, max 60s trim, skip if already ≤720p and ≤3.5MB; still huge → 540p; poster JPEG 720px. Share uses compressed file. Home clips: `SliverList` + cacheExtent 320; play when ≥50% visible.
- Crashlytics: `CrashReport.nonFatal` from player/compress; Firestore mobile cache 48MB (not unlimited). Android Impeller OpenGL (not Vulkan) to avoid AHBTextureSourceVK.
- Feed order: `tvShuffleClips` on home/nearby/recommended/allActive (not owner grid). Process-lifetime seed (`Object.hash(clipId, sessionSeed)`): stable while app is open, new mix on next launch. Do not `Random()` each fetch (pagination used to reshuffle mid-session).
- Clip district stamp: `TvClipGeo.resolveForPublisher` from `users/{phone}.districtId` + `geo_districts` label — never SharedPreferences `ServiceConfigHolder` cache (Urganch user + stale Gurlan cache was writing Гурлан on overlay). `hydrateTvPublisherNames` also overlays owner's current district on existing clips. Onboarding no longer hardcodes address `'Gurlan'`.
- Social IG/FB/TikTok: `tv_clips.socialNetworks` independent of mini-shop (video share, no photos). After publish: system share sheet. Admin: copy video URL + open official composer, then «Соцсетда чоп».
- Shop → Аҳоли бозори: AppBar on `tv_my_shop_screen` / `tv_shop_public_screen` → `CheapProductsScreen`. Market also lists `tv_shop_items` via `TvShopItemGridCard` → `TvShopItemDetailScreen` (zoom + call, no similar-items).
- Admin: