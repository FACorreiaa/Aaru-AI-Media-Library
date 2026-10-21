import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import { Match, Show, Switch, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import { MascotMedallion, Wordmark } from '../components/Brand'
import { Poster } from '../components/Poster'
import { Button } from '../components/ui/button'
import { kindOf, statusLabel } from '../lib/library/model'
import {
  handleProblem,
  invitePlea,
  inviterName,
  normalizeHandle,
} from '../lib/social/model'
import { loadInvite, redeemInvite, saveProfile } from '../lib/social/server'
import type { InvitePreview } from '../lib/social/server'
import { SITE_URL } from '../lib/site'

// SOC-002: a friend invite link, aaruapp.com/i/{code}. The same address opens the Apple apps
// (universal link) when they are installed; everywhere else it lands here. Signed out, it asks
// the friend to join and brings them back after sign-in; signed in, one tap makes them friends.
// It shows only who sent it and the title it carries, never anyone's library.
export const Route = createFileRoute('/i/$code')({
  loader: ({ params }) => loadInvite({ data: { code: params.code } }),
  head: ({ loaderData }) => {
    const preview = loaderData?.preview
    const title = preview
      ? `${inviterName(preview.inviter)} invited you to Aaru`
      : 'Aaru invite'
    const description = preview?.title
      ? invitePlea(
          preview.title.title,
          kindOf(preview.title.type, preview.title.isAnime),
        )
      : 'One private shelf for everything you watch and read.'
    return {
      meta: [
        { title: `${title} · Aaru` },
        { name: 'robots', content: 'noindex' },
        { name: 'description', content: description },
        { property: 'og:type', content: 'website' },
        { property: 'og:title', content: title },
        { property: 'og:description', content: description },
        { property: 'og:image', content: `${SITE_URL}/og.jpg` },
        { name: 'twitter:card', content: 'summary_large_image' },
      ],
    }
  },
  component: Invite,
})

function Page(props: { children: JSX.Element }) {
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col justify-center px-5 py-10">
      <Wordmark class="h-9 w-auto" />
      <div class="mt-8">{props.children}</div>
    </main>
  )
}

type Done = { name: string; titleAdded: boolean }

function Invite() {
  const page = Route.useLoaderData()
  const params = Route.useParams()
  const navigate = useNavigate()
  const [addTitle, setAddTitle] = createSignal(true)
  const [handle, setHandle] = createSignal('')
  const [working, setWorking] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [done, setDone] = createSignal<Done | null>(null)

  const needsHandle = () => !!page().viewer && !page().viewer?.handle

  async function accept(preview: InvitePreview) {
    if (working()) return
    if (needsHandle()) {
      const invalid = handleProblem(handle())
      if (invalid) return setProblem(invalid)
    }
    setWorking(true)
    setProblem(null)
    try {
      if (needsHandle())
        await saveProfile({ data: { handle: normalizeHandle(handle()) } })
      const result = await redeemInvite({
        data: { code: params().code, addTitle: !!preview.title && addTitle() },
      })
      setDone({
        name: inviterName(result.friend),
        titleAdded: result.titleAdded,
      })
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'The invite was not accepted.',
      )
    } finally {
      setWorking(false)
    }
  }

  const join = () =>
    void navigate({ to: '/sign-in', search: { next: `/i/${params().code}` } })

  return (
    <Page>
      <Show when={page().preview} fallback={<Invalid />}>
        {(preview) => (
          <Switch>
            <Match when={done()}>
              {(result) => (
                <>
                  <h1 class="font-display text-4xl leading-tight font-medium tracking-tight text-balance">
                    You and {result().name} are friends.
                  </h1>
                  <p class="mt-4 text-lg leading-relaxed text-muted">
                    <Show
                      when={result().titleAdded && preview().title}
                      fallback="You can now see each other’s shelves."
                    >
                      {(title) => (
                        <>
                          {title().title} is on your Plan to watch. You can now
                          see each other’s shelves.
                        </>
                      )}
                    </Show>
                  </p>
                  <Button
                    variant="ink"
                    size="lg"
                    class="mt-10 min-h-13 w-full text-base"
                    onClick={() => void navigate({ to: '/app' })}
                  >
                    Open Aaru
                  </Button>
                </>
              )}
            </Match>
            <Match when={preview().relationship === 'self'}>
              <h1 class="font-display text-4xl leading-tight font-medium tracking-tight">
                This is your invite.
              </h1>
              <p class="mt-4 text-lg leading-relaxed text-muted">
                Send this link to a friend. It works once, for the first person
                who opens it.
              </p>
              <Link
                to="/app"
                class="mt-10 inline-block font-semibold text-accent"
              >
                Back to Aaru
              </Link>
            </Match>
            <Match when={preview().relationship === 'friend'}>
              <h1 class="font-display text-4xl leading-tight font-medium tracking-tight text-balance">
                You and {inviterName(preview().inviter)} are already friends.
              </h1>
              <Button
                variant="ink"
                size="lg"
                class="mt-10 min-h-13 w-full text-base"
                onClick={() => void navigate({ to: '/app' })}
              >
                Open Aaru
              </Button>
            </Match>
            <Match when={true}>
              <Letter
                preview={preview()}
                addTitle={addTitle()}
                onAddTitle={setAddTitle}
              />
              <Show when={needsHandle()}>
                <label for="handle" class="mt-8 block text-sm font-semibold">
                  Choose a handle so {inviterName(preview().inviter)} knows it’s
                  you
                </label>
                <input
                  id="handle"
                  value={handle()}
                  onInput={(event) => setHandle(event.currentTarget.value)}
                  autocomplete="username"
                  autocapitalize="none"
                  spellcheck={false}
                  placeholder="@yourname"
                  class="mt-2 min-h-12 w-full rounded-panel border-0 bg-surface px-4 text-base text-ink placeholder:text-muted/70 focus:ring-2 focus:ring-accent focus:outline-none"
                />
              </Show>
              <Show
                when={page().viewer}
                fallback={
                  <Button
                    variant="ink"
                    size="lg"
                    class="mt-10 min-h-13 w-full text-base"
                    onClick={join}
                  >
                    Join Aaru
                  </Button>
                }
              >
                <Button
                  variant="ink"
                  size="lg"
                  class="mt-10 min-h-13 w-full text-base"
                  disabled={working()}
                  onClick={() => void accept(preview())}
                >
                  {working()
                    ? 'Adding…'
                    : `Add ${inviterName(preview().inviter)} as a friend`}
                </Button>
              </Show>
              <Show when={problem()}>
                {(message) => (
                  <p role="alert" class="mt-4 text-sm text-danger">
                    {message()}
                  </p>
                )}
              </Show>
              <p class="mt-4 text-sm leading-relaxed text-muted">
                <Show
                  when={page().viewer}
                  fallback="Sign in or create an account, and you’ll come straight back here. Your library stays private: only friends see it."
                >
                  Your library stays private: only friends see it.
                </Show>
              </p>
            </Match>
          </Switch>
        )}
      </Show>
    </Page>
  )
}

/** The invitation itself: who sent it and, when it carries one, the title they want to share. */
function Letter(props: {
  preview: InvitePreview
  addTitle: boolean
  onAddTitle: (add: boolean) => void
}) {
  const name = () => inviterName(props.preview.inviter)
  return (
    <>
      <MascotMedallion class="mx-auto w-28" priority />
      <h1 class="mt-8 font-display text-4xl leading-tight font-medium tracking-tight text-balance">
        {name()} invited you to Aaru.
      </h1>
      <Show when={props.preview.inviter.displayName}>
        <p class="mt-1 text-muted">@{props.preview.inviter.handle}</p>
      </Show>
      <Show when={props.preview.title}>
        {(title) => {
          const kind = () => kindOf(title().type, title().isAnime)
          return (
            <div class="mt-8 flex items-start gap-4">
              <Poster
                url={title().posterUrl}
                kind={kind()}
                radius="thumb"
                class="w-20 shrink-0"
              />
              <div class="min-w-0">
                <p class="font-display text-xl leading-snug italic">
                  “{invitePlea(title().title, kind())}”
                </p>
                <label class="mt-3 flex min-h-11 cursor-pointer items-center gap-3 text-sm">
                  <input
                    type="checkbox"
                    checked={props.addTitle}
                    onChange={(event) =>
                      props.onAddTitle(event.currentTarget.checked)
                    }
                    class="size-5 shrink-0 accent-[var(--accent)]"
                  />
                  Add to my {statusLabel('wishlist', kind())}
                </label>
              </div>
            </div>
          )
        }}
      </Show>
    </>
  )
}

function Invalid() {
  return (
    <>
      <h1 class="font-display text-4xl leading-tight font-medium tracking-tight">
        This invite isn’t valid anymore.
      </h1>
      <p class="mt-4 text-lg leading-relaxed text-muted">
        Invites work once and last two weeks. Ask your friend for a new link.
      </p>
      <Link to="/" class="mt-10 inline-block font-semibold text-accent">
        What is Aaru?
      </Link>
    </>
  )
}
