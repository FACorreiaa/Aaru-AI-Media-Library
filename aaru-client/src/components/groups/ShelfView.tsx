import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
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
 * A shelf channel (GRP-008): titles the whole group adds to and takes off. Each card says who
 * added it and whether it is in my library; "Add to my library" is my own journaled tap.
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
        error instanceof Error ? error.message : 'The shelf did not load.',
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
                'A shelf the whole group adds to. Anyone here can add or remove a title.'}
            </p>
          </div>
          <button
            type="button"
            aria-expanded={adding()}
            onClick={() => setAdding(!adding())}
            class="rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent"
          >
            {adding() ? 'Done' : 'Add a title'}
          </button>
        </div>
        <Show when={adding()}>
          <div class="group-pop mt-4 max-w-xl rounded-2xl border border-line bg-paper p-4 shadow-sm">
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
          fallback={<p class="mt-8 text-sm text-muted">Loading the shelf…</p>}
        >
          {(list) => (
            <Show
              when={list().length > 0}
              fallback={
                <p class="mt-10 text-center text-muted">
                  Nothing here yet. Add the first title.
                </p>
              }
            >
              <ul class="mt-5 grid grid-cols-2 gap-x-4 gap-y-6 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-5">
                <For each={list()}>
                  {(item) => (
                    <li class="group/item relative min-w-0">
                      <Link to="/app/title/$id" params={{ id: item.title.id }}>
                        <Poster
                          url={item.title.posterUrl}
                          kind={kindOf(item.title.type, item.title.isAnime)}
                          class="w-full"
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
                            <button
                              type="button"
                              disabled={busy().has(item.title.id)}
                              onClick={() => addToMine(item)}
                              class="rounded-full border border-ink/25 px-3 py-1 text-xs font-semibold hover:bg-surface disabled:opacity-50"
                            >
                              Add to my library
                            </button>
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
                          <button
                            type="button"
                            aria-label={`Remove ${item.title.title} from the shelf`}
                            title="Remove from the shelf"
                            onClick={() => setRemoving(item.title.id)}
                            class="absolute top-1.5 right-1.5 grid size-7 place-items-center rounded-full bg-paper/90 text-muted opacity-0 shadow-sm group-hover/item:opacity-100 hover:text-danger focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                          >
                            ×
                          </button>
                        }
                      >
                        <div class="absolute inset-x-1.5 top-1.5 flex items-center justify-between gap-2 rounded-xl bg-paper/95 px-3 py-2 text-xs shadow">
                          <button
                            type="button"
                            onClick={() => remove(item)}
                            class="font-semibold text-danger"
                          >
                            Remove
                          </button>
                          <button
                            type="button"
                            onClick={() => setRemoving(null)}
                            class="text-muted"
                          >
                            Keep
                          </button>
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
