// static/service-worker.js

// Versioning for cache busting (optional, but good practice)
const CACHE_NAME = 'v1_cache';

// Listen for push events from the push service
self.addEventListener('push', function(event) {
    let notificationData = {};
    try {
        notificationData = event.data.json();
    } catch (e) {
        notificationData = { title: 'New Notification', body: event.data.text() || 'You have a new notification.' };
    }

    const title = notificationData.title || 'Inventory App';
    const options = {
        body: notificationData.body || 'You have a new message.',
        icon: notificationData.icon || '/static/favicon.ico', // Use your favicon as default icon
        badge: notificationData.badge || '/static/favicon.ico', // Smaller icon for Android badges
        data: {
            url: notificationData.url || '/' // URL to open when notification is clicked
        },
        actions: notificationData.actions || [] // Custom actions for notifications
    };

    event.waitUntil(
        self.registration.showNotification(title, options)
    );
});

// Listen for notification clicks
self.addEventListener('notificationclick', function(event) {
    event.notification.close(); // Close the notification when clicked

    let clickUrl = event.notification.data && event.notification.data.url ? event.notification.data.url : '/';
    
    // Check if the URL is an absolute URL or a relative path
    const url = new URL(clickUrl, self.location.origin).href;

    event.waitUntil(
        clients.matchAll({ type: 'window' }).then(function(clientList) {
            for (let i = 0; i < clientList.length; i++) {
                let client = clientList[i];
                // If the app is already open in a tab, focus it and navigate
                if (client.url === url && 'focus' in client) {
                    return client.focus();
                }
            }
            // If the app is not open or not on the right page, open a new window
            if (clients.openWindow) {
                return clients.openWindow(url);
            }
        })
    );
});


// Optional: Cache some static assets for offline capability (not strictly for push, but good practice for PWA)
self.addEventListener('install', function(event) {
    event.waitUntil(
        caches.open(CACHE_NAME).then(function(cache) {
            return cache.addAll([
                '/',
                '/static/styles.css',
                '/static/favicon.ico',
                '/static/logo.avif',
                'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css',
                'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css'
                // Add other critical static assets here
            ]);
        })
    );
});

self.addEventListener('fetch', function(event) {
    event.respondWith(
        caches.match(event.request).then(function(response) {
            return response || fetch(event.request);
        })
    );
});