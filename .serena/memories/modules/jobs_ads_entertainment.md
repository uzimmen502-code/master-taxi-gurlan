# Jobs board + Ads marketplace + Entertainment

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.
KEY: jobs board and cheap-product marketplace BOTH live in Firestore `ads` collection, discriminated by `type`, but use DIFFERENT Dart models/repos.

## Jobs board (`features/jobs/`)
- `jobs_screen.dart`,`jobs_tabs.dart`,`jobs_controller.dart`, widgets ad_card/add_ad_sheet/edit_ad_sheet/urgent_toggle/complaint_sheet.
- Model `models/job_ad.dart` JobAd + `enum AdKind{work,service,ad}` + AdKindX. Repo `repositories/jobs_repository.dart` JobsRepository (collection `ads`, `type`∈work|service|ad). Complaints → `complaints`.
- AdKindX: expiresInDays work=3/service=30/ad=14; urgentExpiryDays=2; supportsUrgent=work|ad; userPanelKinds=[ad,service]. Legacy `type:sell` filtered out (`isJobsBoardType` false); new create blocked in rules/CF.
- JobAd: type,text,title,priceText,authorName,authorPhone,address,isUrgent,status(pending|active|completed|blocked),expiresAt.
- Flow: create→status `pending` (admin moderation, UI admin_web/jobs_moderation_screen.dart); daily limit 10; owner edit gated by authorPhone. NO CF (pure Firestore).
- **JobsTabs = 2 tabs** (Иш бор=ad / Хизмат=service). P2P «Сотаман» Jobs tab removed — selling is Sell hub + Online market (`mem:modules/sell`).
- CF `onAdUpdate`: Jobs → `authorPhone` + screen `jobs`.

## Ads marketplace / cheap products (`features/ads/`)
- model `ad_model.dart` AdModel (typeKey='cheap_product'); repo `ads_repository.dart`; `ads_storage_service.dart`. screens cheap_products/ad_details/create_ad/edit_ad/my_ads (Фаол/Текширувда/Яширилган); widgets my_ad_actions.
- Firestore `ads` type==`cheap_product`; status **`pending|active|inactive`**. Create: repo forces `pending` (rules require pending). `publishedAt` only on admin activate.
- Owner rules (`cheapProductOwnerUpdateOk`): content + status **inactive** (hide) or **pending** (republish from inactive **or remode after edit of active**) — **never `active`**. Edit active → pending. `requestRepublish`. Sell hub: `mem:modules/sell`.
- Admin: `market_moderation_screen` + CF `adminUpdateMarketAdStatus` / `adminUpdateMarketAd` / `adminDeleteMarketAd` / `adminListMarketAds`.
- CF `onAdUpdate`: market → `ownerId`, screen `my_ads`, types `market_ad_published` / `market_ad_moderation` (inactive notify only admin reject/hide).
- Limits: maxActivePerUser=50. getMyAds client-sort (pending may lack publishedAt).

## Entertainment (`features/entertainment/`)
- passenger entertainment_list/entertainment_player; driver driver_entertainment_picker; services entertainment_storage/entertainment_cache_service. model `entertainment_video.dart`. repo `entertainment_repository.dart`.
- Firestore `entertainment_catalog/{id}` (orderBy sortOrder); driver selection on `intercity_drivers/{id}` entertainmentAllowed + entertainmentIds[] (max 5).
- Access gate: EntertainmentAccessException unless confirmed intercity booking.
- Storage `entertainment/{videoId}.mp4` (max 400MB). Cache LRU ~1.5GB. CF transcodeEntertainmentVideo (720p). Admin UI entertainment_catalog_tab.dart.
