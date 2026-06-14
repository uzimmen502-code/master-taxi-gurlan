import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyANkG7oj7uWAc06euZne8fv3YjJmt_pyR4',
    appId: '1:67136747215:android:0de8f5dae585a5b6e7e9ba',
    messagingSenderId: '67136747215',
    projectId: 'master-taxi-gurlan',
    storageBucket: 'master-taxi-gurlan.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBsAw9sHk_1RQOCbd2u0TJVwp95feSgVvQ',
    appId: '1:67136747215:ios:cd77c2c835a98b01e7e9ba',
    messagingSenderId: '67136747215',
    projectId: 'master-taxi-gurlan',
    storageBucket: 'master-taxi-gurlan.firebasestorage.app',
    iosBundleId: 'com.example.masterTaxiGurlan',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBsAw9sHk_1RQOCbd2u0TJVwp95feSgVvQ',
    appId: '1:67136747215:ios:cd77c2c835a98b01e7e9ba',
    messagingSenderId: '67136747215',
    projectId: 'master-taxi-gurlan',
    storageBucket: 'master-taxi-gurlan.firebasestorage.app',
    iosBundleId: 'com.example.masterTaxiGurlan',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDl6AwtVg1DNoev0zTNKBcaEYFfj93q_FE',
    appId: '1:67136747215:web:06df7d7c3ab0d97ae7e9ba',
    messagingSenderId: '67136747215',
    projectId: 'master-taxi-gurlan',
    storageBucket: 'master-taxi-gurlan.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBsAw9sHk_1RQOCbd2u0TJVwp95feSgVvQ',
    appId: '1:67136747215:web:ab67690cbf41e143e7e9ba',
    messagingSenderId: '67136747215',
    projectId: 'master-taxi-gurlan',
    storageBucket: 'master-taxi-gurlan.firebasestorage.app',
  );
}