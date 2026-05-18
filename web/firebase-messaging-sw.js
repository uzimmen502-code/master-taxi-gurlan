/* eslint-disable no-undef */
/**
 * Firebase Cloud Messaging — веб service worker.
 * `lib/firebase_options.dart` → `DefaultFirebaseOptions.web` билан бир хил конфиг.
 * https://firebase.google.com/docs/cloud-messaging/js/client
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDl6AwtVg1DNoev0zTNKBcaEYFfj93q_FE',
  appId: '1:67136747215:web:ab67690cbf41e143e7e9ba',
  messagingSenderId: '67136747215',
  projectId: 'master-taxi-gurlan',
  storageBucket: 'master-taxi-gurlan.appspot.com',
  authDomain: 'master-taxi-gurlan.firebaseapp.com',
});

firebase.messaging();
