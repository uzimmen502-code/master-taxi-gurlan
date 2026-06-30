# Jobs board + Ads marketplace + Entertainment

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.
KEY: jobs board and cheap-product marketplace BOTH live in Firestore `ads` collection, discriminated by `type`, but use DIFFERENT Dart models/repos.

## Jobs board (`features/jobs/`)
- `jobs_screen.dart`,`jobs_tabs.dart`,`jobs_controller.dart`, widgets ad_card/add_ad_sheet/edit_ad_sheet/urgent_toggle/complaint_sheet.
- Model `models/job_ad.dart` JobAd + `enum AdKind{work,service,ad,sell}` + AdKindX. Repo `repositories/jobs_repository.dart` JobsRepository (collection `ads`, `type`∈work|service|ad|sell). Complaints → `complaints`.
- AdKindX: expiresInDays work=3/service=30/ad=14/sell=14; urgentExpiryDays=2; supportsUrgent=work|ad; userPanelKinds=[ad,service,sell].
- JobAd: type,text,title,priceText,authorName,authorPhone,address,isUrgent,status(pending|active|completed|blocked),expiresAt.
- Flow: create→status `pending` (admin moderation, UI admin_web/jobs_moderation_screen.dart); daily limit 10 (JobsController.dailyAdLimit/dailyCountByAuthor); owner edit gated by authorPhone (`_assertOwner`). isAdmin from prefs `user_role`. NO CF (pure Firestore). JobsTabs = 2 tabs (Иш бор=ad / Хизмат таклифи=service).

## Ads marketplace / cheap products (`features/ads/`)
- model `ad_model.dart` AdModel (typeKey='cheap_product'); repo `ads_repository.dart` AdsRepository; `services/ads_storage_service.dart` AdsStorageService (Firebase Storage img). screens cheap_products/ad_details/create_ad/edit_ad/my_ads; widgets ad_card/ad_image_slider/my_ad_actions.
- Firestore `ads` where type=='cheap_product'; fields ownerId,title,titleLower,description,price(int),phone,sellerName,imageUrls[],status(active|inactive),views,publishedAt.
- Limits: maxActivePerUser=50 (canCreateAd). search via titleLower range. getSimilarAds weighted 50% keyword/30% price/20% freshness minScore .35. NO moderation, NO CF. incrementViews, migrateTitleLowerForCheapProducts (client one-time).

## Entertainment (`features/entertainment/`)
- passenger entertainment_list/entertainment_player; driver driver_entertainment_picker; services entertainment_storage/entertainment_cache_service. model `entertainment_video.dart` EntertainmentVideo. repo `entertainment_repository.dart`.
- Firestore `entertainment_catalog/{id}` (orderBy sortOrder); driver selection on `intercity_drivers/{id}` fields entertainmentAllowed(bool), entertainmentIds[] (maxDriverSelection=5).
- Access gate: EntertainmentAccessException unless confirmed intercity booking (bookingsRepo.userHasEntertainmentAccess).
- Storage `entertainment/{videoId}.mp4` (maxUploadBytes=400MB, matches storage rules). Cache `entertainment_cache/{videoId}.mp4` (maxCacheBytes≈1.5GB, LRU prune by mtime). Player chewie+video_player; local cache file else network STREAM.
- CF transcodeEntertainmentVideo (storage-triggered, 720p) — NOT called from Flutter; client reads catalog downloadUrl. Admin UI admin_web/entertainment_catalog_tab.dart.
