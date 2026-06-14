# Food modulni o'chirish — 0-bosqich (inventarizatsiya)

Bu hujjat Food modulini xavfsiz decommission qilishdan oldingi tayyorgarlik (phase 0) uchun.

## 1) Scope (nimani o'chirmoqchimiz)

- Mobil foydalanuvchi oqimidagi `FoodScreen` va unga bog'liq UI/logic.
- Admin paneldagi `food_catalog` va `food_inventory` bilan ishlovchi bo'lim.
- Firestore/Storage'dagi food'ga tegishli write/read yo'llari.

## 2) Dependency map (topilgan bog'lanishlar)

### 2.1 Mobil feature fayllari

- `lib/features/food/screens/food_screen.dart`
- `lib/features/food/controllers/food_controller.dart`
- `lib/features/food/widgets/cart_sheet.dart`
- `lib/features/food/widgets/food_order_sheet.dart`
- `lib/features/food/widgets/product_card.dart`

### 2.2 Mobil kirish nuqtasi

- `lib/features/home/screens/home_screen.dart`
  - `FoodScreen` import qilingan
  - modul ochish switch'ida `case 'food'`

### 2.3 Shared model/utility

- `lib/models/food_product.dart`
- `lib/utils/food_catalog.dart`
- `lib/core/utils/order_receipt_format.dart` (food izohi/format bo'limi)

### 2.4 Admin panel bog'lanishlari

- `lib/features/admin_web/screens/products_manager_screen.dart`
  - `food_catalog` collection
  - `food_inventory` collection
  - food image boshqaruvi

### 2.5 Repository / inventory

- `lib/repositories/inventory_repository.dart`
  - `food_inventory` bilan ishlash

### 2.6 Storage/Firestore qoidalari

- `storage.rules`
  - `match /food_images/{name=**}`
- `firestore.rules`
  - `match /food_catalog/{id}`
  - `match /food_inventory/{id}`

### 2.7 Rasm upload service bog'lanishi

- `lib/features/bread/services/bread_image_storage.dart`
  - `food_images/$docId.$ext` yo'li

### 2.8 Cloud Functions bog'lanishlari

- `functions/index.js`
  - `food_inventory` reset/dispatch bo'laklari
  - `food_catalog` seed bo'lagi

### 2.9 Lokalizatsiya

- `assets/lang/uz_Cyrl.json` (`food_order`)
- `assets/lang/uz_Latn.json` (`food_order`)
- `assets/lang/ru.json` (`food_order`)
- `lib/l10n/app_localizations.dart` (`food_order`)

## 3) Xavf tahlili (phase 0 xulosasi)

Food modulni "birdaniga" (big-bang) o'chirish xavfli:

- compile xato: `FoodScreen` import/references qoladi
- admin workflow buzilishi: `products_manager_screen` ichida food bo'limi bor
- data-layer uzilishi: `food_catalog`, `food_inventory`, `food_images` hali ishlatiladi
- server taraf qoldiqlari: functions va rules ichida food bo'laklari mavjud

## 4) Freeze rejasi (hozir darhol)

- Food bo'yicha yangi feature/UX qo'shishni to'xtatish.
- Food bilan bog'liq schema/rules'ga vaqtincha yangi o'zgarish kiritmaslik.
- Decommission tugamaguncha faqat bugfix (agar zarur bo'lsa).

## 5) Rollback tayyorgarligi

Decommission bosqichlari uchun rollback shartlari:

- Har bosqich alohida commit.
- Har bosqichdan keyin smoke test:
  - Home ochilishi
  - Bottom bar navigatsiya
  - Admin products manager ochilishi
  - Firestore/Storage permission xatolari yo'qligi
- Muammo chiqsa oxirgi bosqich commit'igacha qaytish.

## 6) "Done" mezoni (phase 0 yopish sharti)

- [x] Food dependency-map tayyor.
- [x] Xavf nuqtalari hujjatlashtirilgan.
- [x] Freeze qoidasi kelishilgan.
- [x] Rollback yondashuvi belgilangan.

---

Keyingi bosqich: **1-bosqich (soft-disable)** — foydalanuvchi UI'dan food modulni yashirish, backend va adminni darhol buzmasdan.

