# Marshrut matnlar — deploy tekshiruv (Bosqich 0)

## 1. Cloud Function `onTripUpdate`

Production kodda marshrut blok **faqat** qabul qilingan safar bekorida:

```javascript
before.status === 'accepted' &&
(cancelledBy === 'passenger' || cancelledBy === 'user')
```

Tekshiruv:

```powershell
# Loyiha functions/index.js (lokal)
Select-String -Path functions\index.js -Pattern "before.status === 'accepted'" -Context 0,3

# Deploy (kerak bo'lsa)
firebase deploy --only functions:onTripUpdate
```

Sinov (Firestore Console yoki test telefon):

1. Kutish ekranida «Bekor qilish» → `users/{tel}/marshrut_block/state` → `cancelCount` **oshmasin**
2. Qabul qilinganidan keyin bekor → `cancelCount` **oshsin**

## 2. Passenger APK

Yangi matnlar (banner, Chaqirish, kutish, bo'sh natija) **release APK** da:

```powershell
flutter build apk --release
```

## 3. Admin panel matni

`marshrut_admin_screen` — «Marshrut: qabul qilingan safardan keyin bekor» CF bilan mos.

## 4. Til fayllari

`assets/lang/uz_Latn.json`, `uz_Cyrl.json`, `ru.json` — yangi kalitlar bir xil nomda mavjudligi.
