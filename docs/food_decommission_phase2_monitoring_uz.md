# Food decommission — 2-bosqich (7–14 kun monitoring)

Bu bosqichda maqsad: 1-bosqich soft-disable'dan keyin tizim barqarorligini tasdiqlash.

## Boshlanish sanasi

- Start: `____-__-__`
- End (kamida): `____-__-__` (7 kun)
- Tavsiya: 14 kungacha kuzatish

## Kuzatiladigan asosiy signal'lar

### 1) Runtime xatolar

- `flutter run` / release testlarda:
  - route/navigation xatolari
  - `NoSuchMethod` / `LateInitialization` / `StateError`
  - `food` bilan bog'liq import/reference xatolari

### 2) Kutilmagan kirish nuqtalari

- Foydalanuvchi Home'dan Food modulga kira olmasligi kerak.
- Agar support'da "Food yo'qoldi / ochilmayapti" murojaatlari tushsa, soni qayd etilsin.

### 3) Admin panel holati

- `products_manager_screen` ochilishi normal.
- Non/extra product oqimlari buzilmagan.
- `food_catalog` bo'limi hali ishlayotgan bo'lsa ham, regressiya bo'lmasin.

### 4) Data-layer sog'ligi

- Firestore/Storage permission-denied to'lqinlari yo'qligi
- `food_catalog`, `food_inventory`, `food_images` bo'yicha kutilmagan spike yo'qligi

## KPI / Qaror mezonlari

Quyidagilar bajarilsa 3-bosqichga o'tiladi:

- 7+ kun davomida **kritik crash = 0**
- Home navigatsiya regressiyasi = 0
- Food'ga kutilmagan kirish holatlari = 0 yoki juda kam (izohlangan)
- Admin asosiy oqimlari (non/extra) barqaror

## Har kunlik qisqa checklist

- [ ] Home ochilishi normal
- [ ] Bottom bar ishlashi normal
- [ ] Cheap products / chat / wallet / profile ochilishi normal
- [ ] Admin products manager ochilishi normal
- [ ] Error loglarda food bilan bog'liq yangi kritik xato yo'q

## Bosqich yakuni (Go / No-Go)

### GO (3-bosqichga o'tish)

- Yuqoridagi KPI'lar bajarilgan
- Jamoa admin workflow'lar barqarorligini tasdiqlagan

### NO-GO (2-bosqichni uzaytirish)

- Regression/crash aniqlangan
- Food bilan bog'liq kutilmagan route yoki support oqimi paydo bo'lgan

## Eslatma

Bu bosqichda kodni keskin o'chirish qilinmaydi. Faqat kuzatuv va barqarorlik tasdiqlanadi.

