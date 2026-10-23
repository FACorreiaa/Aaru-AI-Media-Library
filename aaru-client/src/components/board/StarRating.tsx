import { For, Show, createSignal } from 'solid-js'
import {
  Button,
  RadioGroup,
  RadioGroupItem,
  RadioGroupItemInput,
  RadioGroupItemLabel,
  RadioGroupLabel,
} from '~/components/ui'
import { ratingWords } from '../../lib/board/model'

/**
 * Five stars with halves, stored out of ten (BOARD-002). The title page's control (WEB-012) as
 * ten radios: each star's left half is the odd value, its right half the even one, so the arrow
 * keys move half a star and a screen reader hears "4½ of 5 stars". Hovering previews.
 */
export function StarRating(props: {
  value: number | undefined
  onChange: (rating: number | undefined) => void
}) {
  const [hover, setHover] = createSignal<number | null>(null)
  const shown = () => hover() ?? props.value ?? 0

  return (
    <RadioGroup
      class="flex items-center gap-3"
      value={props.value === undefined ? '' : String(props.value)}
      onChange={(value: string) => props.onChange(Number(value))}
    >
      <RadioGroupLabel class="sr-only">
        Rating
        <Show when={props.value !== undefined}>
          , {ratingWords(props.value!)}
        </Show>
      </RadioGroupLabel>
      <div class="-my-1.5 flex" onPointerLeave={() => setHover(null)}>
        <For each={[1, 2, 3, 4, 5]}>
          {(star) => {
            const fill = () =>
              shown() >= star * 2
                ? 'full'
                : shown() === star * 2 - 1
                  ? 'half'
                  : 'none'
            return (
              <span class="relative grid min-h-11 w-8 place-items-center text-2xl leading-none text-gold">
                <span aria-hidden="true" class="relative">
                  ☆
                  <span
                    class="absolute inset-0"
                    style={{
                      'clip-path':
                        fill() === 'full'
                          ? 'inset(0)'
                          : fill() === 'half'
                            ? 'inset(0 50% 0 0)'
                            : 'inset(0 100% 0 0)',
                    }}
                  >
                    ★
                  </span>
                </span>
                <For each={[star * 2 - 1, star * 2]}>
                  {(value) => (
                    <RadioGroupItem
                      value={String(value)}
                      class={`absolute inset-y-0 w-1/2 gap-0 ${value % 2 === 1 ? 'left-0' : 'right-0'}`}
                    >
                      <RadioGroupItemInput />
                      <RadioGroupItemLabel
                        onPointerEnter={() => setHover(value)}
                        class={`block size-full cursor-pointer peer-focus-visible/radio-group:outline-2 peer-focus-visible/radio-group:outline-ring ${value % 2 === 1 ? 'rounded-l-full' : 'rounded-r-full'}`}
                      >
                        <span class="sr-only">{ratingWords(value)}</span>
                      </RadioGroupItemLabel>
                    </RadioGroupItem>
                  )}
                </For>
              </span>
            )
          }}
        </For>
      </div>
      <Show when={props.value !== undefined}>
        <Button
          variant="ghost"
          size="xs"
          onClick={() => props.onChange(undefined)}
        >
          Clear
        </Button>
      </Show>
    </RadioGroup>
  )
}
