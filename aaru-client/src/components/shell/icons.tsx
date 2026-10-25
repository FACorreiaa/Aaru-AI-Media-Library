import type { JSX } from 'solid-js'

// The shell's line icons: 24px grid, 1.75 stroke, round caps, drawn in currentColor so they
// take the row's ink. Decorative: every one sits beside a visible or tooltip label.
function Icon(props: { children: JSX.Element; class?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      class={props.class}
    >
      {props.children}
    </svg>
  )
}

type IconProps = { class?: string }

export const HomeIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z" />
  </Icon>
)

export const DiscoverIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="m15.5 8.5-2 5-5 2 2-5z" />
  </Icon>
)

export const LibraryIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M5 4.5h3v15H5zM10 4.5h3v15h-3z" />
    <path d="m15.2 5.3 2.9-.8 3.4 14.2-2.9.8z" />
  </Icon>
)

export const CalendarIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <rect x="4" y="5.5" width="16" height="14.5" rx="2" />
    <path d="M4 10h16M8.5 3.5v4M15.5 3.5v4" />
  </Icon>
)

export const ListsIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M9 6.5h11M9 12h11M9 17.5h11" />
    <circle cx="4.75" cy="6.5" r=".9" fill="currentColor" />
    <circle cx="4.75" cy="12" r=".9" fill="currentColor" />
    <circle cx="4.75" cy="17.5" r=".9" fill="currentColor" />
  </Icon>
)

export const FriendsIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <circle cx="10" cy="8.5" r="3.5" />
    <path d="M3.5 19.5c.7-3.4 3.3-5.25 6.5-5.25 1.4 0 2.7.35 3.75 1" />
    <path d="M18 20.25s-3.25-1.9-3.25-4.1a1.6 1.6 0 0 1 3.25-.55 1.6 1.6 0 0 1 3.25.55c0 2.2-3.25 4.1-3.25 4.1Z" />
  </Icon>
)

export const GroupsIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <circle cx="9" cy="9" r="3.25" />
    <path d="M3.5 19.5c.6-3 2.8-4.75 5.5-4.75s4.9 1.75 5.5 4.75" />
    <path d="M15.5 6.2a3 3 0 0 1 0 5.6M17.5 14.9c1.6.6 2.7 2.1 3 4.6" />
  </Icon>
)

export const SportsIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M8 4.5h8v5a4 4 0 0 1-8 0z" />
    <path d="M8 6.5H5.5a2.5 2.5 0 0 0 2.6 3.4M16 6.5h2.5a2.5 2.5 0 0 1-2.6 3.4" />
    <path d="M12 13.5v3M8.5 19.5h7M9.5 19.5c0-1.7 1.1-3 2.5-3s2.5 1.3 2.5 3" />
  </Icon>
)

export const InsightsIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M4.5 19.5h15" />
    <path d="M7 16v-4M12 16V7M17 16v-6.5" />
  </Icon>
)

export const SettingsIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <circle cx="12" cy="12" r="2.75" />
    <path d="M12 3.5v2.2M12 18.3v2.2M20.5 12h-2.2M5.7 12H3.5M18 6l-1.55 1.55M7.55 16.45 6 18M18 18l-1.55-1.55M7.55 7.55 6 6" />
  </Icon>
)

export const SearchIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <circle cx="11" cy="11" r="6.5" />
    <path d="m20 20-4.2-4.2" />
  </Icon>
)

export const MenuIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </Icon>
)

export const BackIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="m14.5 6-6 6 6 6" />
  </Icon>
)

export const ChevronDownIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="m6 9.5 6 6 6-6" />
  </Icon>
)

/** The list lines with a plus: "add to a list". */
export const ListAddIcon = (p: IconProps) => (
  <Icon class={p.class}>
    <path d="M4 6.5h12M4 12h12M4 17.5h7M17 15v6M14 18h6" />
  </Icon>
)
