# `config/passenger_cancel_block` — bir martalik seed

Firebase Console yoki Admin SDK:

```javascript
await admin.firestore().collection('config').doc('passenger_cancel_block').set({
  cancelLimit: 5,
  windowMinutes: 10,
  blockMinutes: 10,
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
}, { merge: true });
```

Dart defaultlar: `PassengerCancelRulesConfig.defaults`  
CF defaultlar: `PASSENGER_CANCEL_RULES_DEFAULTS` in `functions/index.js`

Hujjat bo'lmasa ham ikkala tomonda shu qiymatlar ishlatiladi.
