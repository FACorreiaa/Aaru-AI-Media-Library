import Foundation

/// Decides when a spoken question has ended, from the recorder's meter readings.
/// Pure and clock-free: the caller passes the time of each reading.
public struct SilenceDetector: Sendable {
    public enum Stop: Sendable, Equatable { case silence, noSpeech, cap }

    /// Every tunable in one place, to adjust on a device.
    enum Tuning {
        /// Quiet after speech that ends the recording.
        static let silence: TimeInterval = 1.5
        /// Recording that ends with no speech heard, nothing uploaded.
        static let noSpeech: TimeInterval = 8
        /// Longest recording (the server refuses more than 60 s).
        static let cap: TimeInterval = 60
        /// dB over the floor that counts as speech.
        static let margin: Float = 10
        /// Until the level has varied by `margin`, a reading this loud counts as speech.
        static let loud: Float = -30
        /// Readings at or below this are digital silence and never set the floor.
        static let digitalSilence: Float = -90
    }

    public private(set) var heardSpeech = false
    private var floor: Float?
    private var peak: Float?
    /// When the current stretch of quiet began; nil while someone is talking.
    private var quietSince: TimeInterval?

    public init() {}

    /// One meter reading in dBFS at `time` seconds since recording began. Nil keeps recording.
    public mutating func feed(power: Float, at time: TimeInterval) -> Stop? {
        if time >= Tuning.cap {
            return .cap
        }
        var speaking = false
        if power > Tuning.digitalSilence {
            floor = min(floor ?? power, power)
            peak = max(peak ?? power, power)
            speaking = isSpeech(power)
        }
        if speaking {
            heardSpeech = true
            quietSince = nil
        } else if heardSpeech, quietSince == nil {
            quietSince = time
        }
        if heardSpeech {
            if let quietSince, time - quietSince >= Tuning.silence {
                return .silence
            }
            return nil
        }
        return time >= Tuning.noSpeech ? .noSpeech : nil
    }

    private func isSpeech(_ power: Float) -> Bool {
        guard let floor, let peak else { return false }
        if power >= floor + Tuning.margin {
            return true
        }
        let varied = peak - floor >= Tuning.margin
        return !varied && power >= Tuning.loud
    }
}

/// Turns a Chat turn's markdown into text a voice can read.
public enum SpokenText {
    public static func plain(_ markdown: String) -> String {
        var text = markdown
        let steps: [(String, String)] = [
            (#"\[([^\]\n]+)\]\([^)\s]*\)"#, "$1"),
            (#"https?://\S+"#, ""),
            (#"(?m)^[ \t]*#{1,6}[ \t]+"#, ""),
            (#"(?m)^[ \t]*[-*+][ \t]+"#, ""),
            (#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#, "$1"),
            (#"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])"#, "$1"),
            (#"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#, "$1"),
            (#"`([^`\n]*)`"#, "$1"),
            (#"[ \t]{2,}"#, " "),
            (#"(?m)[ \t]+$"#, ""),
        ]
        for (pattern, template) in steps {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads the language Whisper reports (a code, or an English name) as a two or three letter code.
public enum SpeechLanguage {
    public static func code(from whisper: String) -> String? {
        let value = whisper.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        let codes = Set(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))
        let head = String(value.prefix { $0 != "-" && $0 != "_" })
        if (2 ... 3).contains(head.count), codes.contains(head) {
            return head
        }
        let english = Locale(identifier: "en_US")
        return codes.sorted().first { english.localizedString(forLanguageCode: $0)?.lowercased() == value }
    }
}
