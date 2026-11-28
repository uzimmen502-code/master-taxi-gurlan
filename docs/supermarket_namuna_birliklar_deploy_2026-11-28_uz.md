# AVA Супермаркет: намуна гуруҳлари ва ўлчов бирликлари — deploy ҳужжати (2026-11-28)

## 1. Вазифа

Эга сўзи, 2026-11-28:
- «қўш» — гуруҳи йўқ намуналар учун янги гуруҳлар.
- «намуналар нархи ёнига керакмас, лекин ҳақиқий маҳсулотлар учун: дона, кг, литр ва бошқа ўлчов бирликлар керак».
- Aliases тўғри деб тасдиқланди: семичка, мойка, горох, «Океан … гели».
- «MILTER писта ёғи» → кунгабоқар ёғи: «Ҳа».
- «Консерва ва тузламалар» гуруҳи (Қуриқ қаймоқ, тузланган бодиринг, тузланган қалампир): «ҳа».
- Бирликларни чиқариш тартиби: «ок» — аввал web ва APK, кейин server functions.

**Ҳали эга тасдиқламаган (PROPOSED):**
- гуруҳлар қайси бўлимга тушиши, уларнинг бирлиги, қадами ва синонимлари;
- бирликлар рўйхати (g, ml, box, m).

## 2. Ҳолат

| Қисм | Шохча / коммит | Ҳолат |
|---|---|---|
| Сервер + воситалар | `feat/sm-sample-groups` | push қилинди, **deploy ЙЎҚ** |
| Клиент (web/APK) | `feat/sm-units-samples` 80483153 | push қилинди, **deploy ЙЎҚ** |
| prod `taxonomy/supermarket` | v1 (v3 файли мазмуни) | v2 га кўтарилмаган |
| prod намуналар | 49 тасида гуруҳ бор ва `smSample` = true | қолган 10 таси — пастдаги 3–5-қадамларда |

## 3. Тартиб (ўзгартирилмасин)

**1. Web (hosting) + APK — `feat/sm-units-samples`.**
- Жонли SHA устига қурилади, навбат билан.
- Бу қадамдан кейин клиент 9 та бирликнинг ҳаммасини танийди.
- Намуна нархи бирликсиз кўрсатилади.

**2. Functions — APK фойдаланувчиларга етиб боргандан КЕЙИН, номи бўйича, `--config <abs>\firebase.json` билан.**

Deploy қилинадиган функциялар:
- `adminSetSupermarketTaxonomy`
- `adminUpsertSupermarketOffer`
- `partnerUpsertSupermarketOffer`
- `placeSupermarketOrder`
- `adminReportSupermarketShortage`
- `respondSupermarketShortage`
- `adminSupermarketImportTemplate`, `adminSupermarketImportPreview`, `adminSupermarketImportConfirm`
- `partnerSupermarketImportTemplate`, `partnerSupermarketImportPreview`, `partnerSupermarketImportConfirm`

**Нега шу тартибда:**
- Янги бирликлар (g, ml, box, m) фақат functions deploy'дан кейин қабул қилинади.
- Эски клиент бундай бирликни танимайди ва гуруҳ бирлигини кўрсатади, масалан нотўғри «/кг».

**3–5. Маълумот.** Буни эга ишга туширади. Deploy'га боғлиқ эмас, таксономия 1-қадамдан олдин ҳам кўтарилиши мумкин:
- янги гуруҳлар kg/pack/piece бирлигида, буни эски клиентлар ҳам танийди.

```
$env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token)
node functions/tools/seed_supermarket.js --upgrade --taxonomy-file functions/tools/data/supermarket_taxonomy_v4.json --expected-version 1 --project master-taxi-gurlan [--apply]
node functions/tools/assign_supermarket_sample_groups.js --project master-taxi-gurlan [--apply]     # кутилади: ASSIGN=10
node functions/tools/mark_supermarket_samples.js --project master-taxi-gurlan [--apply]             # assign'дан кейин ДАРҲОЛ
```

## 4. Текширув рўйхати

- [ ] Тестлар яшил (коммит хабарида рақамлар бор).
- [ ] Hosting жонли SHA устида; deploy'дан кейин bundle hash текширилади.
- [ ] Functions versiyalари текширилади.
- [ ] Таксономия DRY RUN: addedGroups = 5 та, removed = йўқ.
- [ ] Assign DRY RUN: ASSIGN=10, UNMATCHED=0.

## 5. Rollback

- **Hosting:** олдинги release'га қайтарилади.
- **Functions:** олдинги манбадан ўша номлар бўйича қайта deploy.
- **Маълумот (тескари тартибда):**
  1. `mark_supermarket_samples.js --ids <10 та ID ёзилган файл> --undo --apply`
  2. `assign_supermarket_sample_groups.js --rollback <backup.json> --apply`
  3. `seed_supermarket.js --upgrade --taxonomy-file functions/tools/data/supermarket_taxonomy_v3.json --expected-version 2 --allow-remove --project master-taxi-gurlan --apply`
