# Маҳаллий такси — сервер нархи ва ҳамён (2026-10-07)

## Нима учун
Тўлиқ тест (`functions/test/local_taxi_*.test.js`) қуйидагиларни исботлади:
- `trips` яратиш қоидаси `userPhone`ни чақирувчига боғламасди → ҳайдовчи
  бировнинг номидан `passengerWalletIntent` + `lockedFare` билан trip яратиб,
  ўзи қабул қилиб, `completeLocalTrip` орқали **бегона ҳамённи 0 гача бўшата олар эди**;
- ҳамёндан ечилган пул `admin_clearing`га тушарди, ҳайдовчига эмас;
- `lockedFare`ни йўловчи ҳам, ҳайдовчи ҳам исталган қийматга ёза оларди;
- нарх клиентда ҳисобланарди, `tariffVersion` йўқ эди.

## Эга қарорлари (CONFIRMED, 2026-10-07)
| Қарор | Амалга оширилиши |
|---|---|
| Ҳамён қисми — **ҳайдовчи ҳамёнига** | `completeLocalTrip`: Dr `passenger_credit:{йўловчи}` / Cr `passenger_credit:{ҳайдовчи}`, иккала `users.bonusBalance` + `wallet_ledger` (`local_taxi_debit` / `local_taxi_credit`) |
| Нарх **серверда**, `tariffVersion` билан; админ мавжуд экранда таҳрирлайди | `functions/local_taxi.js`: `createLocalTaxiTrip`, `lockLocalTripFare`, `adminSetLocalTaxiPrices`; trip'да `tariffVersion` + `tariffSnapshot`; тарих `local_taxi_tariffs/v{n}` (ким, қачон, аввалги қиймат) |
| **Манзил мажбурий** | Илова ва сервер манзилсиз буюртмани рад этади (`DESTINATION_REQUIRED`) |
| Қўшимча коэффициент — **фақат тун, автоматик** | Сервер вақти Asia/Tashkent 23:00–06:00 → ×1.5; байрам/ёмғир/шошилинч/кутиш олиб ташланди |

Формула (эски клиент формуласи билан бир хил, кутишсиз):
`(base + round(км × perKm)) × coef × масофа_коэф × тун_коэф` → 500 га яхлит.
Пул бутун сон; коэффициентлар permille (×1000), BigInt.

## PROPOSED (эга тасдиқламаган, ўтиш даври)
- Эски илова яратган (сервер нархисиз) trip'лар: ҳайдовчи нархи билан **нақд**
  якунланади, ҳамён **ечилмайди**. Янги илова чиққандан кейин бу йўлни ёпиш мумкин.
- Directions жавоб бермаса — буюртма рад (`ROUTE_UNAVAILABLE`), тахминий нарх йўқ.
- `settings/prices`да `local_base`/`local_per_km` бўлмаса — `TARIFF_NOT_CONFIGURED`
  (hardcode default 5000/1500 ишлатилмайди).

## Deploy тартиби (эга қарори билан)
1. `functions` (номи билан): `createLocalTaxiTrip`, `lockLocalTripFare`,
   `adminSetLocalTaxiPrices`, `completeLocalTrip`, `expirePendingTrips`.
2. Hosting (admin web) — `TaxiPriceScreen` CF орқали сақлайди.
3. `firestore.rules` — **алоҳида** буйруқ билан.
4. Янги илова версияси.

Rules илова версиясидан **олдин** чиқиши керак: янги илова release'да
`releasedAt` ёзади, эски rules буни рад этади.
Deploy'дан олдин: production `settings/prices`да `local_base` ва `local_per_km`
борлигини текшириш (йўқ бўлса админ экранида бир марта сақлаш).
