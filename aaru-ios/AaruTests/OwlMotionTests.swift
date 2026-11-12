import Foundation
import Testing
@testable import Aaru

/// The 3D owl's motion (BRD-011). The same expected values are in
/// `aaru-client/src/lib/owl-motion.test.ts`: the web and the Apple owl must move alike.
struct OwlMotionTests {
    private let motion: OwlMotion
    private let rig: OwlRig

    init() throws {
        motion = try OwlMotion.load()
        rig = try OwlRig.load()
    }

    private func track(_ target: String, _ property: OwlMotion.Property) throws -> OwlMotion.Track {
        try #require(motion.standing.first { ($0.joint ?? $0.material) == target && $0.property == property })
    }

    private func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 1e-6
    }

    @Test func theBodyIsHalfwayUpAQuarterIntoItsBreath() throws {
        let breath = try track("Body", .translateY)
        #expect(near(breath.value(at: 0), 0))
        #expect(near(breath.value(at: 1.125), 0.006))
        #expect(near(breath.value(at: 2.25), 0.012))
    }

    @Test func aTrackLoops() throws {
        let breath = try track("Body", .translateY)
        #expect(near(breath.value(at: 4.5 + 1.125), 0.006))
        #expect(near(breath.value(at: -3.375), 0.006))
    }

    @Test func theHeadDriftsBetweenUnevenKeyframes() throws {
        let yaw = try track("Head", .rotateYDegrees)
        #expect(near(yaw.value(at: 1.65), 1.25))
        #expect(near(yaw.value(at: 5.5), 0.25))
        #expect(near(yaw.value(at: 9.35), -1))
    }

    @Test func theAmberLightPulsesAroundItsRest() throws {
        let glow = try track("amber", .emissiveScale)
        #expect(near(glow.value(at: 0), 0.85))
        #expect(near(glow.value(at: 2), 1.2))
    }

    @Test func aBlinkShutsHoldsAndOpens() {
        let blink = motion.blink
        #expect(blink.scale(sinceStart: -1) == 0.001)
        #expect(near(blink.scale(sinceStart: 0.04), 0.5005))
        #expect(blink.scale(sinceStart: 0.1) == 1)
        #expect(near(blink.scale(sinceStart: 0.2), 0.5005))
        #expect(blink.scale(sinceStart: 0.3) == 0.001)
        #expect(near(blink.seconds, 0.27))
    }

    @Test func theOwlWaitsFourToSevenSecondsBetweenBlinks() {
        #expect(motion.blink.wait(random: 0) == 4)
        #expect(motion.blink.wait(random: 0.5) == 5.5)
        #expect(motion.blink.wait(random: 1) == 7)
    }

    @Test func aLookTurnsTowardThePointAndStopsAtItsLimits() {
        let look = motion.lookAt.toward(x: 2, y: -0.5)
        #expect(look.headYawDegrees == 14)
        #expect(look.headPitchDegrees == 4)
        #expect(near(look.pupilX, 0.02))
        #expect(near(look.pupilY, -0.01))
    }

    @Test func aLookEasesTowardItsTargetAndNeverPassesIt() {
        #expect(near(OwlMotion.approach(0, 1, delta: 0.18, timeConstant: 0.18), 0.632121))
        #expect(near(OwlMotion.approach(0, 1, delta: 100, timeConstant: 0.18), 1))
        #expect(OwlMotion.approach(0.4, 1, delta: 0.016, timeConstant: 0) == 1)
    }

    @Test func thePosterPoseIsTheRigFiles() {
        #expect(rig.posterPose["Owl"] == OwlRig.Pose(rotateYDegrees: -32))
        #expect(rig.posterPose["Head"] == OwlRig.Pose(rotateYDegrees: 24, rotateZDegrees: -6))
    }
}
