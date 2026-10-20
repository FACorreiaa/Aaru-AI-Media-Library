// Aaru's service worker: shows airing alerts and opens the show on a tap. It has no fetch
// handler, so it never caches or intercepts a page.

/** Only a same-origin path: an alert must never send the user to another site. */
function safePath(path) {
  return typeof path === 'string' &&
    path.startsWith('/') &&
    !path.startsWith('//')
    ? path
    : '/app'
}

self.addEventListener('push', (event) => {
  let payload = {}
  try {
    payload = event.data ? event.data.json() : {}
  } catch {
    payload = {}
  }
  const notification = payload.notification ?? {}
  const path = safePath(notification.data?.path)
  // Every push must show a notification, or the browser drops the subscription.
  event.waitUntil(
    self.registration.showNotification(notification.title ?? 'Aaru', {
      body: notification.body ?? 'A new episode is out.',
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      tag: path,
      data: { path },
    }),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const target = new URL(
    safePath(event.notification.data?.path),
    self.location.origin,
  ).href
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      })
      const open = windows.find((client) => client.url === target)
      if (open) return open.focus()
      const any = windows.find((client) => 'navigate' in client)
      if (any) {
        await any.focus()
        return any.navigate(target)
      }
      return self.clients.openWindow(target)
    })(),
  )
})
