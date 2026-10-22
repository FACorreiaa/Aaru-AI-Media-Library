import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
import { Button } from '~/components/ui'
import { hitRef } from '../../lib/groups/kinds'
import {
  addChannelItem,
  addTitleToLibrary,
  listChannelItems,
  removeChannelItem,
} from '../../lib/groups/kinds-server'
import type { ChannelItem } from '../../lib/groups/kinds-server'
import type { Channel } from '../../lib/groups/server'
import { kindOf, statusLabel } from '../../lib/library/model'
import type { CatalogHit } from '../../lib/library/model'
import { useRealtime } from '../../lib/realtime/socket'
import { Poster } from '../Poster'
import { ChannelHeader } from './ChannelHeader'
import { TitlePicker } from './TitlePicker'
import { useGroup } from './shell'

/**
 * A `shelf` channel (GRP-008), called a List in the UI (UX-041): titles the whole group adds to
 * and takes off. Each card says who added it and whether it is in my library; "Add to my
 * library" is my own journaled tap. The search opens inline, under its button, rather than in a
 * popover: it holds a field and a page of results.
 */
export function ShelfView(props: {
  channel: Channel
  onOpenMembers: () => void
}) {
  const scope = useGroup()
  const ref = () => ({
    groupId: scope.detail().group.id,
    channelId: props.channel.id,
  })
  const [items, setItems] = createSignal<ChannelItem[] | null>(null)
  const [adding, setAdding] = createSignal(false)
  const [busy, setBusy] = createSignal<Set<string>>(new Set())
  const [removing, setRemoving] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function load() {
    try {
      setItems(await listChannelItems({ data: ref() }))
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : "The list didn't load.",
      )
      if (!items()) setItems([])
    }
  }

  onMount(() => void load())
  useRealtime((event) => {
    if (event.type === 'ready') return void load()
    if (event.type === 'shelf.updated' && event.channelId === props.channel.id)
      void load()
  })

  async function run(key: string, action: () => Promise<void>) {
    setProblem(null)
    setBusy(new Set([...busy(), key]))
    try {
      await action()
    } catch (error) {
      setProblem(error instanceof Error ? error.message : 'That was not saved.')
    } finally {
      const next = new Set(busy())
      next.delete(key)
      setBusy(next)
    }
  }

  function add(hit: CatalogHit) {
    void run('add', async () => {
      setItems(await addChannelItem({ data: { ...ref(), title: hitRef(hit) } }))
      setAdding(false)
    })
  }

  function addToMine(item: ChannelItem) {
    void run(item.title.id, async () => {
      const entry = await addTitleToLibrary({
        data: { titleId: item.title.id, type: item.title.type },
      })
      setItems((list) =>
        (list ?? []).map((i) =>
          i.title.id === item.title.id ? { ...i, myStatus: entry.status } : i,
        ),
      )
    })
  }

  function remove(item: ChannelItem) {
    setRemoving(null)
    void run(item.title.id, async () => {
      await removeChannelItem({ data: { ...ref(), titleId: item.title.id } })
      setItems((list) =>
        (list ?? []).filter((i) => i.title.id !== item.title.id),
      )
    })
  }

  return (
    <section
      aria-label={props.channel.name}
      class="flex min-h-0 min-w-0 flex-1 flex-col bg-paper"
    >
      <ChannelHeader
        channel={props.channel}
        onOpenMembers={props.onOpenMembers}
        e2e={false}
      />
      <div class="min-h-0 flex-1 overflow-y-auto px-4 py-5 md:px-6">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 class="font-display text-2xl font-medium">
              {props.channel.name}
            </h2>
            <p class="mt-0.5 text-sm text-muted">
              {props.channel.topic ??
                'A list the whole group adds to. Anyone here can add or remove a title.'}
            </p>
          </div>
          <Button
            size="sm"
            aria-expanded={adding()}
            onClick={() => setAdding(!adding())}
          >
            {adding() ? 'Done' : 'Add a title'}
          </Button>
        </div>
        <Show when={adding()}>
          <div class="mt-4 max-w-xl rounded-2xl border border-line bg-paper p-4 shadow-sm animate-in duration-150 fade-in-0 slide-in-from-top-1">
            <TitlePicker onPick={add} busy={busy().has('add')} />
          </div>
        </Show>
        <Show when={problem()}>
          {(text) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {text()}
            </p>
          )}
        </Show>
        <Show
          when={items()}
          fallback={<p class="mt-8 text-sm text-muted">Loading the list…</p>}
        >
          {(list) => (
            <Show
              when={list().length > 0}
              fallback={
                <p class="mt-10 text-center text-muted">
                  Nothing on this list yet. Add the first title.
                </p>
              }
            >
              <ul class="mt-5 grid grid-cols-2 gap-x-4 gap-y-6 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-5">
                <For each={list()}>
                  {(item) => (
                    // A container, so an album's remove button can find the top of its square
                    // cover, which sits at the foot of a 2:3 slot (half the width down).
                    <li class="group/item relative @container min-w-0">
                      <Link to="/app/title/$id" params={{ id: item.title.id }}>
                        <Poster
                          url={item.title.posterUrl}
                          kind={kindOf(item.title.type, item.title.isAnime)}
                          class="w-full"
                          frame
                        />
                        <p class="mt-2 truncate text-sm font-semibold">
                          {item.title.title}
                        </p>
                      </Link>
                      <p class="truncate text-xs text-muted">
                        {[
                          item.title.year,
                          item.addedBy
                            ? `added by @${item.addedBy.handle}`
                            : null,
                        ]
                          .filter(Boolean)
                          .join(' · ')}
                      </p>
                      <div class="mt-2 flex items-center gap-2">
                        <Show
                          when={item.myStatus}
                          fallback={
                            <Button
                              variant="outline"
                              size="xs"
                              disabled={busy().has(item.title.id)}
                              onClick={() => addToMine(item)}
                            >
                              Add to my library
                            </Button>
                          }
                        >
                          {(status) => (
                            <span class="rounded-full bg-accent/12 px-2.5 py-1 text-xs font-medium text-accent">
                              {statusLabel(
                                status(),
                                kindOf(item.title.type, item.title.isAnime),
                              )}
                            </span>
                          )}
                        </Show>
                      </div>
                      <Show
                        when={removing() === item.title.id}
                        fallback={
                          <Button
                            variant="ghost"
                            size="bare"
                            aria-label={`Remove ${item.title.title} from list`}
                            title="Remove from list"
                            onClick={() => setRemoving(item.title.id)}
                            class="absolute right-1.5 size-7 bg-paper/90 font-normal opacity-0 shadow-sm group-hover/item:opacity-100 hover:text-danger focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                            classList={{
                              'top-1.5': item.title.type !== 'album',
                              'top-[calc(50cqw+0.375rem)]':
                                item.title.type === 'album',
                            }}
                          >
                            ×
                          </Button>
                        }
                      >
                        <div class="absolute inset-x-1.5 top-1.5 flex items-center justify-between gap-2 rounded-xl bg-paper/95 px-3 py-2 text-xs shadow">
                          <Button
                            variant="ghost"
                            size="bare"
                            onClick={() => remove(item)}
                            class="text-xs font-semibold text-danger hover:text-danger"
                          >
                            Remove from list
                          </Button>
                          <Button
                            variant="ghost"
                            size="bare"
                            onClick={() => setRemoving(null)}
                            class="text-xs font-normal"
                          >
                            Keep
                          </Button>
                        </div>
                      </Show>
                    </li>
                  )}
                </For>
              </ul>
            </Show>
          )}
        </Show>
      </div>
    </section>
  )
}
