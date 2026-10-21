import { createContext, createUniqueId, splitProps, useContext } from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'

// Tabs on plain buttons (the ARIA tabs pattern, no Kobalte): one tab stop on the selected tab,
// Left/Right/Home/End move focus and select (automatic activation), and the tab ↔ panel ids
// are in the server's HTML too. Selected and unselected tabs swap plain utilities. Use one
// `TabsContent` whose `value` follows the selection: the panel stays mounted as it changes.

type TabsContextValue = {
  id: string
  value: () => string
  select: (value: string) => void
}

const TabsContext = createContext<TabsContextValue>()

const tabId = (id: string, value: string) => `${id}-tab-${value}`
const panelId = (id: string, value: string) => `${id}-panel-${value}`

export function Tabs(props: {
  value: string
  onChange: (value: string) => void
  class?: string
  children: JSX.Element
}) {
  const id = `tabs-${createUniqueId()}`
  return (
    <TabsContext.Provider
      value={{ id, value: () => props.value, select: props.onChange }}
    >
      <div class={props.class}>{props.children}</div>
    </TabsContext.Provider>
  )
}

const KEYS = ['ArrowLeft', 'ArrowRight', 'Home', 'End']

export function TabsList(props: JSX.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      role="tablist"
      {...props}
      onKeyDown={(event) => {
        if (!KEYS.includes(event.key)) return
        const tabs = [
          ...event.currentTarget.querySelectorAll<HTMLElement>('[role=tab]'),
        ]
        const at = tabs.indexOf(event.target as HTMLElement)
        if (at < 0) return
        const next =
          event.key === 'Home'
            ? 0
            : event.key === 'End'
              ? tabs.length - 1
              : (at + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) %
                tabs.length
        // The week page's own arrow keys skip a prevented event.
        event.preventDefault()
        tabs[next].focus()
        tabs[next].click()
      }}
    />
  )
}

/** The look of each tab, as the classes it has when selected and when not. `bare` leaves the
 *  shape and the unselected colours to the caller. */
const TAB_LOOKS = {
  pill: [
    'shrink-0 rounded-full px-4 py-1.5 text-sm font-medium transition-colors',
    'bg-ink text-paper',
    'border border-line text-ink hover:bg-surface',
  ],
  bare: ['transition-colors', 'bg-ink text-paper', ''],
} as const

export function TabsTrigger(
  props: Omit<JSX.ButtonHTMLAttributes<HTMLButtonElement>, 'value'> & {
    value: string
    variant?: keyof typeof TAB_LOOKS
  },
) {
  const [local, rest] = splitProps(props, ['value', 'variant', 'class'])
  const tabs = useContext(TabsContext)!
  const selected = () => tabs.value() === local.value
  const look = () => TAB_LOOKS[local.variant ?? 'pill']
  return (
    <button
      type="button"
      role="tab"
      id={tabId(tabs.id, local.value)}
      aria-selected={selected()}
      aria-controls={selected() ? panelId(tabs.id, local.value) : undefined}
      tabindex={selected() ? 0 : -1}
      class={cn(look()[0], look()[selected() ? 1 : 2], local.class)}
      onClick={() => tabs.select(local.value)}
      {...rest}
    />
  )
}

export function TabsContent(
  props: JSX.HTMLAttributes<HTMLDivElement> & { value: string },
) {
  const [local, rest] = splitProps(props, ['value'])
  const tabs = useContext(TabsContext)!
  return (
    <div
      role="tabpanel"
      id={panelId(tabs.id, local.value)}
      aria-labelledby={tabId(tabs.id, local.value)}
      {...rest}
    />
  )
}
