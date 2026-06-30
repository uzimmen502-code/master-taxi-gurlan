# Tech Stack
- Flutter / Dart (mobile + web). pubspec `name: master_taxi_gurlan` (do not rename).
- State management: Provider (`ChangeNotifier` controllers per feature).
- Firebase: Phone Auth, Firestore, Cloud Functions (`firebase-functions` 4.9.0, Node.js 20 1st Gen), Hosting, FCM.
- Key Dart pkgs: cloud_firestore, cloud_functions, connectivity_plus, geolocator, google_maps_flutter, shared_preferences, flutter_local_notifications, flutter_ringtone_player, intl.
- CF deps: firebase-admin; `crypto` (admin PIN sha256 + timingSafeEqual). No ESLint installed — validate JS with `node --check`.
- Web: one Firebase Hosting site; user app at `/`, admin app at `/admin/` (rewrite to index.html).