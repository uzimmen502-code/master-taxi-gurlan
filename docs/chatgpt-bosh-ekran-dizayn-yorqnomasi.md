# ChatGPT учун йўриқнома — Master Taxi Gurlan бош экран дизайни

Бу ҳужжатни ChatGPT (DALL·E / дизайн маслаҳати / UI mockup) га **тўлиқ нусхалаб** юборинг. Код ёзиш шарт эмас — фақат **визуал концепт** ёки **UI тавсиф**.

---

## 1. Лойиҳа

| Майдон | Қиймат |
|--------|--------|
| Номи | **Master Taxi Gurlan** (AVA Taxi бренди билан) |
| Платформа | Android мобил илова (Flutter), қўшимча веб |
| Аудитория | Гурлан / ҳудуд фойдаланувчилари |
| Тил | **Ўзбек тили, кирилл алифбоси** (латиница эмас) |
| Бош экран вазифаси | 6 та асосий хизмат модулини танлаш |

---

## 2. Бош экран — 6 та модул

Ҳар бири алohида ранг ва визуал услубда. Карталар **вертикал рўйхат** (мобил), ўқиш оson.

| № | Модул | Сарлавҳа (кирилл) | Tagline (қисқа, рангли) | Изoh (кульранг, 1 қатор) |
|---|--------|-------------------|-------------------------|---------------------------|
| 1 | Нон | **Нон** | 500 сўм хизмат ҳақи | Ишонч ва садоқат |
| 2 | Маршрут | **Маршрут** | Сизни топишади энди | Кутиш йўқ, AVA хизматингизда |
| 3 | Маҳаллий такси | **Маҳаллий такси AVA TAXI** | Call-центрисиз, тўғридан-тўғри | Ҳайдовчига боғланасиз |
| 4 | Шаҳарлараро | **Шаҳарлараро** | Бошқа шаҳарга бориш муаммо эмас | Автомобилни ўзингиз танlaysiz |
| 5 | Тайёр овқат | **Таомлар** | Буюртма асосида етказиб берамиз | Банкет ва дастурхон учун |
| 6 | ИШ ТОП | **Иш Топ** | Бепул эълон — иш, хизмат, эълон | Керакли эълон шу ерда |

**ИШ ТОП** модули maxsus: унда 4 та мини-таб/чип кўрсатинг: `Иш` | `Хизмат` | `Эълон` | `Шошилинч` (шошилинч qizil 🚨).

---

## 3. Картa tuzilmasi (asosiy andoza)

Ҳар бир модул kartasi **gorizontal** (rasmdagidek):

```
┌─────────────────────────────────────────────────────────────┐
│  [Katta 3D/rasm]  │ [Ikon quti]  Sarlavҳa (qalin)      [›] │
│      chap         │              Tagline (modul rangi)      │
│                   │              Izoh (kulrang)             │
└─────────────────────────────────────────────────────────────┘
```

**Talablar:**
- Fon: **pastel** (ҳар модул ўз ранги — крем, очиқ кўк, мятный, лаванда, пушти, сариқ)
- Burchak: **16–20 px** yumaloq
- Soya: yengil, zamonaviy (flat + soft shadow)
- O‘ngda: dumaloq **›** tugma (kirish belgisi)
- Ikonka: 40×40 px atrofida, rangli kvadrat ichida oddiy line-icon
- Rasm: chapda, **realistik 3D yoki sifatli foto** uslubida (non savat, Damas, sedan, chamadon, taom, portfel)

**Telefon o‘lchami:** 390×844 px (iPhone/Android standart), yuqorida header, pastda 6 ta karta + biroz bo‘shliq.

---

## 4. Header (yuqori qism)

- Chap: salom / foydalanuvchi ismi (ixtiyoriy)
- O‘ng: profil ikonkasi
- Fon: toza oq yoki juda och kulrang
- **Orqa fon:** hozirgi ilovada “space” animatsiyasi bor — dizaynda yulduzli osmon yoki sokin gradient ham mumkin (ixtiyoriy)

---

## 5. Rang palitrasi (modul bo‘yicha)

| Modul | Fon (pastel) | Accent |
|-------|----------------|--------|
| Нон | `#FFF3E0` / krem | `#E65100` to‘q sariq |
| Маршрут | `#E0F7FA` | `#00695C` |
| Маҳаллий такси | `#E8F5E9` | `#1565C0` |
| Шаҳарлараро | `#F3E5F5` | `#6A1B9A` |
| Таомлар | `#FCE4EC` | `#C62828` |
| Иш Топ | `#FFFDE7` / och sariq | `#0277BD` + **#D32F2F** (шошилинч) |

---

## 6. ИШ ТОП — maxsus dizayn (muhim)

ИШ ТОП boshqa kartalardan **ajralib turishi** kerak:

- Karta biroz **kengroq** yoki qizil/sariq **chap chiziq** (4 px)
- Tagline ostida 4 ta kichik **chip**: `Иш` `Хизмат` `Эълон` `Шошилинч`
- `Шошилинч` chip: qizil fon, 🚨
- Ixtiyoriy: kichik `+ Эълон қўшиш` tugmasi o‘ng pastda
- Matn: «Кунига 10 та эълон» — juda kichik, kulrang

**Mantiq (dizayn uchun):** foydalanuvchi ИШ ТОП ni “e’lon doskasi” deb tushunadi — OLX uslubi, lekin mahalliy va ishonchli.

---

## 7. 5 ta variant — ChatGPT dan so‘rash

Quyidagilardan **bittasini** yoki **aralashmasini** so‘rang:

### Variant A — Premium kartochka (asosiy)
Rasmdagidek to‘liq gorizontal karta, 6 modul, batafsil matn.

### Variant B — 2 ustunli grid
Mobil: 2 ustunda qisqa kartalar (rasm yuqori, matn past), ixcham scroll.

### Variant C — Guruhlangan
3 blok: «Транспорт» (3 ta), «Таом ва нон» (2 ta), «Иш Топ» (alohida).

### Variant D — Hero banner
Yuqorida 1 katta banner (Marshrut), pastda 4 tezkor + qolganlari ro‘yxat.

### Variant E — Иш Топ ajratilgan
5 ta oddiy karta + 1 ta maxsus keng ИШ ТОП kartasi (4 chip bilan).

**ChatGPT ga:** «Variant ___ bo‘yicha mobil bosh ekran mockup chizing» deb yozing.

---

## 8. ChatGPT uchun tayyor PROMPT (nusxalash)

Quyidagi matnni **to‘g‘ridan-to‘g‘ri** ChatGPT ga yuboring:

---

```
Sen O‘zbekiston mahalliy mobil ilovasi uchun UI/UX dizaynerisan.

Loyiha: Master Taxi Gurlan (AVA Taxi) — bosh ekran mockup.
Platforma: Android telefon, 390×844 px, vertikal.
Til: FAQAT o‘zbek tili, KIRILL alifbosi. Hech qanday inglizcha label ishlatma.

Vazifa: 6 ta xizmat moduli uchun zamonaviy, ishonchli, pastel rangli bosh ekran dizayni.

Har bir modul kartasi GORIZONTAL:
- Chapda: katta 3D yoki fotorealistik rasm
- O‘rtada: kichik rangli kvadrat ichida ikonka + qalin sarlavha + rangli tagline + kulrang izoh (1 qator)
- O‘ngda: dumaloq › tugma

Modullar (matnlar aniq shunday bo‘lsin):
1. Нон — tagline: «500 сўм хизмат ҳақи», izoh: «Ишонч ва садоқат», krem fon
2. Маршрут — tagline: «Сизни топишади энди», izoh: «Кутиш йўқ, AVA хизматингизда», och ko‘k fon, oq Damas rasmi
3. Маҳаллий такси AVA TAXI — tagline: «Call-центрисiz, to‘g‘ridan-to‘g‘ri», izoh: «Haydovchiga bog‘lanasiz», yashil fon
4. Шаҳарлараро — tagline: «Boshqa shaharga borish muammo emas», izoh: «Avtomobilni o‘zingiz tanlaysiz», binafsha fon
5. Таомлар — tagline: «Buyurtma asosida yetkazib beramiz», izoh: «Banket va dasturxon uchun», pushti fon
6. Иш Топ — MAXSUS karta: sariq fon, qizil chap chiziq, 4 chip: Иш | Хизмат | Эълон | Шошилинч (qizil), tagline: «Bepul e’lon — ish, xizmat, e’lon», izoh: «Kerakli e’lon shu yerda»

Uslub: yumaloq burchaklar 18px, yengil soya, professional marketplace, mahalliy ilova — bolalar o‘yiniga o‘xshamasin.

Variant: [A / B / C / D / E — bittasini tanlang yoki «A + E aralashmasi»]

Chiqish: bitta to‘liq mobil ekran mockup (PNG tavsif), yorqin, o‘qilishi oson, barcha matnlar kesilmasin.
```

---

## 9. Qayta ishlash (iteratsiya) uchun qo‘shimcha buyruqlar

Agar birinchi natija yoqmasa, ChatGPT ga shularni yuboring:

| Muammo | Buyruq |
|--------|--------|
| Matn kesilgan | «Barcha kirill matnlari to‘liq ko‘rinsin, karta balandligini oshir» |
| Juda bolalarona | «Kamroq cartoon, ko‘proq realistik 3D va corporate trust» |
| Иш Топ ajralmayapti | «Иш Топ kartasini 20% kengroq qil va qizil Шошилинч chip qo‘sh» |
| Juda tartibsiz | «6 ta karta bir xil balandlik va grid, 16px margin» |
| Inglizcha chiqdi | «Faqat kirill, lotin yo‘q» |

---

## 10. Nimalarni QILMASIN

- Web admin panel dizayni (bu faqat foydalanuvchi bosh ekrani)
- Login / PIN ekrani
- ИШ ТОП ichki e’lonlar ro‘yxati (alohida ekran)
- Juda ko‘p matn (har kartada max 3 qator)
- Qorong‘u tema (hozircha light mode)
- Boshqa til yoki lotin harflar

---

## 11. Muvaffaqiyat mezonlari

Dizayn quyidagilarga javob bersa — yaxshi:

1. 6 modul bir qarashda tushunarli
2. ИШ ТОП «e’lon / ish / shoshilinch» ekosistemasi seziladi
3. Mahalliy, ishonchli, zamonaviy (taxi + non + ovqat + ish)
4. 45+ yosh foydalanuvchi ham oson o‘qiy oladi (katta shrift, kontrast)
5. Flutter ilovaga implement qilish oson (oddiy kartalar, Stack emas murakkab 3D)

---

*Hujjat: Master Taxi Gurlan loyihasi uchun. Kod implementatsiyasi alohida, ruxsat bilan.*
