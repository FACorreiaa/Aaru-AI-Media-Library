import { createSignal, onCleanup, onMount } from 'solid-js'
import { prefersReducedMotion } from '~/lib/reduced-motion'
import { OwlStill } from './Brand'
import type { OwlScene } from '~/lib/owl3d/scene'

/** The viewer asked their browser to spend less data. */
function savesData(): boolean {
  const connection = (navigator as { connection?: { saveData?: boolean } })
    .connection
  return connection?.saveData === true
}

/** The owl in 3D, off the night disc (BRD-011: an experiment on the beta channel). It stands at
 * rest, breathes, blinks and looks toward the pointer. The still is the first paint and carries
 * the words for a screen reader; the canvas replaces it only once a frame is drawn, and never
 * under reduced motion, Save-Data, without WebGL, or when the model fails to load. One per
 * page: each is a WebGL context. */
export function Owl3D(props: {
  /** Where `owl.glb` is (`OWL_3D_MODEL_URL`). */
  modelUrl: string
  class?: string
  decorative?: boolean
}) {
  let host!: HTMLDivElement
  let canvas!: HTMLCanvasElement
  const [live, setLive] = createSignal(false)

  let scene: OwlScene | undefined
  let gone = false
  let onScreen = false
  let watcher: IntersectionObserver | undefined
  let sizer: ResizeObserver | undefined

  const run = () => scene?.setRunning(onScreen && !document.hidden)

  const follow = (event: PointerEvent) => {
    if (!scene) return
    const box = host.getBoundingClientRect()
    // From the owl's middle to the edge of the page is the whole of its turn.
    const x =
      (event.clientX - (box.left + box.width / 2)) / (window.innerWidth / 2)
    const y =
      (box.top + box.height / 2 - event.clientY) / (window.innerHeight / 2)
    scene.lookAt(x, y)
  }

  onMount(() => {
    // Nothing mounts on the Worker; saying so lets its build leave `three` out altogether.
    if (import.meta.env.SSR) return
    if (prefersReducedMotion() || savesData()) return
    void (async () => {
      try {
        const { mountOwl } = await import('~/lib/owl3d/scene')
        const mounted = await mountOwl(canvas, {
          modelUrl: props.modelUrl,
          onFirstFrame: () => setLive(true),
        })
        if (gone) {
          mounted.dispose()
          return
        }
        scene = mounted
        watcher = new IntersectionObserver(([entry]) => {
          onScreen = entry.isIntersecting
          run()
        })
        watcher.observe(host)
        sizer = new ResizeObserver(() => scene?.resize())
        sizer.observe(host)
        document.addEventListener('visibilitychange', run)
        window.addEventListener('pointermove', follow, { passive: true })
      } catch {
        // No WebGL, or the model did not arrive: the still stays.
      }
    })()
  })

  onCleanup(() => {
    gone = true
    watcher?.disconnect()
    sizer?.disconnect()
    if (typeof document !== 'undefined') {
      document.removeEventListener('visibilitychange', run)
      window.removeEventListener('pointermove', follow)
    }
    scene?.dispose()
  })

  return (
    <div
      ref={host}
      aria-hidden={props.decorative || undefined}
      class={`owl-glow relative aspect-[720/877] ${props.class ?? ''}`}
    >
      <OwlStill
        decorative={props.decorative}
        class={`absolute inset-0 h-full w-full transition-opacity duration-(--motion-slow) ${live() ? 'opacity-0' : ''}`}
      />
      <canvas
        ref={canvas}
        aria-hidden="true"
        class={`absolute inset-0 h-full w-full transition-opacity duration-(--motion-slow) ${live() ? '' : 'opacity-0'}`}
      />
    </div>
  )
}
