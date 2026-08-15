# TV Market (video commerce)

Home attraction + full-screen vertical feed. Module id `tv_market` in `kKnownModuleIds`. Storage: `tv_clips/{ownerPhone}/{file}`. Firestore: `tv_clips`. Settings: `settings/app.tvAutoApprove` (true → create `active`, false → `pending`).

## Files
- `lib/features/tv_market/models/tv_clip.dart` — status `pending|active|blocked`; price 0 = optional/hidden
- `lib/features/tv_market/repositories/tv_clips_repository.dart` — `fetchHomePage` paginates Home: first 7, then +10; nearby district then all-active; `deleteOwnClip` (owner Firestore + Storage)
- `lib/features/tv_market/services/tv_storage_service.dart` — video + poster upload
- `lib/features/tv_market/services/tv_player_pool.dart` — current, then next, then prev sequentially (max 3); `alwaysMuted` for Home
- `lib/features/tv_market/services/tv_screen_playback.dart` — pause when another route covers the screen or app backgrounds (`appRouteObserver`)
- `lib/features/tv_market/screens/tv_market_feed_screen.dart` — vertical PageView; sound only while this route is current; AppBar red camera + arrow; tap play/pause badge; contact → `callPhone`
- `lib/features/tv_market/screens/tv_publish_screen.dart` — `video_compress` MediumQuality + thumbnail; preview pauses in background
- `lib/features/tv_market/widgets/home_video_stage.dart` — Home bottom: 7 muted clips, infinite append; alwaysMuted; pause when leaving Home; owner sees Ўчириш instead of contact
- `lib/features/tv_market/services/tv_clip_delete.dart` — confirm dialog + `deleteOwnClip`
- Admin: `lib/features/admin_web/screens/tv_clips_moderation_screen.dart` — list + АВТО/ҚЎЛДА + activate/block/delete

## Rules / indexes
- Firestore: read all; create `isAuth()`; update/delete admin or ownerPhone match
- Composite: status+districtId+createdAt; status+districtId+viewCount; ownerPhone+createdAt; status+createdAt
- Storage: authenticated write, 100MB

## Gotchas
- Home must not nest a vertical PageView (fights Home scroll). Feed is a separate route.
- Home pool is `alwaysMuted`; feed unmutes only while its route is current and app resumed.
- Old clips may lack `posterUrl` (uploaded before compress).
- No dedicated CF; client writes `tv_clips` directly.
