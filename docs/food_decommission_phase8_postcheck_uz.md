# Food decommission — 8-bosqich (post-check + rollback window)

## Holat

8-bosqich bajarildi: food modul decommission'dan keyingi post-check o'tkazildi.

## Tekshiruv natijalari

### 1) Food mobile feature referenslari

- `lib/features/food/**` olib tashlangan.
- `lib` ichida `FoodScreen` / `FoodController` referenslari yo'q.
- Home'dan food modulga kirish yo'li yopilgan.

### 2) Rules holati

- `firestore.rules`dan `food_catalog` va `food_inventory` bloklari olib tashlangan.
- `storage.rules`dan `food_images` bloki olib tashlangan.
- Dry-run compile: muvaffaqiyatli.

### 3) Qolgan bog'lanishlar (kutilgan)

Quyidagilar hali bor va keyingi cleanup bosqichida ko'rib chiqiladi:

- Admin panel: `products_manager_screen.dart` ichida food catalog/inventory kodi.
- `inventory_repository.dart`, `food_product.dart`, `food_catalog.dart` (admin/data qatlamida).
- `functions/index.js` ichida `food_inventory` / `food_catalog` bo'laklari.
- `bread_image_storage.dart` ichida `food_images` upload yo'li.

Bu bosqichda ular qasddan qoldirildi (rollback xavfsizligi uchun).

## Analyzer holati

- `flutter analyze` umumiy loyiha bo'yicha muammolar ko'rsatdi.
- Topilgan xatolar food decommission bilan bevosita bog'liq emas (oldingi texnik qarzlar).
- Decommission bo'yicha yangi lint xatolar aniqlanmadi.

## Rollback window

- Tavsiya: 3–7 kun rollback window ochiq tursin.
- Shu davrda faqat monitoring:
  - Home navigatsiya
  - Admin products manager
  - Firestore/Storage permission xatolari
  - Support feedback

### Rollback trigger'lar

- Kutilmagan kritik xato
- Admin workflow to'xtashi
- Productionda kuchli permission-denied to'lqini

### Rollback yo'nalishi

- Oxirgi barqaror release/commitga qaytish
- Food write rules kerak bo'lsa vaqtincha qayta ochish (faqat favqulodda holatda)

## Keyingi qadam (ixtiyoriy)

- Admin/data/functions qatlamidagi food qoldiqlarini alohida bosqichda tozalash.
- Yakuniy release'dan oldin smoke test + release note.

