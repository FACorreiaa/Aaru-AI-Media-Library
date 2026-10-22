import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { Poster } from '../components/Poster'
import { kindOf } from '../lib/library/model'
import {
  countsLine,
  friendsSince,
  inviterName,
  itemProgress,
  monogram,
} from '../lib/social/model'
import { loadFriendProfile } from '../lib/social/server'
import type { FriendItem } from '../lib/social/server'
import type { components } from '../lib/api/schema'
import { getSession } from '../lib/session/session'

type TitleSummary = components['schemas']['TitleSummary']

// SOC-001 / SOC-003 on the web: a friend's profile, shelf first. What they are watching, what
// you share, what they finished. Friends only; anyone else gets the same "not here" page.
export const Route = createFileRoute('/app_/friends/$handle')({
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: ({ params }) =>
    loadFriendProfile({ data: { handle: params.handle } }),
  // After the loader, so its data types the title.
  head: ({ loaderData }) => ({
    meta: [
      {
        title: `${loaderData?.profile ? inviterName(loaderData.profile.user) : 'Friend'} · Aaru`,
      },
    ],
  }),
  component: Profile,
})

function Profile() {
  const loaded = Route.useLoaderData()
  const profile = () => loaded().profile
  return (
    <div class="min-h-[100dvh]">
      <AppHeader class="max-w-4xl" />
      <main class="mx-auto max-w-4xl px-5 pb-20 md:px-8">
        <Show
          when={profile()}
          fallback={
            <>
              <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
                Not your friend
              </h1>
              <p class="mt-3 text-muted">
                Only friends see each other’s shelves.
              </p>
              <Link
                to="/app/friends"
                class="mt-6 inline-block font-semibold text-accent"
              >
                Back to Friends
              </Link>
            </>
          }
        >
          {(friend) => {
            const name = () => inviterName(friend().user)
            return (
              <>
                <header class="mt-4 flex items-center gap-4">
                  <span
                    aria-hidden="true"
                    class="grid size-16 shrink-0 place-items-center rounded-full bg-medallion/20 font-display text-2xl font-medium"
                  >
                    {monogram(friend().user)}
                  </span>
                  <div class="min-w-0">
                    <h1 class="font-display text-4xl font-medium tracking-tight">
                      {name()}
                    </h1>
                    <p class="text-sm text-muted">
                      @{friend().user.handle} ·{' '}
                      {friendsSince(friend().friendsSince)}
                    </p>
                    <Show when={countsLine(friend().counts)}>
                      {(line) => <p class="text-sm text-muted">{line()}</p>}
                    </Show>
                  </div>
                </header>

                <Show
                  when={friend().sharing}
                  fallback={
                    <p class="mt-10 text-muted">
                      {name()} keeps their library to themselves.
                    </p>
                  }
                >
                  <Shelf
                    title="Watching"
                    count={friend().watching?.length ?? 0}
                    empty="Nothing in progress."
                  >
                    <For each={friend().watching}>
                      {(item) => (
                        <Cover
                          title={item.title}
                          caption={itemProgress(item)}
                        />
                      )}
                    </For>
                  </Shelf>

                  <Show when={friend().compare}>
                    {(compare) => (
                      <section class="mt-10 rounded-[20px] bg-surface p-5">
                        <h2 class="font-display text-xl font-medium">
                          You both
                        </h2>
                        <p class="mt-1 text-sm text-muted">
                          {bothFinished(compare().bothFinished)}
                        </p>
                        <Show when={compare().bothWant.length > 0}>
                          <Shelf
                            title="Want to watch"
                            count={compare().bothWant.length}
                            level="h3"
                          >
                            <For each={compare().bothWant}>
                              {(title) => <Cover title={title} />}
                            </For>
                          </Shelf>
                        </Show>
                        <Show when={compare().theyLoved.length > 0}>
                          <Shelf
                            title={`${name()} loved, you haven’t`}
                            count={compare().theyLoved.length}
                            level="h3"
                          >
                            <For each={compare().theyLoved}>
                              {(title) => <Cover title={title} />}
                            </For>
                          </Shelf>
                        </Show>
                      </section>
                    )}
                  </Show>

                  <Shelf
                    title="Recently finished"
                    count={friend().recentlyFinished?.length ?? 0}
                    empty="Nothing finished yet."
                  >
                    <For each={friend().recentlyFinished}>
                      {(item) => (
                        <Cover title={item.title} caption={rated(item)} />
                      )}
                    </For>
                  </Shelf>
                </Show>
              </>
            )
          }}
        </Show>
      </main>
    </div>
  )
}

function bothFinished(count: number): string {
  if (count === 0) return 'Nothing finished by both of you yet.'
  return count === 1
    ? '1 title finished by both of you'
    : `${count} titles finished by both of you`
}

function rated(item: FriendItem): string | null {
  return item.rating != null ? `★ ${item.rating}` : null
}

/** A titled row of covers that scrolls sideways on a phone and wraps on a wide screen. */
function Shelf(props: {
  title: string
  count: number
  empty?: string
  level?: 'h2' | 'h3'
  children: JSX.Element
}) {
  const heading = () =>
    props.level === 'h3' ? (
      <h3 class="mt-6 text-sm font-semibold">{props.title}</h3>
    ) : (
      <h2 class="mt-10 font-display text-xl font-medium">{props.title}</h2>
    )
  return (
    <section>
      {heading()}
      <Show
        when={props.count > 0}
        fallback={<p class="mt-2 text-sm text-muted">{props.empty}</p>}
      >
        <ul class="mt-3 flex gap-4 overflow-x-auto pb-2 md:flex-wrap md:overflow-visible">
          {props.children}
        </ul>
      </Show>
    </section>
  )
}

function Cover(props: { title: TitleSummary; caption?: string | null }) {
  return (
    <li class="w-24 shrink-0">
      <Poster
        url={props.title.posterUrl}
        kind={kindOf(props.title.type, props.title.isAnime)}
        frame
      />
      <p class="mt-2 line-clamp-2 text-sm leading-snug font-medium">
        {props.title.title}
      </p>
      <Show when={props.caption}>
        {(caption) => <p class="text-xs text-muted">{caption()}</p>}
      </Show>
    </li>
  )
}
