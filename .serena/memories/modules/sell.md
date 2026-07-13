# Sell / Marketplace seller UX (P0+P1)

## Entry
- Home `sell` module + SellerCtaBanner → **`SellHubScreen`** (`features/sell/screens/sell_hub_screen.dart`).
- 3 paths: Platforma (`SellOfferScreen` platform), Onlayn bozor (create/my ads/feed sheet), P2P (`JobsScreen` sell tab).
- Tabs: Менинг таклифларим | Менга юборилган (`watchForwardedForUser`).

## Platform submissions
- Model `SellSubmission`: `collectionCompleted`, `progressLabel`, `estimatedTotal`, forward/collection fields.
- Tile `SellSubmissionTile` — status chip, sum, forward badge, collection task line (`CollectionTasksRepository.getById` + `finalValue`).
- Repo `watchForwardedForUser`: merge `forwardAudience==all` + `visibleToUserIds` arrayContains.
- Indexes: forwardAudience+createdAt; visibleToUserIds CONTAINS+createdAt.
- Push forward → screen sell, tab forwarded → SellHub.

## Cheap product remode
- Owner edit of **active** → `status: pending` (rules allow active→pending).
- Create/republish already pending (P0).

## Seller POS
- `sessionTotal` persisted SharedPreferences key `seller_pos_daily_{phone}_{YYYY-MM-DD}` (survives app restart same day).
