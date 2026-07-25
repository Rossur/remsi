// Give the service worker access to Firebase Messaging.
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker by passing in the web app configuration.
// Replace placeholders with your actual Web App credentials from the Firebase Console.
firebase.initializeApp({
  apiKey: "AIzaSyAkAqpl4GmxgqjXI0LQ1mw6hWNliJkhtPw",
  authDomain: "remsi00.firebaseapp.com",
  projectId: "remsi00",
  storageBucket: "remsi00.firebasestorage.app",
  messagingSenderId: "621710502960",
  appId: "1:621710502960:web:403efe14e54b3ae37911f5",
  measurementId: "G-BMYDN44JP7"
});

// Retrieve an instance of Firebase Messaging so that it can handle background messages.
const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);

  const notificationTitle = payload.notification?.title || 'REMSI Alert';
  const notificationOptions = {
    body: payload.notification?.body || 'New alert triggered',
    icon: '/favicon.png',
    data: payload.data
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
