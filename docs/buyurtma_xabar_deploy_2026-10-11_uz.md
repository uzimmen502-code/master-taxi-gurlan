# «Буюртма хабар» — deploy тартиби (commit `0c0313e`, ҳеч бири бажарилмаган)

1. **Индекс** — `admin_news (category ASC, createdAt DESC)`. Жонлида йўқ
   (2026-10-11 текширилди). `--force`сиз; «Deleting N» қаторини ўқинг.
   Индекс `READY` бўлмагунча 2-банд чиқмасин (акс ҳолда админ рўйхати
   `failed-precondition` беради).
2. **Hosting (админ)** — жонли SHA устига шу commit (hosting навбати бор).
3. **Functions, номи билан** (тўлиқ `functions:default` эмас):
   `onAdminNewsCreate`, `onOrderCreate`, `onOrderUpdate`,
   `courierSubmitPayment`, `courierFinalizeCollection`, `courierMarkArrived`,
   `courierMarkCollectionArrived`, `courierMarkCarpetArrived`,
   `courierMarkAgroPickupArrived`.
   `notifyUserInApp` чақирадиган бошқа функциялар қайта deploy бўлгунча улар
   аввалгидек 2 push юборади (ёмонлашув йўқ). Ресторан функциялари —
   D-REST-15 (deploy қилинмаган) билан бирга кетади, эга қарори.
   ⚠ Бу branch'да deploy қилинмаган бошқа commit'лар бор — deploy branch
   жонли SHA'дан қурилсин.
4. **APK** — илова қисми (бош badge, `orderId`сиз хабар картаси, ёрлиқлар).
   Сервер ўзгаришлари эски APK билан мос.

Migration керак эмас (`pushDirect` йўқ бўлса `false`).

## Очиқ масалалар

- **O-4** — `admin_news` ўқиш `if true`: шахсий чеклар (манзил, сумма)
  ҳаммага очиқ. Тузатиш алоҳида `feat/admin-news-privacy` branch'ида
  (merge қилинмаган), релиз вақти — эга қарори. Бу commit унга зид эмас
  (у ердаги rules'да ҳам админ `list` рухсат).
- **Илова лентаси (PROPOSED)** — шахсий сўров (`whereIn targetUserId`,
  limit 30) барча шахсий хабарларни олиб, кейин буюртмаларни ажратади:
  мурожаат/ҳамён хабарлари кўп мижозда эски буюртма хабарлари лентадан
  тушиши мумкин. Тузатиш: `targetUserId + category + createdAt` индекси + APK.
- **Админ «Хабарлар» (умумий) бўлими** — худди шу 300 тадан клиент фильтри:
  буюртма хабарлари кўпайганда умумий хабарлар рўйхатдан тушади. Алоҳида
  вазифа (Firestore `!=` + `orderBy` чекловини текшириш керак).
- **`onOrderCreate` админ/сотувчи FCM'и** (admin_news эмас) — триггер қайта
  етказилса push такрорланиши мумкин; бу бўлим доирасидан ташқари қолди.
- **`orderReadyMode = auto`** — мижоз «Қабул қилинди» хабарини олмайди
  (дарҳол «Тайёр»). Мавжуд хатти-ҳаракат, ўзгартирилмади — қасдданми, эга
  тасдиқласин.
- **UNKNOWN** — репо бошланишидан (a6a0ac3) олдинги эски ҳужжатларда
  `category` бошқача бўлиши мумкинми. Репо тарихида барча ёзувчилар
  `category: 'order'` ёзади; бошқача бўлса улар янги админ рўйхатида
  кўринмайди.
- **Админ экрани браузерда кўз билан текширилмаган** — production'да админ
  логини ортида; hosting deploy'дан кейин эга кўриши керак.
