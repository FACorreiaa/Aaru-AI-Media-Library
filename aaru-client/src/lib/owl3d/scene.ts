// The 3D owl's renderer (BRD-011). The only module that imports `three`: `Owl3D.tsx` loads it
// with a dynamic import after first paint, so it is its own chunk, never runs on the Worker and
// never downloads for someone who does not see the owl.
import {
  ACESFilmicToneMapping,
  Color,
  DirectionalLight,
  MathUtils,
  PMREMGenerator,
  PerspectiveCamera,
  Scene,
  WebGLRenderer,
} from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js'
import { COLORS } from '../tokens.gen'
import {
  BLINK,
  LOOK_AT,
  POSTER_POSE,
  STATES,
  approach,
  blinkScale,
  blinkSeconds,
  blinkWait,
  lookToward,
  sampleTrack,
} from '../owl-motion'
import type { Material, Mesh, MeshStandardMaterial, Object3D } from 'three'
import type { Look, OwlState } from '../owl-motion'

export interface OwlScene {
  /** Where to look: each from -1 to 1 across the page, right and up positive. */
  lookAt: (x: number, y: number) => void
  /** Draw or rest: off-screen and in a hidden tab the loop stops. */
  setRunning: (running: boolean) => void
  /** Match the canvas to its box. */
  resize: () => void
  dispose: () => void
}

// The owl is one unit tall and stands on the origin (owl-rig.json "space").
const FIELD_OF_VIEW = 30
/** What the camera frames: the owl alone, or the owl on its stack of books
 * (`owl-on-books.glb`, a quarter of a unit taller and the same joints). */
export type OwlFraming = 'owl' | 'books'
const FRAMES: Record<
  OwlFraming,
  { cameraY: number; cameraZ: number; aimY: number }
> = {
  owl: { cameraY: 0.54, cameraZ: 2.2, aimY: 0.5 },
  books: { cameraY: 0.68, cameraZ: 2.75, aimY: 0.64 },
}
const MAX_PIXEL_RATIO = 2
/** A frame that took longer (a tab coming back) moves the owl this far and no further. */
const MAX_STEP_SECONDS = 0.1

interface Joint {
  node: Object3D
  x: number
  y: number
  z: number
  /** The rest scale, one number: every joint a track scales is the same on each axis. */
  scale: number
  /** Degrees, the rest plus the poster pose. */
  pitch: number
  yaw: number
  roll: number
}

function isMesh(node: Object3D): node is Mesh {
  return (node as Mesh).isMesh
}

function isStandard(material: Material): material is MeshStandardMaterial {
  return (material as MeshStandardMaterial).isMeshStandardMaterial
}

/** Loads the model into `canvas` and starts the owl at rest. Rejects when WebGL is missing or
 * the model cannot be read; the caller keeps the still. `onFirstFrame` runs once the first
 * frame is on the canvas. */
export async function mountOwl(
  canvas: HTMLCanvasElement,
  options: {
    modelUrl: string
    framing?: OwlFraming
    /** What the owl is doing. Left out: standing at rest. */
    state?: OwlState
    onFirstFrame: () => void
  },
): Promise<OwlScene> {
  const renderer = new WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    powerPreference: 'low-power',
  })
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, MAX_PIXEL_RATIO))
  renderer.toneMapping = ACESFilmicToneMapping

  const scene = new Scene()
  // Something for the ceramic and the metal to reflect, without an HDR file to download.
  const pmrem = new PMREMGenerator(renderer)
  const room = new RoomEnvironment()
  const environment = pmrem.fromScene(room, 0.04)
  scene.environment = environment.texture
  // The room is bright enough to wash the white ceramic out; turned down, the two lights read.
  scene.environmentIntensity = 0.55
  room.dispose()
  pmrem.dispose()

  // The poster's light: amber from the front, the accent blue on the edge. Its sky is night in
  // both appearances, so the lights are the dark values.
  const key = new DirectionalLight(new Color(COLORS.gold.dark), 2.4)
  key.position.set(1.4, 1.8, 2.2)
  const rim = new DirectionalLight(new Color(COLORS.accent.dark), 2.4)
  rim.position.set(-1.6, 1.2, -2)
  scene.add(key, rim)

  const camera = new PerspectiveCamera(FIELD_OF_VIEW, 1, 0.1, 20)
  const frame = FRAMES[options.framing ?? 'owl']
  camera.position.set(0, frame.cameraY, frame.cameraZ)
  camera.lookAt(0, frame.aimY, 0)

  let model: Object3D
  try {
    model = (await new GLTFLoader().loadAsync(options.modelUrl)).scene
  } catch (error) {
    environment.dispose()
    renderer.dispose()
    throw error
  }
  scene.add(model)

  const joints = new Map<string, Joint>()
  const joint = (name: string): Joint | undefined => {
    const known = joints.get(name)
    if (known) return known
    const node = model.getObjectByName(name)
    if (!node) return undefined
    const stance = POSTER_POSE[name] ?? {}
    // Yaw, then pitch, then roll: the order OwlMotion.swift composes them in.
    node.rotation.order = 'YXZ'
    const made: Joint = {
      node,
      x: node.position.x,
      y: node.position.y,
      z: node.position.z,
      scale: node.scale.x,
      pitch: MathUtils.radToDeg(node.rotation.x),
      yaw: MathUtils.radToDeg(node.rotation.y) + (stance.rotateYDegrees ?? 0),
      roll: MathUtils.radToDeg(node.rotation.z) + (stance.rotateZDegrees ?? 0),
    }
    joints.set(name, made)
    return made
  }
  for (const name of Object.keys(POSTER_POSE)) joint(name)

  // The lights a track pulses, by material name, with the strength each rests at.
  const lit = new Map<
    string,
    Array<{ material: MeshStandardMaterial; rest: number }>
  >()
  const geometries = new Set<{ dispose: () => void }>()
  const materials = new Set<Material>()
  model.traverse((node) => {
    if (!isMesh(node)) return
    geometries.add(node.geometry)
    for (const material of [node.material].flat()) {
      if (materials.has(material)) continue
      materials.add(material)
      if (!isStandard(material)) continue
      const list = lit.get(material.name) ?? []
      list.push({ material, rest: material.emissiveIntensity })
      lit.set(material.name, list)
    }
  })

  const tracks = STATES[options.state ?? 'standing']
  const look: Look = lookToward(LOOK_AT, 0, 0)
  let target: Look = look
  let seconds = 0
  let blinkAt = blinkWait(BLINK, Math.random())

  function pose(delta: number) {
    seconds += delta
    look.headYawDegrees = approach(
      look.headYawDegrees,
      target.headYawDegrees,
      delta,
      LOOK_AT.timeConstantSeconds,
    )
    look.headPitchDegrees = approach(
      look.headPitchDegrees,
      target.headPitchDegrees,
      delta,
      LOOK_AT.timeConstantSeconds,
    )
    look.pupilX = approach(
      look.pupilX,
      target.pupilX,
      delta,
      LOOK_AT.timeConstantSeconds,
    )
    look.pupilY = approach(
      look.pupilY,
      target.pupilY,
      delta,
      LOOK_AT.timeConstantSeconds,
    )

    // Each joint starts the frame at its posed rest; the tracks and the look add to it.
    const moved = new Map<
      Joint,
      { y: number; pitch: number; yaw: number; roll: number; scale: number }
    >()
    const offsets = (j: Joint) => {
      let entry = moved.get(j)
      if (!entry) {
        entry = { y: 0, pitch: 0, yaw: 0, roll: 0, scale: 1 }
        moved.set(j, entry)
      }
      return entry
    }
    for (const track of tracks) {
      const value = sampleTrack(track, seconds)
      if (track.material) {
        for (const light of lit.get(track.material) ?? []) {
          light.material.emissiveIntensity = light.rest * value
        }
        continue
      }
      const j = track.joint ? joint(track.joint) : undefined
      if (!j) continue
      const entry = offsets(j)
      if (track.property === 'translateY') entry.y += value
      else if (track.property === 'rotateXDegrees') entry.pitch += value
      else if (track.property === 'rotateYDegrees') entry.yaw += value
      else if (track.property === 'rotateZDegrees') entry.roll += value
      else if (track.property === 'scale') entry.scale *= value
    }
    const head = joint('Head')
    if (head) {
      const entry = offsets(head)
      entry.yaw += look.headYawDegrees
      entry.pitch += look.headPitchDegrees
    }
    for (const [j, entry] of moved) {
      j.node.position.y = j.y + entry.y
      j.node.rotation.set(
        MathUtils.degToRad(j.pitch + entry.pitch),
        MathUtils.degToRad(j.yaw + entry.yaw),
        MathUtils.degToRad(j.roll + entry.roll),
      )
      // The lids are never among these: the blink below is the one thing that scales them.
      j.node.scale.setScalar(j.scale * entry.scale)
    }
    for (const name of ['PupilL', 'PupilR']) {
      const pupil = joint(name)
      if (!pupil) continue
      pupil.node.position.x = pupil.x + look.pupilX
      pupil.node.position.y = pupil.y + look.pupilY
    }

    if (seconds >= blinkAt + blinkSeconds(BLINK)) {
      blinkAt = seconds + blinkWait(BLINK, Math.random())
    }
    const lid = blinkScale(BLINK, seconds - blinkAt)
    for (const name of BLINK.joints) {
      const node = joint(name)?.node
      if (node) node.scale.set(node.scale.x, lid, lid)
    }
  }

  function resize() {
    const width = canvas.clientWidth
    const height = canvas.clientHeight
    if (width === 0 || height === 0) return
    renderer.setSize(width, height, false)
    camera.aspect = width / height
    camera.updateProjectionMatrix()
  }

  let request = 0
  let last = 0
  let running = false
  let drawn = false
  let disposed = false

  function draw(now: number) {
    request = 0
    if (!running || disposed) return
    const delta = last ? Math.min((now - last) / 1000, MAX_STEP_SECONDS) : 0
    last = now
    pose(delta)
    renderer.render(scene, camera)
    if (!drawn) {
      drawn = true
      options.onFirstFrame()
    }
    request = requestAnimationFrame(draw)
  }

  resize()

  return {
    lookAt(x, y) {
      target = lookToward(LOOK_AT, x, y)
    },
    setRunning(next) {
      if (disposed || next === running) return
      running = next
      // The time away is not played back: the owl carries on from where it stopped.
      last = 0
      if (running && !request) request = requestAnimationFrame(draw)
    },
    resize,
    dispose() {
      disposed = true
      running = false
      if (request) cancelAnimationFrame(request)
      for (const geometry of geometries) geometry.dispose()
      for (const material of materials) material.dispose()
      environment.dispose()
      renderer.dispose()
    },
  }
}
