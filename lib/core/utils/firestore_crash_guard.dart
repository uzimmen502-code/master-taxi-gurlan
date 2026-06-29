/// Firestore veb SDK "Unexpected state" bug'idan avto-tiklash qalqoni.
///
/// Web: global JS xatolarini (`error` / `unhandledrejection`) va Dart zonasiga
/// yetgan xatolarni ushlaydi; aniqlangach sahifani qayta yuklaydi (loop guard
/// bilan). Boshqa platformalarda — no-op.
library;

export 'firestore_crash_guard_stub.dart'
    if (dart.library.html) 'firestore_crash_guard_web.dart';
