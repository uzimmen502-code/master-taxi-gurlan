# Marshrut Dispatch Test Plan

Бу checklist Marshrut taxi dispatch архитектурасини production'га чиқаришдан олдин қўлда текшириш учун.

## 1. Асосий Queue Dispatch

- User pickup/dropoff MFY танлайди ва marshrut taxi қидиради.
- Тизим 1-навбатдаги driver'га offer юборади.
- 1-driver жавоб бермаса, offer timeout бўлади.
- Тизим 2-навбатдаги driver'га offer юборади.
- 2-driver рад этса, тизим 3-навбатдаги driver'га offer юборади.
- 3-driver қабул қилса, user'да accepted dialog чиқади.

Кутиладиган натижа:
- Offer'лар кетма-кет юборилади.
- Бир вақтда бир нечта driver'га бир request кетмайди.
- Dispatch history'да `offered`, `timeout`, `rejected`, `accepted` event'лар кўринади.

## 2. Duplicate Request Protection

- User marshrut request очади.
- Биринчи request `pending` ёки `accepted` ҳолатда турганида яна янги request очишга уринади.

Кутиладиган натижа:
- User'га active marshrut request борлиги ҳақида хабар чиқади.
- Янги duplicate request яратилмайди.
- Агар эски `pending` request'нинг муддати ўтган бўлса, у `expired` қилинади ва янги request очилиши мумкин.

## 3. Driver Timeout Policy

- Admin panel'да `Маршрут мониторинги -> Policy` орқали timeout auto-pause threshold'ни текширинг.
- Driver ketma-ket белгиланган threshold миқдорида offer'га жавоб бермасин.

Кутиладиган натижа:
- Driver'нинг `dispatchTimeoutStreak` ошади.
- Threshold'га етганда driver queue'дан вақтинча чиқади.
- Admin `Auto-paused` tab'да driver'ни кўради.
- Driver panel'да auto-paused banner чиқади.
- Admin ёки driver reactivation қилганда driver навбатга қайтади.

## 4. Offer Timeout Setting

- Admin panel'да `Driver offer timeout` қийматини 5-120 секунд оралиғида ўзгартиринг.
- User янги marshrut request очсин.

Кутиладиган натижа:
- Waiting screen таймери admin белгилаган секундга мос ишлайди.
- Trip `offerTimeoutSeconds` билан сақланади.
- Dispatch history'да offer timeout қиймати кўринади.

## 5. Seat Sync

- Driver'да `seatsLeft` 2 бўлсин.
- User request очади, driver қабул қилади.

Кутиладиган натижа:
- `schedules.seatsLeft` 1 тага камаяди.
- `queue.seatsLeft` 1 тага камаяди.
- Агар seat 0 бўлса, driver queue active ҳолатдан чиқади.

Cancel сценарий:
- Accepted trip'ни user ёки admin cancel қилсин.

Кутиладиган натижа:
- `schedules.seatsLeft` 1 тага қайта ошади.
- `queue.seatsLeft` 1 тага қайта ошади.
- Double cancel қилинса, seat қайта-қайта ошмайди.

## 6. Trip Completion

- Driver request'ни қабул қилади.
- Driver panel'да accepted trip card чиқади.
- Driver `Якунлаш` тугмасини босади.

Кутиладиган натижа:
- Trip status `completed` бўлади.
- Dispatch history'да `completed` event чиқади.
- User кейин янги marshrut request оча олади.

Admin fallback:
- Driver trip'ни якунламаса, admin `Dispatch history -> Active requests` tab'дан accepted trip'ни `Completed` қилади.

Кутиладиган натижа:
- Trip status `completed` бўлади.
- Dispatch history'да `admin_completed` event чиқади.
- Trip ҳужжатида `completedBy: admin` сақланади.

## 7. Race Condition Checks

Timeout vs accept:
- Driver offer вақти тугашига яқин `accept` босади.

Кутиладиган натижа:
- Агар transaction пайтида trip ҳали `pending` бўлса, `accepted` бўлади.
- Агар trip муддати ўтган бўлса, `expired` бўлади ва timeout policy ишлайди.
- Accepted trip кейинчалик кечикиб келган timeout билан `expired` бўлиб кетмайди.

Reject vs accept/cancel:
- Driver кечикиб `reject` босади, trip эса аллақачон `accepted`, `completed`, `cancelled` ёки `expired` бўлган бўлади.

Кутиладиган натижа:
- Trip status ўзгармайди.
- Rejected event ёзилмайди.
- Reject policy ишламайди.

## 8. Admin Monitoring

- `Dispatch history -> Active requests` tab'ни очинг.
- Pending ва accepted trip'лар кўриниши керак.
- Pending trip учун `Admin cancel` ишласин.
- Accepted trip учун `Completed` ва `Admin cancel` ишласин.

Кутиладиган натижа:
- Admin action'лар history'да алоҳида кўринади:
  - `admin_cancelled`
  - `admin_completed`

## 9. Minimal Production Readiness

Production'га чиқишдан олдин қуйидагилар камида бир марта live data ёки test project'да текширилсин:

- 3 driver билан queue dispatch.
- 1 timeout, 1 reject, 1 accept сценарий.
- Duplicate request protection.
- Seat decrement ва restore.
- Auto-pause ва reactivation.
- Driver completed.
- Admin completed.
- Admin cancelled.
- Full user web build.
- Full admin web build.
