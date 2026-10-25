import { Link, useLocation, useRouter } from '@tanstack/solid-router'
import {
  For,
  Show,
  Suspense,
  createEffect,
  createMemo,
  createSignal,
  lazy,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import type { JSX } from 'solid-js'
import { requestMALPull } from '../../lib/mal/server'
import { Wordmark } from '../Brand'
import type { Scope } from '../SearchPanel'
import {
  Button,
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
  Dialog,
  DialogContent,
  DialogPortal,
  Kbd,
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarRail,
  SidebarTrigger,
  Toaster,
  useSidebar,
} from '~/components/ui'
import { createFocusReturn, focusFieldOnOpen } from '../../lib/dialog-focus'
import { listGroups } from '../../lib/groups/server'
import { browserQueryClient } from '../../integrations/tanstack-query/provider'
import { sportSettingsQuery } from '../../lib/sports/query'
import { upsert } from '../../lib/library/model'
import type { LibraryEntry } from '../../lib/library/model'
import { getLibrary } from '../../lib/library/server'
import { ShellContext } from './context'
import type { AppShellContext, Previous, SearchHost } from './context'
import {
  BOTTOM,
  TOP,
  inMore,
  isAt,
  moreRows,
  readMoreOpen,
  writeMoreOpen,
} from '../../lib/shell/nav'
import type { NavPath, NavTarget } from '../../lib/shell/nav'
import {
  BooksIcon,
  CalendarIcon,
  ChevronDownIcon,
  DiscoverIcon,
  FriendsIcon,
  GroupsIcon,
  HomeIcon,
  InsightsIcon,
  LibraryIcon,
  ListsIcon,
  MangaIcon,
  MenuIcon,
  MoreIcon,
  MusicIcon,
  SearchIcon,
  SettingsIcon,
  SportsIcon,
} from './icons'

const SearchPanel = lazy(() =>
  import('../SearchPanel').then((m) => ({ default: m.SearchPanel })),
)

// GAM-004's unlock toast and card: its own chunk, after the page, never on a first load's path.
const UnlockWatcher = lazy(() =>
  import('../achievements/UnlockWatcher').then((m) => ({
    default: m.UnlockWatcher,
  })),
)

type Icon = (p: { class?: string }) => JSX.Element

const ICONS: Record<NavPath, Icon> = {
  '/app': HomeIcon,
  '/app/discover': DiscoverIcon,
  '/app/library': LibraryIcon,
  '/app/calendar': CalendarIcon,
  '/app/lists': ListsIcon,
  '/app/friends': FriendsIcon,
  '/app/groups': GroupsIcon,
  '/app/books': BooksIcon,
  '/app/manga': MangaIcon,
  '/app/music': MusicIcon,
  '/app/sports': SportsIcon,
  '/app/insights': InsightsIcon,
  '/app/settings': SettingsIcon,
}

/** "Andor · Aaru" → "Andor"; "Account · Settings · Aaru" → "Account". */
function labelOf(title: string): string {
  const first = title.split(' · ')[0]?.trim()
  return first && first !== 'Aaru' ? first : 'Back'
}

export type ShellSession = { displayName: string | null; handle: string | null }

/**
 * The signed-in web app's one shell (DESIGN.md §18, UX-002): the sidebar, persistent and
 * collapsible to icons from 1024px, a sheet behind a top bar below that; one Search that opens
 * in place on every page (⌘K); and a fluid `main` every `/app` page renders into.
 */
export function AppShell(props: {
  session: ShellSession
  defaultOpen: boolean
  children: JSX.Element
}) {
  const router = useRouter()
  const [host, setHost] = createSignal<SearchHost | null>(null)
  const [searchOpen, setSearchOpen] = createSignal(false)
  const [searchMounted, setSearchMounted] = createSignal(false)
  const [scope, setScope] = createSignal<Scope | undefined>()
  // Bumped when Search is asked for a tab, so the panel opens on it.
  const [searchKey, setSearchKey] = createSignal(0)
  const [ownEntries, setOwnEntries] = createSignal<LibraryEntry[]>([])
  const [previous, setPrevious] = createSignal<Previous | null>(null)
  const [mentions, setMentions] = createSignal(0)
  const [sportsOn, setSportsOn] = createSignal(false)
  // Esc or Done returns focus to the control that opened Search.
  const focusReturn = createFocusReturn()
  let ownRequested = false

  function loadOwnLibrary() {
    if (ownRequested) return
    ownRequested = true
    getLibrary()
      .then((library) =>
        setOwnEntries((recent) => recent.reduce(upsert, library)),
      )
      .catch(() => {
        // Search still works; only its "In your library" marks wait.
        ownRequested = false
      })
  }

  function openSearch(next?: Scope, from?: Element) {
    if (!searchOpen()) focusReturn.remember(from)
    if (next !== undefined || scope() !== undefined) {
      setScope(next)
      setSearchKey((k) => k + 1)
    }
    setSearchMounted(true)
    setSearchOpen(true)
    if (!host()) loadOwnLibrary()
  }

  const entries = () => host()?.entries() ?? ownEntries()
  function added(entry: LibraryEntry) {
    setOwnEntries((list) => upsert(list, entry))
    host()?.onAdded(entry)
  }

  async function refreshMentions() {
    try {
      const groups = await listGroups()
      setMentions(groups.reduce((sum, g) => sum + g.mentions, 0))
    } catch {
      // The badge is a nicety; Groups itself shows the counts.
    }
  }

  onMount(() => {
    const keydown = (event: KeyboardEvent) => {
      if (event.key.toLowerCase() === 'k' && (event.metaKey || event.ctrlKey)) {
        event.preventDefault()
        openSearch()
      }
    }
    // MyAnimeList changes come back on each open (SCR-010); the server ignores asks too close
    // together and accounts without MAL.
    const askMAL = () => void requestMALPull().catch(() => undefined)
    // Without an answer the Sports row stays hidden, as Concerts do on Music. Asked again each
    // time the tab comes back, so a server that turned Sports on shows it without a reload.
    const checkSports = (fresh: boolean) =>
      void browserQueryClient()
        ?.fetchQuery(
          fresh ? { ...sportSettingsQuery, staleTime: 0 } : sportSettingsQuery,
        )
        .then((settings) => setSportsOn(settings.available))
        .catch(() => undefined)
    const visible = () => {
      if (document.visibilityState !== 'visible') return
      void refreshMentions()
      checkSports(true)
      askMAL()
    }
    window.addEventListener('keydown', keydown)
    document.addEventListener('visibilitychange', visible)
    void refreshMentions()
    checkSports(false)
    askMAL()
    // The page you leave is the one a detail page's back link names.
    const unsubscribe = router.subscribe('onBeforeNavigate', (event) => {
      if (!event.pathChanged || !event.fromLocation) return
      setPrevious({
        href: event.fromLocation.href,
        label: labelOf(document.title),
      })
    })
    onCleanup(() => {
      window.removeEventListener('keydown', keydown)
      document.removeEventListener('visibilitychange', visible)
      unsubscribe()
    })
  })

  const shell: AppShellContext = {
    openSearch,
    setSearchHost: setHost,
    previous,
    setMentions,
  }

  return (
    <ShellContext.Provider value={shell}>
      <SidebarProvider defaultOpen={props.defaultOpen}>
        <a
          href="#content"
          class="sr-only z-50 rounded-full bg-ink px-4 py-2 text-sm text-paper focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
        >
          Skip to content
        </a>
        <AppSidebar
          session={props.session}
          mentions={mentions()}
          sports={sportsOn()}
          onSearch={(from) => openSearch(undefined, from)}
        />
        <SidebarInset class="min-w-0">
          <TopBar onSearch={(from) => openSearch(undefined, from)} />
          <div
            id="content"
            tabIndex={-1}
            class="flex min-w-0 flex-1 flex-col outline-none"
          >
            {props.children}
          </div>
        </SidebarInset>
      </SidebarProvider>

      <Dialog open={searchOpen()} onOpenChange={setSearchOpen}>
        <DialogPortal>
          <DialogContent
            showCloseButton={false}
            aria-label="Search"
            onOpenAutoFocus={focusFieldOnOpen}
            onCloseAutoFocus={focusReturn.restore}
            class="block w-[min(40rem,calc(100vw-2rem))] gap-0 p-0 sm:max-w-none"
          >
            <Show when={searchMounted()}>
              <Suspense
                fallback={
                  <p class="px-5 py-8 text-center text-sm text-muted">
                    Loading…
                  </p>
                }
              >
                {/* A new key mounts a fresh panel on the asked-for tab. */}
                <For each={[searchKey()]}>
                  {() => (
                    <SearchPanel
                      scope={scope()}
                      entries={entries()}
                      onAdded={added}
                      onClose={() => setSearchOpen(false)}
                    />
                  )}
                </For>
              </Suspense>
            </Show>
          </DialogContent>
        </DialogPortal>
      </Dialog>
      <Toaster />
      {/* Its own boundary, so loading it never suspends the page around it. */}
      <Suspense>
        <UnlockWatcher />
      </Suspense>
    </ShellContext.Provider>
  )
}

function NavRow(props: { d: NavTarget; badge?: number }) {
  const location = useLocation()
  const active = () => isAt(location().pathname, props.d)
  const label = () =>
    props.badge ? `${props.d.label}, ${props.badge} mentions` : props.d.label
  const RowIcon = () => {
    const Glyph = ICONS[props.d.to]
    return <Glyph class="size-[1.15rem]! shrink-0" />
  }
  return (
    <SidebarMenuItem>
      <SidebarMenuButton
        as={Link}
        to={props.d.to}
        isActive={active()}
        aria-current={active() ? 'page' : undefined}
        aria-label={label()}
        tooltip={props.d.label}
        size="lg"
        class="h-10 gap-3 rounded-full px-3 text-md text-muted hover:bg-stone/70 hover:text-ink data-[active=true]:bg-stone data-[active=true]:font-semibold data-[active=true]:text-ink group-data-[collapsible=icon]:size-10! group-data-[collapsible=icon]:p-3!"
      >
        <RowIcon />
        <span>{props.d.label}</span>
      </SidebarMenuButton>
      <Show when={props.badge}>
        {(count) => (
          <SidebarMenuBadge class="top-2.5! right-2 rounded-full bg-accent px-1.5 text-on-accent">
            {count() > 99 ? '99+' : count()}
          </SidebarMenuBadge>
        )}
      </Show>
    </SidebarMenuItem>
  )
}

/**
 * NAV-001: More (Groups, Books, Manga, Music, Sports) folds under one header. It is open on its
 * own pages; elsewhere it keeps the state it was last left in (this browser only). Closed, the
 * header carries a dot while Groups has mentions.
 */
function MoreGroup(props: {
  rows: NavTarget[]
  mentions: number
  badgeFor: (d: NavTarget) => number | undefined
}) {
  const location = useLocation()
  const inside = createMemo(() => inMore(location().pathname))
  // What the user last chose. Read after mount: the server has no storage, so it renders the
  // group closed unless the page is one of its rows.
  let chosen = false
  const [open, setOpen] = createSignal(inside())
  onMount(() => {
    chosen = readMoreOpen()
    if (!inside()) setOpen(chosen)
  })
  // Arriving on a More page opens it; leaving goes back to the user's own choice.
  createEffect(on(inside, (now) => setOpen(now || chosen), { defer: true }))
  function toggle(next: boolean) {
    chosen = next
    setOpen(next)
    writeMoreOpen(next)
  }
  const dot = () => !open() && props.mentions > 0

  return (
    <Collapsible open={open()} onOpenChange={toggle} class="group/more mt-0.5">
      <SidebarMenu>
        <SidebarMenuItem>
          <CollapsibleTrigger
            as={SidebarMenuButton}
            size="lg"
            class="h-10 gap-3 rounded-full px-3 text-md text-muted hover:bg-stone/70 hover:text-ink"
          >
            <MoreIcon class="size-[1.15rem]! shrink-0" />
            <span class="flex-1">More</span>
            <Show when={dot()}>
              <span
                aria-hidden="true"
                class="size-2 shrink-0 rounded-full bg-accent"
              />
              <span class="sr-only">, new mentions in Groups</span>
            </Show>
            <ChevronDownIcon class="size-4! shrink-0 transition-transform group-data-[expanded]/more:rotate-180 motion-reduce:transition-none" />
          </CollapsibleTrigger>
        </SidebarMenuItem>
      </SidebarMenu>
      <CollapsibleContent>
        <SidebarMenu class="mt-0.5 gap-0.5 pl-3">
          <For each={props.rows}>
            {(d) => <NavRow d={d} badge={props.badgeFor(d)} />}
          </For>
        </SidebarMenu>
      </CollapsibleContent>
    </Collapsible>
  )
}

function AppSidebar(props: {
  session: ShellSession
  mentions: number
  sports: boolean
  onSearch: (from: Element) => void
}) {
  const sidebar = useSidebar()
  const location = useLocation()
  // A link in the sheet takes you there and closes it.
  createEffect(
    on(
      () => location().pathname,
      () => sidebar.setOpenMobile(false),
      { defer: true },
    ),
  )
  // The persistent sidebar folded to icons; the phone sheet is never a rail.
  const rail = () => sidebar.state() === 'collapsed' && !sidebar.isMobile()
  const more = () => moreRows(props.sports)
  const badgeFor = (d: NavTarget) =>
    d.to === '/app/groups' ? props.mentions : undefined
  const name = () =>
    props.session.displayName ??
    (props.session.handle ? `@${props.session.handle}` : 'Your account')
  const initial = () => name().replace('@', '').charAt(0).toUpperCase()

  return (
    <Sidebar collapsible="icon" aria-label="Aaru">
      <SidebarHeader class="gap-3 px-3 pt-4">
        <div class="flex items-center justify-between gap-2 group-data-[collapsible=icon]:justify-center">
          <div class="pl-1 group-data-[collapsible=icon]:hidden">
            <Wordmark to="/app" class="h-7 w-auto" />
          </div>
          <SidebarTrigger
            aria-label={sidebar.open() ? 'Collapse sidebar' : 'Expand sidebar'}
            class="hidden size-9 rounded-full text-muted hover:text-ink lg:inline-flex"
          />
        </div>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={(event: MouseEvent) =>
                props.onSearch(event.currentTarget as Element)
              }
              tooltip="Search (⌘K)"
              aria-keyshortcuts="Meta+K Control+K"
              size="lg"
              class="h-10 gap-3 rounded-full border border-line bg-paper px-3 text-muted hover:bg-paper hover:text-ink group-data-[collapsible=icon]:size-10! group-data-[collapsible=icon]:border-0 group-data-[collapsible=icon]:p-3!"
            >
              <SearchIcon class="size-[1.15rem]! shrink-0" />
              <span class="flex-1">Search</span>
              <Kbd class="bg-surface group-data-[collapsible=icon]:hidden">
                ⌘K
              </Kbd>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent class="px-1">
        <SidebarGroup>
          <SidebarMenu class="gap-0.5">
            <For each={TOP}>{(d) => <NavRow d={d} />}</For>
            {/* In the icon rail a header would be one more unlabeled icon: More's rows stand
 in the list as they are. */}
            <Show when={rail()}>
              <For each={more()}>
                {(d) => <NavRow d={d} badge={badgeFor(d)} />}
              </For>
            </Show>
          </SidebarMenu>
          <Show when={!rail()}>
            <MoreGroup
              rows={more()}
              mentions={props.mentions}
              badgeFor={badgeFor}
            />
          </Show>
        </SidebarGroup>
        <SidebarGroup class="mt-auto">
          <SidebarMenu class="gap-0.5">
            <For each={BOTTOM}>{(d) => <NavRow d={d} />}</For>
          </SidebarMenu>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter class="border-t border-line px-3 py-3">
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              as={Link}
              to="/app/settings/account"
              tooltip={name()}
              size="lg"
              class="h-12 gap-3 rounded-full px-1.5 hover:bg-stone/70 group-data-[collapsible=icon]:size-10! group-data-[collapsible=icon]:p-1!"
            >
              <span
                aria-hidden="true"
                class="grid size-8 shrink-0 place-items-center rounded-full bg-ink font-display text-sm text-paper"
              >
                {initial()}
              </span>
              <span class="flex min-w-0 flex-col leading-tight">
                <span class="truncate text-sm font-semibold text-ink">
                  {name()}
                </span>
                <Show when={props.session.handle && props.session.displayName}>
                  <span class="truncate text-xs text-muted">
                    @{props.session.handle}
                  </span>
                </Show>
              </span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}

/** Below 1024px: the wordmark, Search and the menu that opens the sidebar as a sheet. */
function TopBar(props: { onSearch: (from: Element) => void }) {
  const sidebar = useSidebar()
  return (
    <header class="sticky top-0 z-30 flex h-14 items-center gap-2 border-b border-line bg-paper/95 px-4 backdrop-blur-sm lg:hidden">
      <Wordmark to="/app" class="h-7 w-auto" />
      <div class="ml-auto flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          aria-label="Search"
          onClick={(event) => props.onSearch(event.currentTarget)}
          class="text-ink"
        >
          <SearchIcon class="size-5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Menu"
          aria-expanded={sidebar.openMobile()}
          onClick={() => sidebar.setOpenMobile(true)}
          class="text-ink"
        >
          <MenuIcon class="size-5" />
        </Button>
      </div>
    </header>
  )
}
