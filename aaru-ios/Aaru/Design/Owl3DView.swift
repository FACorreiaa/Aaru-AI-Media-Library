import RealityKit
import SwiftUI

/// The owl in 3D, off the night disc (BRD-011: an experiment on the beta channel; DESIGN.md
/// "Brand"). It stands at rest in the poster's pose, breathes, blinks and looks toward the
/// pointer or a finger; with `pose: .curious` (the first run's opening screen) it tilts its
/// head, flicks an ear and widens its eyes. The still shows until the model's first frame, and stays under Reduce
/// Motion, in Low Power Mode, and when the model cannot be read.
///
/// In every build, the App Store's included (owner, 2026-11-13).
struct Owl3DView: View {
    /// What the owl is, for VoiceOver.
    let label: Text
    /// Where the pointer or a finger is, in global coordinates. Nil: the owl looks ahead.
    var pointer: CGPoint?
    /// Standing or curious: the still is this pose, and so is the motion. The other poses have
    /// no motion yet and play as standing.
    var pose = OwlPose.standing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = OwlStage()
    @State private var frame = CGRect.zero

    private var draws: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            Image(pose.image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .opacity(draws && stage.isLive ? 0 : 1)
            if draws {
                OwlScene(stage: stage, state: pose == .curious ? .curious : .standing)
                    .opacity(stage.isLive ? 1 : 0)
            }
        }
        .aspectRatio(OwlStage.aspect, contentMode: .fit)
        .background { glow }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onChange(of: pointer) { _, point in stage.look(at: point, from: frame) }
        .animation(AaruMotion.ease(AaruMotion.slow), value: stage.isLive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    /// The amber light the disc's glow gives the still owl, here without a disc to sit behind.
    private var glow: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [Color(.gold).opacity(0.35), Color(.gold).opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: min(proxy.size.width, proxy.size.height) * 0.5
            )
        }
        .opacity(0.4)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Reports where the pointer or a finger is over this view, in global coordinates, for an
    /// `Owl3DView` inside it to look at. Scrolling and taps go on as before.
    func owlFollows(_ pointer: Binding<CGPoint?>) -> some View {
        onContinuousHover(coordinateSpace: .global) { phase in
            switch phase {
            case let .active(point): pointer.wrappedValue = point
            case .ended: pointer.wrappedValue = nil
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { pointer.wrappedValue = $0.location }
                .onEnded { _ in pointer.wrappedValue = nil }
        )
    }
}

/// The RealityKit view itself: a virtual camera, no AR. Its background is clear, so the owl
/// stands on whatever SwiftUI draws behind it.
private struct OwlScene: View {
    let stage: OwlStage
    let state: OwlMotion.StateName

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            guard let owl = await stage.load(state) else { return }
            content.add(owl)
            for entity in stage.rig {
                content.add(entity)
            }
            stage.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                stage.step(event.deltaTime)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The loaded owl and its motion: joints found by name (`design/owl-rig.json`), moved each frame
/// by `OwlMotion`. The arithmetic is the web's (`aaru-client/src/lib/owl3d/scene.ts`).
@MainActor @Observable
final class OwlStage {
    /// The still's shape, so the swap to the model does not move the layout.
    static let aspect: CGFloat = 720 / 877
    /// A frame that took longer (the app coming back) moves the owl this far and no further.
    private static let longestStep = 0.1

    /// The first frame is drawn: the still can go.
    private(set) var isLive = false
    @ObservationIgnored var updates: EventSubscription?
    /// The camera and the lights, made with the owl.
    @ObservationIgnored private(set) var rig: [Entity] = []

    private struct Joint {
        let entity: Entity
        let position: SIMD3<Float>
        let orientation: simd_quatf
        let scale: SIMD3<Float>
        /// The poster pose, in degrees.
        var yaw = 0.0
        var roll = 0.0
    }

    private struct Offsets {
        var lift = 0.0
        var pitch = 0.0
        var yaw = 0.0
        var roll = 0.0
        var scale = 1.0

        mutating func add(_ value: Double, to property: OwlMotion.Property) {
            switch property {
            case .translateY: lift += value
            case .rotateXDegrees: pitch += value
            case .rotateYDegrees: yaw += value
            case .rotateZDegrees: roll += value
            case .scale: scale *= value
            case .emissiveScale: break
            }
        }
    }

    private struct Light {
        let entity: Entity
        let material: PhysicallyBasedMaterial
        var scale = 1.0
    }

    @ObservationIgnored private var motion: OwlMotion?
    @ObservationIgnored private var tracks: [OwlMotion.Track] = []
    @ObservationIgnored private var joints: [String: Joint] = [:]
    @ObservationIgnored private var lights: [String: [Light]] = [:]
    @ObservationIgnored private var look = OwlMotion.Look()
    @ObservationIgnored private var target = OwlMotion.Look()
    @ObservationIgnored private var seconds = 0.0
    @ObservationIgnored private var blinkAt = 0.0

    /// Reads the model and the motion from the bundle and poses the owl. Nil when either is
    /// missing: the still stays.
    func load(_ state: OwlMotion.StateName = .standing) async -> Entity? {
        guard let motion = try? OwlMotion.load(), let pose = try? OwlRig.load().posterPose,
              let model = try? await Entity(named: "Owl", in: .main)
        else { return nil }
        // The file wraps the rig in an entity that is also called Owl: start below it.
        let root = model.findEntity(named: "Root") ?? model
        let tracks = motion.tracks(for: state)
        let names = Set(tracks.compactMap(\.joint) + motion.blink.joints + pose.keys)
            .union(["Head", "PupilL", "PupilR"])
        for name in names {
            guard let entity = root.findEntity(named: name) else { continue }
            joints[name] = Joint(
                entity: entity, position: entity.position, orientation: entity.orientation,
                scale: entity.scale,
                yaw: pose[name]?.rotateYDegrees ?? 0, roll: pose[name]?.rotateZDegrees ?? 0
            )
        }
        for material in Set(tracks.compactMap(\.material)) {
            lights[material] = lit(by: material, under: root)
        }
        self.motion = motion
        self.tracks = tracks
        blinkAt = motion.blink.wait(random: .random(in: 0 ... 1))
        rig = [
            camera(),
            light(.gold, intensity: 1500, from: [1.4, 1.8, 2.2]),
            light(.accent, intensity: 2500, from: [-1.6, 1.2, -2]),
        ]
        step(0)
        return model
    }

    /// Looks toward `point`, given where the owl is on screen. A point one and a half owls away
    /// is the whole of its turn.
    func look(at point: CGPoint?, from frame: CGRect) {
        guard let motion, let point, !frame.isEmpty else {
            target = OwlMotion.Look()
            return
        }
        let reach = max(frame.width, frame.height) * 1.5
        target = motion.lookAt.toward(
            x: (point.x - frame.midX) / reach, y: (frame.midY - point.y) / reach
        )
    }

    /// One frame: the tracks, the look and the blink, each added to the posed rest.
    func step(_ elapsed: TimeInterval) {
        guard let motion else { return }
        let delta = min(elapsed, Self.longestStep)
        seconds += delta
        easeLook(by: delta, over: motion.lookAt.timeConstantSeconds)

        let blink = motion.blink
        if seconds >= blinkAt + blink.seconds {
            blinkAt = seconds + blink.wait(random: .random(in: 0 ... 1))
        }
        let lid = Float(blink.scale(sinceStart: seconds - blinkAt))

        for (name, offsets) in offsets(from: tracks) {
            guard let joint = joints[name] else { continue }
            var position = joint.position
            position.y += Float(offsets.lift)
            if name.hasPrefix("Pupil") {
                position.x += Float(look.pupilX)
                position.y += Float(look.pupilY)
            }
            joint.entity.position = position
            // Yaw, then pitch, then roll: the order the web composes them in.
            joint.entity.orientation = joint.orientation
                * turn(joint.yaw + offsets.yaw, about: [0, 1, 0])
                * turn(offsets.pitch, about: [1, 0, 0])
                * turn(joint.roll + offsets.roll, about: [0, 0, 1])
            joint.entity.scale = blink.joints.contains(name)
                ? [joint.scale.x, lid, lid]
                : joint.scale * Float(offsets.scale)
        }
        if delta > 0 {
            isLive = true
        }
    }

    /// Moves the look a frame closer to where the pointer is.
    private func easeLook(by delta: Double, over ease: Double) {
        look.headYawDegrees = OwlMotion.approach(
            look.headYawDegrees, target.headYawDegrees, delta: delta, timeConstant: ease
        )
        look.headPitchDegrees = OwlMotion.approach(
            look.headPitchDegrees, target.headPitchDegrees, delta: delta, timeConstant: ease
        )
        look.pupilX = OwlMotion.approach(look.pupilX, target.pupilX, delta: delta, timeConstant: ease)
        look.pupilY = OwlMotion.approach(look.pupilY, target.pupilY, delta: delta, timeConstant: ease)
    }

    /// What each joint adds to its rest this frame: the tracks, and the look on the head. A
    /// track that lights a material is applied here, since no joint carries it.
    private func offsets(from tracks: [OwlMotion.Track]) -> [String: Offsets] {
        var moved = joints.mapValues { _ in Offsets() }
        for track in tracks {
            let value = track.value(at: seconds)
            if let material = track.material {
                glow(material, scale: value)
            } else if let name = track.joint {
                moved[name]?.add(value, to: track.property)
            }
        }
        moved["Head"]?.yaw += look.headYawDegrees
        moved["Head"]?.pitch += look.headPitchDegrees
        return moved
    }

    private func turn(_ degrees: Double, about axis: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: Float(degrees * .pi / 180), axis: axis)
    }

    /// The parts drawn in `material`: the model names each mesh "<joint>_<material>".
    private func lit(by material: String, under root: Entity) -> [Light] {
        var found: [Light] = []
        var queue = [root]
        while let entity = queue.popLast() {
            queue.append(contentsOf: entity.children)
            guard entity.name.hasSuffix("_" + material),
                  let rest = entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
            else { continue }
            found.append(Light(entity: entity, material: rest))
        }
        return found
    }

    /// Brightens or dims a material's own light around its rest. A change too small to see is
    /// not sent to the renderer.
    private func glow(_ material: String, scale: Double) {
        guard var parts = lights[material] else { return }
        for index in parts.indices where abs(parts[index].scale - scale) > 0.01 {
            parts[index].scale = scale
            var lit = parts[index].material
            lit.emissiveIntensity *= Float(scale)
            parts[index].entity.components[ModelComponent.self]?.materials = [lit]
        }
        lights[material] = parts
    }

    /// The web's camera: the owl is one unit tall and stands on the origin.
    private func camera() -> Entity {
        let entity = Entity()
        var lens = PerspectiveCameraComponent()
        lens.fieldOfViewInDegrees = 30
        entity.components.set(lens)
        entity.look(at: [0, 0.5, 0], from: [0, 0.54, 2.2], relativeTo: nil)
        return entity
    }

    /// The poster's light: amber from the front, the accent blue on the edge.
    private func light(_ colour: ColorResource, intensity: Float, from position: SIMD3<Float>) -> Entity {
        let entity = Entity()
        #if os(macOS)
            let tint = NSColor(resource: colour)
        #else
            let tint = UIColor(resource: colour)
        #endif
        entity.components.set(DirectionalLightComponent(color: tint, intensity: intensity))
        entity.look(at: [0, 0.5, 0], from: position, relativeTo: nil)
        return entity
    }
}
