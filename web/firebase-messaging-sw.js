importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyC0zL5ZiB5c-m8GP7caqKctralJ9bK8lPY",
  appId: "1:398027497819:web:b9bb6da7dd98b0715dba7e",
  messagingSenderId: "398027497819",
  projectId: "lunara-project",
  authDomain: "lunara-project.firebaseapp.com",
  storageBucket: "lunara-project.firebasestorage.app"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  
  const notificationTitle = payload.notification?.title || 'New Notification';
  const notificationOptions = {
    body: payload.notification?.body || 'You have a new message.',
    icon: '/favicon.png'
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
