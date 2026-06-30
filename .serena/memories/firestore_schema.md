# Firestore Schema Map

Source of truth: `firestore.rules`, `firestore.indexes.json`. Doc IDs usually phone digits (`998XXXXXXXXX`); `phoneDocIdsMatch` tolerates 9-digit vs 12-digit. Admin SDK in CFs bypasses rules. "CF-only" = `allow write: if false` (Admin SDK writes).

## Identity / Users / Devices
- `users/{uid}` — profile+wallet. read owner/admin; create any-auth (must have `phone`, role only `user`, no wallet fields); update blocks wallet (CF-only) + role-transition/car-info/profile patches. Fields: phone,name,role(user|admin|superadmin|dispatcher|finance|auditor|driver|courier),bonusBalance,fcmToken,gender,birthDate,treeComponentId,treePersonId,blockedUntil,cancelCount.
  - `users/{uid}/wallet_ledger/{txId}` — immutable wallet log. CF-only write.
  - `users/{uid}/birthday_bonus_claims/{year}` — CF-only.
  - `users/{uid}/marshrut_state/{active}` — passenger↔marshrut-driver live sync. owner/matched-driver write.
  - `users/{uid}/driverProfiles/{marshrut}` — marshrut reg profile.
  - `users/{uid}/marshrut_block/{state}`, `users/{uid}/local_taxi_block/{...}` — usage blocks.
- `pending_codes/{phoneId}` — OTP/admin codes. CF-only write.
- `device_bindings/{hash}`, `device_bindings_legacy`, `device_aliases`, `device_change_requests` — phone↔device. CF-only (except change_requests create).
- `risk_events/{id}` — risk signals (admin review).
- `birthdate_change_requests/{id}` — birthdate change (admin approves).

## Taxi
- `drivers/{driverId}` — driver master + live online. read public; update owner/admin/work-state/marshrut-reg/approval patches. Fields: approved,approvalStatus,taxiType(local|alone|intercity|marshrut|both),taxiTypes[],isOnline,isBusy,isAvailable,lat,lng,seats,seatsLeft,car,plate.
- `trips/{tripId}` — local/alone/marshrut ride. read public; create auth (local `searching` / marshrut `pending`); update admin/marshrut-lifecycle/local-ownership. status: searching|pending|accepted|rejected|no_seats|cancelled|completed|expired. fare,driverId,acceptedDriverId,targetDriverId,taxiType,pickupMfy,dropoffMfy.
- `queue/{driverId}` — dispatch queue. guest-dispatch lifecycle patch allowed (no-auth whitelist). isActive,scheduleId,price,seatsLeft,queueEligibleAt,autoPausedReason.
- `schedules/{id}` — daily work schedule. seats,seatsLeft,date,direction,stops[],price(intercity),actualOnlineAt.
- `ratings/{id}` — driver ratings (create-only).
- `driver_requests/{id=uid}` — driver application. status pending|rejected|approved.
- `marshrut_route_prices/{from|to}` — flat route price. CF-only write (seed/admin). price,setByName,lockedByAdmin.
- `marshrut_coordinates/{key}` — crowd route geometry (confirmCount).
- `marshrut_dispatch_events/{id}` — dispatch log.

## Intercity
- `intercity_drivers/{id}` — profile+schedule+entertainment perms. seatCapacity,seats,price,isActive,isOnPanel,autoAcceptBookings,entertainmentAllowed,entertainmentIds[],from,to,stops.
  - `intercity_drivers/{id}/clients/{phone}` — loyalty aggregation. bookingCount,totalSpent,lastBookingAt.
- `intercity_bookings/{id}` — seat bookings. status pending→confirmed→completed; totalAmount>0,seats,pickup*,pickedUp.
- `intercity_booking_locks/{driverId}_{userKey}`, `intercity_passenger_locks/{phone}` — seat/one-active locks.
- `intercity_trips/{id}` (legacy web), `intercity_orders` (admin read stream only).

## Orders / Catalog / Stock
- `orders/{id}` — bread/food delivery. read staff or owner-phone; create auth (`status='new'`,total>0); update client-cancel/courier-fields/admin. fulfillmentStatus,paymentStatus,fulfillmentMode,courierId,items[],extras[].
  - `orders/{id}/payment_lines/{id}` + `payment_events/{id}` — CF-only.
- `bread_products/{id}`, `extra_products/{id}`, `food_catalog/{id}`, `food_inventory/{id}` — catalogs/stock. read public; write admin.
- `procurement_products/{code}` — buy prices. read auth; write admin.

## Courier
- `couriers/{uid}` — presence. isOnline,lat,lng,fcmToken.
- `courier_orders/{id}` — direct courier orders. status pending→...; create customer; update courier/admin.
- `delivery_routes/{id}` — multi-stop routes. status ready|active|completed; courierId,orderIds,currentIndex. create admin; courier lifecycle patch.
- `sell_submissions/{id}` — user sell offers. items[1..20],status pending|reviewed|archived,visibleToUserIds.
- `collection_tasks/{id}` — courier pickup tasks. CF-only write.
- `warehouse_stock/{code}` — inventory. read admin; CF-only write.

## Comms / Content / Config
- `support_chats/{uid}` (+ `/messages/{id}`) — support chat. client cannot set `fromAdmin:true`.
- `admin_news/{id}` — broadcast. category(info|update|promo|warning|emergency),audience(all|user|driver|courier).
- `notifications/{id}` — FCM queue. create needs targetPhone+sent==false; update only sent→true.
- `home_ticker_ads/{id}` — home ticker. admin write.
- `config/{passenger_cancel_block}` — cancel-block rules. write admin.
- `settings/{app|prices|settlement}` — server config/pricing. read all-but-courier; sensitive keys client-blocked. `settings/courier` — courier-only.
- `reports/{id}` — circles/dating abuse reports. create any-auth; read/manage admin.
- `complaints/{id}` — ad complaints.

## Ads / Jobs board (single `ads` collection)
- `ads/{id}` — DUAL: jobs/services board (`type` work|service|ad|sell) + marketplace (`type` cheap_product). read: board public, cheap_product if active|owner. Distinct Dart models: JobAd/JobsRepository vs AdModel/AdsRepository. status pending|active|completed|blocked. NO separate `jobs` collection.

## Circles ("Mening yaqinlarim" / Davra)
- `circles/{id}` — group. type(classmates|coursemates|colleagues),ownerId,memberCount,subgroupsEnabled. create auth (ownerId==self,memberCount==1); delete owner/admin.
  - `/members/{phone}` — self-write only. `/posts` `/events`(RSVP attendees) `/album` `/chat` `/subgroups`(reserved). member-scoped read; author/owner/admin delete.
- collection-group index on `members.userId` (for watchMyCircleIds).

## Relatives (private)
- `relatives/{uid}/people/{id}` (+ `/photos/{id}`), `relatives/{uid}/events/{id}` — owner-only read/write. (`tree_persons` is the shared mirror.)

## Dating (Tanishuv) — CF-only writes
- `dating_profiles/{uid}` — read if status==approved | owner | admin. status,gender,active,lastActive.
- `dating_interests/{id}` — read from/to/admin. fromId,toId,status,createdAt.
- `dating_matches/{id}` (+ `/messages/{id}`) — read participant; update only lastMessage/lastMessageAt; messages create participant (senderId==self,text≤2000).
- `dating_blocks/{uid}/list/{targetId}` — owner-only.

## Family Tree (Nasab daraxti, global) — CF-only writes
- `tree_persons/{id}` — graph nodes. read if node `componentId`==caller's `myTreeComponent()` | owner | claimer | admin. componentId,fullName,ownerUid,claimedBy,fatherId,motherId,spouseId,survivorId.
- `tree_link_invites/{id}` — read from/to/admin.
- `tree_redirects/{oldId}` — old→survivor after merge. read auth.
- `tree_history/{id}` — audit/undo. read same-component | admin.

## Settlement Ledger (double-entry) — all CF-only writes; read `isFinanceReader()`
- `journal_entries/{idemKey}` (immutable, append-only), `ledger_accounts/{id}` (materialized balances), `settlements/{id}` (read also party), `period_closings/{YYYY-MM-DD}`, `ledger_exceptions/{id}`. See `mem:settlement_ledger`.
- `wallet_idempotency/{key}` — wallet idempotency guard (CF-only).

## Payments / Reports
- `payout_requests/{id}` — CF-only. `daily_reports/{YYYY-MM-DD}` — read admin, CF-only.

## Composite indexes (collection: [fields])
- dating_profiles:[status,gender,active,lastActive↓] · dating_interests:[toId,status,createdAt↓]/[fromId,status,createdAt↓] · dating_matches:[users(arr),lastMessageAt↓]
- tree_persons:[componentId,fullName] · tree_link_invites:[toUid,status,createdAt↓]/[fromUid,createdAt↓] · tree_history:[componentId,createdAt↓]
- trips: many (userPhone+status+completedAt↓; taxiType+status; acceptedDriverId+status+...; status+createdAt; targetDriverId+status+taxiType; status+expiresAt)
- schedules:[taxiType,date,isActive]/[driverId,...]/[date,isActive] · queue:[taxiType,isActive,autoPausedReason]/[taxiType,onlineAt]
- orders:[userPhone,createdAt↓]/[status,createdAt]/[userPhone,paymentStatus] · drivers:[isOnline,*] · ads:[type,status,...] (several)
- intercity_bookings/intercity_drivers/clients/couriers/delivery_routes/courier_orders/collection_tasks/driver_requests/payout_requests/admin_news/sell_submissions — see firestore.indexes.json.

## Rules helpers (key)
isAuth, isOwner(uid), isAdmin()={admin,superadmin,dispatcher}, isStaff()=+courier, isFinanceReader()={admin,superadmin,finance,auditor}, phoneFromToken/phoneDigits/userDocIdFromPhoneToken, phoneDocIdsMatch (9↔12 digit), myTreeComponent(), walletFieldsUntouched/notChanged, approvedDriverForTaxi(driverId,taxiType), isCircleMember/isCircleOwner, plus many whitelisted-patch helpers per domain (intercity*, marshrut*, ad*, cheapProduct*, sellSubmission*, queueGuestDispatchPatchOnly, *LifecycleUpdate).
