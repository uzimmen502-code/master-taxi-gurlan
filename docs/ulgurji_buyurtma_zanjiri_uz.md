# Улгуржи бозор — буюртма занжири: лойиҳа ва босқичлар

> Сана: 2026-10-31. Ҳолат: 1-босқич (қадоқ + қолдиқ) LIVE; 2–6 — қурилмоқда.
> Манба: эга қарорлари (чат, 2026-10-31) + код таҳлили (relay, ҳамён, ресторан).

## 1. Эга қарорлари — CONFIRMED

| # | Қарор |
|---|---|
| Q-1 | Харидор **ҳамёндан олдиндан** тўлайди (товар + етказиш). Пул AVA'да ушланади. |
| Q-2 | Ҳудуд — **бутун Ўзбекистон**. |
| Q-3 | Етказиш — **фақат AVA курьерлари** (сотувчи ўзи етказмайди). |
| Q-4 | AVA улуши ва курьер ҳақи — **админда таҳрирланади** (версияли, audit). |
| Q-5 | Пул сотувчига — курьер **«етказилди» кодини** киритганда, автоматик. |
| Q-6 | 14×14 вилоят матрицаси ва 20 кг+ нархлар — админда бўш жадвал, рақамларни эга/админ киритади. |
| Q-7 | Юридик тасдиқ кутилмайди — **ички синов режими** (тестчилар) билан қурилади; ҳаммага очиш — эга қарори. |
| Q-8 | Қадоқ ≤5 (ҳар бирининг поғонаси, ихтиёрий расми), сонли қолдиқ харидорга кўринади; битта ихтиёрий видео. |

## 2. Архитектура — PROPOSED (мавжуд тизимлар устида, параллел тизим йўқ)

Икки сервер коди умумий код ишлатмайди (`functions` = ҳамён/ledger, `functions_demand` = relay/курьер).
Улар **Firestore ҳужжатлари орқали** боғланади (relay'даги `shipments.paymentStatus` каби).

```
харидор ── quoteWholesaleOrder (demand) ──► wholesale_quotes/{id}   (сервер ёзади, 15 дақиқа)
        └─ placeWholesaleOrder (default) ─► 1 транзакция: квота текшируви, қолдиқ −N,
                                            ҳамён Dr passenger_credit / Cr escrow:wholesale:{order},
                                            wholesale_orders/{id} = placed
demand триггер `onWholesaleOrderCreated` (wholesale_orders onCreate, `placed`) ─► relay shipment АВТОМАТИК (эга = сотувчи, олувчи = харидор),
                                            1 direct LEG (вилоятлараро — икки ҳудудни қамраган
                                            курьер/юк; бўлиш — admin `adminPlanShipmentRoute`)
         (сотувчи қабул/рад ҚИЛМАЙДИ — эга, 2026-10-31; буюртма дарҳол етказишга ўтади)
default триггер (wholesale_orders onUpdate):
   placed → in_delivery (shipment очилганда) → етказиш ҳақи escrow:wholesale → escrow:{shipmentId}
   cancelled → харидорга тўлиқ қайтариш + қолдиқ +N (идемпотент)
default триггер (custody delivery, мавжуд onLogisticsCustodyEvent):
   wholesaleOrderId бор → товар пули: сотувчига (товар − AVA улуши), AVA улуши earnings:ava_wholesale_fee
```

- **Нарх** — фақат серверда: қадоқ поғонаси (`priceForQty` қоидаси, `platform_pricing.js` билан бир хил)
  × миқдор; етказиш — relay тарифи (`module_tariffs/logistics_v*`, `tariffVersion` муҳрланади).
- **AVA улуши** — `settings/wholesale_orders.avaFeeBps` (админ callable, audit, версия буюртмада муҳрланади).
- **Қолдиқ** — `wholesale_stock/{productId}` (1-босқич), камайиш/қайтиш фақат транзакцияда.
- **Идемпотентлик** — ҳар пул ҳаракати ўз калити билан (`wholesaleHold:{order}`, `wholesaleRelease:{order}`,
  `wholesaleRefund:{order}`, `wholesaleShipFund:{order}`); `placeWholesaleOrder` — `clientRequestId`.
- **Дарвоза** — `module_config/wholesale_orders_all.{enabled, stage, testerIds}` (logistics андозаси):
  `internal` + тестчилар; ҳаммага очиш — эга.
- **Relay ўзгаришлари** (минимал): shipment'да `recipientId` (харидор) — `getShipmentSecrets`
  deliveryCode'ни олувчига ҳам беради; `source: 'wholesale'`, `wholesaleOrderId`; ички яратиш
  ёрдамчиси (callable'сиз, `createShipmentInternal`) — эга текшируви чақирувчи функцияда.

### Буюртма ҳолатлари (сервер state machine)

`placed → in_delivery → delivered`; `placed → cancelled` (харидор, етказиш очилмагунча);
`placed | in_delivery → cancelled` (admin, курьер ҳали олмаган бўлса); ҳар ўтиш — `history` (immutable). **Сотувчи буюртмага аралашмайди** (қабул/рад йўқ, эга 2026-10-31).

## 3. Босқичлар

| # | Нима | Ҳолат |
|---|---|---|
| 1 | Қадоқ, қолдиқ (`setWholesaleStock`), битта видео | **LIVE** 2026-10-31 |
| 2 | Сервер: квота, буюртма, ушлаш, қолдиқ −N, бекор + қайтариш, дарвоза, AVA улуши созламаси (сотувчи қабул/рад йўқ) | **LIVE** 2026-10-31 (ёпиқ: дарвоза ҳужжати йўқ), rules c2dc93b7 |
| 3 | Relay боғлаш: буюртма берилиши билан shipment АВТОМАТИК, етказиш ҳақи escrow'га, етказилганда товар пули сотувчига | код + тест тайёр (`feat/ulg-orders`), **production'да ҲАЛИ йўқ** (deploy қилинмаган) |
| 4 | Илова: «Буюртма бериш», харидор буюртмалари + кузатув; сотувчига фақат «янги буюртма — курьер олиб кетади» хабари ва рўйхат (қабул/рад тугмаси ЙЎҚ) | — |
| 5 | Админ: буюртмалар, AVA улуши, вилоят матрицаси + 20 кг+ нархлар жадвали (бўш), тестчилар | — |
| 6 | Аҳоли бозори қадоқлари | — |

Ҳар босқич: тест (позитив/негатив/чегара) → rules алоҳида → функциялар номма-ном → hosting.
APK — фақат эга рухсати билан.

## 4. Хавфлар / UNKNOWN

- Шаҳарлараро LEG'ни ким олади — икки вилоятни қамраган курьер ёки «юк» провайдери; бўлмаса LEG
  муддати ўтади → admin `adminReactivateLeg` / `adminPlanShipmentRoute`.
- Тариф матрицаси тўлдирилмаса — квота `zone_not_found` / `tariff_extra_price_missing` → харидорга
  «етказиш нархи ҳали белгиланмаган», буюртма йўқ.
- Курьерга тўлов ҳозир қўлда (`supplier_payable`) — relay каби.
- **3-босқич relay guard'лари ҲАЛИ ЖОНЛИДА ЙЎҚ** (`feat/ulg-relay-guards` бранчи, 2026-10-31): жонли
  relay функциялари (`getShipmentSecrets`, `cancelLogisticsOrder`, `cancelDemand`, `acceptOffer`,
  `fundShipmentEscrow`, `onLogisticsShipmentUpdate`, `onLogisticsCustodyEvent`) lineage'дан фарқ қилади —
  бошқа сессияларнинг тасдиқланмаган ўзгаришлари туфайли қайта deploy қилинмади. Шу пайтгача Ulgurji
  жўнатмасининг эгаси (сотувчи) API орқали: жўнатмани бекор қилиши (`cancelLogisticsOrder`), LEG'ни
  бекор қилиши (`cancelDemand`), ўзи тўлаши (`fundShipmentEscrow` → SHIP_FUND аномалия), **етказиш
  кодини олиши** (`getShipmentSecrets` эгага беради → курьер билан келишиб харидорсиз «етказилди»)
  мумкин; relay REFUND етказиш ҳақини **сотувчи ҳамёнига** қайтаради. Тестларда қулфланган.
  **`module_config/wholesale_orders_all` дарвозаси guard'лар live-merge билан deploy бўлгунча ЁПИҚ турсин.**
  Харидор коди — алоҳида `getWholesaleDeliveryCode`; товар пули — алоҳида `onWholesaleCustodyEvent`.
- Firestore rules ҳажми чегарада (262 031 / 262 144) — янги қоидадан олдин изоҳлар қисқартирилади.
