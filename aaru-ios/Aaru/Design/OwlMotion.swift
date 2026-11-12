import Foundation

/// How the 3D owl moves (BRD-011). The numbers are `design/owl-motion.json`, copied into the
/// bundle; this type only turns a time into values. It knows no renderer: `Owl3DView` applies
/// what it returns, and `aaru-client/src/lib/owl-motion.ts` is the same arithmetic for the web.
/// A change here is a change there, and both tests hold the same expected values.
///
/// Left out of the Release build with `Owl3DView` (`Release.xcconfig`).
struct OwlMotion: Decodable, Sendable {
    enum Easing: String, Decodable, Sendable {
        case sine, linear

        /// 0 to 1 along one span between two keyframes.
        func callAsFunction(_ progress: Double) -> Double {
            switch self {
            case .sine: 0.5 - 0.5 * cos(.pi * progress)
            case .linear: progress
            }
        }
    }

    struct Keyframe: Decodable, Sendable {
        /// Fraction of the track's period, 0 to 1.
        let time: Double
        let value: Double

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: KeyframeKey.self)
            time = try values.decode(Double.self, forKey: .time)
            value = try values.decode(Double.self, forKey: .value)
        }
    }

    enum Property: String, Decodable, Sendable {
        case translateY, rotateXDegrees, rotateYDegrees, rotateZDegrees, emissiveScale
    }

    struct Track: Decodable, Sendable {
        /// The joint the value moves, or the material it lights. One of the two.
        let joint: String?
        let material: String?
        let property: Property
        let periodSeconds: Double
        let easing: Easing
        let keyframes: [Keyframe]

        /// The looping track's value at `seconds`.
        func value(at seconds: Double) -> Double {
            guard let last = keyframes.last else { return 0 }
            let wrapped = seconds.truncatingRemainder(dividingBy: periodSeconds)
            let phase = (wrapped < 0 ? wrapped + periodSeconds : wrapped) / periodSeconds
            for (start, end) in zip(keyframes, keyframes.dropFirst()) where phase <= end.time {
                let span = end.time - start.time
                let progress = span > 0 ? (phase - start.time) / span : 1
                return start.value + (end.value - start.value) * easing(progress)
            }
            return last.value
        }
    }

    struct State: Decodable, Sendable {
        let tracks: [Track]
    }

    struct Blink: Decodable, Sendable {
        let joints: [String]
        let open: Double
        let shut: Double
        let intervalSeconds: [Double]
        let closeSeconds: Double
        let holdSeconds: Double
        let openSeconds: Double

        /// How long a whole blink takes.
        var seconds: Double {
            closeSeconds + holdSeconds + openSeconds
        }

        /// The lids' scale `sinceStart` seconds into a blink: shut, held, open again.
        func scale(sinceStart: Double) -> Double {
            let range = shut - open
            if sinceStart < 0 {
                return open
            }
            if sinceStart < closeSeconds {
                return open + range * Easing.sine(sinceStart / closeSeconds)
            }
            let held = sinceStart - closeSeconds
            if held < holdSeconds {
                return shut
            }
            let opening = held - holdSeconds
            if opening < openSeconds {
                return shut - range * Easing.sine(opening / openSeconds)
            }
            return open
        }

        /// The wait before the next blink, from a random number in 0…1.
        func wait(random: Double) -> Double {
            let least = intervalSeconds.first ?? 0
            let most = intervalSeconds.last ?? least
            return least + (most - least) * random
        }
    }

    /// Where the owl is looking: the head's turn in degrees, the pupils' shift in model units.
    struct Look: Equatable, Sendable {
        var headYawDegrees = 0.0
        var headPitchDegrees = 0.0
        var pupilX = 0.0
        var pupilY = 0.0
    }

    struct LookAt: Decodable, Sendable {
        let headYawDegrees: Double
        let headPitchDegrees: Double
        let pupilOffset: Double
        let timeConstantSeconds: Double

        /// Where the owl looks for a point at (`x`, `y`): each from -1 to 1, right and up
        /// positive, and held inside that range. Turning the head toward +X is a positive yaw;
        /// looking up is a negative pitch (a turn about X tips the face down).
        func toward(x: Double, y: Double) -> Look {
            let clampedX = min(1, max(-1, x))
            let clampedY = min(1, max(-1, y))
            return Look(
                headYawDegrees: clampedX * headYawDegrees,
                headPitchDegrees: -clampedY * headPitchDegrees,
                pupilX: clampedX * pupilOffset,
                pupilY: clampedY * pupilOffset
            )
        }
    }

    let states: [String: State]
    let blink: Blink
    let lookAt: LookAt

    /// The owl at rest: the one state the experiment plays.
    var standing: [Track] {
        states["standing"]?.tracks ?? []
    }

    /// One frame's step from `current` toward `target`: quick at first, never past it.
    static func approach(
        _ current: Double, _ target: Double, delta: Double, timeConstant: Double
    ) -> Double {
        guard timeConstant > 0 else { return target }
        return current + (target - current) * (1 - exp(-delta / timeConstant))
    }

    static func load(from bundle: Bundle = .main) throws -> OwlMotion {
        try decode("owl-motion", from: bundle)
    }

    fileprivate static func decode<Value: Decodable>(_ name: String, from bundle: Bundle) throws -> Value {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }
}

/// The part of `design/owl-rig.json` the app reads: the poster's stance, as degrees added to a
/// joint's rest, by joint name.
struct OwlRig: Decodable, Sendable {
    struct Pose: Decodable, Equatable, Sendable {
        var rotateYDegrees: Double?
        var rotateZDegrees: Double?
    }

    let posterPose: [String: Pose]

    static func load(from bundle: Bundle = .main) throws -> OwlRig {
        try OwlMotion.decode("owl-rig", from: bundle)
    }
}

/// A keyframe's short names in the file.
private enum KeyframeKey: String, CodingKey {
    case time = "t"
    case value = "v"
}
