# TV Market (video commerce)

Home attraction + full-screen vertical feed. Module id `tv_market` in `kKnownModuleIds`. Storage: `tv_clips/{ownerPhone}/{file}`. Firestore: `tv_clips`. Settings: `settings/app.tvAutoApprove` (true → create `active`, false → `pending`).

## Files
- `lib/features/tv_market/models/tv_clip.dart` — status `pending|active|blocked`; price 0 = optional/hidden
- `lib/features/tv_market/repositories/tv_clips_repository.dart` — `fetchHomePage` paginates Home: first 7, then +10; nearby district then all-active
- `lib/features/tv_market/services/tv_storage_service.dart` — video + poster upload
- `lib/features/tv_market/services/tv_player_pool.dart` — keep current + next players, sequential prefetch
- `lib/features/tv_market/screens/tv_market_feed_screen.dart` — vertical PageView; AppBar red camera + arrow; tap play/pause badge; contact → `callPhone`
- `lib/features/tv_market/screens/tv_publish_screen.dart` — `video_compress` MediumQuality + thumbnail before upload
- `lib/features/tv_market/widgets/home_video_stage.dart` — Home bottom: 7 muted clips (~80% height), infinite append from TV Market on scroll (current + next decoder only); tap → full feed
- Admin: `lib/features/admin_web/screens/tv_clips_moderation_screen.dart` — list + АВТО/ҚЎЛДА + activate/block/delete

## Rules / indexes
- Firestore: read all; create `isAuth()`; update/delete admin or ownerPhone match
- Composite: status+districtId+createdAt; status+districtId+viewCount; ownerPhone+createdAt; status+createdAt
- Storage: authenticated write, 100MB

## Gotchas
- Home must not nest a vertical PageView (fights Home scroll). Feed is a separate route.
- Old clips may lack `posterUrl` (uploaded before compress).
- No dedicated CF; client writes `tv_clips` directly.
