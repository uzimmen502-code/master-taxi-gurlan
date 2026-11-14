# Жонли код нусхалари (2026-11-14)

Бу функциялар production'да турибди, лекин уларнинг коди **ҳеч бир Git коммитида йўқ эди**
(2026-10-31 да тўғридан-тўғри deploy қилинган). Репозиторийдан қайта deploy қилинса, ичидаги
Улгуржи ҳимояси йўқолиб кетарди. Шунинг учун жонли манба шу ерга сақланди.

Манба: Cloud Functions v1 `:generateDownloadUrl` (2026-11-14), `.env*` файллар олиб ташланган,
фақат `.js` ва `package.json` олинган.

| Функция | Регион | Муҳим файл | Изоҳ |
|---|---|---|---|
| onLogisticsShipmentUpdate | us-central1 (default) | `relay_escrow.js` (sha d105dfde…) | Улгуржи жўнатмаси қайтими сотувчига эмас, `escrow:wholesale:{orderId}` га |
| acceptOffer | europe-west1 (demand) | `api/offers.js` (f656c95d…) | `assertNotWholesaleLegInTx` — Улгуржи LEG ҳимояси |
| cancelDemand | europe-west1 (demand) | `api/offers.js` (f656c95d…) | ўша |

Қоида: бу функцияларни deploy қилишдан олдин уларнинг коди шу нусха билан солиштирилсин
ва ҳимоя қаторлари янги манбага кўчирилсин. Ушбу файллар **deploy манбаи эмас** — фақат архив.
