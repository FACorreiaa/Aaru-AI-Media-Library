import { For, Show } from 'solid-js'
import {
  badgeName,
  byFamily,
  progressFraction,
  progressText,
  tierName,
} from '../../lib/achievements/model'
import type { Badge, BadgeAward } from '../../lib/achievements/model'
import { BadgeMedallion } from './BadgeMedallion'

// `BadgeShelf` (VIEWS.md): the catalog by family on the Achievements page, earned first, the
// rest with "62 / 100" under them; and a friend's earned badges on their profile.

export function BadgeShelf(props: { badges: Badge[] }) {
  return (
    <div class="flex flex-col gap-10">
      <For each={byFamily(props.badges)}>
        {(group) => (
          <section aria-labelledby={`family-${group.family}`}>
            <h2 id={`family-${group.family}`} class="eyebrow">
              {group.label}
            </h2>
            <ul class="mt-4 grid grid-cols-2 gap-x-4 gap-y-6 sm:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-6">
              <For each={group.badges}>
                {(badge) => <BadgeCell badge={badge} />}
              </For>
            </ul>
          </section>
        )}
      </For>
    </div>
  )
}

function BadgeCell(props: { badge: Badge }) {
  const secret = () => props.badge.hidden && !props.badge.earned
  const tier = () => tierName(props.badge.tier, props.badge.maxTier)
  const progress = () => progressText(props.badge)
  return (
    <li class="flex flex-col items-center text-center">
      <BadgeMedallion
        family={props.badge.family}
        tier={props.badge.tier}
        secret={secret()}
      />
      <p class="mt-3 min-h-4 text-[0.6875rem] font-semibold tracking-[0.12em] text-muted uppercase">
        {tier() ?? (props.badge.earned ? 'Earned' : '')}
      </p>
      <h3
        class="font-display text-lg leading-tight font-medium"
        classList={{ 'text-muted': !props.badge.earned }}
      >
        {badgeName(props.badge)}
      </h3>
      <Show when={props.badge.description}>
        {(text) => <p class="mt-1 text-xs leading-snug text-muted">{text()}</p>}
      </Show>
      <Show when={progress()}>
        {(text) => (
          <div class="mt-2 w-full max-w-28">
            <div class="h-1 overflow-hidden rounded-full bg-line">
              <div
                class="h-full rounded-full bg-accent"
                style={{ width: `${progressFraction(props.badge) * 100}%` }}
              />
            </div>
            <p class="mt-1 text-xs text-muted tabular-nums">{text()}</p>
          </div>
        )}
      </Show>
    </li>
  )
}

/** Earned badges in one row (a friend's profile), newest first. */
export function AwardShelf(props: { awards: BadgeAward[] }) {
  return (
    <ul class="flex gap-4 overflow-x-auto pb-2 md:flex-wrap md:overflow-visible">
      <For each={props.awards}>
        {(award) => (
          <li class="flex w-20 shrink-0 flex-col items-center text-center">
            <BadgeMedallion family={award.family} tier={award.tier} size="sm" />
            <p class="mt-2 line-clamp-2 text-xs leading-snug font-medium">
              {award.name}
            </p>
            <Show when={tierName(award.tier, award.maxTier)}>
              {(name) => <p class="text-[0.6875rem] text-muted">{name()}</p>}
            </Show>
          </li>
        )}
      </For>
    </ul>
  )
}
