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
