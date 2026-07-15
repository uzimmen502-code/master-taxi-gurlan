# Sell / Marketplace seller UX

## Entry
- Home `sell` module + SellerCtaBanner → **`SellHubScreen`** (`features/sell/screens/sell_hub_screen.dart`).
- **2 paths only**: Platforma (`SellOfferScreen` → `sell_submissions`), Onlayn bozor (create/my ads/feed sheet). Jobs P2P «Сотаман» / `AdKind.sell` / `publishAsPublicAd` **removed**.
- Tabs: Менинг таклифларим | Менга юборилган (`watchForwardedForUser`).

## Platform submissions
- Model `SellSubmission`: `collectionCompleted`, `progressLabel`, `estimatedTotal`, forward/collection fields.
- Tile `SellSubmissionTile` — status chip, sum, forward badge, collection task line (`CollectionTasksRepository.getById` + `finalValue`).
- Repo `SellOffersRepository` — create/watch/forward status only (no Jobs ads bridge).
- Indexes: forwardAudience+createdAt; visibleToUserIds CONTAINS+createdAt.
- Push forward → screen sell, tab forwarded → SellHub.
- Admin forward: users only (no «Иш топ Сотаман» checkbox).

## Cheap product remode
- Owner edit of **active** → `status: pending` (rules allow active→pending).
- Create/republish already pending (P0).

## Seller POS
- `sessionTotal` persisted SharedPreferences key `seller_pos_daily_{phone}_{YYYY-MM-DD}` (survives app restart same day).
