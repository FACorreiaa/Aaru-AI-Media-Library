import { MascotMedallion } from '../Brand'
import { For, Match, Show, Switch } from 'solid-js'
import type { JSX } from 'solid-js'
import { Poster } from '../Poster'
import { hoursLabel } from '../../lib/home/model'
import { countLabel, ratingLabel, titleKind } from '../../lib/recap/deck'
import type { RecapCard } from '../../lib/recap/deck'
import { dayLabel, periodLabel } from '../../lib/recap/model'
import type { Stats, StatsTitle } from '../../lib/recap/model'
import { createCountUp } from './motion'

// GAM-006a/e: one full-height card of the Recap story per `RecapCard` kind. Entrances are CSS
// (`.recap-*` in styles.css) and replay each time a card is shown.

function Count(props: { value: number }) {
  const value = createCountUp(() => props.value)
  return <>{value().toLocaleString('en')}</>
}

function Eyebrow(props: { children: JSX.Element }) {
  return (
    <p class="recap-rise text-sm font-medium tracking-[0.14em] uppercase opacity-80">
      {props.children}
    </p>
  )
}

function Big(props: { children: JSX.Element; delay?: number }) {
  return (
    <p
      class="recap-rise mt-3 font-display text-7xl leading-none font-medium tracking-tight tabular-nums md:text-8xl"
      style={{ '--delay': `${props.delay ?? 120}ms` }}
    >
      {props.children}
    </p>
  )
}

function Line(props: { children: JSX.Element; delay?: number }) {
  return (
    <p
      class="recap-rise mt-5 max-w-sm text-lg leading-snug opacity-90"
      style={{ '--delay': `${props.delay ?? 360}ms` }}
    >
      {props.children}
    </p>
  )
}

function TopRow(props: { entry: StatsTitle; rank: number }) {
  return (
    <li
      class="recap-rise flex items-center gap-4"
      style={{ '--delay': `${150 + props.rank * 110}ms` }}
    >
      <span class="w-6 font-display text-2xl tabular-nums opacity-70">
        {props.rank}
      </span>
      <Poster
        url={props.entry.title.posterUrl}
        kind={titleKind(props.entry.title)}
        class="w-12 shrink-0 ring-1 ring-current/20"
      />
      <span class="min-w-0">
        <span class="block truncate font-display text-xl">
          {props.entry.title.title}
        </span>
        <span class="text-sm opacity-75">
          {props.entry.episodes > 0
            ? `${props.entry.episodes} episodes`
            : `${props.entry.minutes} minutes`}
        </span>
      </span>
    </li>
  )
}

export function RecapCardView(props: {
  card: RecapCard
  stats: Stats
  share: JSX.Element
}) {
  const period = () => ({ year: props.stats.year, month: props.stats.month })
  return (
    <Switch>
      <Match when={props.card.kind === 'intro' && props.card}>
        {(card) => (
          <>
            {/* Aaru opens the story. Still: a card may be captured as an image. */}
            <div class="recap-rise mb-8">
              <MascotMedallion decorative class="w-20 md:w-24" />
            </div>
            <Eyebrow>{card().partial ? 'So far' : 'Your recap'}</Eyebrow>
            <h2
              class="recap-rise mt-4 font-display text-6xl leading-[1.02] font-medium tracking-tight md:text-7xl"
              style={{ '--delay': '120ms' }}
            >
              {card().heading}
            </h2>
            <Line>
              Everything you watched, read and listened to, from your own
              library. Tap to go on.
            </Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'time' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Time with stories</Eyebrow>
            <Big>
              <Count value={card().minutes} />
            </Big>
            <p class="recap-rise mt-2 text-xl" style={{ '--delay': '200ms' }}>
              minutes
            </p>
            <Line>{card().caption}</Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'episodes' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Episodes</Eyebrow>
            <Big>
              <Count value={card().episodes} />
            </Big>
            <div class="mt-8 flex h-40 items-end gap-[3px]" aria-hidden="true">
              <For each={card().bars}>
                {(bar, i) => (
                  <div class="flex h-full flex-1 flex-col justify-end gap-1">
                    <div
                      class="recap-bar rounded-t-[3px]"
                      classList={{
                        'bg-current': bar.busiest,
                        'bg-current/35': !bar.busiest,
                      }}
                      style={{
                        height: `${Math.max(bar.height * 100, bar.height > 0 ? 4 : 1)}%`,
                        '--delay': `${200 + i() * 35}ms`,
                      }}
                    />
                    <Show when={card().bars.length <= 12}>
                      <span class="text-center text-[11px] opacity-70">
                        {bar.label}
                      </span>
                    </Show>
                  </div>
                )}
              </For>
            </div>
            <Show when={card().busiest}>
              {(busiest) => <Line delay={700}>{busiest()}</Line>}
            </Show>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'biggestDay' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Your biggest day</Eyebrow>
            <h2
              class="recap-rise mt-4 font-display text-6xl leading-none font-medium tracking-tight md:text-7xl"
              style={{ '--delay': '120ms' }}
            >
              {card().day}
            </h2>
            <Line>
              {[
                card().episodes > 0
                  ? `${card().episodes} episode${card().episodes === 1 ? '' : 's'}`
                  : null,
                card().minutes > 0 ? hoursLabel(card().minutes) : null,
              ]
                .filter(Boolean)
                .join(', ')}{' '}
              in one day.
            </Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'top' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Most time with</Eyebrow>
            <div
              class="recap-pop relative mt-6 w-40 md:w-48"
              style={{ '--delay': '120ms' }}
            >
              {/* The poster's own colours, blurred behind it: a glow, not a second image. */}
              <Show when={card().entry.title.posterUrl}>
                {(url) => (
                  <img
                    src={url()}
                    alt=""
                    aria-hidden="true"
                    class="pointer-events-none absolute inset-0 -z-10 h-full w-full scale-125 object-cover opacity-60 blur-3xl"
                  />
                )}
              </Show>
              <Poster
                url={card().entry.title.posterUrl}
                kind={titleKind(card().entry.title)}
                class="ring-1 ring-current/20"
              />
            </div>
            <h2
              class="recap-rise mt-6 font-display text-5xl leading-tight font-medium tracking-tight"
              style={{ '--delay': '320ms' }}
            >
              {card().entry.title.title}
            </h2>
            <Line delay={460}>
              {card().entry.episodes > 0
                ? `${card().entry.episodes} episodes, ${card().entry.minutes.toLocaleString('en')} minutes.`
                : `${card().entry.minutes.toLocaleString('en')} minutes.`}
            </Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'topList' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Your top {card().entries.length}</Eyebrow>
            <ol class="mt-6 space-y-4">
              <For each={card().entries}>
                {(entry, i) => <TopRow entry={entry} rank={i() + 1} />}
              </For>
            </ol>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'onRepeat' && props.card}>
        {(card) => (
          <>
            <Eyebrow>On repeat</Eyebrow>
            <Big>{card().artist}</Big>
            <p class="recap-rise mt-2 text-xl" style={{ '--delay': '200ms' }}>
              {card().plays.toLocaleString('en')} play
              {card().plays === 1 ? '' : 's'}
              <Show when={card().minutes > 0}>
                {' '}
                · {hoursLabel(card().minutes)}
              </Show>
            </p>
            <ol class="mt-6 space-y-2">
              <For each={card().tracks}>
                {(track, i) => (
                  <li
                    class="recap-rise flex items-baseline gap-4 text-2xl"
                    style={{ '--delay': `${360 + i() * 160}ms` }}
                  >
                    <span class="w-6 font-display tabular-nums opacity-70">
                      {i() + 1}
                    </span>
                    <span class="min-w-0 truncate font-display">{track}</span>
                  </li>
                )}
              </For>
            </ol>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'genres' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Your genres</Eyebrow>
            <ol class="mt-4 space-y-2">
              <For each={card().genres}>
                {(genre, i) => (
                  <li
                    class="recap-rise flex items-baseline gap-4"
                    style={{ '--delay': `${120 + i() * 160}ms` }}
                  >
                    <span class="w-6 font-display text-2xl tabular-nums opacity-70">
                      {i() + 1}
                    </span>
                    <span class="font-display text-5xl leading-tight font-medium tracking-tight">
                      {genre.name}
                    </span>
                  </li>
                )}
              </For>
            </ol>
            <Line delay={640}>
              {hoursLabel(card().genres[0].minutes)} of{' '}
              {card().genres[0].name.toLowerCase()}, across{' '}
              {card().genres[0].titles}{' '}
              {card().genres[0].titles === 1 ? 'title' : 'titles'}.
            </Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'kinds' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Where the time went</Eyebrow>
            <ul class="mt-6 space-y-5">
              <For each={card().parts}>
                {(part, i) => (
                  <li
                    class="recap-rise"
                    style={{ '--delay': `${120 + i() * 140}ms` }}
                  >
                    <div class="flex items-baseline justify-between gap-4">
                      <span class="font-display text-3xl capitalize">
                        {part.kind === 'film'
                          ? 'Films'
                          : part.kind === 'show'
                            ? 'Shows'
                            : 'Anime'}
                      </span>
                      <span class="text-lg tabular-nums opacity-80">
                        {Math.round(part.share * 100)}%
                      </span>
                    </div>
                    <div class="mt-2 h-2 overflow-hidden rounded-full bg-current/20">
                      <div
                        class="h-full rounded-full bg-current"
                        style={{
                          width: `${Math.max(2, Math.round(part.share * 100))}%`,
                        }}
                      />
                    </div>
                  </li>
                )}
              </For>
            </ul>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'finished' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Finished</Eyebrow>
            <ul class="mt-4 space-y-1">
              <For each={card().parts}>
                {(part, i) => (
                  <li
                    class="recap-rise font-display text-5xl leading-tight font-medium tracking-tight tabular-nums md:text-6xl"
                    style={{ '--delay': `${120 + i() * 140}ms` }}
                  >
                    {countLabel(part.kind, part.count)}
                  </li>
                )}
              </For>
            </ul>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'run' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Longest run</Eyebrow>
            <Big>
              <Count value={card().days} />
            </Big>
            <p class="recap-rise mt-2 text-xl" style={{ '--delay': '200ms' }}>
              days in a row
            </p>
            <Line>{card().range}</Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'ratings' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Your average rating</Eyebrow>
            <Big>{ratingLabel(card().mean)}</Big>
            <Line delay={240}>
              Across {card().count} finished{' '}
              {card().count === 1 ? 'title' : 'titles'}.
            </Line>
            <Show when={card().highest}>
              {(highest) => (
                <div
                  class="recap-rise mt-8 flex items-center gap-4"
                  style={{ '--delay': '480ms' }}
                >
                  <Poster
                    url={highest().posterUrl}
                    kind={titleKind(highest())}
                    class="w-14 shrink-0 ring-1 ring-current/20"
                  />
                  <p>
                    <span class="block text-sm opacity-75">Rated highest</span>
                    <span class="font-display text-2xl">{highest().title}</span>
                    <Show when={card().highestRating}>
                      {(rating) => (
                        <span class="ml-2 tabular-nums opacity-80">
                          {ratingLabel(rating())}
                        </span>
                      )}
                    </Show>
                  </p>
                </div>
              )}
            </Show>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'bookends' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Bookends</Eyebrow>
            <div class="mt-6 space-y-8">
              <For
                each={[
                  { label: 'First', moment: card().first },
                  { label: 'Last', moment: card().last },
                ]}
              >
                {(item, i) => (
                  <div
                    class="recap-rise flex items-center gap-4"
                    style={{ '--delay': `${120 + i() * 220}ms` }}
                  >
                    <Poster
                      url={item.moment.title.posterUrl}
                      kind={titleKind(item.moment.title)}
                      class="w-16 shrink-0 ring-1 ring-current/20"
                    />
                    <p>
                      <span class="block text-sm opacity-75">
                        {item.label} · {dayLabel(item.moment.at.slice(0, 10))}
                      </span>
                      <span class="font-display text-3xl leading-tight">
                        {item.moment.title.title}
                      </span>
                    </p>
                  </div>
                )}
              </For>
            </div>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'persona' && props.card}>
        {(card) => (
          <>
            <Eyebrow>Your {props.stats.year}, in a word</Eyebrow>
            <h2
              class="recap-pop mt-4 font-display text-6xl leading-[1.02] font-medium tracking-tight md:text-7xl"
              style={{ '--delay': '160ms' }}
            >
              {card().title}
            </h2>
            <Line delay={480}>{card().line}</Line>
          </>
        )}
      </Match>
      <Match when={props.card.kind === 'summary'}>
        <Eyebrow>{periodLabel(period())}</Eyebrow>
        <h2
          class="recap-rise mt-4 font-display text-5xl leading-tight font-medium tracking-tight"
          style={{ '--delay': '120ms' }}
        >
          {props.stats.isPartial
            ? `That's your ${props.stats.month ? 'month' : 'year'} in Aaru so far.`
            : `That was your ${props.stats.month ? 'month' : 'year'} in Aaru.`}
        </h2>
        <div class="recap-rise mt-10" style={{ '--delay': '320ms' }}>
          {props.share}
        </div>
      </Match>
    </Switch>
  )
}
