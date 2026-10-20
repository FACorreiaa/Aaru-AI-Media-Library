import { isRedirect } from '@tanstack/solid-router'
import { createSignal, onCleanup, onMount } from 'solid-js'
import {
  HIDDEN_GRACE_MS,
  STALE_AFTER_MS,
  backoffDelay,
  parseEvent,
  typingDue,
} from './model'
import type { RealtimeEvent } from './model'
import { realtimeTicket } from './server'

// GRP-006 on the web: one socket for the whole signed-in tab, shared by every pane that
// subscribes. The first subscriber opens it and the last one closes it. Browser-only.

export type ConnectionState = 'idle' | 'connecting' | 'open' | 'closed'

type Listener = (event: RealtimeEvent) => void

const listeners = new Set<Listener>()
const [state, setState] = createSignal<ConnectionState>('idle')
const [stale, setStale] = createSignal(false)

let socket: WebSocket | null = null
let attempt = 0
let retryTimer: number | undefined
let hiddenTimer: number | undefined
let staleTimer: number | undefined
let generation = 0
const lastTyping = new Map<string, number>()

/** Where the shared socket is. */
export const connectionState = state

/** True once the socket has been down long enough to say so. */
export const reconnecting = stale

function setConnection(next: ConnectionState) {
  setState(next)
  if (next === 'open') {
    window.clearTimeout(staleTimer)
    staleTimer = undefined
    setStale(false)
  } else if (staleTimer === undefined && !stale()) {
    staleTimer = window.setTimeout(() => {
      staleTimer = undefined
      if (state() !== 'open' && listeners.size > 0) setStale(true)
    }, STALE_AFTER_MS)
  }
}

async function connect() {
  if (socket || listeners.size === 0) return
  if (document.visibilityState !== 'visible') return
  const mine = ++generation
  setConnection('connecting')
  let url: string
  try {
    url = (await realtimeTicket()).url
  } catch (error) {
    // Signed out: the next REST call sends the page to sign-in; stop trying here.
    if (isRedirect(error)) return stop()
    return scheduleRetry(mine)
  }
  if (mine !== generation || listeners.size === 0) return
  const ws = new WebSocket(url)
  socket = ws
  ws.onopen = () => {
    if (socket !== ws) return
    attempt = 0
    setConnection('open')
  }
  ws.onmessage = (frame) => {
    if (socket !== ws || typeof frame.data !== 'string') return
    const event = parseEvent(frame.data)
    if (!event) return
    for (const listener of [...listeners]) {
      try {
        listener(event)
      } catch {
        // One pane's failure must not starve the others.
      }
    }
  }
  ws.onclose = () => {
    if (socket !== ws) return
    socket = null
    setConnection('closed')
    scheduleRetry(mine)
  }
}

function scheduleRetry(mine: number) {
  if (mine !== generation || listeners.size === 0) return
  window.clearTimeout(retryTimer)
  if (document.visibilityState !== 'visible') return
  retryTimer = window.setTimeout(() => {
    retryTimer = undefined
    void connect()
  }, backoffDelay(attempt++))
}

function close() {
  generation++
  window.clearTimeout(retryTimer)
  retryTimer = undefined
  const ws = socket
  socket = null
  ws?.close(1000)
}

function stop() {
  close()
  window.clearTimeout(hiddenTimer)
  window.clearTimeout(staleTimer)
  hiddenTimer = undefined
  staleTimer = undefined
  setStale(false)
  setState('idle')
  document.removeEventListener('visibilitychange', onVisibility)
}

/** A hidden tab lets its socket go after a minute, and reconnects the moment it is back. */
function onVisibility() {
  if (document.visibilityState === 'visible') {
    window.clearTimeout(hiddenTimer)
    hiddenTimer = undefined
    if (!socket) {
      attempt = 0
      void connect()
    }
  } else if (hiddenTimer === undefined) {
    hiddenTimer = window.setTimeout(() => {
      hiddenTimer = undefined
      close()
      setConnection('closed')
    }, HIDDEN_GRACE_MS)
  }
}

/** Listens to every event on the shared socket until the returned function is called. */
export function subscribe(listener: Listener): () => void {
  listeners.add(listener)
  if (listeners.size === 1) {
    document.addEventListener('visibilitychange', onVisibility)
    attempt = 0
    void connect()
  }
  return () => {
    listeners.delete(listener)
    if (listeners.size === 0) stop()
  }
}

/** `subscribe` for a component's lifetime. */
export function useRealtime(listener: Listener) {
  onMount(() => onCleanup(subscribe(listener)))
}

/** Says the user is typing in a channel, at most once every three seconds per channel. */
export function sendTyping(groupId: string, channelId: string) {
  const now = Date.now()
  if (!typingDue(lastTyping.get(channelId), now)) return
  if (!socket || socket.readyState !== WebSocket.OPEN) return
  lastTyping.set(channelId, now)
  socket.send(JSON.stringify({ type: 'typing', groupId, channelId }))
}
