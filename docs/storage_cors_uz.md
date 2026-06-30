# Firebase Storage: Rules + CORS (нон расми, админ web)

Код (`BreadImageStorage.putData`) ўзгармайди. Браузер юклаш учун **Firebase томонида** Rules жойланади ва bucket учун **CORS** қўлланади.

---

## Сиз қилишингиз керак бўлган қисм

### 1) Storage Rules (≈1 дақиқа)

1. [Firebase Console](https://console.firebase.google.com/) → лойиҳа **master-taxi-gurlan** → **Build** → **Storage** → **Rules**.
2. Репозиторийдаги `storage.rules` мазмунини нусхалаб, консольга ёпиштиринг (ёки CLI билан жойлаш — қадам 4).
3. **Publish** босинг.

Репозиторийдаги файл: `storage.rules` — `bread_images/**` учун `read`/`write`, қолган pathлар **ёпиқ**.

---

### 2) CORS (≈2–5 дақиқа)

CORS **Google Cloud Storage** bucket учун; `firebase deploy` uni автоматик қўймайди — `gsutil` керак.

#### Вариант A — Cloud Shell (тавсия)

1. [shell.cloud.google.com](https://shell.cloud.google.com) очинг.
2. Юқорида лойиҳани **master-taxi-gurlan**га уланг.
3. Репозиторийдан `cors.json`ни Cloud Shellга юкланг (Upload) ёки мазмунни қўлда яратинг.
4. Терминалда:

```bash
gcloud config set project master-taxi-gurlan

gsutil cors set cors.json gs://master-taxi-gurlan.appspot.com
gsutil cors get gs://master-taxi-gurlan.appspot.com

# Агар лойиҳада иккинчи bucket бўлса (хато берсангиз — ўтказиб юборинг):
gsutil cors set cors.json gs://master-taxi-gurlan.firebasestorage.app 2>/dev/null || true
```

Текшириш: `gsutil cors get gs://...` чиқишида JSON массив кўриниши керак.

#### Вариант B — Windows (локал)

1. [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) ўрнатинг.
2. PowerShell:

```powershell
gcloud auth login
cd C:\projects\ava_gurlan
powershell -ExecutionPolicy Bypass -File .\scripts\apply_storage_cors.ps1
```

---

### 3) Rulesни CLI орқали жойлаш (ихтиёрий)

Лойиҳа ildizida:

```powershell
cd C:\projects\ava_gurlan
firebase login
firebase deploy --only storage
```

Бу `firebase.json` → `storage.rules`ни Firebaseга юборади.

---

### 4) Браузер

Админ вебни **Ctrl+Shift+R** (hard reload) билан янгиланг, кейин **Юклаш**ни синанг.

Chrome **F12 → Network**: `PUT` / `POST` storage доменига — **200/204** яқин; **CORS** хатоси йўқлигини текширинг.

---

## Репозиторийда амалга оширilgan (сиз учун тайёр)

| Файл | Маъно |
|------|--------|
| `cors.json` | Bucket учун CORS (OPTIONS, resumable headerлар) |
| `storage.rules` | `bread_images/**` ochiq, қолгани ёпиқ |
| `scripts/apply_storage_cors.ps1` | `gsutil cors set` икки bucket учун (мавжуд бўлмаса хабар) |
| `firebase.json` | `storage.rules` deploy учун |

---

## `appspot.com` 404 чиқса

Янги Firebase лойиҳаларда bucket **`master-taxi-gurlan.firebasestorage.app`** бўлади; **`master-taxi-gurlan.appspot.com`** умуман йўқ — `gsutil` 404 нормал.

- CORS **firebasestorage.app** учун қўйилса етарли.
- Иловада `lib/firebase_options.dart` → `storageBucket` шу ном билан мос бўлиши керак (репода янгиланган).

---

## `firebase_storage/unauthorized`

Бу **Storage rules** клиентга **ёзиш**га рухсат бермаяпти (одатда консольда default rules қолган).

1. [Firebase Console](https://console.firebase.google.com/) → **Storage** → **Rules** — `bread_images` учун `allow write` борлигини текширинг.
2. Репозиторийдан жойланг: `firebase deploy --only storage`
3. **Publish**дан кейин 10–30 с кутинг, браузерни **Ctrl+Shift+R**.

Агар upload **муваффақ**, кейин Firestore **permission-denied** бўлса — `firestore.rules`да `bread_products` (репода `allow create, update: if true`).

---

## Bucket номи аниқ эмас бўлса

Firebase Console → **Storage** → файллар рўйхати устида **`gs://...`** кўринади — шу номни `gsutil cors set cors.json gs://...`да ишлатинг.

---

## Хавфсизлик (кейин)

- `bread_images` учун `write`ни фақат **аутентификацияланган админ**га чегараш (Custom Claims + `request.auth`).
- `cors.json`да `"origin": ["*"]`ни productionда **ўз доменингиз** билан алмаштиринг.
