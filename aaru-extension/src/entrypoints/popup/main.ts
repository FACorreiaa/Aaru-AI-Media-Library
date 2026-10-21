import { browser } from '#imports'
import { WEB_BASE, nowItem, recentItem, tokenItem } from '../../lib/store'
import type { NowPlaying, RecentPlay } from '../../lib/store'
import { SOURCE_LABELS, label } from '../../lib/types'

// SCR-007's popup: what plays now and what Aaru matched it to, the last few plays, and the
// connection. It reads the background's storage and redraws when it changes.
const app = document.querySelector<HTMLElement>('#app')!

const RESULTS: Record<RecentPlay['result'], string> = {
  marked: 'marked',
  finished: 'finished',
  unmatched: 'not matched',
}

function element<TTag extends keyof HTMLElementTagNameMap>(
  tag: TTag,
  props: { class?: string; text?: string; data?: Record<string, string> } = {},
  ...children: Node[]
): HTMLElementTagNameMap[TTag] {
  const node = document.createElement(tag)
  if (props.class) node.className = props.class
  if (props.text !== undefined) node.textContent = props.text
  for (const [key, value] of Object.entries(props.data ?? {}))
    node.dataset[key] = value
  node.append(...children)
  return node
}

async function connect() {
  const platform = await browser.runtime.getPlatformInfo()
  const os =
    { mac: 'macOS', win: 'Windows', linux: 'Linux', cros: 'ChromeOS' }[
      platform.os as string
    ] ?? platform.os
  const name = `${import.meta.env.BROWSER === 'firefox' ? 'Firefox' : 'Chrome'} on ${os}`
  await browser.tabs.create({
    url: `${WEB_BASE}/connect/extension?name=${encodeURIComponent(name)}`,
  })
  window.close()
}

function signedOut(): Node[] {
  const button = element('button', { class: 'primary', text: 'Connect' })
  button.addEventListener('click', () => void connect())
  return [
    element(
      'section',
      {},
      element('p', {
        class: 'muted',
        text: 'Connect your Aaru library, and what you finish on Netflix, Disney+ and Prime Video here is marked watched there.',
      }),
      button,
    ),
  ]
}

function nowSection(now: NowPlaying | null): Node {
  if (!now)
    return element(
      'section',
      {},
      element('p', { class: 'eyebrow', text: 'Now' }),
      element('p', {
        class: 'muted',
        text: 'Nothing playing. Play something on Netflix, Disney+ or Prime Video.',
      }),
    )
  const { playing } = now
  const episode =
    playing.type === 'show'
      ? [
          playing.season !== undefined ? `S${playing.season}` : '',
          playing.episode !== undefined ? `E${playing.episode}` : '',
        ]
          .filter(Boolean)
          .join(' · ') +
        (playing.episodeTitle ? `  ${playing.episodeTitle}` : '')
      : 'Film'
  return element(
    'section',
    {},
    element('p', {
      class: 'eyebrow',
      text: `Now · ${SOURCE_LABELS[playing.source]}`,
    }),
    element('p', { class: 'title', text: playing.title }),
    element(
      'p',
      { class: 'meta' },
      element('span', { text: episode }),
      element('span', { text: `${Math.round(now.progress)}%` }),
    ),
    element('p', {
      class: 'match',
      data: { matched: String(now.matched !== null) },
      text: now.matched
        ? `✓ Matched: ${now.matched}`
        : '? Not matched. Add it in Aaru by hand.',
    }),
  )
}

function recentSection(recent: RecentPlay[]): Node[] {
  if (recent.length === 0) return []
  return [
    element(
      'section',
      {},
      element('p', { class: 'eyebrow', text: 'Recent' }),
      element(
        'ul',
        {},
        ...recent.map((play) =>
          element(
            'li',
            {},
            element('span', {
              text: `${play.result === 'unmatched' ? '?' : '✓'} ${label(play.playing)}`,
            }),
            element('span', { text: RESULTS[play.result] }),
          ),
        ),
      ),
    ),
  ]
}

function footer(): Node {
  const disconnect = element('button', { class: 'link', text: 'Disconnect' })
  disconnect.addEventListener('click', () => void tokenItem.setValue(null))
  return element(
    'footer',
    {},
    element('span', { text: 'Connected' }),
    disconnect,
  )
}

async function render() {
  const [token, now, recent] = await Promise.all([
    tokenItem.getValue(),
    nowItem.getValue(),
    recentItem.getValue(),
  ])
  const header = element('header', { text: 'Aaru' })
  app.replaceChildren(
    header,
    ...(token
      ? [nowSection(now), ...recentSection(recent), footer()]
      : signedOut()),
  )
}

void render()
for (const item of [tokenItem, nowItem, recentItem])
  item.watch(() => void render())
