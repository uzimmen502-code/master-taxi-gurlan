# Taxi Modules (local + marshrut + intercity + driver)

Backbone: `RidesRepository` (`repositories/rides_repository.dart`) over `trips`; driver state in `schedules`/`queue`/`drivers`. Phone via `core/utils/formatters.dart` (canonicalPhoneId). MFY normalize `utils/gurlan_places.dart` (GurlanPlaces.normalizeMfyName). Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`. Money: `mem:settlement_ledger`.

## local_taxi (door-to-door, "alone"/"local")
- `features/local_taxi/passenger/screens/{local_taxi_screen,searching_screen,local_taxi_active_trip_screen}.dart`; controllers `local_taxi_controller.dart`,`searching_controller.dart`; `services/price_service.dart`.
- `LocalTaxiController` (GPS + saved places pref `saved_places` max6), `SearchingController`, `PriceService` (static).
- Flow: set from/to → createSearchRequest(taxiType `'local'`) → SearchingController radius 3→5→7km (30s each) → drivers.getAvailable filtered by distance → selectDriver sets trips.targetDriverId → driver accepts → active trip.
- Pricing: `PriceService.calculate = base + km*perKm`; `settings/prices`.local_base/local_per_km (fallback 3000/2000). Fare confirmed driver-side on finish.
- GOTCHA: passenger writes taxiType `'local'`, driver prefs use `'alone'`; bridged by `DriverHomeController._matchesTaxiType`. No seats for local. `reserved`=10s hold.

## marshrut (fixed-route shuttle, system queue dispatch — passenger does NOT pick driver)
- passenger `{marshrut_taxi_screen,marshrut_waiting_screen,marshrut_accepted_screen}.dart`; controllers `marshrut_search_controller.dart`,`marshrut_waiting_controller.dart`. driver `driver_panel_marshrut_screen.dart`,`driver_register_marshrut_screen.dart`; controllers `marshrut_driver_panel_controller.dart`,`marshrut_register_controller.dart`. widgets `route_card`,`ride_request_card`,`mfy_dropdown`,`schedule_card`.
- Repos: MarshrutDriverRepository, MarshrutRoutePriceRepository (`routeKey='from|to'`), MarshrutBlockRepository, SchedulesRepository, QueueRepository. Service MarshrutPricingService.
- Flow: driver registers route+price → online (joins queue) → passenger searches MFY from/to (searchActiveToday: filters route/seats/online/price>0/≤5km) → ЧАҚИРИШ → QueueRepository.findNextEligibleMarshrutDrivers (queue order, limit7) → MarshrutWaitingController calls drivers sequentially (timeout default 15s, getMarshrutOfferTimeoutSeconds), createMarshrutRequest per driver → driver accept/reject → settlement on complete.
- **Pricing**: FLAT per route in `marshrut_route_prices/{from|to}`, CF-only. First driver `seedMarshrutRoutePrice` (locked after), admin `adminSetMarshrutRoutePrice`. **price<=0 reys HIDDEN** from search AND queue. No commission — only change refunded via Settlement Ledger.
- GOTCHAS: panel dispose() ≠ offline (only toggle/forceLeave/app-kill or CF marshrutDriverAutoOffline). Route validity: forward iFrom<iTo, backward iFrom>iTo (normalized stop indices). Block ONLY on cancel-after-accepted (`core/passenger_cancel_block_rules.dart`); pending/waiting cancel free. Reachability probe 5s auto-offline on Firestore unreachable. End-stop dialog within 1.0km of route end.

## intercity_taxi (city-to-city, seat reservation, direct Firestore txn not CF)
- passenger `intercity_taxi_screen.dart`; controllers `intercity_taxi_controller.dart`,`me_and_passengers_controller.dart`. driver `intercity_driver_panel_screen.dart`; controller `intercity_driver_panel_controller.dart`.
- Repos IntercityRidesRepository, IntercityBookingsRepository; service IntercityPickupRouteService. Models IntercityRide, IntercityBooking. Places `utils/intercity_places.dart`.
- Flow: passenger from/to(+Tashkent district)+today/tomorrow+passengers → watchActiveRides (filter city/route/date, seats≥passengers, sort rating) → bookRide → createBooking (TRANSACTION: seat decrement + loyalty + driver notify) → driver accept/reject/pickUp/complete; calculatePickupRoute optimizes order.
- Pricing: per-seat `ride.price` set by driver at schedule reg (pref `intercity_price_{type}`). total=price*passengers; price<=0 → ride_not_accepting.
- GOTCHAS: requires fresh FirebaseAuth idToken before booking. leavePanel(isOnPanel=false) keeps ride visible; endTripListing cancels bookings+isActive=false. Optimistic local seat stats via applyLocalBookingStats. Passengers clamp 1..4.

## driver_home (universal driver home: local/alone + multi-seat dispatch)
- `features/driver_home/screens/{driver_home_screen,driver_trip_screen}.dart`; `driver_home_controller.dart`. widgets online_pulse_toggle,fare_calculator_dialog,queue_card,trip_request_dialog,active_ride_card,seats_card.
- Uses DriverRepository/SchedulesRepository/RidesRepository/QueueRepository; models DriverSession,TripRequest,QueueEntry,ActiveTrip; `utils/fare_calculator.dart`. Services BackgroundGpsService,BalanceService,SettlementService,DeferredSettlementQueue.
- Flow: load session → startLocalWork (today schedule seats=1 + online) → toggleOnline→goOnline (GPS + drivers.goOnline + queue.join + BackgroundGpsService) → incoming trips filtered (age<3min, taxiType match, within radiusKm+0.5) → reserveRide(10s) → confirmReservedRide→acceptRide → trip → finishRide(fare,cashPaid) → settlement.
- Settlement: finishRide if cashPaid>fare → SettlementService.openSettlement (opId `settle_trip_{id}`); fallback BalanceService.creditChange (`change_trip_{id}`); else DeferredSettlementQueue.enqueue (offline).
- GOTCHAS: must "ИШНИ БОШЛАШ" (schedule) before online. local/alone NO seat decrement; non-local decrements schedules.seatsLeft + driver/queue seats. marshrut trips excluded from this stream. abandonRide → trip back to `searching`.

## driver_schedule (register today's reys)
- `features/driver_schedule/screens/driver_schedule_screen.dart`; `driver_schedule_controller.dart`. taxiType = marshrut|alone|intercity.
- marshrut→MarshrutDriverRepository.register; alone/intercity→SchedulesRepository.registerDriverSchedule. Writes `schedules` (expiresAt 23:59:59). Only intercity sets `price`; marshrut price via separate route-price CF; alone no price.
- GOTCHA: atomic register deactivates old schedules + updates queue/drivers. scheduleDay=tomorrow only for intercity when departureIsTomorrow.
