/* ============================================================================
   sw.js — service worker for Word Vibe
   Developed by Prasidha Jagtap.
   Copyright (c) 2026 Prasidha Jagtap. All rights reserved.

   Put this file NEXT TO index.html, at the root of the repo.

   Its only job is to receive a push message and show it. It deliberately
   does no caching, so the game itself is never served from a stale copy.
   ============================================================================ */

self.addEventListener("install", (e) => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  /* The fallback title is what a player sees when a push arrives without
     one. It still carried the game's old name. The notification TAG below
     stays "word-search": it is an internal key, and changing it would make
     one stale notification sit beside the next instead of being replaced. */
  let data = { title: "Word Vibe", body: "Today's puzzle is waiting.", url: "./" };
  try {
    if (event.data) data = Object.assign(data, event.data.json());
  } catch (e) {
    try { data.body = event.data.text(); } catch (e2) {}
  }

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "./icon-192.png",
      badge: "./icon-192.png",
      tag: "word-search",          // a new message replaces the old one
      renotify: true,
      data: { url: data.url || "./" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || "./";

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      // focus the game if it is already open, rather than opening a duplicate
      for (const c of list) {
        if ("focus" in c) { c.navigate(target); return c.focus(); }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    })
  );
});
