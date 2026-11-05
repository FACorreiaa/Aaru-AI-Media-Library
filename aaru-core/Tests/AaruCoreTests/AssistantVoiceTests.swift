import Foundation
import Testing
@testable import AaruCore

struct AssistantVoiceTests {
    /// What one run of the detector came to.
    private struct Outcome {
        let stop: SilenceDetector.Stop?
        let time: TimeInterval
        let heard: Bool
    }

    /// Feeds each (power, seconds) segment at 0.1 s steps; returns the stop and the time it came at.
    private func run(
        _ segments: [(Float, TimeInterval)],
        then tail: (Float, TimeInterval)? = nil
    ) -> Outcome {
        var detector = SilenceDetector()
        var step = 0
        var all = segments
        if let tail {
            all.append(tail)
        }
        for (power, seconds) in all {
            let count = Int((seconds * 10).rounded())
            for _ in 0 ..< count {
                let time = Double(step) / 10
                if let stop = detector.feed(power: power, at: time) {
                    return Outcome(stop: stop, time: time, heard: detector.heardSpeech)
                }
                step += 1
            }
        }
        return Outcome(stop: nil, time: Double(step) / 10, heard: detector.heardSpeech)
    }

    @Test func stopsAfterSpeechAndAboutASecondAndAHalfOfQuiet() {
        let result = run([(-55, 1), (-25, 2)], then: (-55, 10))
        #expect(result.stop == .silence)
        #expect(abs(result.time - 4.5) <= 0.1)
    }

    @Test func keepsGoingThroughAPauseBetweenWords() {
        let result = run([(-55, 1), (-25, 1), (-55, 1), (-25, 1)])
        #expect(result.stop == nil)
    }

    @Test func hearsSomeoneTalkingFromTheFirstInstant() {
        let result = run([(-20, 2)], then: (-55, 10))
        #expect(result.stop == .silence)
        #expect(abs(result.time - 3.5) <= 0.1)
    }

    @Test func nobodySpeakingStopsWithoutAnUpload() {
        let result = run([(-55, 20)])
        #expect(result.stop == .noSpeech)
        #expect(abs(result.time - 8) <= 0.1)
        #expect(result.heard == false)
    }

    @Test func digitalSilenceDoesNotBecomeTheFloor() {
        let result = run([(-160, 0.5), (-55, 20)])
        #expect(result.stop == .noSpeech)
        #expect(result.heard == false)
    }

    @Test func aNoisyRoomStillStops() {
        let result = run([(-30, 1), (-15, 2)], then: (-30, 10))
        #expect(result.stop == .silence)
    }

    @Test func capsAtSixtySeconds() {
        let result = run([(-25, 70)])
        #expect(result.stop == .cap)
        #expect(abs(result.time - 60) <= 0.1)
    }

    @Test(arguments: [
        ("**Severance** is on tonight", "Severance is on tonight"),
        ("*Dune* and _Arrival_", "Dune and Arrival"),
        ("Try `Up Next`", "Try Up Next"),
        ("# Tonight\n- Severance\n- Dune", "Tonight\nSeverance\nDune"),
        ("See [Severance](https://aaruapp.com/s/x) now", "See Severance now"),
        ("More at https://example.com today", "More at today"),
        ("snake_case stays", "snake_case stays"),
        ("2 * 3 stays", "2 * 3 stays"),
    ]) func stripsMarkdownForSpeech(input: String, spoken: String) {
        #expect(SpokenText.plain(input) == spoken)
    }

    @Test(arguments: [
        ("pt", "pt"),
        ("PT", "pt"),
        ("pt-BR", "pt"),
        ("portuguese", "pt"),
        ("English", "en"),
        ("", nil),
        ("klingonese", nil)
    ])
    func readsWhisperLanguage(input: String, code: String?) {
        #expect(SpeechLanguage.code(from: input) == code)
    }
}
