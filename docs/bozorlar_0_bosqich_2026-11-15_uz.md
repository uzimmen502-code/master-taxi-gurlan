# «Бозорлар» — 0-босқич: тайёргарлик (2026-11-15)

## 1. Вазифа

Эганинг сўзи (2026-11-15): **«Маъқул , 0-босқичдан бошла»**.

**Тушунганим (ҳажм):** бу босқичда код ёзилмайди. Тўртта иш қилинади:
1. production ҳолатини текшириш;
2. 3 тилдаги матнларни тайёрлаш;
3. категориялар ҳужжатининг тузилмасини ёзиш;
4. эгадан керак бўладиган маълумотлар рўйхатини тузиш.

Келишилган қарорлар хотирада турибди: `project-markets-bozorlar-2026-11-15`.

## 2. Production ҳолати (CONFIRMED, 2026-11-15, фақат ўқилди)

| Нима | Ҳолат | Таъсири |
|---|---|---|
| `server_config/business_orders` (бизнес буюртмалари) | **ҳужжат йўқ** → код бўйича `off` (`feat/biz-order-srv:functions/business_orders.js:124-127`) | 11-босқичда ёқиш керак (синовчилар → пилот → ҳамма) |
| `settings/restaurant_delivery` (бизнес буюртмаларининг етказиш тарифи) | **ҳужжат йўқ** | 11-босқичдан олдин эга етказиш нархларини белгилайди |
| `module_config/wholesale_orders_all` | `enabled: true`, `stage: public`, `cashDeliveryEnabled: true` (2026-11-15 05:25Z) | Улгуржи буюртмалари жонли; 7-босқичда унга тегилмайди |
| `module_config/restaurants_all` | `stage: public` | ресторанлар ўзгармайди (эга: кейинроқ) |
| `taxonomy/markets` | **ҳужжат йўқ** | 1-босқичда яратилади |
| YouTube'га чиқариш (`onTvClipSocialPublish`) | охирги уринишлар **`invalid_grant`** (2026-11-04 12:13Z, 12:18Z; 10-24 да ҳам) | YouTube уланиши ишламаяпти (INFERRED). Видеони YouTube'га чиқариш учун эга Google ҳисобини қайта улаши керак |
| `geo_regions` | 14 та вилоят (жумладан `xorazm`), **координаталар йўқ** | ҳалқалар учун марказлар керак (5-бўлим) |

## 3. Матнлар — 3 тил (PROPOSED, эга тасдиқлайди)

### 3.1. Номлар

| Калит (таклиф) | uz_Cyrl | uz_Latn | ru |
|---|---|---|---|
| блок сарлавҳаси | Бозорлар | Bozorlar | Рынки |
| мол | Мол бозори | Mol bozori | Рынок скота |
| мошина | Мошина бозори | Mashina bozori | Авторынок |
| гўшт | Гўшт бозори | Go'sht bozori | Мясной рынок |
| деҳқон | Деҳқон бозори | Dehqon bozori | Фермерский рынок |
| уй-жой (`home_module_realty`, `home_section_realty`, `realty_title`) | Уй-жой бозори | Uy-joy bozori | Недвижимость (эга танлади) |
| улгуржи (мавжуд) | Улгуржи бозор | Ulgurji bozor | Оптовый рынок |
| хитой (мавжуд) | Хитой бозори | Xitoy bozori | Китайский рынок |
| аралаш (мавжуд калит КАТТА ҲАРФ: «АРАЛАШ БОЗОР») | Аралаш бозор | Aralash bozor | Смешанный рынок |
| қидирув | AVA'да қидириш… | AVA'da qidirish… | Поиск в AVA… |

### 3.2. Шиорлар

1. **Мол**
   - uz_Cyrl: Қорамол ва паррандаларни эгасидан тўғридан-тўғри топинг — танланг, солиштиринг ва сотувчи билан келишинг.
   - uz_Latn: Qoramol va parrandalarni egasidan to'g'ridan-to'g'ri toping — tanlang, solishtiring va sotuvchi bilan kelishing.
   - ru: Скот и птица напрямую от владельцев — выбирайте, сравнивайте и договаривайтесь с продавцом.
2. **Мошина**
   - uz_Cyrl: Мошина, мото, бошқа техникалар ва эҳтиёт қисмларни нарх ва сифат бўйича танлаб, мос вариантни топинг.
   - uz_Latn: Mashina, moto, boshqa texnikalar va ehtiyot qismlarni narx va sifat bo'yicha tanlab, mos variantni toping.
   - ru: Автомобили, мото, другая техника и запчасти — выбирайте по цене и качеству и находите подходящий вариант.
3. **Гўшт (буюртма ёқилган)**
   - uz_Cyrl: Маҳаллий ва импорт гўштлар, парранда ва балиқларни яқин сотувчилардан танланг — нархларни солиштиринг ва етказиб беришдан фойдаланинг.
   - uz_Latn: Mahalliy va import go'shtlar, parranda va baliqlarni yaqin sotuvchilardan tanlang — narxlarni solishtiring va yetkazib berishdan foydalaning.
   - ru: Местное и импортное мясо, птица и рыба от ближайших продавцов — сравнивайте цены и пользуйтесь доставкой.
4. **Гўшт (буюртма ўчиқ)**
   - uz_Cyrl: …нархларни солиштиринг ва сотувчи билан келишинг.
   - uz_Latn: …narxlarni solishtiring va sotuvchi bilan kelishing.
   - ru: …сравнивайте цены и договаривайтесь с продавцом.
5. **Деҳқон**
   - uz_Cyrl: Сабзавот, мева, полиз ва донни деҳқондан тўғридан-тўғри олинг — янги маҳсулотни яхши нархда топинг.
   - uz_Latn: Sabzavot, meva, poliz va donni dehqondan to'g'ridan-to'g'ri oling — yangi mahsulotni yaxshi narxda toping.
   - ru: Овощи, фрукты, бахчевые и зерно напрямую от фермеров — свежие продукты по хорошей цене.
6. **Уй-жой**
   - uz_Cyrl: Уй, квартира ва ерни сотиб олиш ёки ижарага топинг — ҳудуд, нарх ва харита бўйича танланг.
   - uz_Latn: Uy, kvartira va yerni sotib olish yoki ijaraga toping — hudud, narx va xarita bo'yicha tanlang.
   - ru: Дома, квартиры и участки для покупки или аренды — выбирайте по району, цене и на карте.
7. **Улгуржи**
   - uz_Cyrl: Ишлаб чиқарувчи ва улгуржи сотувчилардан тўғридан-тўғри харид қилинг — катта партия учун қулай нарх ва шартларни топинг.
   - uz_Latn: Ishlab chiqaruvchi va ulgurji sotuvchilardan to'g'ridan-to'g'ri xarid qiling — katta partiya uchun qulay narx va shartlarni toping.
   - ru: Покупайте напрямую у производителей и оптовиков — выгодные цены и условия для крупных партий.
8. **Хитой**
   - uz_Cyrl: Хитой маҳсулотларини танланг — таклифларни кўринг, нархларни солиштиринг ва сотувчига сўров юборинг.
   - uz_Latn: Xitoy mahsulotlarini tanlang — takliflarni ko'ring, narxlarni solishtiring va sotuvchiga so'rov yuboring.
   - ru: Товары из Китая — смотрите предложения, сравнивайте цены и отправляйте запрос продавцу.
9. **Аралаш**
   - uz_Cyrl: Барча бозорлардаги таклифларни бир жойдан кўринг — керакли маҳсулотни тез топинг ва энг мақбул вариантни танланг.
   - uz_Latn: Barcha bozorlardagi takliflarni bir joydan ko'ring — kerakli mahsulotni tez toping va eng maqbul variantni tanlang.
   - ru: Предложения всех рынков в одном месте — быстро находите нужное и выбирайте лучший вариант.

### 3.3. Бўлимлар (таб / чип)

| Бозор | uz_Cyrl | uz_Latn | ru |
|---|---|---|---|
| Мошина | Мошиналар · Мото · Техника · Эҳтиёт қисмлар | Mashinalar · Moto · Texnika · Ehtiyot qismlar | Автомобили · Мото · Техника · Запчасти |
| Гўшт | Барчаси · Мол · Қўй · Парранда · Балиқ · Бошқа · Импорт | Barchasi · Mol · Qo'y · Parranda · Baliq · Boshqa · Import | Все · Говядина · Баранина · Птица · Рыба · Другое · Импорт |
| Деҳқон (**таклиф, ҳали келишилмаган**) | Барчаси · Сабзавот · Мева · Полиз · Дон · Бошқа | Barchasi · Sabzavot · Meva · Poliz · Don · Boshqa | Все · Овощи · Фрукты · Бахчевые · Зерно · Другое |
| Мол | бўлинмасиз | — | — |

### 3.4. Майдонлар

**Мол бозори**

| uz_Cyrl | uz_Latn | ru |
|---|---|---|
| Зоти | Zoti | Порода |
| Ёши (ой) | Yoshi (oy) | Возраст (мес.) |
| Жинси: Эркак / Урғочи | Jinsi: Erkak / Urg'ochi | Пол: Самец / Самка |
| Сони | Soni | Количество |
| Тахминий вазни (кг) | Taxminiy vazni (kg) | Примерный вес (кг) |
| Бўғоз | Bo'g'oz | Стельная |

**Мошина бозори**

| uz_Cyrl | uz_Latn | ru |
|---|---|---|
| Марка | Marka | Марка |
| Модель | Model | Модель |
| Йили | Yili | Год |
| Пробег (км) | Probeg (km) | Пробег (км) |
| Ёқилғи: Бензин / Метан / Пропан / Дизел / Электр / Гибрид (**рўйхат таклиф**) | Yoqilg'i: Benzin / Metan / Propan / Dizel / Elektr / Gibrid | Топливо: Бензин / Метан / Пропан / Дизель / Электро / Гибрид |
| Эҳтиёт қисм — Қайси машинага | Qaysi mashinaga | Для какого авто |
| Эҳтиёт қисм — Ҳолати: Янги / Ишлатилган | Holati: Yangi / Ishlatilgan | Состояние: Новое / Б/у |

**Гўшт бозори**

| uz_Cyrl | uz_Latn | ru |
|---|---|---|
| Сўйилган санаси (ихтиёрий) | So'yilgan sanasi (ixtiyoriy) | Дата забоя (необязательно) |
| Импорт | Import | Импорт |

Нарх бирлиги сўм/кг.

**Деҳқон бозори**

| uz_Cyrl | uz_Latn | ru |
|---|---|---|
| Бирлик: кг / тонна / дона | Birlik: kg / tonna / dona | Единица: кг / тонна / шт. |
| Ҳосил вақти (ихтиёрий) | Hosil vaqti (ixtiyoriy) | Время сбора (необязательно) |

## 4. `taxonomy/markets` тузилмаси (PROPOSED)

```
taxonomy/markets
  version: int                 // ҳар ўзгаришда +1; маҳсулотга taxonomyVersion ёзилади
  updatedAt, updatedBy
  markets:
    <marketId>:                // livestock | auto | meat | farm
      moduleId: string         // livestock_market | auto_market | meat_market | farm_market
      order: int
      names / slogan / sloganNoOrder: { uz_Cyrl, uz_Latn, ru }
      imageUrl: string         // админ алмаштиради
      categories: [ { id, names{3}, orderable: bool } ]
      fields: [ { key, type: int|text|select|bool|date, names{3},
                  options?: [ { id, names{3} } ], required: bool,
                  min?, max?, unit?, categories?: [catId] } ]
      priceUnits: [ PriceUnit wire ]   // гўшт: ['kg']
```

- **Ёзиш:** фақат админ callable орқали, ҳар ўзгариш аудит журналига (41-банд). Тарих `taxonomy_history/v{n}`'га ёзилади.
- **Ўқиш:** ҳамма (rules'да `taxonomy` read true аллақачон бор).
- Уй-жой, Улгуржи, Хитой ва Аралаш ўз маълумот моделида қолади. Taxonomy фақат 4 та янги бозор учун.

## 5. Вилоят марказлари — ҳалқалар учун (PROPOSED)

Манба: OpenStreetMap Nominatim, 2026-11-15. Шаҳар номи бўйича қидирилди, натижа манзили текширилди.

| `geo_regions` id | Марказ | lat | lng |
|---|---|---|---|
| toshkent_shahri | Тошкент | 41.3123 | 69.2787 |
| toshkent_viloyati | Нурафшон | 41.0429 | 69.3578 |
| andijon | Андижон | 40.7833 | 72.3507 |
| fargona | Фарғона | 40.3765 | 71.7913 |
| namangan | Наманган | 40.9996 | 71.6726 |
| samarqand | Самарқанд | 39.6550 | 66.9757 |
| buxoro | Бухоро | 39.7760 | 64.4152 |
| navoiy | Навоий | 40.1035 | 65.3734 |
| qashqadaryo | Қарши | 38.8398 | 65.7928 |
| surxondaryo | Термиз | 37.2442 | 67.2832 |
| jizzax | Жиззах | 40.1332 | 67.8234 |
| sirdaryo | Гулистон | 40.5221 | 68.7802 |
| qoraqalpogiston | Нукус | 42.4600 | 59.6177 |
| xorazm | Урганч | 41.5518 | 60.6313 |

Бу координаталар фақат вилоятлар орасидаги масофани тартиблаш учун ишлатилади, аниқ манзил учун эмас.

## 6. Очиқ масалалар

| Масала | Ҳолат | Ким ҳал қилади / кейинги қадам |
|---|---|---|
| 3-бўлимдаги таржималар | PROPOSED | эга тасдиқлайди |
| Деҳқон бозори чиплари (Сабзавот · Мева · Полиз · Дон · Бошқа) | PROPOSED | эга |
| Ёқилғи рўйхати | PROPOSED | эга |
| Вилоят марказлари (5-бўлим) | PROPOSED | эга тасдиқлайди |
| Модуль id'лари `livestock_market` / `auto_market` / `meat_market` / `farm_market` | PROPOSED (мавжуд `wholesale_market` услубида) | техник; эга эътирози бўлмаса шу |
| Аралаш номи бош саҳифа картасида «Аралаш бозор» (мавжуд калит КАТТА ҲАРФ) | PROPOSED: карта учун янги калит, бозор экрани ўзгармайди | эга |
| Аралаш учун алоҳида тўлиқ расм (ҳозир коллаж бўлаги) | UNKNOWN | эга беради |
| Синовчилар рўйхати (INTERNAL) | UNKNOWN | эга |
| Бизнес буюртмаларининг етказиш тарифи `settings/restaurant_delivery` | ҳужжат йўқ (CONFIRMED) | эга, 11-босқичдан олдин |
| Шошилинч ва реклама нархлари (бозор эълонлари учун) | UNKNOWN | эга, 5-босқичдан олдин |
| YouTube уланиши (`invalid_grant`) | INFERRED: ишламаяпти | эга Google ҳисобини қайта улайди |
| Ресторан ва кафелар | эга: кейинроқ | — |
