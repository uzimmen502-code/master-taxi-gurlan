# Marshrut Dispatch Release Notes

Бу ҳужжат Marshrut taxi dispatch архитектураси бўйича қилинган ўзгаришларни қисқа жамлайди.

## Асосий мақсад

Marshrut taxi flow user танлайдиган driver model'дан professional dispatch model'га ўтказилди:

`user -> request -> dispatch queue -> 1-навбат -> 2-навбат -> 3-навбат -> accept/reject/timeout`

## Қўшилган имкониятлар

- Queue-based dispatch: driver'лар `onlineAt` бўйича навбатда чақирилади.
- Duplicate active request protection: user'да `pending` ёки `accepted` marshrut request бўлса, янги request очилмайди.
- Dispatch session audit: ҳар бир request session ID билан history'га тушади.
- Offer timeout setting: admin offer timeout секундларини `Policy` tab'дан созлайди.
- Auto-pause policy: driver кетма-кет timeout қилса, queue'дан вақтинча чиқарилади.
- Admin policy controls: timeout threshold ва offer timeout admin panel'дан бошқарилади.
- Active requests admin fallback: admin pending/accepted trip'ларни кўради, cancel ёки complete қила олади.
- Driver accepted trip lifecycle: driver accepted trip'ни panel'да кўради ва `Якунлаш` билан completed қилади.
- Seat sync protection: accept/cancel ҳолатларида `schedule` ва `queue` seats sync қилинади.
- Race condition guards: timeout/reject/accept/cancel кечикиб келса, нотўғри status overwrite қилмайди.
- Dispatch history: offered, rejected, timeout, accepted, completed, admin_completed, cancelled, admin_cancelled, driver_auto_paused event'лари кўринади.

## Admin экранлар

- `Маршрут мониторинги`
  - Фаол ҳайдовчилар
  - Policy
  - Auto-paused
  - Бугунги сафарлар

- `Marshrut dispatch history`
  - Active requests
  - History

## Firestore ўзгаришлари

- `trips` ҳужжатларига dispatch metadata қўшилди:
  - `dispatchSessionId`
  - `dispatchAttempt`
  - `dispatchTotal`
  - `dispatchMode`
  - `offerTimeoutSeconds`
  - `completedBy`
  - `completedByPhone`

- `marshrut_dispatch_events` audit collection ишлатилади.
- `settings/app` ичида policy settings сақланади:
  - `marshrutTimeoutAutoPauseStreak`
  - `marshrutOfferTimeoutSeconds`

## Rules ва Indexes

- Firestore rules dispatch queue lifecycle patch'ларига мослаштирилди.
- Firestore indexes қўшилди:
  - `trips: taxiType + status`
  - `trips: userPhone + taxiType + status`
  - `trips: acceptedDriverId + status + taxiType`
  - `queue: taxiType + isActive + autoPausedReason`

## Текширилганлар

- `dart analyze` targeted files учун тоза ўтди.
- `flutter test` ўтди.
- User web build ўтди.
- Admin web build ўтди.
- Combined hosting build ўтди.
- Firestore rules dry-run ўтди.
- Firestore indexes dry-run ўтди.
- Firebase Hosting dry-run ўтди.

## Қолган warning'лар

Бу warning'лар build'ни тўхтатмади:

- Admin web wasm dry-run: `dart:html unsupported`.
- Geolocator deprecated parameters.
- Кўп UI файлларда `withOpacity` deprecated info.
- Full `dart analyze`да warning/info бор, лекин dispatch targeted analyze ва build'лар ўтган.

## Deploy олдидан

Deploy қилишдан олдин:

- `docs/marshrut_dispatch_test_plan_uz.md` бўйича test project ёки live test data'да қўлда сценарийларни текшириш.
- Untracked dispatch files staging'га тушганини текшириш.
- Firestore rules/indexes deploy қилиш.
- Combined hosting artifact билан hosting deploy қилиш.

Deploy commands, агар тасдиқ берилса:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_combined_web.ps1
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only hosting
```
